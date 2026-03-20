# PRD / Bootstrap Spec — SNES Music Constraint/Export Tool

## Status: Pre-implementation | v0.1

> **Normative sections:** 1–8, 12–14, 17. These define the product constraints, contracts, and exit criteria.
> **Operational guidance:** 0, 9–11, 15–16, 18. These describe workflow, tooling, session practices, and open questions.
> If guidance conflicts with normative sections, normative sections win.

---

## 0. How to read this document

This file is the **primary bootstrap document** for the project. It lives at the repo root and is the first thing any agent — human or AI — reads. Other key context lives in `CLAUDE.md`, `.claude/rules/`, and `docs/decisions/` — but this document establishes the project's goals, constraints, and operating model.

There are three roles:

| Role | Runtime | Identity | Repo access |
|---|---|---|---|
| **Human operator** | Physical person | The composer-developer. Comfortable with REAPER, DSP, web toolchains, research workflows. Not an assembly programmer. Drives scope. Copy-pastes instructions between PM and CC. Tests artifacts in REAPER. Runs `/compact` when PM recommends it. Does not commit or run build/test commands — those go through CC. | Copy-paste, REAPER testing, `/compact` |
| **Product architect (PM)** | Claude web/app session | Clones this repo. Maintains cross-session project understanding. Gives instructions to the engineer. Reviews each pass. Owns decisions and spec integrity. | Read only (clone/pull) |
| **Engineer** | Claude Code (CC) | Executes implementation inside the repo. Runs all build, test, and CLI commands. Relies on filesystem context, not chat memory. | Read + write (sole committer) |

If you are the **product architect** and your first instruction was something like _"You are the product architect, please clone [link] and begin"_ — read this entire document now before doing anything else.

---

## 1. Purpose

Build a **REAPER-first authoring toolchain** for SNES music composition that lets the user compose in REAPER's piano roll, validates the composition against SNESGSS/SNES audio constraints, and exports a deterministic package suitable for downstream SNES integration.

This is not a generic SNES soundchip VST. It is a **constraint-aware authoring and export harness** for one engine path first: **SNESGSS**.

SNESGSS defines a workable MIDI-facing subset and has documented import assumptions, making it the right first target. PVSnesLib's audio path is tracker-centric and would require a different adapter.

---

## 2. Product goals

1. Let the composer stay inside REAPER for sequencing.
2. Surface SNES-native constraints **during** authoring, not after the fact.
3. Produce repeatable exports from a known subset of REAPER project semantics.
4. Make the development harness resumable across Claude Code sessions without needing to restate project context.
5. Keep the system simple enough that one technically strong user plus Claude Code can iterate on it.

---

## 3. Non-goals for v0.1

1. Not a cross-DAW product.
2. Not a cycle-accurate SNES audio emulator/VST.
3. Not a universal exporter for every SNES music engine.
4. Not a direct compiler for arbitrary REAPER automation, plugin chains, or audio effects.
5. Not a fully headless `.gsm` authoring pipeline unless the `.gsm` structure proves tractable; v0.1 should not assume that up front.

---

## 4. Target user

**Primary user:** one developer-composer already comfortable with REAPER piano-roll authoring and willing to work inside an explicitly constrained SNES subset.

---

## 5. v0.1 scope

### 5.1 Authoring model

Compose notes in REAPER using standard MIDI items and tracks. Only a restricted subset is considered supported:

- Note events
- Tempo map subset
- Loop metadata
- Track/channel-to-instrument assignment
- Drum-channel mapping
- Limited per-song echo configuration
- Limited global export settings

No arbitrary REAPER FX semantics are part of the supported format.

### 5.2 Validation features

The tool must validate at least:

- Maximum effective 8 SNES voices
- Monophonic-per-channel rules for the SNESGSS target subset
- Legal channel usage and drum channel conventions
- Unsupported overlaps
- Instrument assignment completeness
- Note-range and transposition sanity checks
- ARAM budget estimate
- Sample count / sample-size estimate
- Echo configuration summary
- Unsupported project features present in the source arrangement

These constraints follow from SNES hardware limits and SNESGSS's documented MIDI assumptions. Unsupported semantics must be surfaced explicitly as warnings or errors; they must never be silently dropped.

### 5.3 Export outputs

v0.1 export produces:

- A **normalized intermediate project JSON**
- A **constrained MIDI export**
- A **validation report**
- A **build manifest** with deterministic hashes / timestamps / version info
- Optional **helper artifacts** for the SNESGSS import/export path

v0.1 does **not** promise native generation of every final runtime asset directly from REAPER alone. Treat "fully direct `.gsm` generation" as a later milestone unless the format is documented or reverse-engineered cleanly.

---

## 6. System architecture

### 6.1 REAPER-side components

**A. JSFX validator panel**

A JSFX plugin provides in-session visibility: channel occupancy, note-overlap warnings, rough voice pressure, selected export mode, and user-facing warnings. JSFX can process/generate MIDI and draw custom UI directly in REAPER.

> **Risk note:** JSFX drawing capabilities are primitive. Prototype this early. The question is whether the constraint UI is genuinely useful inline or just noisy. If it's noisy, fall back to a simpler "traffic light" indicator in JSFX and push detail to the validation report.

**B. ReaScript exporter**

A REAPER Lua script performs project introspection and export orchestration. Lua is embedded, portable, and better suited than Python for a shareable REAPER-side scripting layer. ReaScript can call into most of the REAPER API and is the right place for project scanning and deterministic export.

### 6.2 External build components

**C. Python validation/build CLI**

A repo-local Python CLI performs second-pass validation, manifest generation, regression checks, and any non-REAPER-heavy file transformations. Python is not the REAPER-side control plane; it is the repo-side build and test layer.

**D. Engine adapter**

The first adapter targets SNESGSS only. It consumes the normalized export package and either:

- Prepares assets for manual SNESGSS import, or
- Drives a partially automated SNESGSS export flow where feasible.

---

## 7. Supported music semantics in v0.1

**Supported:**

- Note on/off
- Duration
- Velocity only if mapped to a defined engine semantic
- Channel/instrument assignment
- Loop start/end markers
- Simple tempo map subset
- Drum split rules
- Song metadata

**Unsupported in v0.1:**

- Arbitrary CC automation
- Arbitrary modulation lanes
- Arbitrary plugin effects
- Arbitrary insert/send routing
- Polyphonic-per-channel voice stealing logic beyond explicit documented behavior
- "Sound like the final SNES output" preview guarantees

---

## 8. Constraint model

The system's core abstraction is not "DAW tracks" but **SNES resources:**

- Voices (8 max)
- ARAM (64 KiB)
- Samples
- Echo participation
- Exportable events
- Engine-target compatibility

The UI should expose:

- Current estimated voice occupancy
- Unsupported overlaps
- Sample-memory pressure
- Echo-on channels
- Echo delay / buffer settings summary
- Export blockers
- Warnings vs hard errors

Because SNES audio has 8 channels and 64 KiB ARAM, and echo routing is controlled with chip-level registers (EON/EDL/ESA), the model must remain **resource-centric** rather than **DAW-centric**.

---

## 9. Workflow architecture

### 9.1 The three-agent model

This project uses a **PM-outer-loop** workflow, not pure Claude Code autonomy.

```
Human operator
    │  - Copy-pastes instructions between PM and CC
    │  - Tests artifacts in REAPER (the one thing neither agent can do)
    │  - Runs /compact on CC when PM recommends it
    │  - Does NOT commit, run build/test commands, or edit files directly
    │
    ▼
Product architect (Claude web session)
    │  - Clones repo (read-only)
    │  - Reads SPEC.md + docs/decisions/
    │  - Gives scoped instructions to CC (via human copy-paste)
    │  - Reviews each CC pass
    │  - Pulls repo after each pass
    │  - Maintains cross-session project understanding via the repo-facing workflow
    │  - Pushes durable decisions into the filesystem via CC
    │
    ▼
Engineer (Claude Code)
    │  - Implements within the repo
    │  - Runs all build, test, and lint commands
    │  - Relies on CLAUDE.md + .claude/rules/ + auto memory + filesystem
    │  - Does NOT maintain cross-session reasoning — that's the PM's job
    │  - Uses native subagents for verbose/mechanical subtasks
    │  - Sole committer — all repo writes and CLI commands go through CC
    ▼
Repo filesystem (source of truth)
```

### 9.2 Why this model

Claude Code compacts aggressively. When it does, accumulated reasoning about _why_ decisions were made is lost. The PM web session serves as a **persistent reasoning layer** — it holds the evolving mental model, remembers what was tried, and gives CC instructions that reflect session-over-session learning. Critically, the PM must ensure that understanding reaches the repo — by instructing CC to update `docs/decisions/` — rather than relying solely on its own chat context surviving.

Native CC subagents are **child processes within a single CC session**. They do not survive compaction or session boundaries. Their memory files persist, but their reasoning does not. They are useful for keeping the main CC thread clean, not for durable oversight.

Therefore:

- **Cross-session continuity** → PM web instance (not subagents)
- **Within-session context management** → CC native subagents
- **Durable project state** → filesystem (SPEC.md, CLAUDE.md, docs/decisions/, auto memory)

### 9.3 What the PM must understand

1. **You are the spec-keeper.** CC will drift. Your job is to catch it. After each CC pass, pull the repo and verify that what was built aligns with this spec and with `docs/decisions/active.md`.

2. **You are the instruction interface.** Don't give CC vague goals. Give it scoped, concrete tasks: "Implement the JSFX channel occupancy counter for channels 1–8, reading MIDI note-on/note-off events. Write a test fixture in `docs/fixtures/` with expected output. Run the test-runner subagent to verify." The more specific the instruction, the less CC burns context figuring out what you mean.

3. **You maintain decisions in the filesystem, not just in your own memory.** After each significant decision or scope clarification, instruct CC to update `docs/decisions/active.md`. If you lose your web session, that file is how the next PM session recovers. The PM has read access (clone/pull) but not push access. The human operator does not commit directly either — all repo writes go through CC.

4. **You recommend compaction, but the human executes it.** You cannot see CC's context usage — the human can see it on the CLI. When you believe a task is complete and CC should compact, say so. The human will either run `/compact` immediately or ask you for a final wrap-up instruction to CC first. Do not assume compaction happens automatically.

5. **You do not need to understand every line of code.** You need to understand: what was the instruction, what was built, does it match the spec, what broke, what decisions were made. CC handles implementation detail.

---

## 10. PM setup checklist — do this before CC begins

When you first clone the repo and read this file, ensure the following setup is complete before giving CC implementation instructions. The PM has read-only repo access and the human operator does not commit directly; all file creation below should be done by **instructing CC** as its first tasks.

### 10.1 Create the directory structure

```
.claude/
  rules/
    reaper-lua.md
    jsfx.md
    python-build.md
    snes-audio.md
    tests-fixtures.md
    docs-decisions.md
  agents/
    test-runner.md
    export-auditor.md
docs/
  decisions/
    active.md
  fixtures/
  design/
tools/
  export/
  validate/
  reaper/
```

### 10.2 Write CLAUDE.md

Place at repo root. Keep it **short and contractual** — this loads into every CC session. Target under 80 lines.

Contents:

- Project purpose (one paragraph)
- Canonical engine target: SNESGSS
- Supported v0.1 subset (bulleted, terse)
- Build/test commands (as they're established — can start empty)
- File ownership map (which directories own what)
- Repo conventions (naming, formatting, commit style)
- Memory-writing rules (what goes in auto memory vs docs/decisions/)
- Explicit non-goals (copy from section 3 of this spec)

Do NOT put the full spec in CLAUDE.md. It's a pointer and a contract, not a comprehensive document.

### 10.3 Write the scoped rule files

Each `.claude/rules/` file should be terse and path-scoped. Examples:

**reaper-lua.md** — Lua conventions, ReaScript API patterns, REAPER version assumptions, how export scripts should structure output.

**jsfx.md** — JSFX language constraints, `@gfx` section patterns, MIDI processing idioms, known JSFX limitations to work around.

**python-build.md** — Python version, dependency management, CLI conventions, test framework, how the validation CLI relates to the Lua exporter output.

**snes-audio.md** — SNES hardware audio facts: 8 voices, 64 KiB ARAM, BRR sample format, echo register model (EON/EDL/ESA/EFB/FIR), SNESGSS-specific MIDI import assumptions and constraints.

**tests-fixtures.md** — Test fixture format, where fixtures live, how to add a new fixture, what a passing export looks like.

**docs-decisions.md** — How decision records are structured, when to write one, format template.

Start these as stubs with the key constraints. They'll grow as CC encounters issues.

### 10.4 Write docs/decisions/active.md

Start with:

```markdown
# Active decisions

## Engine target
SNESGSS is the sole v0.1 engine target. No other engine adapters in scope.

## .gsm generation
Deferred. v0.1 targets manual SNESGSS import via constrained MIDI + helper artifacts.
Do not assume or build toward direct .gsm generation unless the format is cleanly documented.

## JSFX scope
Start with minimal traffic-light validation (channel count, overlap detection).
Prototype early. If the drawing UX is too limited, move detail to the validation report.

## Subagent usage
- test-runner: YES, use from session 1
- export-auditor: add when export pipeline exists
- spec-keeper: NO, the PM web instance fills this role
```

### 10.5 Write the subagent definitions

**agents/test-runner.md:**

```markdown
# test-runner subagent

Purpose: Run build, lint, and test commands. Return compact summaries only.

Tool restrictions: bash (read + execute), file read. No file writes.

Behavior:
- Run the specified command
- If output > 30 lines, summarize: what passed, what failed, first error with context
- Never paste raw output into the main thread
- If a test fails, include the failing assertion and the relevant file:line

Memory: Record recurring issues for promotion into docs/decisions/active.md. If a repo-local findings convention is established later, use that instead.
```

**agents/export-auditor.md:**

```markdown
# export-auditor subagent

Purpose: Verify export artifacts are consistent and complete.

Tool restrictions: bash (read only), file read. No file writes except to audit report.

Checks:
- Intermediate JSON exists and is valid
- Constrained MIDI exists and has expected track count
- Validation report exists and has no unexpected errors
- Build manifest exists with hashes and timestamps
- All files referenced in manifest exist on disk

Output: Pass/fail summary with first discrepancy if any.
```

### 10.6 Confirm hooks intent

CC hooks are configured in `.claude/hooks/` or via `claude config`. The PM should instruct CC to set up the following hooks early:

- **PostToolUse (Write/Edit):** Run format/lint on changed files. Run targeted tests if a test file or tested module changed.
- **Stop:** Propose updates to `docs/decisions/active.md` and auto memory if the session produced decisions or recurring findings.

Don't over-engineer hooks on day one. Start with the post-write lint/test hook. Add others as pain points emerge.

---

## 11. CC native subagent guidance

### 11.1 Use the test-runner subagent from session 1

Every time CC needs to run a build or test, it should delegate to the test-runner subagent. This keeps compiler output, test logs, and stack traces out of the main reasoning thread. The main thread gets a compact summary and can act on it immediately.

This is the single highest-leverage subagent pattern for this project, because the SNES/JSFX tooling will produce verbose, messy output regularly.

### 11.2 Add the export-auditor when the export pipeline exists

Once there's a working Lua exporter producing intermediate JSON and constrained MIDI, enable the export-auditor subagent. Before that, there's nothing to audit.

### 11.3 Do not create a spec-keeper subagent

The PM web instance is the spec-keeper. A CC subagent cannot maintain cross-session understanding of spec intent. It would just re-read files the main thread already has. This adds orchestration cost with no context benefit.

---

## 12. Source-of-truth policy

| Priority | Source | Status |
|---|---|---|
| 1 | This spec + `docs/decisions/` | Normative |
| 2 | Code and tests | Defines current implemented behavior |
| 3 | CLAUDE.md + `.claude/rules/` | Operational contract for CC |
| 4 | CC auto memory | Advisory, may be stale |
| 5 | Chat history (any session) | Not authoritative |

If CC's behavior contradicts the spec or decisions docs, the spec wins. If the spec is wrong, update the spec first, then update the code.

---

## 13. Evaluation plan

### 13.1 Product evals

A song authored in REAPER should, for supported features, produce:

- Deterministic intermediate JSON
- Stable validation results
- Stable constrained MIDI export
- No silent dropping of unsupported semantics

### 13.2 Harness evals

After a brand-new CC session, the engineer should be able to recover:

- Engine target = SNESGSS
- v0.1 non-goals
- Current blockers
- Export subset
- Required test commands
- Known design decisions

If it cannot, the context/memory system has failed. The PM should test this periodically by starting a fresh CC session and asking it to summarize the project state.

---

## 14. Known challenges and risk register

### 14.1 REAPER-to-SNES semantic boundary

The biggest technical challenge is choosing the right boundary between REAPER semantics and SNES semantics. REAPER is flexible; SNESGSS import is opinionated; SNES hardware is tighter still. The harness must preserve that distinction or the project will drift into unsupported pseudo-features.

**Mitigation:** The constraint model (section 8) is resource-centric, not DAW-centric. Every validation check maps to a SNES hardware or SNESGSS engine limit, not a REAPER feature.

### 14.2 Export realism

SNESGSS documents MIDI import assumptions and a `.gsm`-to-export CLI path, but that does not mean a clean path from arbitrary REAPER state to final runtime assets. That gap is real.

**Mitigation:** v0.1 targets "constrained MIDI + helper artifacts for manual SNESGSS import." Direct `.gsm` generation is explicitly deferred (see decisions doc).

### 14.3 JSFX UI limitations

JSFX `@gfx` is primitive. A complex constraint dashboard may not be feasible or useful inline.

**Mitigation:** Prototype early. Fall back to traffic-light indicator in JSFX + full detail in the Python validation report if the UX doesn't work.

### 14.4 Memory and context quality

Better retrieval and context compilation matter more than elaborate memory structures. Stale instructions are worse than no instructions.

**Mitigation:** Keep CLAUDE.md short. Use scoped rules. Prune aggressively. The PM reviews memory state periodically and tells CC to clean up stale entries.

### 14.5 Cost and latency

Large-context Opus sessions are powerful but expensive. Verbose subtasks in the main thread waste budget and context.

**Mitigation:** Subagents for test/audit. PM gives scoped instructions. Human runs `/compact` between tasks on PM's recommendation.

---

## 15. Session protocol (for the PM)

Each substantial work session should follow this rhythm:

1. **Pull the repo.** Read `docs/decisions/active.md` and any recent commits.
2. **Decide the session's goal.** One or two concrete deliverables, not a vague direction.
3. **Write a scoped instruction for CC.** Include: what to build, what file(s) to touch, what test/fixture to use, what to avoid.
4. **Let CC work.** Don't interrupt mid-implementation unless it's clearly off-track.
5. **Pull and review.** Check: does the output match the instruction? Does it match the spec? Are there new decisions to record?
6. **Instruct CC to update `docs/decisions/active.md`** with anything learned.
7. **Recommend compaction to the human** if the session was long or context is getting foggy. The human will run `/compact` on the CLI.
8. **Repeat or end.**

---

## 16. First session plan

When the PM starts the first CC session, the recommended first instruction sequence is:

1. **"Read SPEC.md, CLAUDE.md, and .claude/rules/. Confirm you understand the project, engine target, v0.1 scope, and non-goals. Summarize in 5 bullets."** — This verifies the harness works.

2. **"Create the repo skeleton and stubs for any missing directories/files from section 10."** — Ensures filesystem structure is in place before implementation begins.

3. **"Create a minimal JSFX file that loads on a REAPER track, reads MIDI note-on/note-off events, counts active notes per channel (1–8), and draws a simple channel occupancy bar in `@gfx`."** — First real deliverable. Tests the JSFX toolchain and validates the core constraint-surfacing concept.

4. **"Write a test fixture in docs/fixtures/ describing expected JSFX behavior for a 4-channel test case."** — Establishes the fixture pattern separately so it can be reviewed on its own.

5. **"Set up the test-runner subagent as defined in .claude/agents/test-runner.md and add a post-write lint/test hook."** — Now that there's something to test, wire up the automation.

Do not try to build the full Lua exporter, Python CLI, and engine adapter in session one. Start with the JSFX panel because it's the riskiest UX component and the one most likely to force early scope decisions. Defer hooks until after the first working artifact — they're valuable, but they're classic first-night yak-shave bait.

---

## 17. v0.1 exit criteria

v0.1 is complete when all of the following are true:

- A JSFX panel loads in REAPER and shows channel occupancy for channels 1–8.
- A Lua exporter emits intermediate JSON and constrained MIDI for at least one fixture song.
- The Python validator produces a deterministic validation report and manifest.
- One fixture project imports into SNESGSS via the documented manual path, using only the documented helper artifacts, with no undocumented hand edits or unexpected blockers.
- Unsupported semantics are reported explicitly rather than silently ignored.

---

## 18. Open questions

These are known ambiguities that should be resolved during implementation, not assumed away:

- What exact REAPER metadata will represent loop markers? (Region markers? Named markers? Custom notation?)
- Will velocity survive as a meaningful engine semantic in v0.1, or be ignored?
- What is the minimum useful JSFX UI before it becomes noise? (Traffic light vs. full dashboard)
- What helper artifacts are actually needed for the manual SNESGSS import path?
- Is a constrained single-tempo prototype preferable before supporting a tempo-map subset?
- What is the intermediate JSON schema? (Defer pinning this until after the first Lua exporter pass produces real output.)

---

_This document is the project's primary bootstrap reference. If it conflicts with any other artifact, update the other artifact or update this document — never leave the conflict unresolved. Once implementation stabilizes, split into PRD.md (goals/scope/workflow) and TECH_SPEC.md (schemas/contracts/validation rules)._
