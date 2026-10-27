# Full verification — 2026-10-27 (fresh Arena.ai Agent Mode session)

Repo: `https://github.com/oggyogji/REA-ARENA.git`
Workspace: `/home/user/REA-ARENA`
Session branch: `arena/ed0c4164-rea-arena` (fixed for this session)
Baseline at inspection: `2cde1c2d6292e4723eb9b06e5dd907fd798dd046`

Scope: verify the restored REA-ARENA lab **without rebuilding anything that is
already healthy**. No third-party software was reverse-engineered; the only binary
compiled and executed was this repo's own harmless `rea-lab/test-target/target.c`.

---

## 1. Git inspection

```
git status                    -> On branch arena/ed0c4164-rea-arena; clean
git branch -a                 -> arena/ed0c4164-rea-arena, main,
                                 remotes/origin/HEAD -> origin/main,
                                 remotes/origin/main
git log --oneline -5          -> 2cde1c2 Initial commit      (only commit)
git remote -v                 -> origin https://github.com/oggyogji/REA-ARENA.git
git ls-remote origin          -> 2cde1c2... HEAD
                                 2cde1c2... refs/heads/main
```

The repository was **not literally empty** (1 ref) but was an effective blank:
`git ls-files` returned only `README.md` (12 bytes, `# REA-ARENA`). GitHub repo
metadata showed `created_at 2026-10-27T01:36:18Z`, `size: 0`. The previously
reported HEADs `8315c49` and `2aff78b` returned **HTTP 422 "No commit found"**
from the GitHub API — they are no longer on the remote.

## 2. Restore from Dropbox

The Dropbox connector was enabled and both recovery artifacts existed at the
account root:

| File | Size | SHA-256 content hash (Dropbox) |
|---|---|---|
| `rea-lab-backup-20261027.zip` | 33,763 B | `2443a76845d952fc224429c63cd519273eecf1df04e85a4baa685ea4aa4ecbda` |
| `rea-lab-bundle-20261027.bundle` | 26,558 B | `3fa5c47bc4024e7f9cf2279a2015395dddcf25f1e899dfe8dad66e8e998bea62` |

Direct `curl` to `*.dl.dropboxusercontent.com` is blocked by this sandbox, so the
files were pulled in through the Dropbox connector (`get_file_content`), which
staged them under `dropbox/` in the workspace. The zip was extracted into the
checkout root (the backup assumed a `/home/user` repo root; this session's repo
root is `/home/user/REA-ARENA`) and staged with:

```
git add .gitignore README.md rea-lab uploads
```

`git bundle verify` on the bundle reported *"The bundle records a complete
history"* with head `8315c49a5a9e56ca71d69f2d43701813e165e6b7` —
*"feat(rea): reproducible bootstrap for Arena.ai ... - restored after snapshot
loss (2nd restore)"*. It was fetched into a local-only ref
`refs/remotes/backup/8315c49` for reference; it is **not** pushed.

`dropbox/` and `*.bundle` were added to `.gitignore` so the recovery artifacts
never enter the patchset.

## 3. Tracked files (step 3)

`git ls-files` — **15 files, 93 KB total**:

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
rea-lab/test-target/test-output.txt
uploads/REA-DEMO-REPORT.md
uploads/Screenshot_20261027-064745.png   (0 B in backup)
uploads/Screenshot_20261027-064755.png   (0 B in backup)
uploads/Screenshot_20261027-071220.png   (0 B in backup)
```

All five required files are **TRACKED**:
`rea-lab/bootstrap.sh`, `rea-lab/setup-rea.sh`, `rea-lab/env.sh`,
`rea-lab/PERSISTENCE.md`, `rea-lab/REPRODUCIBILITY-REPORT.md`.

Generated/log artifacts (`rea-lab/doctor-output.txt`,
`test-target/rea-analyze.json`, `*.log`, `test-target/target`, `pseudo/`) are
excluded by `.gitignore` — they exist on disk from the backup but are not tracked.
Note the restored `rea-analyze.json` is a **truncated 2,000-byte fragment** of the
original analysis JSON, not valid complete JSON.

### Deliberate changes vs. the backup

- `rea-lab/bootstrap.sh`, `rea-lab/setup-rea.sh`, `rea-lab/env.sh`: default
  `TOOL_ROOT` / `REA_TOOLS_DIR` changed from `$HOME/tools` to
  **`$HOME/.cache/tools`** so large deps live in a snapshot-excluded directory
  and cannot push the patchset past 128 MB. `REA_TOOLS_DIR` still overrides.
- `PERSISTENCE.md`: appended a dated addendum reconciling the old `$HOME/tools`
  documentation with the new default.
- `.gitignore`: appended `dropbox/` and `*.bundle`.
- This file added.

## 4. Toolchain check (step 4) — initially UNHEALTHY

```
node        v22.22.3 (system)         -> want 22.23.4
java        NOT FOUND                 -> want JDK 21
gcc         12.2.0, python3 3.11.2   -> OK
~/.cache/tools/node-v22.23.4-linux-x64/bin/node              missing
~/.cache/tools/jdk-21/bin/java                               missing
~/.cache/tools/ghidra_12.1.4_PUBLIC/Ghidra/application.properties  missing
~/tools/...                                                  missing (dir absent)
```

Sandbox outbound allowlist: `github.com`, `codeload.github.com`,
`api.github.com`, `registry.npmjs.org`, `pypi.org`,
`files.pythonhosted.org`. Confirmed **blocked**: `nodejs.org`,
`release-assets.githubusercontent.com` / `objects.githubusercontent.com`
(where every GitHub release asset 302-redirects), and the Dropbox CDN.

## 5. Bootstrap (step 5) — attempted, partial

**Attempt 1** — `BOOTSTRAP_YES=1 bash rea-lab/bootstrap.sh`, unmodified sources:

```
[setup-rea] REA setup starting — TOOL_ROOT=/home/user/.cache/tools (outside /tmp)
[setup-rea] Step 1/4 — Node.js
[setup-rea] Downloading Node 22.23.4 from nodejs.org ...
curl: (35) OpenSSL SSL_connect ... nodejs.org:443
GnuTLS: The TLS connection was non-properly terminated.
  ✗ Failed to download Node
EXIT: 1
```

To get as far as possible, Node and Java were rehydrated **from the two allowed
registries** into `$HOME/.cache/tools` (not `/tmp`, not `~/tools`):

```bash
T=$HOME/.cache/tools
curl -fL -o "$T/node-linux-x64-22.23.4.tgz" \
  https://registry.npmjs.org/node-linux-x64/-/node-linux-x64-22.23.4.tgz   # 51,634,932 B
mkdir -p "$T/node-v22.23.4-linux-x64"
tar -xzf "$T/node-linux-x64-22.23.4.tgz" -C "$T/node-v22.23.4-linux-x64" --strip-components=1
# -> $T/node-v22.23.4-linux-x64/bin/node  == v22.23.4

curl -fL -o "$T/jdk4py-21.0.8.2.whl" \
  https://files.pythonhosted.org/packages/a2/61/f3b5936908ff6de66c61aef69bf1074cb468fb883f5a0bb9e15e67a6b484/jdk4py-21.0.8.2-py3-none-manylinux_2_17_x86_64.whl  # 33,794,570 B
unzip -q "$T/jdk4py-21.0.8.2.whl" -d "$T/jdk4py-extract"
mv "$T/jdk4py-extract/jdk4py/java-runtime" "$T/jdk-21"
# -> $T/jdk-21/bin/java == openjdk version "21.0.8" (Temurin) — JRE, no javac
```

**Attempt 2** — same bootstrap command, now with the cache pre-populated:

```
✓ Node tarball already extracted at /home/user/.cache/tools/node-v22.23.4-linux-x64 — reusing
✓ Installed Node v22.23.4 satisfies REA requirements
✓ Found JDK 21 at /home/user/.cache/tools/jdk-21 (openjdk 21.0.8) — reusing
  javac not found (JRE only)
[setup-rea] Downloading Ghidra 12.1.4 (570 MB) ...
curl: (35) ... release-assets.githubusercontent.com:443
  ✗ Failed to download Ghidra
EXIT: 1
```

The "skip if already healthy" behaviour is confirmed for Node and JDK. Zero-byte
partial downloads were removed. **`setup-rea.sh` never reached step 4/4
(rea-agents install)**, but `npx --yes rea-agents@6.8.0` works from the npm
registry directly (`--version` -> `6.8.0`).

**Root blocker:** Ghidra 12.1.4's only pinned source is
`https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip`
(569,649,598 B, asset id 579530646). Both `github.com` and
`api.github.com/repos/.../releases/assets/579530646` 302-redirect to
`release-assets.githubusercontent.com`, which this sandbox resets. No
allowlisted mirror exists. This is not a script defect — it is a network policy
limitation of this session.

## 6. Doctor (step 6)

`source rea-lab/env.sh` resolved:

```
TOOL_ROOT           = /home/user/.cache/tools
Node                = v22.23.4
Java                = openjdk 21.0.8   JAVA_HOME=/home/user/.cache/tools/jdk-21
Ghidra              = NOT FOUND        GHIDRA_INSTALL_DIR=<unset>
REA                 = npx --yes rea-agents@6.8.0
```

`source rea-lab/env.sh && npx --yes rea-agents@6.8.0 doctor --provider ghidra --json`
→ exit **1**:

```json
{"healthy": false, "environment_healthy": false,
 "scope": {"mode":"explicit","clients":[],"providers":["ghidra"],"skill":false,"target":null},
 "scope_checks": [
   {"name":"node","ok":true,"classification":"healthy","detail":"22.23.4"},
   {"name":"ghidra","ok":false,"classification":"missing_analysis_engine",
    "detail":"GHIDRA_INSTALL_DIR is not set",
    "remediation":"Set GHIDRA_INSTALL_DIR to an extracted Ghidra 12.1.x release directory."}
 ],
 "providerInspections": [{"id":"ghidra","configured":false,"available":false,
   "providerVersion":null,"checks":[{"name":"configuration","ok":false,
   "code":"not_configured","detail":"GHIDRA_INSTALL_DIR is not set"}]}]}
```

Expected `healthy: true` with Ghidra 12.1.4 — **NOT ACHIEVED**. The Node half is
now green; the Ghidra half is blocked by step 5. `GHIDRA_INSTALL_DIR` was left
unset rather than pointed at a stub, so the doctor result is honest.

## 7. Harmless test target (step 7)

Source `rea-lab/test-target/target.c` exists; compiled with
`gcc -O2 -o rea-lab/test-target/target` (16,136 B,
sha256 `afa863cdae02cad79fbf620b6d04fa061bfc7532d02147472a844d3435c18538`).

| Command | Result |
|---|---|
| `./rea-lab/test-target/target PWwzWC5Y` | **`LICENCE OK`** |
| `./rea-lab/test-target/target AAAAAAAA` (negative control) | `LICENCE BAD` |
| `python3 rea-lab/test-target/solve_from_pseudocode.py` | `recovered valid key: 'n7VUWkQz' at iteration 56769`, `hash = 0x0A01A5F0 low16 = 0xA5F0` |
| recovered `n7VUWkQz` re-tested against binary | **`LICENCE OK`** |
| `$REA analyze ./rea-lab/test-target/target --json` | **exit 1**, `{"error":"Analysis failed","code":"provider_unavailable",...}`, Ghidra rejection `not_configured` |

**Segments 33 was NOT reproduced live.** It is a documented result from the
earlier session (`uploads/REA-DEMO-REPORT.md:59`,
`rea-lab/REPRODUCIBILITY-REPORT.md:168`, `rea-lab/README.md:64`), and the backed-up
`rea-analyze.json` is only a truncated 2,000-byte fragment. No live SEGMENT count
can be claimed until Ghidra 12.1.4 is installed.

## 8. Persistence (step 8)

**Persists via GitHub** — 15 text files, 93 KB total (all scripts <100 KB):
`.gitignore`, root `README.md`, `rea-lab/*.sh` (bootstrap, setup-rea, env),
`rea-lab/*.md` (README, PERSISTENCE, REPRODUCIBILITY-REPORT, this file),
`rea-lab/test-target/{target.c,solve_from_pseudocode.py,test-output.txt}`,
`uploads/REA-DEMO-REPORT.md` and the three 0-byte screenshot placeholders.

**Must be recreated per session:**
- `$HOME/.cache/tools/` — Node 22.23.4, jdk-21, Ghidra 12.1.4 (~1.4 GB with
  Ghidra). `.cache/` is snapshot-excluded by design.
- `$HOME/tools/` — legacy default documented in the original PERSISTENCE.md;
  also non-persistent (size-capped).
- `.git/` — recreated by `git clone` (and `.git/config` is excluded).
- `node_modules/`, `/tmp/*`, compiled `test-target/target`, `pseudo/`,
  `doctor-output.txt`, `rea-analyze.json`, `*.log` — generated/ignored.

See `rea-lab/PERSISTENCE.md` (including its 2026-10-27 addendum) for the full audit.

## 9. Blockers and next steps

1. **Ghidra 12.1.4 cannot be downloaded in this sandbox.** `github.com` and
   `api.github.com` release-asset requests redirect to a blocked CDN. Needed for
   `doctor healthy=true`, `providerVersion 12.1.4`, and the live
   `rea analyze` / segments-33 check. Fix options: run the setup in an environment
   that permits `release-assets.githubusercontent.com`, or supply the
   `ghidra_12.1.4_PUBLIC_20260921.zip` out-of-band and re-run bootstrap (it skips
   the download when the zip is cached in `$HOME/.cache/tools`).
2. **nodejs.org and Adoptium release assets are also blocked.** Worked around
   using the npm and PyPI registries. Consequence: the Java runtime is
   `21.0.8` and **JRE-only (no `javac`)**, not the pinned Temurin JDK
   `21.0.13+9`. Doctor does not require `javac`, but a full Ghidra setup might.
3. **Branch policy:** this session is pinned to `arena/ed0c4164-rea-arena`; it
   cannot push to or switch to `main`. The restored content is pushed to the
   session branch and a PR to `main` is the route for landing it on the default
   branch. `main` on the remote still points at the placeholder `2cde1c2` until
   that PR is merged.
EOF
echo "wrote verification report: $(wc -c < rea-lab/VERIFICATION-20261027.md) bytes"
## 10. Push result (step 9)

GitHub is **Connected** (`gh auth status` -> logged in as `oggyogji`). This
session is pinned to `arena/ed0c4164-rea-arena`, so the requested
`git push -u origin main` was replaced by a push to the session branch (pushing
to `main` from a different branch is not permitted here).

```
$ git push -u origin arena/ed0c4164-rea-arena
To https://github.com/oggyogji/REA-ARENA.git
 * [new branch]      arena/ed0c4164-rea-arena -> arena/ed0c4164-rea-arena
branch 'arena/ed0c4164-rea-arena' set up to track 'origin/arena/ed0c4164-rea-arena'.
PUSH_EXIT=0
```

- Remote URL: `https://github.com/oggyogji/REA-ARENA.git`
- Restore commit: `31e00d9e42b85e62d69356cb2958b734a4247954`
- `git ls-remote origin` after push:
  - `refs/heads/arena/ed0c4164-rea-arena` -> `31e00d9e42b85e62d69356cb2958b734a4247954`
  - `refs/heads/main` / `HEAD` -> `2cde1c2d6292e4723eb9b06e5dd907fd798dd046`
- Pull request to default branch: **https://github.com/oggyogji/REA-ARENA/pull/1**
  (open; `main` stays at the placeholder until merged).
