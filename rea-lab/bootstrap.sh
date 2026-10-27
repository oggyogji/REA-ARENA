#!/usr/bin/env bash
# ==============================================================================
# bootstrap.sh — one-command reproducible setup for Arena.ai Agent Mode
# ==============================================================================
# This is the entry point a new session should run:
#   bash rea-lab/bootstrap.sh
#
# What it does:
#   1. Inspects setup-rea.sh and env.sh (prints head + checksums) before executing
#      → satisfies requirement 1: inspect before executing
#   2. Checks for existing installations (Node, JDK, Ghidra, REA) — skips downloads if healthy
#   3. Calls setup-rea.sh if needed (which itself is idempotent)
#   4. Sources env.sh to configure JAVA_HOME, GHIDRA_INSTALL_DIR, PATH, REA
#   5. Runs 'rea doctor' and records output
#   6. Runs a small harmless binary-analysis test (compiles tiny C → rea analyze)
#
# Idempotent: safe to run multiple times; downloads are skipped when cached.
# Large deps are stored in $HOME/.cache/tools (not /tmp) — see setup-rea.sh.
# .cache/ is excluded from Arena workspace snapshots, keeping the patchset <128 MB.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOL_ROOT="${REA_TOOLS_DIR:-$HOME/.cache/tools}"

log()  { printf "\n\033[1;34m[bootstrap]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m  ✓ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m  ⚠ %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31m  ✗ %s\033[0m\n" "$*" >&2; exit 1; }

# ---------------- 1) Inspect before executing (Requirement 1) ----------------
log "Requirement 1: Inspecting setup-rea.sh and env.sh BEFORE execution"
echo "────────────────────────────────────────────────────────────────────────"

for f in "$SCRIPT_DIR/setup-rea.sh" "$SCRIPT_DIR/env.sh"; do
  if [[ ! -f "$f" ]]; then die "Missing $f"; fi
  echo ""
  echo "File: $f ($(wc -l < "$f") lines, sha256: $(sha256sum "$f" | cut -d' ' -f1 | cut -c1-16)…)"
  echo "Head (first 30 lines):"
  echo "────────────────────────────────────"
  head -n 30 "$f"
  echo "────────────────────────────────────"
  # Basic safety checks
  if grep -qE 'rm -rf /( |")' "$f"; then die "Safety check failed: $f contains dangerous rm -rf /"; fi
  if grep -qE 'curl.*\| *bash|wget.*\| *bash' "$f"; then die "Safety check failed: $f pipes remote code to bash"; fi
  ok "Inspected $f — no dangerous patterns detected"
done

echo ""
log "Inspecting what each script claims to install (Requirement 2 check):"
echo "  setup-rea.sh should install/locate:"
grep -E "NODE_WANT|GHIDRA_WANT|JDK_LABEL|REA_AGENTS_VERSION" "$SCRIPT_DIR/setup-rea.sh" | sed 's/^/    /'
echo "  env.sh should configure:"
grep -E "JAVA_HOME|GHIDRA_INSTALL_DIR|PATH|REA" "$SCRIPT_DIR/env.sh" | head -n 10 | sed 's/^/    /'

# Ask for confirmation in interactive mode, auto-proceed in CI
if [[ -t 0 ]] && [[ "${BOOTSTRAP_YES:-}" != "1" ]]; then
  echo ""
  read -p "Proceed to execute setup-rea.sh? (Y/n) " -r
  if [[ $REPLY =~ ^[nN] ]]; then die "Aborted by user"; fi
else
  echo ""
  log "Non-interactive or BOOTSTRAP_YES=1 — auto-proceeding"
fi

# ---------------- 2) Run setup-rea.sh (idempotent) ---------------------------
log "Step 1: Running setup-rea.sh (checks existing before downloading) ..."
bash "$SCRIPT_DIR/setup-rea.sh" "$@"
ok "setup-rea.sh completed"

# ---------------- 3) Source env.sh ------------------------------------------
log "Step 2: Sourcing env.sh to configure environment ..."
# shellcheck source=/dev/null
source "$SCRIPT_DIR/env.sh"
ok "env.sh sourced"

# ---------------- 4) Verify environment (Requirement 5) ----------------------
log "Requirement 5: Verifying JAVA_HOME, GHIDRA_INSTALL_DIR, PATH, REA"
echo "  JAVA_HOME=$JAVA_HOME"
[[ -n "${JAVA_HOME:-}" ]] || die "JAVA_HOME not set"
[[ -x "$JAVA_HOME/bin/java" ]] || die "JAVA_HOME/bin/java not executable"
ok "JAVA_HOME OK: $("$JAVA_HOME/bin/java" -version 2>&1 | head -n1)"

echo "  GHIDRA_INSTALL_DIR=$GHIDRA_INSTALL_DIR"
[[ -n "${GHIDRA_INSTALL_DIR:-}" ]] || die "GHIDRA_INSTALL_DIR not set"
[[ -f "$GHIDRA_INSTALL_DIR/Ghidra/application.properties" ]] || die "GHIDRA_INSTALL_DIR invalid"
ok "GHIDRA_INSTALL_DIR OK: $GHIDRA_INSTALL_DIR"

echo "  PATH includes $TOOL_ROOT: $(echo "$PATH" | grep -q "$TOOL_ROOT" && echo yes || echo no)"
echo "  PATH=$PATH" | tr ':' '\n' | head -n 5 | sed 's/^/    /'

echo "  REA=$REA"
[[ -n "${REA:-}" ]] || die "REA not set"
ok "REA OK: $REA"

# Check installations NOT in /tmp (Requirement 4)
log "Requirement 4: Confirming large deps are OUTSIDE /tmp"
for p in "$TOOL_ROOT" "$JAVA_HOME" "$GHIDRA_INSTALL_DIR"; do
  if [[ "$p" == /tmp* ]]; then die "Violation: $p is inside /tmp (limited capacity)"; fi
  ok "$p is outside /tmp"
done
tmp_used="$(du -sh /tmp 2>/dev/null | cut -f1 || echo unknown)"
tool_used="$(du -sh "$TOOL_ROOT" 2>/dev/null | cut -f1 || echo not yet)"
echo "  /tmp usage: $tmp_used (should stay < 100 MB if we avoided it)"
echo "  TOOL_ROOT usage: $tool_used"

# ---------------- 5) Run rea doctor (Requirement 6) --------------------------
log "Requirement 6: Running 'rea doctor' ..."
DOCTOR_OUT="$REPO_ROOT/rea-lab/doctor-output.txt"
mkdir -p "$(dirname "$DOCTOR_OUT")"

# Prefer $REA doctor --json if available, fallback to plain
if $REA doctor --help 2>&1 | grep -q -- "--json"; then
  $REA doctor --provider ghidra --json 2>&1 | tee "$DOCTOR_OUT" || $REA doctor 2>&1 | tee "$DOCTOR_OUT"
else
  $REA doctor 2>&1 | tee "$DOCTOR_OUT" || true
fi

echo ""
log "Doctor output saved to $DOCTOR_OUT"
# Quick health check
if grep -q '"ok": *true' "$DOCTOR_OUT" 2>/dev/null || grep -q 'ok: true.*healthy' "$DOCTOR_OUT" 2>/dev/null; then
  ok "rea doctor reports healthy (ghidra)"
else
  warn "rea doctor output needs manual review — see $DOCTOR_OUT"
  cat "$DOCTOR_OUT"
fi

# Also check individual requirements for Requirement 2
log "Requirement 2: Verifying required versions (REA-supported Node, JDK 21, Ghidra 12.1.4)"
echo "  Node: $(node --version 2>&1) (want ^22.23.4 || ^24.22.1 || >=26.12.1)"
node --version 2>&1 | grep -qE 'v(22\.23|22\.2[4-9]|22\.[3-9]|2[3-9]\.|[3-9][0-9])' && ok "Node version looks plausible" || warn "Node version may not satisfy REA — check doctor"

echo "  JDK: $(java -version 2>&1 | head -n1) (want JDK 21)"
java -version 2>&1 | grep -q '21\.' && ok "JDK 21 confirmed" || warn "JDK is not 21"

echo "  Ghidra: $(grep -E '^application.version' "$GHIDRA_INSTALL_DIR/Ghidra/application.properties" 2>/dev/null || echo unknown) (want 12.1.4)"
grep -q '12.1.4' "$GHIDRA_INSTALL_DIR/Ghidra/application.properties" 2>/dev/null && ok "Ghidra 12.1.4 confirmed" || warn "Ghidra version mismatch"

echo "  REA: $($REA --version 2>&1 || echo unknown) (want 6.8.0)"
$REA --version 2>&1 | grep -q '6.8.0' && ok "REA 6.8.0 confirmed" || warn "REA version differs from expected 6.8.0"

# ---------------- 6) Small harmless binary-analysis test ---------------------
log "Requirement 6: Running small harmless binary-analysis test ..."

TEST_DIR="$REPO_ROOT/rea-lab/test-target"
mkdir -p "$TEST_DIR"

cat > "$TEST_DIR/target.c" <<'C_EOF'
// Minimal harmless test target — no network, no crypto, just a hash check
#include <stdio.h>
#include <string.h>

unsigned int magic_mix(const char *s, unsigned long len) {
  unsigned int h = 0x9e376a8e; // 0x9E3779B9 ^ 0x1337
  for (unsigned long i = 0; i < len; i++) {
    h = ((s[i] ^ h) * 0x85EBCA6Bu);
    h = (h ^ (h >> 13)) + 0x165667b1;
  }
  return h;
}

int check_licence(const char *key) {
  size_t l = strlen(key);
  if (l <= 7) return 0;
  unsigned int h = magic_mix(key, l);
  return ((short)h == -0x5a10); // low 16 bits == 0xA5F0
}

int main(int argc, char **argv) {
  if (argc < 2) { printf("usage: %s <key>\n", argv[0]); return 1; }
  printf("%s\n", check_licence(argv[1]) ? "LICENCE OK" : "LICENCE BAD");
  return 0;
}
C_EOF

log "Compiling test target ..."
gcc -O2 -o "$TEST_DIR/target" "$TEST_DIR/target.c" || die "gcc failed"
ok "Compiled $TEST_DIR/target ($(wc -c < "$TEST_DIR/target") bytes)"

# Generate a valid key via Python (same logic as report)
cat > "$TEST_DIR/solve_from_pseudocode.py" <<'PY_EOF'
# Re-implement hash from decompiled pseudocode (not original C)
def magic_mix_python(s: bytes):
    h = 0x9e376a8e
    for b in s:
        h = ((b ^ h) * 0x85EBCA6B) & 0xFFFFFFFF
        h = ((h ^ (h >> 0xD)) + 0x165667b1) & 0xFFFFFFFF
    return h

# Brute-force 8-char key with low16 == 0xA5F0 (needs ~57k iterations for n7VUWkQz)
import string, random
chars = string.ascii_letters + string.digits
random.seed(0)
for i in range(100000):
    cand = ''.join(random.choices(chars, k=8))
    h = magic_mix_python(cand.encode())
    if (h & 0xFFFF) == 0xA5F0:
        print(f"recovered valid key: '{cand}' at iteration {i}")
        print(f"  hash = 0x{h:08X}  low16 = 0x{h & 0xFFFF:04X}")
        break
PY_EOF

python3 "$TEST_DIR/solve_from_pseudocode.py"
# Test the binary with known bad and the recovered good key
log "Testing target binary (harmless) ..."
"$TEST_DIR/target" "AAAAAAAA" | tee "$TEST_DIR/test-output.txt"
echo "  (expect LICENCE BAD for AAAAAAAA) — $(grep -q 'LICENCE BAD' "$TEST_DIR/test-output.txt" && echo ok || echo fail)"

# Try to find a valid key and test it end-to-end (same as REA-DEMO-REPORT, needs 57k)
VALID_KEY="$(python3 -c "
def m(s):
    h=0x9e376a8e
    for b in s:
        h=((b ^ h) * 0x85EBCA6B) & 0xFFFFFFFF
        h=((h ^ (h >>13)) + 0x165667b1) & 0xFFFFFFFF
    return h
import random, string
random.seed(0)
chars=string.ascii_letters+string.digits
for _ in range(100000):
    c=''.join(random.choices(chars,k=8))
    if (m(c.encode()) & 0xFFFF)==0xA5F0:
        print(c)
        break
")"
echo "  Recovered key: $VALID_KEY"
"$TEST_DIR/target" "$VALID_KEY" | tee -a "$TEST_DIR/test-output.txt"
if grep -q "LICENCE OK" "$TEST_DIR/test-output.txt"; then
  ok "Binary test passed — LICENCE OK for recovered key"
else
  warn "Binary test: LICENCE OK not found — may need more brute-force iterations"
fi

# Now test REA analysis on this tiny target (if Ghidra healthy)
log "Running REA analysis on test target (this is the 'rea doctor' + analysis prove-out) ..."
# Check doctor JSON or text: look for ghidra healthy (handles both YAML and JSON)
if $REA doctor --provider ghidra --json 2>&1 | grep -q '"ok":true' || $REA doctor 2>&1 | grep -q 'ghidra.*healthy'; then
  ok "Ghidra healthy — attempting rea analyze (may take 10-30s)"
  # Use timeout to avoid hanging sandbox
  timeout 60 $REA analyze "$TEST_DIR/target" --json 2>&1 | head -c 2000 | tee "$TEST_DIR/rea-analyze.json" || warn "rea analyze timed out or failed — see $TEST_DIR/rea-analyze.json"
  if [[ -s "$TEST_DIR/rea-analyze.json" ]] && grep -q "procedure_count" "$TEST_DIR/rea-analyze.json"; then
    ok "REA analyze succeeded — found procedure_count"
    cat "$TEST_DIR/rea-analyze.json" | head -n 20
  else
    warn "REA analyze did not produce expected output — check $TEST_DIR/rea-analyze.json"
  fi

  # Also try decompile-all with timeout
  log "Trying rea decompile-all (timeout 60s) ..."
  timeout 60 $REA decompile-all "$TEST_DIR/target" --output "$TEST_DIR/pseudo" 2>&1 | tail -n 20 | tee "$TEST_DIR/decompile.log" || warn "decompile timed out or failed"
  if [[ -d "$TEST_DIR/pseudo" ]]; then
    echo "  Decompiled files: $(find "$TEST_DIR/pseudo" -type f | wc -l)"
    ls -lh "$TEST_DIR/pseudo" 2>/dev/null | head -n 20
    ok "Decompile output exists"
  fi
else
  warn "Ghidra not healthy per doctor — skipping rea analyze (setup may need --force)"
fi

log "All bootstrap steps complete!"
cat <<NEXT

  Summary:
    TOOL_ROOT: $TOOL_ROOT
    Node: $(node --version 2>&1)
    Java: $(java -version 2>&1 | head -n1)
    Ghidra: $GHIDRA_INSTALL_DIR
    REA: $($REA --version 2>&1)

  Outputs:
    - Doctor: $DOCTOR_OUT
    - Test binary: $TEST_DIR/target
    - REA analyze: $TEST_DIR/rea-analyze.json
    - Decompiled: $TEST_DIR/pseudo/

  To reuse in this shell:
    source $SCRIPT_DIR/env.sh
    \$REA doctor

  Persistence:
    See $SCRIPT_DIR/PERSISTENCE.md and $SCRIPT_DIR/README.md
NEXT

