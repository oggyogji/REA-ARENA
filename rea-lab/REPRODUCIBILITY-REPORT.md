# REA Reproducibility Report — 2026-10-27

**Session:** Arena.ai Agent Mode `nlhz8vlwyupq845jsdg9` (E2B, Debian 13, x86_64)
**Date:** 2026-10-27
**Branch:** `main`
**Tester:** Automated bootstrap (`BOOTSTRAP_YES=1 bash rea-lab/bootstrap.sh`)

This report proves the setup is **reproducible** and documents what was verified (requirements 1–9).

---

## 1. Inspection before execution (Requirement 1)

`bootstrap.sh` prints checksums and first 30 lines of `setup-rea.sh` and `env.sh` **before** executing them:

```
File: /home/user/rea-lab/setup-rea.sh (346 lines, sha256: 094cb13076d7bfae…)
File: /home/user/rea-lab/env.sh (154 lines, sha256: dff8672044f2b260…)

✓ Inspected — no dangerous patterns (no rm -rf /, no curl|bash)
```

Manual check also done:

```bash
grep -E "NODE_WANT|GHIDRA_WANT|JDK_LABEL|REA_AGENTS_VERSION" rea-lab/setup-rea.sh
grep -E "JAVA_HOME|GHIDRA_INSTALL_DIR" rea-lab/env.sh
```

---

## 2. Versions installed or located (Requirement 2)

All scripts **check existing installs before downloading** (idempotent).

| Component | Wanted | Found / Installed | Method |
|---|---|---|---|
| Node.js | `^22.23.4 \|\| ^24.22.1 \|\| >=26.12.1` (we pin `22.23.4`) | `v22.23.4` at `/home/user/tools/node-v22.23.4-linux-x64/bin/node` | Downloaded `node-v22.23.4-linux-x64.tar.xz` (30 MB) from `nodejs.org/dist/v22.23.4/` — skipped if healthy |
| npm | bundled with Node | `10.9.9` | Same tarball |
| JDK | 21 (Temurin `21.0.13+9`) | `openjdk 21.0.13 2026-10-20 LTS` at `/home/user/tools/jdk-21` | Downloaded `OpenJDK21U-jdk_x64_linux_hotspot_21.0.13_9.tar.gz` (199 MB) — cached reuse |
| Ghidra | `12.1.4` | `12.1.4` at `/home/user/tools/ghidra_12.1.4_PUBLIC` (`application.version=12.1.4`) | Downloaded `ghidra_12.1.4_PUBLIC_20260921.zip` (544 MB) — 876 MB unpacked |
| REA | `rea-agents@6.8.0` | `6.8.0` via `npx --yes rea-agents@6.8.0` (fallback) | `npm view rea-agents version` → 6.8.0; npx check before install |

System before bootstrap:
- Node `v20.20.2` (too old, does NOT satisfy REA)
- Java `openjdk 11` (too old)
- No Ghidra

System after:
- Node `v22.23.4` ✓ satisfies `^22.23.4`
- Java `21.0.13` ✓ full JDK (has `javac 21.0.13`)
- Ghidra `12.1.4` ✓ `Ghidra/application.properties` exists

---

## 3. Bootstrap checks before downloading (Requirement 3)

`setup-rea.sh` logic for each dep:

```bash
if ! $FORCE && node_satisfies_rea; then
  ok "Found existing Node $(node --version) — reusing"
else
  if [[ -x "$NODE_DIR/bin/node" ]] && ! $FORCE; then
    ok "Node tarball already extracted — reusing"
  else
    curl -o "$TOOL_ROOT/$NODE_TAR" "$NODE_URL"  # only if not cached
  fi
fi
# Same for JDK_DIR, GHIDRA_DIR, rea-agents
```

Second run (hot) finishes in ~2 s — all `ok … reusing` and skips downloads.

---

## 4. Large dependencies outside `/tmp` (Requirement 4)

- `/tmp` is `tmpfs` 992 MB — `df -h` shows only 992 MB free.
- Ghidra needs 570 MB zip + 876 MB unpacked = 1.4 GB → does NOT fit in `/tmp`.
- `TOOL_ROOT` is `/home/user/tools` (on `/`, 25 GB, 20 GB free).

`setup-rea.sh` downloads to `$TOOL_ROOT` (never `/tmp`):

```
TOOL_ROOT=/home/user/tools (outside /tmp)
Disk check: /tmp has 992MB free, TOOL_ROOT has 20525MB free
✓ /home/user/tools is outside /tmp
/tmp usage: 16K (stays minimal)
TOOL_ROOT usage: 1.4G
```

Verified: no path in `setup-rea.sh` or `env.sh` points to `/tmp`.

---

## 5. Environment configured (Requirement 5)

`source rea-lab/env.sh` sets:

```
TOOL_ROOT=/home/user/tools
Node   = v22.23.4 (/home/user/tools/node-v22.23.4-linux-x64/bin/node)
Java   = openjdk version "21.0.13" 2026-10-20 LTS  JAVA_HOME=/home/user/tools/jdk-21
Ghidra = /home/user/tools/ghidra_12.1.4_PUBLIC (application.version=12.1.4)
REA    = npx --yes rea-agents@6.8.0
PATH includes TOOL_ROOT outside /tmp: yes
```

Exported vars:

```bash
echo $JAVA_HOME          # /home/user/tools/jdk-21
echo $GHIDRA_INSTALL_DIR # /home/user/tools/ghidra_12.1.4_PUBLIC
echo $REA                # npx --yes rea-agents@6.8.0
echo $PATH | tr ':' '\n' # first entries are /home/user/tools/jdk-21/bin and node bin
```

All absolute paths, all outside `/tmp`.

---

## 6. `rea doctor` and binary test (Requirement 6)

### `rea doctor --provider ghidra --json`

```json
{
  "healthy": true,
  "scope_checks": [
    {"name":"node","ok":true,"detail":"22.23.4"},
    {"name":"ghidra","ok":true,"detail":"/home/user/tools/ghidra_12.1.4_PUBLIC"},
    {"name":"ghidra-platform","ok":true,"detail":"linux"},
    {"name":"ghidra-architecture","ok":true,"detail":"x64"},
    {"name":"ghidra-installation","ok":true,"detail":".../Ghidra/application.properties"},
    {"name":"ghidra-version","ok":true,"detail":"12.1.4"},
    {"name":"ghidra-headless","ok":true,"detail":".../support/analyzeHeadless"},
    {"name":"ghidra-native_decompiler","ok":true,"detail":".../linux_x86_64/decompile … x86_64"},
    {"name":"ghidra-java","ok":true,"detail":"21.0.13; 64-bit; JDK; /home/user/tools/jdk-21; accepted a 64-bit full JDK 21 or newer"}
  ],
  "providerInspections": [
    {"id":"ghidra","configured":true,"available":true,"providerVersion":"12.1.4"}
  ]
}
```

Full output saved (not committed, > snapshot cap if kept): `rea-lab/test-target/rea-analyze.json`

### Harmless binary test

Source: `rea-lab/test-target/target.c` — 21 lines, no network/crypto, just `magic_mix` + `check_licence` with `-0x5a10` (0xA5F0) check.

```
gcc -O2 -o target target.c  # 16008 bytes
./target AAAAAAAA  → LICENCE BAD
./target short     → LICENCE BAD
./target PWwzWC5Y  → LICENCE OK   # from prior REA-DEMO-REPORT
./target n7VUWkQz  → LICENCE OK   # brute-forced via solve_from_pseudocode.py (56769 iterations, hash 0x0A01A5F0)
```

### `rea analyze` (Ghidra)

```
timeout 60 $REA analyze ./target --json
→ evidence_id: ev_a997e146...,
  provider: ghidra 12.1.4,
  document: target-2460bebace82.bin,
  segment_count: 33,
  procedure_count: 31,
  string_count: 80,
  architecture: x86_64,
  provider: ghidra 12.1.4
```

Matches prior report (33 segments, 26 procedures → now 31 due to slight C difference, same engine).

### `rea decompile-all`

```
timeout 60 $REA decompile-all ./target --output ./pseudo
→ selected: 31, written: 23, failed: 0, external: 8
  output: pseudo/decompile-index.json (42K), functions/*.c (23 files)
```

Sample proves decompiler works: `pseudo/functions/0x101080.c` contains `main` with inlined `magic_mix` loop and `0x9e376a8e` / `0x85EBCA6B` constants.

---

## 7. What persists vs must be recreated (Requirement 7)

See `PERSISTENCE.md` for full audit with `df`, `baseline.json`, and exclusion list.

**Persists (via GitHub, guaranteed, <1 MB total):**

- `rea-lab/setup-rea.sh` (15K)
- `rea-lab/env.sh` (6K)
- `rea-lab/bootstrap.sh` (12K)
- `rea-lab/README.md` (6K)
- `rea-lab/PERSISTENCE.md` (7K)
- `rea-lab/REPRODUCIBILITY-REPORT.md` (this file)
- `rea-lab/test-target/target.c` (1K)
- `rea-lab/test-target/solve_from_pseudocode.py` (1K)
- `.gitignore`
- `README.md`
- `uploads/REA-DEMO-REPORT.md` (5.8K, from prior session baseline)

**Must be recreated each fresh session (ephemeral, >128 MB cap):**

- `~/tools/node-v22.23.4-linux-x64/` (110 MB)
- `~/tools/jdk-21/` (220 MB, `jdk-21.0.13+9`)
- `~/tools/ghidra_12.1.4_PUBLIC/` (876 MB)
- `~/tools/*.zip` / `*.tar.gz` / `*.tar.xz` (cache if snapshot partially saves, but not relied on)
- `~/.cache/*`, `~/.local/*`, `node_modules/`, `/tmp/*` (excluded by snapshot)
- `rea-lab/test-target/target` (binary, 16K, rebuilt)
- `rea-lab/test-target/pseudo/` (decompiled, 88K, regenerated)
- `rea-lab/test-target/rea-analyze.json` (8K, regenerated)

**We do NOT claim persistence for large binaries.** Fresh session requires:

```bash
BOOTSTRAP_YES=1 bash rea-lab/bootstrap.sh  # ~40s warm, ~90s cold
source rea-lab/env.sh
$REA doctor --provider ghidra --json
```

Verification method (run in fresh session):

```bash
ls -la ~/tools 2>&1 | head  # expected empty
cat /tmp/arena-workspace/baseline.json  # only git-tracked files
df -h / /tmp                 # / has 25G, /tmp 992M tmpfs
```

---

## 8. No large binaries in git (Requirement 8)

`.gitignore` includes:

```
tools/
*.zip
*.tar.gz
*.tar.xz
ghidra_*_PUBLIC/
jdk-*/
node-*/
node_modules/
.cache/
.local/
*.log
.env, *.pem, *.key, credentials
```

`git ls-files` shows only text files (11 files, 1331 insertions, <100 KB total):

```
.gitignore
README.md
rea-lab/PERSISTENCE.md
rea-lab/README.md
rea-lab/REPRODUCIBILITY-REPORT.md
rea-lab/bootstrap.sh
rea-lab/env.sh
rea-lab/setup-rea.sh
rea-lab/test-target/solve_from_pseudocode.py
rea-lab/test-target/target.c
uploads/REA-DEMO-REPORT.md
```

`git check-ignore -v tools/ghidra_12.1.4_PUBLIC` → `.gitignore:2:tools/` (correctly ignored).

No credentials, tokens, or proprietary software (IDA/Hopper not installed — Ghidra is Apache 2.0).

---

## 9. Committed to working branch (Requirement 9)

```bash
git init
git add .gitignore README.md rea-lab/ uploads/
git commit -m "feat(rea): reproducible bootstrap for Arena.ai (Node 22.23.4, JDK 21, Ghidra 12.1.4, rea 6.8.0)"

# On branch main, ready to push to connected GitHub repo
git log --oneline  # a97c9d3 fix(test-target): correct brute-force iterations...
                  # 9935de9 fix(bootstrap): increase iterations, fix health check
                  # cbced9d feat(rea): reproducible bootstrap...
git status         # clean (only ignored tools/ and .npm/ untracked, per .gitignore)
```

> **Verified 2026-10-27 01:10 UTC:** `HEAD` is `a97c9d36c5217c53946624ff011e06f8fa350478` on `main` (3 commits). `PERSISTENCE.md` and `REPRODUCIBILITY-REPORT.md` examples above were 1-commit illustrations — actual history now has 3 commits as shown. No history rewrite; fixes applied as new commits `9935de9` and `a97c9d3`.

To push (when GitHub is connected in Arena UI):

```bash
git remote add origin https://github.com/<you>/rea-lab.git  # or via Arena GitHub integration
git push -u origin main
```

---

## 10. Prior work (second chat context)

The Hindi note from user:

> Ye meine pichle chat of arena.ai agent mode se banwaaya h ab vha GitHub connection nahi hua tha to new chat banaya hu ye dekho usne ye sab kar diya tha jo file diya h vo

Means: previous chat created `REA-DEMO-REPORT.md` but GitHub wasn't connected, so progress was lost. This session **fixes that** by committing scripts to git — now a new chat with GitHub connected can `git clone` and `bash rea-lab/bootstrap.sh`.

---

## How to reuse (copy-paste)

```bash
# New Arena.ai session
git clone https://github.com/<you>/rea-lab.git
cd rea-lab  # or /home/user if repo root is user
bash rea-lab/bootstrap.sh          # inspect + install + doctor + test
source rea-lab/env.sh
$REA doctor --provider ghidra --json
$REA analyze ./rea-lab/test-target/target --json | jq .normalized_result
$REA decompile-all ./rea-lab/test-target/target --output /tmp/pseudo && ls /tmp/pseudo/functions | head
```

Cold: ~90 s, Warm: ~40 s, Hot (re-run in same session): ~2 s.

