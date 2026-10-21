#!/usr/bin/env bash
# K9 — quarantine + scan orchestrator (read-only by design)
# Usage: k9-scan.sh <git-url | local-path> [--caged] [--strict]
#   default : quarantine + skillspector static scan (egress: OSV.dev only,
#             via SkillSpector's own CVE lookup — package names, no content)
#   --caged : run the scan inside a no-network Docker/OrbStack container
#             (CVE check falls back to SkillSpector's offline list)
#   --strict: pass --fail-on-findings to skillspector (v2.12.0+) and exit 1
#             when the scan reports any finding — for CI / pre-commit gates
set -euo pipefail

K9_HOME="${K9_HOME:-$HOME/k9}"
QUARANTINE="$K9_HOME/quarantine"
REPORTS="$K9_HOME/reports"
mkdir -p "$QUARANTINE" "$REPORTS"

TARGET="${1:?Usage: k9-scan.sh <git-url|local-path> [--caged] [--strict]}"
CAGED=0; STRICT=0
for ARG in "${@:2}"; do
  case "$ARG" in
    --caged)  CAGED=1 ;;
    --strict) STRICT=1 ;;
    *) echo "[K9] Unknown option: $ARG" >&2; exit 2 ;;
  esac
done
STAMP="$(date +%Y%m%d-%H%M%S)"

# ── Stage 0: Quarantine ──────────────────────────────────────────────
if [[ "$TARGET" == http*://* || "$TARGET" == git@* ]]; then
  NAME="$(basename "$TARGET" .git)"
  DEST="$QUARANTINE/$NAME-$STAMP"
  echo "[K9] Quarantining $TARGET -> $DEST"
  git clone --quiet --depth 1 "$TARGET" "$DEST"
else
  NAME="$(basename "$TARGET")"
  DEST="$QUARANTINE/$NAME-$STAMP"
  echo "[K9] Copying local target into quarantine -> $DEST"
  cp -R "$TARGET" "$DEST"
fi

# record provenance for the approval receipt (read by k9-approve.sh)
python3 - "$DEST" "$TARGET" <<'PYSRC'
import datetime, json, os, subprocess, sys
dest, target = sys.argv[1], sys.argv[2]
info = {"target": target, "type": "local",
        "quarantined_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
if os.path.isdir(os.path.join(dest, ".git")):
    info["type"] = "git"
    try:
        info["commit"] = subprocess.run(["git", "-C", dest, "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        info["commit"] = None
json.dump(info, open(os.path.join(dest, ".k9-source.json"), "w"), indent=1)
PYSRC

REPORT_BASE="$REPORTS/$NAME-$STAMP"

# ── Stage 1: Inventory ───────────────────────────────────────────────
{
  echo "K9 INVENTORY — $NAME — $STAMP"
  echo "── files (incl. hidden) ──"
  find "$DEST" -not -path '*/.git/*' -exec ls -ld {} + 2>/dev/null
  echo "── executable-permission files ──"
  find "$DEST" -not -path '*/.git/*' -type f -perm -u+x 2>/dev/null || true
  echo "── symlinks ──"
  find "$DEST" -type l -exec ls -l {} + 2>/dev/null || true
  echo "── files > 5MB ──"
  find "$DEST" -not -path '*/.git/*' -type f -size +5M -exec ls -lh {} + 2>/dev/null || true
} > "$REPORT_BASE-inventory.txt"
echo "[K9] Inventory -> $REPORT_BASE-inventory.txt"

# ── Stage 2-3: SkillSpector static scan ──────────────────────────────
SCAN_FLAGS=(--no-llm)
[[ "$STRICT" == 1 ]] && SCAN_FLAGS+=(--fail-on-findings)
SCAN_RC=0
if [[ "$CAGED" == 1 ]]; then
  echo "[K9] Caged scan (no network; offline CVE fallback)"
  docker run --rm --network none -v "$DEST":/scan:ro skillspector \
    scan /scan "${SCAN_FLAGS[@]}" --format json --output /dev/stdout \
    > "$REPORT_BASE-scan.json" || SCAN_RC=$?
  docker run --rm --network none -v "$DEST":/scan:ro skillspector \
    scan /scan --no-llm | tee "$REPORT_BASE-scan.txt" || true
else
  echo "[K9] Static scan (egress: api.osv.dev only, dependency names)"
  skillspector scan "$DEST" "${SCAN_FLAGS[@]}" --format json \
    --output "$REPORT_BASE-scan.json" || SCAN_RC=$?
  skillspector scan "$DEST" --no-llm | tee "$REPORT_BASE-scan.txt" || true
fi

# ── Stage 6: Summary + decision box ──────────────────────────────────
python3 - "$REPORT_BASE-scan.json" <<'PY' | tee "$REPORT_BASE-DECISION.md"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"[K9] Could not parse scan JSON ({e}) — inspect the .txt report."); sys.exit(0)
r = d.get("risk_assessment", {})
score, sev, rec = r.get("score","?"), r.get("severity","?"), r.get("recommendation","?")
dog = {"SAFE":"🟢/🟡 sniffed, no alert","CAUTION":"🟠 SAT DOWN","DO_NOT_INSTALL":"🔴 BARKED"}.get(rec,"?")
print(f"# K9 VERDICT: {dog}")
print(f"SkillSpector: {score}/100 · {sev} · {rec}")
print(f"Findings: {len(d.get('issues',[]))} "
      f"(exec scripts present: {d.get('metadata',{}).get('has_executable_scripts')})")
print()
print("Reminder: static scan only — stage-2 semantic review pending;")
print("a clean scan is evidence, not a guarantee.")
print()
print("DECISION (human): [ ] install   [ ] reject   [ ] deeper review")
PY

echo
echo "[K9] Reports: $REPORT_BASE-{inventory.txt,scan.json,scan.txt,DECISION.md}"
echo "[K9] Quarantine kept at: $DEST"
echo "[K9] After a human 'install' decision: scripts/k9-approve.sh $DEST <destination>"

if [[ "$STRICT" == 1 && "$SCAN_RC" -ne 0 ]]; then
  echo "[K9] STRICT MODE: scan reported findings (skillspector exit $SCAN_RC)" >&2
  exit 1
fi
