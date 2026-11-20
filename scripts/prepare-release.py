import re
import subprocess
import sys
from pathlib import Path

version = sys.argv[1]
source = Path("src/UintQuantizationLib.sol")
updated_source, replacements = re.subn(
    r'(?m)^(    string internal constant VERSION = )"[0-9]+\.[0-9]+\.[0-9]+";$',
    lambda match: f'{match[1]}"{version}";',
    source.read_text(),
)
if replacements != 1:
    sys.exit("Expected a single VERSION declaration in the library.")

source.write_text(updated_source)
for command in ("build", "test"):
    subprocess.run(
        ["env", "-u", "GITHUB_TOKEN", "forge", command], check=True
    )
