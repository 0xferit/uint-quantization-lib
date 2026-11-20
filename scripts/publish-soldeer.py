import io
import json
import os
import subprocess
import sys
from http import HTTPStatus
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen
from zipfile import ZipFile

PACKAGE = "uint-quantization-lib"
REQUEST_TIMEOUT_SECONDS = 30


def registry_archive(version):
    query = urlencode({"project_name": PACKAGE, "revision": version})
    request = Request(
        f"https://api.soldeer.xyz/api/v1/revision-cli?{query}",
        headers={"User-Agent": PACKAGE},
    )
    try:
        response = urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS)
    except HTTPError as error:
        if error.code == HTTPStatus.NOT_FOUND:
            return None
        raise
    with response:
        metadata = json.load(response)
    revisions = metadata.get("data") if isinstance(metadata, dict) else None
    if not isinstance(revisions, list) or metadata.get("status") != "success" or len(revisions) > 1:
        sys.exit(f"Unexpected Soldeer registry response for {PACKAGE} {version}.")
    if not revisions:
        return None
    revision = revisions[0]
    if not isinstance(revision, dict) or not isinstance(revision.get("url"), str):
        sys.exit(f"Unexpected Soldeer registry entry for {PACKAGE} {version}.")
    url = urlsplit(revision["url"])
    if (
        revision.get("version") != version
        or revision.get("deleted") is not False
        or revision.get("private") is not False
        or url.scheme != "https"
        or url.netloc != "soldeer-revisions.s3.amazonaws.com"
        or not url.path.startswith(f"/{PACKAGE}/")
    ):
        sys.exit(f"Unexpected Soldeer archive location for {PACKAGE} {version}.")
    with urlopen(url.geturl(), timeout=REQUEST_TIMEOUT_SECONDS) as response:
        return response.read()


def verify_solidity_sources(archive):
    source_paths = sorted(str(path) for path in Path("src").rglob("*.sol"))
    with ZipFile(io.BytesIO(archive)) as package:
        published_paths = sorted(
            name for name in package.namelist()
            if name.startswith("src/") and name.endswith(".sol")
        )
        if not source_paths or source_paths != published_paths or any(
            Path(path).read_bytes() != package.read(path) for path in source_paths
        ):
            sys.exit("Soldeer Solidity sources differ from the release tag.")


def publish(version):
    archive = registry_archive(version)
    if archive is None:
        if not os.environ.get("SOLDEER_API_TOKEN"):
            sys.exit("SOLDEER_API_TOKEN is required to upload the package.")
        subprocess.run(
            ["forge", "soldeer", "push", f"{PACKAGE}~{version}", "--skip-warnings"],
            check=True,
        )
        archive = registry_archive(version)
        if archive is None:
            sys.exit(f"Soldeer does not yet serve {PACKAGE} {version}. Retry the release.")
    verify_solidity_sources(archive)
    print(f"Verified Soldeer Solidity sources for {PACKAGE} {version}.")


if __name__ == "__main__":
    publish(sys.argv[1])
