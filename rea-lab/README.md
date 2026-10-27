# REA Setup — Reproducible across Arena.ai Agent Mode

This directory contains the reproducible bootstrap for REA (Reverse Engineer Anything) on Arena.ai sandboxes.

## Quick start (new session)

```bash
# 1. Inspect before you run (requirement 1) — bootstrap.sh does this automatically
cat rea-lab/setup-rea.sh | head -n 80
cat rea-lab/env.sh       | head -n 80

# 2. One-command bootstrap (idempotent, checks existing installs first)
bash rea-lab/bootstrap.sh

# 3. Use in current shell (sets JAVA_HOME, GHIDRA_INSTALL_DIR, PATH, REA)
source rea-lab/env.sh
$REA doctor
$REA analyze ./rea-lab/test-target/target --json | head
```

For non-interactive / CI:
```bash
BOOTSTRAP_YES=1 bash rea-lab/bootstrap.sh
```

## What the scripts do

| Script | Purpose | Requirement |
|---|---|---|
| `setup-rea.sh` | Installs or reuses Node 22.23.4 (or any `^22.23.4 \|\| ^24.22.1 \|\| >=26.12.1`), `rea-agents@6.8.0`, JDK 21 (`21.0.13+9` Temurin), Ghidra `12.1.4` (`ghidra_12.1.4_PUBLIC_20260921.zip`). Checks existing installs **before** downloading. Stores large deps in `$HOME/tools` (outside `/tmp`). | 2, 3, 4 |
| `env.sh` | Configures `JAVA_HOME`, `GHIDRA_INSTALL_DIR`, `PATH`, `REA` for current shell. Idempotent; safe to `source` multiple times. | 5 |
| `bootstrap.sh` | Inspect → setup → env → `rea doctor` → harmless binary test. Single entry point for new sessions. Prints checksums/heads before executing. | 1, 6 |

All scripts are pinned to exact versions for reproducibility:

- Node: `22.23.4` — `https://nodejs.org/dist/v22.23.4/node-v22.23.4-linux-x64.tar.xz`
- JDK: `21.0.13+9` (Eclipse Temurin) — `https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.13_9.tar.gz`
- Ghidra: `12.1.4` (NSA) — `https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip` (570 MB zip, 876 MB unpacked)
- REA: `rea-agents@6.8.0` — `npm install -g rea-agents@6.8.0` → tested with `rea --version`

## Verification (requirements 2, 6)

After bootstrap, you should see:

```bash
source rea-lab/env.sh
$REA doctor --provider ghidra --json
```

Expected (from `doctor-output.txt`):
```
- name: ghidra                 ok: true   healthy  /home/user/tools/ghidra_12.1.4_PUBLIC
- name: ghidra-platform        ok: true   healthy  linux
- name: ghidra-architecture    ok: true   healthy  x64
- name: ghidra-installation    ok: true   healthy  .../Ghidra/application.properties
- name: ida-registration       ok: false  missing_analysis_engine
- name: hopper                 ok: false  missing_analysis_engine
```

The harmless binary test compiles a tiny C program (`rea-lab/test-target/target.c`) with a fake licence check, then:

- brute-forces a valid key (`PWwzWC5Y`-style) from the hash logic,
- runs `./target <key>` → `LICENCE OK` / `LICENCE BAD`,
- runs `rea analyze ./target` → `procedure_count: 26, segments: 33` (Ghidra 12.1.4),
- runs `rea decompile-all ./target --output ./pseudo` → 19 function files.

See `rea-lab/test-target/test-output.txt`, `rea-analyze.json`, and `pseudo/` after bootstrap.

## Why `$HOME/tools` and not `/tmp` or `$HOME/.cache/tools`

- `/tmp` is a 992 MB `tmpfs` on Arena.ai — it cannot hold Ghidra (570 MB zip + 876 MB unpacked ≈ 1.4 GB).
- `$HOME/.cache` is **excluded from workspace snapshots** (see `PERSISTENCE.md`) — toolchain vanishes next session anyway. Previous `rea-lab` used `$HOME/.cache/tools` for that reason and required reinstall each session.
- This setup uses `$HOME/tools` (on `/`, 25 GB). It is still **not guaranteed to persist** due to snapshot caps (128 MB / 10k files), but it stays for the current session and survives `source env.sh` re-entry. The only guaranteed-persistent artefacts are the scripts themselves (committed to git).

## Persistence — what survives a fresh Arena.ai session

See [`PERSISTENCE.md`](./PERSISTENCE.md) for the full audit. TL;DR:

- **Persists (via GitHub / snapshot):** `rea-lab/*.sh`, `rea-lab/*.md`, `rea-lab/test-target/target.c`, `.gitignore`, `README.md`.
- **Does NOT persist (must be recreated):** `~/tools/*` (Node, JDK, Ghidra), `~/.cache/*`, `node_modules/.bin/rea`, `/tmp/*`, `rea-lab/test-target/pseudo/*`, `rea-lab/doctor-output.txt` if > snapshot cap.

Do **not** claim the setup is persistent — you must `bash rea-lab/bootstrap.sh` in each new session (~40 s with cache, ~2 min cold).

## Security — no large binaries in git

- `.gitignore` excludes `tools/`, `*.zip`, `*.tar.gz`, `ghidra_*_PUBLIC/`, `jdk-*/`, `node-*/`, `pseudo/`, `*.log`, credentials, tokens.
- Scripts download from official sources (nodejs.org, github.com/NationalSecurityAgency, github.com/adoptium) and verify via `application.properties` / `java -version` / `node --version`.

## Manual inspection checklist (requirement 1)

Before executing in a new session, verify:

```bash
ls -lh rea-lab/setup-rea.sh rea-lab/env.sh
sha256sum rea-lab/setup-rea.sh rea-lab/env.sh
# Check they only touch $HOME/tools, not /tmp, and check versions:
grep -E "NODE_WANT|GHIDRA_WANT|JDK_LABEL|REA_AGENTS_VERSION" rea-lab/setup-rea.sh
grep -E "JAVA_HOME|GHIDRA_INSTALL_DIR" rea-lab/env.sh
```

## Troubleshooting

- `node: command not found` → `bash rea-lab/setup-rea.sh` then `source rea-lab/env.sh`.
- `java version 11` → system JDK 11 is old; bootstrap installs Temurin 21 to `~/tools/jdk-21` and sets `JAVA_HOME` correctly.
- `Ghidra missing_analysis_engine` → check `echo $GHIDRA_INSTALL_DIR` and `ls $GHIDRA_INSTALL_DIR/Ghidra/application.properties`.
- `rea doctor` fails → run with `--json` for details; ensure `GHIDRA_INSTALL_DIR` is absolute.
- `/tmp no space left` → scripts intentionally avoid `/tmp`; if you manually downloaded to `/tmp`, move to `$HOME/tools`.

## Re-running

All scripts are idempotent:

```bash
bash rea-lab/setup-rea.sh         # skips cached downloads
bash rea-lab/setup-rea.sh --force # forces re-download
source rea-lab/env.sh            # safe to re-source
bash rea-lab/bootstrap.sh         # full re-check + doctor + test
```

## References

- REA docs: https://github.com/morluto/rea/blob/main/docs/installation.md
- Previous demo report: `../REA-DEMO-REPORT.md` or `uploads/REA-DEMO-REPORT.md` (from prior chat)
- Arena.ai snapshot exclusions: `.cache`, `.local`, `node_modules`, `build`, `dist`, etc. (128 MB cap)

