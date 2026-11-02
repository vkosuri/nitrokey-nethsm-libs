"""Validate the v-prefixed SemVer tag used to name a release bundle."""
import re
import sys

number = r"(?:0|[1-9][0-9]*)"
identifier = rf"(?:{number}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
build = r"[0-9A-Za-z-]+"
tag = rf"v{number}\.{number}\.{number}(?:-{identifier}(?:\.{identifier})*)?(?:\+{build}(?:\.{build})*)?"

if __name__ == "__main__":
    if len(sys.argv) != 2 or not re.fullmatch(tag, sys.argv[1]):
        sys.exit("Expected vMAJOR.MINOR.PATCH with optional SemVer prerelease and build metadata")
