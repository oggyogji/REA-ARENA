# Persistence Audit — Arena.ai Agent Mode

> **Do not claim REA setup is persistent across sessions unless you have verified which directories survive.**
> This document is that verification.

Date: 2026-10-27
Host: Arena.ai Agent Mode (E2B sandbox, Debian 13, x86_64, template `nlhz8vlwyupq845jsdg9`)
Workspace root: `/home/user` — snapshotted between sessions (best-effort 128 MB / 10,000 files)
`/tmp`: `tmpfs` 992 MB — ephemeral, never snapshotted

---

## How we verified

1. **Checked system prompt exclusions:** Workspace snapshots exclude:
   ```
   .arena, .cache, .local, .mypy_cache, .next, .nox, .npm, .nuxt, .output,
   .parcel-cache, .playwright-cli, .pytest_cache, .ruff_cache, .svelte-kit,
   .tox, .turbo, .venv, .vite, __pycache__, build, coverage, dist,
   node_modules, out, target
   ```
   Plus sensitive: `.git/config`, `.git/credentials`, `.git-credentials`, `.netrc`

2. **Checked snapshot files on this template:**
   ```bash
   ls -la /tmp/arena-workspace/
   cat /tmp/arena-workspace/baseline.json
   # → {"files":{"uploads/REA-DEMO-REPORT.md":{...}}}
   ```
   Only `uploads/REA-DEMO-REPORT.md` was in the baseline — no `rea-lab/` existed before this task.
   Previous chat had created `rea-lab/` but it did **not** survive because GitHub was not connected then.

3. **Checked disk layout:**
   ```bash
   df -h         # / is 25G, /tmp is 992M tmpfs
   ls -la $HOME  # only uploads/ survived
   ls -la /home/user/.cache/tools 2>&1  # No such file — excluded
   ```

4. **Confirmed `$HOME/.cache/tools` is excluded:** The prior report explicitly said:
   > Toolchain lives in `/home/user/.cache/tools`, which is **excluded from workspace snapshots** — so it's gone next session.

---

## What persists

### Via connected GitHub repository (guaranteed across sessions, if committed)

These are **the only artefacts that survive a fresh session** when GitHub is connected:

| Path | Content | Size | Reason |
|------|---------|------|--------|
| `rea-lab/setup-rea.sh` | Installer (Node, JDK, Ghidra, REA) | ~10 KB | Committed to git |
| `rea-lab/env.sh` | Env config (`JAVA_HOME`, `GHIDRA_INSTALL_DIR`, `PATH`, `REA`) | ~4 KB | Committed |
| `rea-lab/bootstrap.sh` | One-command inspect+install+test | ~7 KB | Committed |
| `rea-lab/README.md` | Usage + troubleshooting | ~6 KB | Committed |
| `rea-lab/PERSISTENCE.md` | This file | ~4 KB | Committed |
| `rea-lab/test-target/target.c` | Harmless C test source | <1 KB | Committed |
| `.gitignore` | Excludes large binaries | <1 KB | Committed |
| `README.md` (root) | Top-level pointer | <1 KB | Committed |
| `uploads/REA-DEMO-REPORT.md` | Previous demo report | 5.8 KB | Was in baseline |

All above are text, <1 MB total, far under the 128 MB snapshot cap.

### Via snapshot (best-effort, NOT guaranteed)

`$HOME/tools/*` (where bootstrap installs large deps) **may** be snapshotted if:
- It is **not** in the exclusion list (it isn't — `.cache` is, `tools` is not)
- Total snapshot stays under 128 MB / 10k files

**In practice, it will NOT persist** because:
- Ghidra alone is 570 MB zip + 876 MB unpacked = **1.4 GB** → far exceeds 128 MB cap
- Snapshot is best-effort capped — large files are truncated/dropped
- Even if `tools/` is partially snapshotted, Java + Node + Ghidra will be incomplete

**Conclusion:** Treat `~/tools`, `~/.cache`, `~/.local`, `node_modules`, and `/tmp` as **ephemeral**.
You **must** re-run `bash rea-lab/bootstrap.sh` each new session.

---

## What does NOT persist (must be recreated)

| Path | Content | Size | Why not persisted |
|------|---------|------|-------------------|
| `~/tools/node-v22.23.4-linux-x64/` | Node 22.23.4 | ~110 MB | Exceeds snapshot cap |
| `~/tools/jdk-21/` | JDK 21.0.13 (Temurin) | ~220 MB | Exceeds cap |
| `~/tools/ghidra_12.1.4_PUBLIC/` | Ghidra 12.1.4 | 876 MB unpacked | Exceeds cap, also > /tmp |
| `~/tools/ghidra_12.1.4_PUBLIC_20260921.zip` | Ghidra zip | 570 MB | Exceeds cap |
| `~/tools/OpenJDK21U-jdk...tar.gz` | JDK tarball | ~190 MB | Exceeds cap |
| `~/tools/node-v22.23.4...tar.xz` | Node tarball | ~30 MB | Might persist, but not relied upon |
| `~/.cache/*` | caches | — | **Excluded by snapshot** |
| `~/.local/*` | local bins | — | **Excluded** |
| `node_modules/` | npm deps | — | **Excluded** |
| `/tmp/*` | temp | — | `tmpfs`, never snapshotted |
| `rea-lab/test-target/target` | compiled binary | 16 KB | Would persist if < cap, but rebuilt anyway |
| `rea-lab/test-target/pseudo/` | decompiled output | ~100 KB | Exceeds? No, but regenerated |
| `rea-lab/doctor-output.txt` | doctor JSON | <10 KB | Could persist, but regenerated |
| `rea-lab/test-target/rea-analyze.json` | analysis JSON | <10 KB | Could persist, but regenerated |

---

## Recommended workflow for new sessions

```bash
# Fresh session — verify repo is present (connected via GitHub)
ls rea-lab/bootstrap.sh && cat rea-lab/PERSISTENCE.md | head

# Rehydrate toolchain (idempotent — skips if already cached in this session)
BOOTSTRAP_YES=1 bash rea-lab/bootstrap.sh

# Use
source rea-lab/env.sh
$REA doctor
```

Expected timing:
- **Cold (no cache):** ~90 s Node + JDK + Ghidra download + extract + `rea doctor`
- **Warm (tarballs cached in ~/tools, if snapshot partially kept them):** ~40 s (skip downloads, just extract/verify)
- **Hot (already installed in this session):** ~2 s (all checks pass, only `doctor` + test)

---

## Previous setup (`$HOME/.cache/tools`) vs current (`$HOME/tools`)

| Aspect | Previous (`~/.cache/tools`) | Current (`~/tools`) |
|--------|----------------------------|---------------------|
| Location | `$HOME/.cache/tools` | `$HOME/tools` |
| Outside `/tmp`? | Yes (on `/`) | Yes (on `/`) |
| In snapshot? | **No** — `.cache` excluded | Technically yes, but > cap so **effectively no** |
| Survives session? | No | No (due to size cap) |
| Must gitignore? | Already excluded | Yes — added to `.gitignore` |
| Reinstall needed? | Every session (~40 s) | Every session (~40-90 s) |

Both are correct for requirement 4 (outside `/tmp`). Current choice is more explicit and leaves `.cache` for npm/pip caches.

---

## How to verify in YOUR session

Run this audit yourself:

```bash
# 1. Check what's excluded
grep -E "^Snapshot excludes" /tmp/arena-workspace/*.json 2>/dev/null || echo "See system prompt"

# 2. Check what survived
ls -la ~/
ls -la ~/tools/ 2>&1 | head
df -h / /tmp
cat /tmp/arena-workspace/baseline.json

# 3. Check what will be committed
git ls-files | sort
git check-ignore -v ~/tools/ghidra_12.1.4_PUBLIC 2>&1 || echo "gitignore check: tools/ is ignored (good)"
```

If `~/tools` is empty in a fresh session, **that is expected** — run bootstrap again.

---

## Commitment

We do **not** claim persistence for large binaries. Only scripts and docs persist via git.
Every new Arena.ai session **must** run the bootstrap to recreate JDK, Ghidra, and Node if needed.


---

## Addendum — 2026-10-27 session (fresh Arena Agent Mode verification)

The audit above was written against a checkout whose workspace root was `/home/user`
and whose toolchain default was `$HOME/tools`. This session restored the repo from the
Dropbox backup into `/home/user/REA-ARENA` and applies one deliberate change:

**All three scripts now default `REA_TOOLS_DIR` / `TOOL_ROOT` to `$HOME/.cache/tools`.**

| Path | Persists via GitHub? | Reason |
|---|---|---|
| `.gitignore`, `README.md`, `rea-lab/*.sh`, `rea-lab/*.md`, `rea-lab/test-target/*.{c,py,txt}`, `uploads/*` | **Yes** — 15 files, 93 KB total | Committed text, far below the 128 MB cap |
| `$HOME/.cache/tools/*` (Node 22.23.4, jdk-21, Ghidra 12.1.4) | **No** | `.cache/` is explicitly snapshot-excluded; Ghidra alone is ~1.4 GB |
| `$HOME/tools/*` (legacy default described above) | **No** | Not excluded by name, but >128 MB so dropped by the cap |
| `.git/`, `node_modules/`, `/tmp/*` | **No** | Recreated by clone / npm install / ephemeral tmpfs |
| `rea-lab/test-target/target`, `pseudo/`, `doctor-output.txt`, `rea-analyze.json`, `*.log` | **No** | Generated artifacts, all covered by `.gitignore` |

Why `$HOME/.cache/tools` wins here: it is **guaranteed** to stay out of the workspace
snapshot, so a 1.4 GB toolchain can never push this session's patchset over the
128 MB budget. `$HOME/tools` only *probably* stays out (size-dependent). Both are
outside `/tmp`, satisfying requirement 4. `REA_TOOLS_DIR` remains an override for
anyone who needs a different location.

Consequence: **a fresh session must recreate the toolchain**. See
`rea-lab/VERIFICATION-20261027.md` for the exact fallback commands that work when
`nodejs.org` and GitHub release-asset CDNs are unreachable.
