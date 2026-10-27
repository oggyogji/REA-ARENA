# REA live in the sandbox — what actually ran

**Date:** 2026-10-27 · **Version:** `rea-agents` 6.8.0 · **Engine:** Ghidra 12.1.4 · **Host:** Debian 13, x86_64

This is not a summary of a blog post. Every number and code block below is real output from
this workspace.

---

## 1. Can it run here? Yes — with two caveats

| Requirement | Sandbox status |
|---|---|
| Node `^22.23.4 \|\| ^24.22.1 \|\| >=26.12.1` | Shipped with v20 → **I installed Node 22.23.4** |
| `rea-agents` on npm (49 MB unpacked, 42 deps) | Installed, 176 packages, 13s |
| Ghidra `12.1.x` + JDK 21 | Neither present → **installed JDK 21.0.13 + Ghidra 12.1.4 (570 MB zip, 876 MB unpacked)** |
| IDA Pro / Hopper | **Not available** — proprietary, licensed. Ghidra is the free substitute and is what I used. |
| `/tmp` | Only 992 MB tmpfs → everything moved to `/home/user/.cache/tools` |

`rea doctor` after setup:

```
- name: ghidra                 ok: true   healthy  /home/user/.cache/tools/ghidra_12.1.4_PUBLIC
- name: ghidra-platform        ok: true   healthy  linux
- name: ghidra-architecture    ok: true   healthy  x64
- name: ghidra-installation    ok: true   healthy  .../Ghidra/application.properties
- name: ida-registration       ok: false  missing_analysis_engine
- name: hopper                 ok: false  missing_analysis_engine
```

## 2. The important caveat about "running it for you"

REA is fundamentally **an MCP server that gives an AI agent reverse-engineering powers**.
I'm not an MCP client inside this sandbox, so I can't literally hand myself the tools.

What I *can* do — and did — is drive **the same CLI that the MCP server exposes**, which is
the identical provider layer:

```
rea analyze                   rea decompile-all          rea function
rea inspect-artifact          rea decompile              rea list-procedures
rea analyze-web-bundle        rea analyze-javascript-application
rea inspect-android-package   rea extract-firmware       rea doctor
```

So functionally: **yes, I can do REA tasks for you.** I just do the agent's job myself —
read the evidence, reason over it, write and test the reconstruction — instead of paying a
model API to do it. Arguably better, since I check the claims.

## 3. The test target

I wrote a small C program with a fake "licence key" check and compiled it normally
(`gcc -O2`, not stripped, 16,008 bytes) — a deliberately small but genuinely non-trivial
target: a hash-mixing loop with a truncated 16-bit comparison.

`rea analyze ./target` → **12.5 s**:

```json
"segments": 33, "procedure_count": 26, "string_count": 76,
"provider": { "id": "ghidra", "version": "12.1.4" },
"confidence": "derived", "authority": "shipped-artifact"
```

`rea decompile-all ./target --output ./pseudo` → **12.8 s**, 19 function files written.

## 4. What Ghidra + REA recovered

`pseudo/functions/0x101080.c` — decompiled `main`, with `check_licence` and `magic_mix`
inlined. Constants folded, algorithm intact:

```c
if (7 < sVar2) {
  pbVar3 = __s + sVar2;
  uVar4 = 0x9e376a8e;                       // = 0x9E3779B9 ^ 0x1337
  do {
    bVar1 = *__s; __s = __s + 1;
    uVar4 = (bVar1 ^ uVar4) * -0x7a143595;   // * 0x85EBCA6B
    uVar4 = (uVar4 ^ uVar4 >> 0xd) + 0x165667b1;
  } while (pbVar3 != __s);
  __s_00 = "LICENCE OK";
  if ((short)uVar4 != -0x5a10) {             // low 16 bits == 0xA5F0
    __s_00 = "LICENCE BAD";
  }
}
```

Note the evidence quality: every file carries its own provenance header — name, address,
exact inclusive range, non-contiguity flags, provider version, the analysis-profile digest,
and an explicit limitations list. That "seen vs inferred vs unknown" discipline I mentioned
is real and visible in the output, not marketing.

## 5. Proof the reconstruction is correct

From the pseudocode alone (not the original source), I rewrote the hash in Python
(`solve_from_pseudocode.py`) and brute-forced an 8-char input whose low 16 bits hit `0xA5F0`:

```
recovered valid key: 'PWwzWC5Y'
  hash = 0x4096A5F0  low16 = 0xA5F0
```

Then fed it to the **original, unmodified binary**:

```
$ ./target PWwzWC5Y
LICENCE OK

$ ./target AAAAAAAA        # control
LICENCE BAD

$ ./target short           # length gate respected
LICENCE BAD
```

End-to-end: compiled artifact → evidence → recovered algorithm → new implementation →
verified against the real thing. That is exactly the workflow REA exists for.

## 6. Honest limits I hit or confirmed

- **It is not magic and not free of setup.** 570 MB of Ghidra, a Node upgrade, and 25 min of
  my time to get to a first decompile. The "one `npx` command" videos skip this.
- **Pseudocode ≠ source.** Variable names, comments, structure: gone. `magic_mix` was inlined
  and its name lost; I recovered *behaviour*, not the author's file.
- **Stripped + obfuscated binaries are much harder.** This target was unstripped with a
  symbol table. Strip it, add control-flow flattening, and the same task becomes research.
- **Ghidra sessions are ephemeral.** Every provider query re-imports the artifact; annotations
  don't survive a cancel. Fine for CLI use, noticeable on big binaries.
- **No commercial engines here.** No IDA, no Hopper, no JADX, no apktool, no rizin, no
  Playwright browser, no adb. Those targets are unsupported in this sandbox today.

## 7. Reusing this

Toolchain lives in `/home/user/.cache/tools`, which is **excluded from workspace snapshots** —
so it's gone next session. Reinstall in ~40 s:

```bash
bash /home/user/rea-lab/setup-rea.sh
source /home/user/rea-lab/env.sh     # sets PATH, JAVA_HOME, GHIDRA_INSTALL_DIR, $REA
$REA doctor
```

Files in this folder: `target.c`, `target` (the binary), `pseudo/` (all decompiled functions
+ index + journal), `manifest.json`, `solve_from_pseudocode.py`, `setup-rea.sh`, `env.sh`.
