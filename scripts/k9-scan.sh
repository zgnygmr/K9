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

# ── Stage 2-3: static scan (dual engine: "two dogs" when both exist) ─
HAVE_SS=0; HAVE_CS=0
command -v skillspector >/dev/null 2>&1 && HAVE_SS=1
command -v skill-scanner >/dev/null 2>&1 && HAVE_CS=1
if [[ "$HAVE_SS" == 0 && "$HAVE_CS" == 0 ]]; then
  echo "[K9] WARNING: no scan engine installed (skillspector / skill-scanner)" >&2
fi

SCAN_FLAGS=(--no-llm)
[[ "$STRICT" == 1 ]] && SCAN_FLAGS+=(--fail-on-findings)
SCAN_RC=0
if [[ "$HAVE_SS" == 0 ]]; then
  : # SkillSpector not installed; skip
elif [[ "$CAGED" == 1 ]]; then
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

# Cisco skill-scanner (second dog) — local analyzers only: no --use-llm,
# no AI Defense / VirusTotal cloud calls (their defaults are off)
CISCO_RC=0
if [[ "$HAVE_CS" == 1 ]]; then
  if [[ "$CAGED" == 1 ]]; then
    echo "[K9] Caged mode: skipping skill-scanner (no caged wrapper yet)"
  else
    echo "[K9] Second dog: cisco skill-scanner (local analyzers only)"
    CS_FLAGS=(--lenient)
    [[ "$STRICT" == 1 ]] && CS_FLAGS+=(--fail-on-findings)
    skill-scanner scan "$DEST" "${CS_FLAGS[@]}" --format json \
      --output "$REPORT_BASE-cisco.json" || CISCO_RC=$?
    skill-scanner scan "$DEST" --lenient --format table \
      --output "$REPORT_BASE-cisco.txt" || true
  fi
fi

# ── Stage 6: Summary + decision box ──────────────────────────────────
python3 - "$REPORT_BASE-scan.json" "$REPORT_BASE-cisco.json" <<'PY' | tee "$REPORT_BASE-DECISION.md"
import json, os, sys

def load(p):
    try:
        return json.load(open(p))
    except Exception:
        return None

ss, cs = load(sys.argv[1]), load(sys.argv[2])
if ss is None and cs is None:
    print("[K9] No engine report parsed — inspect the .txt reports."); sys.exit(0)

verdicts = []
if ss is not None:
    r = ss.get("risk_assessment", {})
    score, sev, rec = r.get("score","?"), r.get("severity","?"), r.get("recommendation","?")
    dog = {"SAFE":"🟢/🟡 sniffed, no alert","CAUTION":"🟠 SAT DOWN","DO_NOT_INSTALL":"🔴 BARKED"}.get(rec,"?")
    verdicts.append(rec in ("CAUTION","DO_NOT_INSTALL"))
    print(f"# K9 DOG 1 — SkillSpector: {dog}")
    print(f"  {score}/100 · {sev} · {rec} · findings: {len(ss.get('issues',[]))} "
          f"(exec scripts: {ss.get('metadata',{}).get('has_executable_scripts')})")
if cs is not None:
    safe, msev, n = cs.get("is_safe"), cs.get("max_severity","?"), cs.get("findings_count","?")
    dog = "🟢/🟡 sniffed, no alert" if safe else ("🔴 BARKED" if str(msev).lower() in ("critical","high") else "🟠 SAT DOWN")
    verdicts.append(not safe)
    print(f"# K9 DOG 2 — cisco skill-scanner: {dog}")
    print(f"  max_severity: {msev} · findings: {n} · is_safe: {safe}")
print()
if len(verdicts) == 2 and verdicts[0] != verdicts[1]:
    print("NOTE: the dogs DISAGREE — stage-2 semantic review is mandatory.")
print("Reminder: static scan only — stage-2 semantic review pending;")
print("a clean scan is evidence, not a guarantee.")
print()
print("DECISION (human): [ ] install   [ ] reject   [ ] deeper review")
PY

echo
echo "[K9] Reports: $REPORT_BASE-{inventory.txt,scan.json,scan.txt,DECISION.md}"
echo "[K9] Quarantine kept at: $DEST"
echo "[K9] After a human 'install' decision: scripts/k9-approve.sh $DEST <destination>"

if [[ "$STRICT" == 1 && ( "$SCAN_RC" -ne 0 || "$CISCO_RC" -ne 0 ) ]]; then
  echo "[K9] STRICT MODE: findings reported (skillspector exit $SCAN_RC, skill-scanner exit $CISCO_RC)" >&2
  exit 1
fi
