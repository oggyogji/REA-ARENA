#!/usr/bin/env bash
# ==============================================================================
# setup-rea.sh — Idempotent REA toolchain installer for Arena.ai Agent Mode
# ==============================================================================
# Installs or reuses:
#   - Node.js 22.23.4 (or any REA-supported: ^22.23.4 || ^24.22.1 || >=26.12.1)
#   - rea-agents (npm, default 6.8.0)
#   - JDK 21 (Temurin 21.0.13+9)
#   - Ghidra 12.1.4 (ghidra_12.1.4_PUBLIC_20260921.zip)
#
# Checks for existing installations BEFORE downloading (requirement 3).
# Installs large dependencies OUTSIDE /tmp (requirement 4) → $HOME/.cache/tools
# (.cache/ is snapshot-excluded, so deps never count against the 128 MB cap)
# Safe to re-run: skips anything already present and healthy.
#
# Usage:
#   bash rea-lab/setup-rea.sh
#   bash rea-lab/setup-rea.sh --force   # re-download even if present
#
# Environment overrides (optional):
#   REA_TOOLS_DIR   Where large deps live (default: $HOME/.cache/tools)
#   REA_NODE_VERSION Node version to install if missing (default: 22.23.4)
#   REA_GHIDRA_VERSION Ghidra version (default: 12.1.4)
#   REA_JDK_VERSION JDK version label (default: 21.0.13_9)
# ==============================================================================

set -euo pipefail

# ----------------------------- Config -----------------------------------------
TOOL_ROOT="${REA_TOOLS_DIR:-$HOME/.cache/tools}"
NODE_WANT="${REA_NODE_VERSION:-22.23.4}"
GHIDRA_WANT="${REA_GHIDRA_VERSION:-12.1.4}"
JDK_LABEL="${REA_JDK_VERSION:-21.0.13_9}"
REA_AGENTS_VERSION="${REA_AGENTS_VERSION:-6.8.0}"

# Concrete URLs / paths (pinned for reproducibility)
NODE_TAR="node-v${NODE_WANT}-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_WANT}/${NODE_TAR}"
NODE_DIR="$TOOL_ROOT/node-v${NODE_WANT}-linux-x64"

# JDK 21.0.13+9 — Eclipse Temurin
JDK_TAR="OpenJDK21U-jdk_x64_linux_hotspot_21.0.13_9.tar.gz"
JDK_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/${JDK_TAR}"
# JDK extracts to jdk-21.0.13+9 — normalize to $TOOL_ROOT/jdk-21
JDK_DIR="$TOOL_ROOT/jdk-21"
JDK_EXTRACTED="$TOOL_ROOT/jdk-21.0.13+9"

# Ghidra 12.1.4 — official NSA release 20260921
GHIDRA_ZIP="ghidra_12.1.4_PUBLIC_20260921.zip"
GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/${GHIDRA_ZIP}"
GHIDRA_DIR="$TOOL_ROOT/ghidra_12.1.4_PUBLIC"
# Some extracts create ghidra_12.1.4_PUBLIC with date suffix; handle both
GHIDRA_ALT="$TOOL_ROOT/ghidra_12.1.4_PUBLIC_20260921"

FORCE=false
if [[ "${1:-}" == "--force" ]]; then FORCE=true; fi

# ----------------------------- Helpers ----------------------------------------
log()  { printf "\n\033[1;34m[setup-rea]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m  ✓ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m  ⚠ %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31m  ✗ %s\033[0m\n" "$*" >&2; exit 1; }

# semver_ge compares dotted versions: semver_ge A B → true if A >= B
semver_ge() {
  # sort -V is GNU coreutils version-sort
  local a="$1" b="$2"
  [[ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | head -n1)" == "$b" ]]
}

node_satisfies_rea() {
  # Returns 0 if node --version satisfies ^22.23.4 || ^24.22.1 || >=26.12.1
  local ver raw major minor patch
  if ! command -v node >/dev/null 2>&1; then return 1; fi
  raw="$(node --version 2>/dev/null | sed 's/^v//')"
  [[ -z "$raw" ]] && return 1
  major="${raw%%.*}"; tmp="${raw#*.}"; minor="${tmp%%.*}"; patch="${tmp##*.}"; patch="${patch%%-**}"
  # normalize patch may contain extra
  patch="$(echo "$patch" | grep -oE '^[0-9]+' || echo 0)"
  if [[ "$major" -eq 22 ]] && semver_ge "$raw" "22.23.4"; then return 0; fi
  if [[ "$major" -eq 24 ]] && semver_ge "$raw" "24.22.1"; then return 0; fi
  if [[ "$major" -ge 26 ]]; then
    if [[ "$major" -gt 26 ]]; then return 0; fi
    # major == 26
    semver_ge "$raw" "26.12.1" && return 0 || return 1
  fi
  return 1
}

check_tmp_space() {
  # Requirement 4: ensure we do NOT use /tmp for large deps
  local tmp_avail tool_avail
  tmp_avail="$(df -m /tmp | awk 'NR==2{print $4}')"
  tool_avail="$(df -m "$TOOL_ROOT" 2>/dev/null | awk 'NR==2{print $4}' || df -m "$HOME" | awk 'NR==2{print $4}')"
  log "Disk check: /tmp has ${tmp_avail}MB free, TOOL_ROOT ($TOOL_ROOT) has ${tool_avail}MB free"
  if [[ "$tmp_avail" -lt 992 ]]; then
    warn "/tmp is limited (tmpfs ~992MB) — large downloads will use $TOOL_ROOT instead (requirement 4 satisfied)"
  fi
}

# ----------------------------- Start ------------------------------------------
log "REA setup starting — TOOL_ROOT=$TOOL_ROOT (outside /tmp)"
mkdir -p "$TOOL_ROOT"
check_tmp_space

# Show what we are about to do
log "Target versions: Node $NODE_WANT (or any REA-supported), JDK 21 ($JDK_LABEL), Ghidra $GHIDRA_WANT, rea-agents $REA_AGENTS_VERSION"
log "Force mode: $FORCE"

# ----------------------------- 1) Node.js -------------------------------------
log "Step 1/4 — Node.js"

# Check existing node first (before downloading)
if ! $FORCE && node_satisfies_rea; then
  ok "Found existing Node $(node --version) satisfying REA ^22.23.4 || ^24.22.1 || >=26.12.1 — reusing"
  # Ensure npm is present
  if ! command -v npm >/dev/null 2>&1; then
    warn "node present but npm missing — will install Node tarball anyway"
  else
    ok "npm $(npm --version) present"
  fi
else
  if $FORCE; then warn "Force requested — will (re)install Node $NODE_WANT"; fi
  if command -v node >/dev/null 2>&1; then
    warn "Existing Node $(node --version) does NOT satisfy REA requirements — will install $NODE_WANT"
  else
    log "No Node found — will install $NODE_WANT"
  fi

  # Check if already extracted
  if [[ -x "$NODE_DIR/bin/node" ]] && ! $FORCE; then
    ok "Node tarball already extracted at $NODE_DIR — reusing"
  else
    log "Downloading Node $NODE_WANT from nodejs.org ..."
    # Download outside /tmp → $TOOL_ROOT
    if [[ ! -f "$TOOL_ROOT/$NODE_TAR" ]] || $FORCE; then
      curl -fL --progress-bar -o "$TOOL_ROOT/$NODE_TAR" "$NODE_URL" || \
        wget -O "$TOOL_ROOT/$NODE_TAR" "$NODE_URL" || die "Failed to download Node"
      ok "Downloaded $NODE_TAR ($(du -h "$TOOL_ROOT/$NODE_TAR" | cut -f1))"
    else
      ok "Tarball already cached at $TOOL_ROOT/$NODE_TAR — skipping download"
    fi
    log "Extracting to $TOOL_ROOT ..."
    rm -rf "$NODE_DIR"
    tar -xf "$TOOL_ROOT/$NODE_TAR" -C "$TOOL_ROOT"
    ok "Extracted $NODE_DIR"
    # Optionally keep tarball for cache; don't delete automatically
  fi

  # Put new Node first in PATH for remainder of script
  export PATH="$NODE_DIR/bin:$PATH"
  log "Node now: $(node --version) at $(which node)"
  log "npm now: $(npm --version) at $(which npm)"

  # Verify satisfies REA
  if node_satisfies_rea; then
    ok "Installed Node $(node --version) satisfies REA requirements"
  else
    die "Installed Node $(node --version) still does not satisfy REA requirements — check $NODE_WANT"
  fi
fi

# ----------------------------- 2) JDK 21 --------------------------------------
log "Step 2/4 — JDK 21"

# Helper to check existing java
jdk_ok=false
if ! $FORCE && [[ -n "${JAVA_HOME:-}" ]] && [[ -x "$JAVA_HOME/bin/java" ]]; then
  ver_str="$("$JAVA_HOME/bin/java" -version 2>&1 | head -n1)"
  if echo "$ver_str" | grep -qE '"21\.'; then
    ok "JAVA_HOME=$JAVA_HOME already points to JDK 21 ($ver_str) — reusing"
    jdk_ok=true
  else
    warn "JAVA_HOME exists but not JDK 21: $ver_str — will install correct one"
  fi
fi
# Also check if JDK_DIR exists even if JAVA_HOME not set
if ! $jdk_ok && ! $FORCE && [[ -x "$JDK_DIR/bin/java" ]]; then
  ver_str="$("$JDK_DIR/bin/java" -version 2>&1 | head -n1)"
  if echo "$ver_str" | grep -qE '"21\.'; then
    ok "Found JDK 21 at $JDK_DIR ($ver_str) — reusing"
    export JAVA_HOME="$JDK_DIR"
    jdk_ok=true
  fi
fi
if ! $jdk_ok; then
  if $FORCE; then warn "Force — (re)installing JDK 21"; fi
  log "Checking for existing JDK tarball ..."
  if [[ -x "$JDK_DIR/bin/java" ]] && ! $FORCE; then
    ok "JDK already at $JDK_DIR — reusing"
    export JAVA_HOME="$JDK_DIR"
  else
    # If extracted with version suffix, handle
    if [[ -x "$JDK_EXTRACTED/bin/java" ]] && ! $FORCE; then
      ok "Found JDK at $JDK_EXTRACTED — normalizing to $JDK_DIR"
      rm -rf "$JDK_DIR"
      mv "$JDK_EXTRACTED" "$JDK_DIR"
      export JAVA_HOME="$JDK_DIR"
    else
      log "Downloading JDK 21 ($JDK_LABEL) from adoptium.net ..."
      if [[ ! -f "$TOOL_ROOT/$JDK_TAR" ]] || $FORCE; then
        curl -fL --progress-bar -o "$TOOL_ROOT/$JDK_TAR" "$JDK_URL" || \
          wget -O "$TOOL_ROOT/$JDK_TAR" "$JDK_URL" || die "Failed to download JDK"
        ok "Downloaded $JDK_TAR ($(du -h "$TOOL_ROOT/$JDK_TAR" | cut -f1))"
      else
        ok "JDK tarball cached at $TOOL_ROOT/$JDK_TAR — skipping download"
      fi
      log "Extracting JDK to $TOOL_ROOT ..."
      rm -rf "$JDK_DIR" "$JDK_EXTRACTED"
      tar -xzf "$TOOL_ROOT/$JDK_TAR" -C "$TOOL_ROOT"
      # Temurin extracts as jdk-21.0.13+9 — normalize
      if [[ -d "$JDK_EXTRACTED" ]]; then
        mv "$JDK_EXTRACTED" "$JDK_DIR"
      else
        # fallback: find newly extracted jdk dir
        newdir="$(ls -d "$TOOL_ROOT"/jdk-21* 2>/dev/null | head -n1)"
        if [[ -n "$newdir" && "$newdir" != "$JDK_DIR" ]]; then mv "$newdir" "$JDK_DIR"; fi
      fi
      ok "JDK extracted to $JDK_DIR"
      export JAVA_HOME="$JDK_DIR"
    fi
  fi
  # verify
  ver_str="$("$JAVA_HOME/bin/java" -version 2>&1 | head -n1)"
  ok "JAVA_HOME=$JAVA_HOME → $ver_str"
  if ! echo "$ver_str" | grep -qE '"21\.'; then
    die "JDK verification failed — not Java 21: $ver_str"
  fi
fi

# Ensure JAVA_HOME/bin is in PATH for Ghidra
export PATH="$JAVA_HOME/bin:$PATH"
log "java -version: $(java -version 2>&1 | head -n1)"
log "javac -version: $(javac -version 2>&1 || echo 'javac not found (JRE only)')"

# ----------------------------- 3) Ghidra 12.1.4 --------------------------------
log "Step 3/4 — Ghidra $GHIDRA_WANT"

ghidra_ok=false
if ! $FORCE && [[ -d "$GHIDRA_DIR" ]] && [[ -f "$GHIDRA_DIR/Ghidra/application.properties" ]]; then
  ok "Found Ghidra at $GHIDRA_DIR — reusing (exists before download check)"
  ghidra_ok=true
elif ! $FORCE && [[ -d "$GHIDRA_ALT" ]] && [[ -f "$GHIDRA_ALT/Ghidra/application.properties" ]]; then
  ok "Found Ghidra at $GHIDRA_ALT — normalizing to $GHIDRA_DIR"
  rm -rf "$GHIDRA_DIR"
  mv "$GHIDRA_ALT" "$GHIDRA_DIR"
  ghidra_ok=true
fi

if ! $ghidra_ok; then
  if $FORCE; then warn "Force — (re)installing Ghidra $GHIDRA_WANT"; fi
  log "Checking for cached Ghidra zip ..."
  if [[ -d "$GHIDRA_DIR" ]] && ! $FORCE; then
    ok "Ghidra dir already exists — reusing"
  else
    if [[ ! -f "$TOOL_ROOT/$GHIDRA_ZIP" ]] || $FORCE; then
      log "Downloading Ghidra $GHIDRA_WANT (570 MB) — this may take ~30s ..."
      # Use curl with retry; file is large, must be outside /tmp
      curl -fL --retry 2 --progress-bar -o "$TOOL_ROOT/$GHIDRA_ZIP" "$GHIDRA_URL" || \
        wget -O "$TOOL_ROOT/$GHIDRA_ZIP" "$GHIDRA_URL" || die "Failed to download Ghidra"
      ok "Downloaded $GHIDRA_ZIP ($(du -h "$TOOL_ROOT/$GHIDRA_ZIP" | cut -f1))"
    else
      ok "Ghidra zip cached at $TOOL_ROOT/$GHIDRA_ZIP — skipping download"
    fi
    log "Unzipping to $TOOL_ROOT (876 MB unpacked) ..."
    rm -rf "$GHIDRA_DIR" "$GHIDRA_ALT"
    unzip -q "$TOOL_ROOT/$GHIDRA_ZIP" -d "$TOOL_ROOT" || die "Failed to unzip Ghidra"
    # Handle both possible extracted names
    if [[ -d "$GHIDRA_ALT" ]]; then
      mv "$GHIDRA_ALT" "$GHIDRA_DIR"
    fi
    ok "Ghidra extracted to $GHIDRA_DIR"
  fi
fi

# Verify
if [[ -f "$GHIDRA_DIR/Ghidra/application.properties" ]]; then
  ver="$(grep -E '^application.version' "$GHIDRA_DIR/Ghidra/application.properties" || echo 'unknown')"
  ok "Ghidra verified: $GHIDRA_DIR ($ver)"
  export GHIDRA_INSTALL_DIR="$GHIDRA_DIR"
else
  die "Ghidra verification failed — $GHIDRA_DIR/Ghidra/application.properties not found"
fi

# ----------------------------- 4) REA (rea-agents) ----------------------------
log "Step 4/4 — REA (rea-agents@$REA_AGENTS_VERSION)"

# Check existing rea
if ! $FORCE && command -v rea >/dev/null 2>&1; then
  existing_ver="$(rea --version 2>/dev/null || npx rea-agents --version 2>/dev/null || echo unknown)"
  ok "Found existing 'rea' at $(which rea) version $existing_ver — reusing (use --force to reinstall)"
else
  # Also check npx
  if ! $FORCE && npx --yes rea-agents@$REA_AGENTS_VERSION --version >/dev/null 2>&1; then
    ok "npx rea-agents@$REA_AGENTS_VERSION works — reusing"
  else
    log "Installing rea-agents@$REA_AGENTS_VERSION via npm ..."
    # Install globally if writable, otherwise locally in TOOL_ROOT
    # Prefer global install; fallback to prefix=$TOOL_ROOT/rea-npm
    if npm install -g "rea-agents@$REA_AGENTS_VERSION" 2>&1 | tee "$TOOL_ROOT/rea-install.log"; then
      ok "Installed rea-agents globally"
    else
      warn "Global install failed (permission) — installing with prefix $TOOL_ROOT/rea-npm"
      mkdir -p "$TOOL_ROOT/rea-npm"
      npm install --prefix "$TOOL_ROOT/rea-npm" "rea-agents@$REA_AGENTS_VERSION" || die "npm install failed"
      # Add to PATH
      export PATH="$TOOL_ROOT/rea-npm/node_modules/.bin:$TOOL_ROOT/rea-npm/bin:$PATH"
      # symlink for convenience
      mkdir -p "$HOME/.local/bin"
      ln -sf "$TOOL_ROOT/rea-npm/node_modules/.bin/rea" "$HOME/.local/bin/rea" 2>/dev/null || true
      export PATH="$HOME/.local/bin:$PATH"
      ok "Installed rea-agents to $TOOL_ROOT/rea-npm"
    fi
  fi
fi

# Ensure rea is available; if still not, use npx as fallback
if command -v rea >/dev/null 2>&1; then
  export REA="$(which rea)"
  ok "REA command: $REA ($(rea --version 2>/dev/null || echo 'version unknown'))"
else
  warn "'rea' not in PATH — will use npx fallback"
  export REA="npx --yes rea-agents@$REA_AGENTS_VERSION"
  # test npx
  $REA --version >/dev/null 2>&1 || die "REA npx fallback failed"
  ok "REA via npx works: $REA --version = $($REA --version 2>/dev/null)"
fi

# ----------------------------- Summary ----------------------------------------
log "All steps done. Verifying environment:"

cat <<SUMMARY

  TOOL_ROOT (outside /tmp): $TOOL_ROOT
  Node:  $(node --version) at $(which node)  (satisfies REA: $(node_satisfies_rea && echo yes || echo no))
  npm:   $(npm --version)
  Java:  $(java -version 2>&1 | head -n1)  JAVA_HOME=$JAVA_HOME
  Ghidra: $GHIDRA_INSTALL_DIR  ($(grep -E '^application.version' "$GHIDRA_INSTALL_DIR/Ghidra/application.properties" 2>/dev/null || echo 'version unknown'))
  REA:   $REA  ($($REA --version 2>/dev/null || echo 'version check failed'))

  Next:
    source rea-lab/env.sh
    \$REA doctor --provider ghidra
SUMMARY

log "Setup complete — now run: source rea-lab/env.sh && \$REA doctor"

