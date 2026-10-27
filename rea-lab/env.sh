#!/usr/bin/env bash
# ==============================================================================
# env.sh — sets up environment for REA in current shell
# ==============================================================================
# Source this file (do NOT execute it):
#   source rea-lab/env.sh
#
# It:
#   - puts the correct Node first in PATH (if installed to $HOME/.cache/tools)
#   - sets JAVA_HOME to JDK 21
#   - sets GHIDRA_INSTALL_DIR to Ghidra 12.1.4
#   - sets REA to the rea command (or npx fallback)
#   - verifies each variable and prints a summary
#
# Idempotent — safe to source multiple times.
# ==============================================================================

# ---- Determine TOOL_ROOT (same default as setup-rea.sh) ---------------------
export REA_TOOLS_DIR="${REA_TOOLS_DIR:-$HOME/.cache/tools}"
export TOOL_ROOT="$REA_TOOLS_DIR"

# ---- Node -------------------------------------------------------------------
# Prefer TOOL_ROOT Node if it exists and satisfies REA requirements
NODE_WANT="22.23.4"
NODE_DIR="$TOOL_ROOT/node-v${NODE_WANT}-linux-x64"

# Helper: check if current node satisfies REA
_rea_node_ok() {
  local raw major
  if ! command -v node >/dev/null 2>&1; then return 1; fi
  raw="$(node --version 2>/dev/null | sed 's/^v//')"
  [[ -z "$raw" ]] && return 1
  major="${raw%%.*}"
  if [[ "$major" -eq 22 ]]; then
    [[ "$(printf '%s\n22.23.4\n' "$raw" | sort -V | head -n1)" == "22.23.4" ]] && return 0 || return 1
  elif [[ "$major" -eq 24 ]]; then
    [[ "$(printf '%s\n24.22.1\n' "$raw" | sort -V | head -n1)" == "24.22.1" ]] && return 0 || return 1
  elif [[ "$major" -ge 26 ]]; then
    if [[ "$major" -gt 26 ]]; then return 0; fi
    [[ "$(printf '%s\n26.12.1\n' "$raw" | sort -V | head -n1)" == "26.12.1" ]] && return 0 || return 1
  fi
  return 1
}

if [[ -x "$NODE_DIR/bin/node" ]]; then
  # Only prepend if current node doesn't already satisfy, or to ensure correct version
  if ! _rea_node_ok; then
    export PATH="$NODE_DIR/bin:$PATH"
  else
    # Still ensure our Node is available first — user may have installed it for this reason
    case ":$PATH:" in
      *":$NODE_DIR/bin:"*) ;; # already in PATH
      *) export PATH="$NODE_DIR/bin:$PATH" ;;
    esac
  fi
fi

# ---- JDK 21 -----------------------------------------------------------------
# Prefer TOOL_ROOT/jdk-21, fallback to jdk-21.0.13+9, then system java
if [[ -x "$TOOL_ROOT/jdk-21/bin/java" ]]; then
  export JAVA_HOME="$TOOL_ROOT/jdk-21"
elif [[ -x "$TOOL_ROOT/jdk-21.0.13+9/bin/java" ]]; then
  export JAVA_HOME="$TOOL_ROOT/jdk-21.0.13+9"
elif [[ -z "${JAVA_HOME:-}" ]] && command -v java >/dev/null 2>&1; then
  # Derive JAVA_HOME from java binary if not set
  java_bin="$(command -v java)"
  # readlink -f to resolve /usr/bin/java → /usr/lib/jvm/...
  real_java="$(readlink -f "$java_bin" 2>/dev/null || echo "$java_bin")"
  # Heuristic: JAVA_HOME is two levels up from bin/java
  guess_home="$(dirname "$(dirname "$real_java")")"
  if [[ -f "$guess_home/bin/java" ]]; then
    # Only set if it's JDK 21; else leave for setup-rea.sh to fix
    if "$guess_home/bin/java" -version 2>&1 | grep -qE '"21\.'; then
      export JAVA_HOME="$guess_home"
    fi
  fi
fi

if [[ -n "${JAVA_HOME:-}" ]]; then
  # Ensure JAVA_HOME/bin is in PATH front
  case ":$PATH:" in
    *":$JAVA_HOME/bin:"*) ;;
    *) export PATH="$JAVA_HOME/bin:$PATH" ;;
  esac
fi

# ---- Ghidra 12.1.4 -----------------------------------------------------------
if [[ -d "$TOOL_ROOT/ghidra_12.1.4_PUBLIC" ]]; then
  export GHIDRA_INSTALL_DIR="$TOOL_ROOT/ghidra_12.1.4_PUBLIC"
elif [[ -d "$TOOL_ROOT/ghidra_12.1.4_PUBLIC_20260921" ]]; then
  export GHIDRA_INSTALL_DIR="$TOOL_ROOT/ghidra_12.1.4_PUBLIC_20260921"
fi

# ---- REA --------------------------------------------------------------------
if command -v rea >/dev/null 2>&1; then
  export REA="$(command -v rea)"
elif [[ -x "$TOOL_ROOT/rea-npm/node_modules/.bin/rea" ]]; then
  export REA="$TOOL_ROOT/rea-npm/node_modules/.bin/rea"
  export PATH="$TOOL_ROOT/rea-npm/node_modules/.bin:$PATH"
elif [[ -x "$HOME/.local/bin/rea" ]]; then
  export REA="$HOME/.local/bin/rea"
  export PATH="$HOME/.local/bin:$PATH"
else
  # Fallback to npx — requires no install, but slower
  export REA="npx --yes rea-agents@6.8.0"
fi

# Also ensure npm global bin is in PATH (if rea installed globally via npm -g)
if command -v npm >/dev/null 2>&1; then
  npm_bin="$(npm bin -g 2>/dev/null || echo '')"
  if [[ -n "$npm_bin" && -d "$npm_bin" ]]; then
    case ":$PATH:" in
      *":$npm_bin:"*) ;;
      *) export PATH="$npm_bin:$PATH" ;;
    esac
  fi
fi

# ---- Summary (printed when sourced interactively) ---------------------------
if [[ "${BASH_SOURCE[0]}" != "${0}" ]] || [[ "$0" == "bash" ]]; then
  # Sourced
  echo ""
  echo "[env.sh] Environment configured:"
  echo "  TOOL_ROOT           = $TOOL_ROOT"
  if command -v node >/dev/null 2>&1; then
    echo "  Node                = $(node --version) ($(which node))"
  else
    echo "  Node                = NOT FOUND (run bash rea-lab/setup-rea.sh)"
  fi
  if command -v java >/dev/null 2>&1; then
    echo "  Java                = $(java -version 2>&1 | head -n1)  JAVA_HOME=$JAVA_HOME"
  else
    echo "  Java                = NOT FOUND"
  fi
  if [[ -n "${GHIDRA_INSTALL_DIR:-}" ]]; then
    echo "  Ghidra              = $GHIDRA_INSTALL_DIR"
    if [[ -f "$GHIDRA_INSTALL_DIR/Ghidra/application.properties" ]]; then
      grep -E '^application.version' "$GHIDRA_INSTALL_DIR/Ghidra/application.properties" | sed 's/^/                      /'
    fi
  else
    echo "  Ghidra              = NOT FOUND"
  fi
  echo "  REA                 = $REA"
  if [[ "$REA" == npx* ]]; then
    echo "    (npx fallback — works but slower; install with bash rea-lab/setup-rea.sh for 'rea' binary)"
  fi
  echo "  PATH includes TOOL_ROOT outside /tmp: $(echo "$PATH" | grep -q "$TOOL_ROOT" && echo yes || echo "no (may be system paths)")"
  echo ""
else
  echo "NOTE: env.sh should be sourced, not executed. Run: source $0" >&2
fi

# Clean up helper
unset -f _rea_node_ok 2>/dev/null || true
