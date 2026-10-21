#!/usr/bin/env bash
# K9 — leash check: verify installed targets against approval receipts
# Usage: k9-verify.sh [receipt.json | destination-path]
#   no args : verify every receipt in ~/k9/receipts/ (latest per destination)
# Exit codes: 0 all OK · 1 drift or missing target · 2 usage/no receipts
# Any DRIFT means the target is no longer what was screened and approved:
# treat it as unscreened — re-run the K9 screening before continued use.
set -euo pipefail

K9_HOME="${K9_HOME:-$HOME/k9}"
RECEIPTS="$K9_HOME/receipts"

python3 - "$RECEIPTS" "${1:-}" <<'PY'
import glob, hashlib, json, os, sys

receipts_dir, arg = sys.argv[1], sys.argv[2]

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

paths = sorted(glob.glob(os.path.join(receipts_dir, "*.receipt.json")))
if arg:
    if arg.endswith(".receipt.json"):
        paths = [arg]
    else:
        want = os.path.abspath(arg)
        paths = [p for p in paths
                 if json.load(open(p)).get("destination") == want]
if not paths:
    print("[K9] no matching receipts found", file=sys.stderr)
    sys.exit(2)

# latest receipt per destination wins
latest = {}
for p in paths:
    r = json.load(open(p))
    latest[r["destination"]] = (p, r)

bad = 0
for dest, (p, r) in sorted(latest.items()):
    if not os.path.isdir(dest):
        print(f"🔴 MISSING  {dest}  (receipt: {os.path.basename(p)})")
        bad += 1
        continue
    now, want = manifest(dest), r["files"]
    changed = sorted(f for f in want if f in now and now[f] != want[f])
    removed = sorted(f for f in want if f not in now)
    added   = sorted(f for f in now  if f not in want)
    if not (changed or removed or added):
        print(f"🟢 OK       {dest}  ({len(want)} files)")
        continue
    bad += 1
    print(f"🔴 DRIFT    {dest}  (receipt: {os.path.basename(p)})")
    for f in changed: print(f"      changed: {f}")
    for f in removed: print(f"      removed: {f}")
    for f in added:   print(f"      added:   {f}")
    print("      -> treat as UNSCREENED: re-run K9 screening before use")

sys.exit(1 if bad else 0)
PY
