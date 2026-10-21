#!/usr/bin/env bash
# K9 — approval receipt + install (integrity & provenance layer)
# Usage: k9-approve.sh <quarantine-dir> <destination-dir>
# Run ONLY after an explicit human "install" decision on the K9 report.
# Writes a receipt (source, commit, SHA-256 file manifest) to ~/k9/receipts/,
# moves the quarantine copy to its destination, and verifies the move.
set -euo pipefail

K9_HOME="${K9_HOME:-$HOME/k9}"
RECEIPTS="$K9_HOME/receipts"
mkdir -p "$RECEIPTS"

SRC="${1:?Usage: k9-approve.sh <quarantine-dir> <destination-dir>}"
DEST="${2:?Usage: k9-approve.sh <quarantine-dir> <destination-dir>}"
[[ -d "$SRC" ]] || { echo "[K9] quarantine dir not found: $SRC" >&2; exit 2; }
[[ -e "$DEST" ]] && { echo "[K9] destination already exists: $DEST" >&2; exit 2; }

SSVER="$(skillspector --version 2>/dev/null | head -1 || echo unknown)"

python3 - "$SRC" "$DEST" "$RECEIPTS" "$SSVER" <<'PY'
import hashlib, json, os, re, shutil, sys, datetime

src, dest, receipts, ssver = sys.argv[1:5]

def manifest(root):
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for fn in sorted(filenames):
            if fn == ".k9-source.json":
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root)
            h = hashlib.sha256()
            with open(p, "rb") as f:
                for chunk in iter(lambda: f.read(65536), b""):
                    h.update(chunk)
            out[rel] = h.hexdigest()
    return out

source = {"type": "unknown", "target": None}
sp = os.path.join(src, ".k9-source.json")
if os.path.exists(sp):
    source = json.load(open(sp))

m = manifest(src)
if not m:
    print("[K9] refusing: quarantine dir has no files to install", file=sys.stderr)
    sys.exit(2)

shutil.move(src, dest)
# drop quarantine metadata from the installed copy
meta = os.path.join(dest, ".k9-source.json")
if os.path.exists(meta):
    os.remove(meta)

after = manifest(dest)
if after != m:
    print("[K9] FATAL: post-move manifest mismatch — investigate before use", file=sys.stderr)
    sys.exit(1)

slug = re.sub(r"[^A-Za-z0-9._-]+", "_", os.path.abspath(dest)).strip("_")
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
receipt = {
    "schema": "k9-receipt/1",
    "approved_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "source": source,
    "destination": os.path.abspath(dest),
    "skillspector_version": ssver,
    "files": m,
}
path = os.path.join(receipts, f"{slug}-{stamp}.receipt.json")
json.dump(receipt, open(path, "w"), indent=1, ensure_ascii=False)
print(f"[K9] Installed {len(m)} file(s) -> {dest}")
print(f"[K9] Receipt -> {path}")
PY
