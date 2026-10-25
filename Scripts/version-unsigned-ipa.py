#!/usr/bin/env python3
"""Set bundle metadata in an unsigned IPA, preserving its compiled executables."""
import argparse
import os
import plistlib
import tempfile
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("ipa")
parser.add_argument("--version", required=True)
parser.add_argument("--build", required=True)
args = parser.parse_args()
fd, temporary = tempfile.mkstemp(suffix=".ipa", dir=os.path.dirname(args.ipa))
os.close(fd)
try:
    with zipfile.ZipFile(args.ipa) as original, zipfile.ZipFile(temporary, "w") as output:
        if any("/_CodeSignature/" in name or name.endswith("embedded.mobileprovision") for name in original.namelist()):
            raise ValueError("Expected an unsigned, unprovisioned IPA")
        updated = 0
        for item in original.infolist():
            data = original.read(item.filename)
            if item.filename.endswith((".app/Info.plist", ".appex/Info.plist")):
                info = plistlib.loads(data)
                info["CFBundleShortVersionString"] = args.version
                info["CFBundleVersion"] = args.build
                data = plistlib.dumps(info, fmt=plistlib.FMT_BINARY)
                updated += 1
            output.writestr(item, data)
        if updated != 2:
            raise ValueError(f"Expected app and widget plists; found {updated}")
    os.replace(temporary, args.ipa)
finally:
    if os.path.exists(temporary):
        os.remove(temporary)
