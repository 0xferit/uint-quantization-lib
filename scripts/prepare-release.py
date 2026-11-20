import re
import subprocess
import sys
from pathlib import Path


def with_release_version(path, pattern, version):
    updated, count = re.subn(
        pattern,
        lambda match: f"{match[1]}{version}{match[2]}",
        path.read_text(),
        flags=re.MULTILINE,
    )
    if count != 1:
        sys.exit(f"Expected one release version in {path}, found {count}.")
    return updated


version = sys.argv[1]
stable_version = r"[0-9]+\.[0-9]+\.[0-9]+"
source = Path("src/UintQuantizationLib.sol")
readme = Path("README.md")
updated_source = with_release_version(
    source, rf'^(    string internal constant VERSION = "){stable_version}(";)$', version
)
updated_readme = with_release_version(
    readme, rf"^(forge soldeer install 'uint-quantization-lib~){stable_version}('.*)$", version
)
source.write_text(updated_source)
readme.write_text(updated_readme)
for command in ("build", "test"):
    subprocess.run(
        ["env", "-u", "GITHUB_TOKEN", "forge", command], check=True
    )
