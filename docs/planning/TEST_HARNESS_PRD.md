# TEST_HARNESS_PRD — C700 Automated Test System

## Status
Draft v0.3 — **Parked.** Only M1 (pluginval + ReaScript smoke) is active now as a safety net during the bitmap UI reconstruction (M8). The full plan activates after the modernized UI milestone ships.

## 0. Purpose of this document

This document defines the product and rollout plan for an automated test harness for the Linux VST3 fork of **C700**.

It is intentionally narrower than a general QA strategy document. Its job is to answer:

- what the harness must do,
- what parts are confirmed vs. still unknown,
- what the first shippable testing loop is,
- and how a coding agent should extend it without turning it into a science project.

### Activation timeline

The C700 fork is currently mid-UI-reconstruction (M8): a faithful bitmap recreation of the original editor to prove the VST3 wrapper works. After that, the plan is a **modernized UI** with scalable rendering (75%/100%/125% à la Serum) and QoL improvements. That modernized UI is the actual shipped product.

- **Now (M8 reconstruction):** Only M1 is active — pluginval + ReaScript smoke as a safety net. The manual Codex workflow (rebuild → test by ear → accept) is sufficient for a plugin with this few features in flux.
- **After modernized UI ships:** Activate the full plan. The UI layout is stable, regressions matter, and automated testing pays for itself.

This revision promotes several earlier hypotheses to documented statements:

- **pluginval** is available as a Linux binary release, supports headless CLI use, supports strictness levels **1–10**, defaults to **5**, and currently requires **Ubuntu 22.04+** for Linux release binaries. It also supports `--skip-gui-tests`, `--timeout-ms`, `--output-dir`, and `--validate-in-process`.
- **REAPER** documents ReaScript as a first-class scripting interface, and Cockos has documented command-line support for passing a project plus a ReaScript file, as well as `-nonewinst` plus a script.
- **SWS** documents both **per-project startup actions** and a **global startup action**, which gives a second supported way to auto-run a ReaScript harness.
- **ReaScript** exposes the concrete API functions we need for a first harness, including `TrackFX_AddByName`, `TrackFX_SetParam`, `TrackFX_GetPresetIndex`, `MIDI_InsertNote`, and `MIDI_InsertCC`.
- **Xvfb** is a virtual X server suitable for running GUI applications without a physical display, and `xvfb-run` is a wrapper that simplifies launching commands inside such an environment.
- **xdotool** should be treated as an **X11/Xvfb-only** tool for this project. Its own docs/issues explicitly say many functions do not work on Wayland, and it is unclear whether full Wayland compatibility is even possible.

---

## 1. Product goal

Build a daily-runnable automated test system that:

1. rebuilds the current C700 Linux plugin,
2. validates it with cheap generic plugin tests,
3. exercises it in **REAPER on Ubuntu** through a scripted host-level harness,
4. emits a structured machine-readable report,
5. and gives the evening development session a concrete regression list instead of vague "seems okay" impressions.

The first version is **not** a full GUI robot. The first version is a reliable **build → validate → open host → instantiate plugin → send MIDI → verify output → write report** loop. REAPER is scriptable and extensible enough for this to be a realistic first milestone, and pluginval is specifically designed for automated plugin compatibility/stability testing.

---

## 2. Non-goals

For the first shipped harness, the system will **not**:

- perform fully general exploratory testing,
- guarantee visual regression coverage,
- depend on AI vision to be useful,
- require Wayland-native automation,
- require a custom DAW plugin host other than REAPER,
- attempt bit-perfect parity proof for every render.

---

## 3. Confirmed capabilities vs. remaining unknowns

## 3.1 Confirmed capabilities

### pluginval
Confirmed:
- Linux binary releases exist.
- Latest release found: **1.0.4**.
- Linux release binaries require **Ubuntu 22.04** minimum.
- Strictness levels are **1–10**, with **5** recognized as the baseline for host compatibility.
- Headless CLI options include `--validate`, `--strictness-level`, `--skip-gui-tests`, `--validate-in-process`, `--timeout-ms`, `--verbose`, and `--output-dir`.

### REAPER scripting and automation
Confirmed:
- ReaScript is a supported automation/scripting system inside REAPER.
- Cockos documented command-line support for passing a project and a ReaScript file, e.g. `reaper projectfile.rpp scriptfile.lua`.
- Cockos also documented `-nonewinst` command-line support for running a script in an already-running REAPER instance.
- REAPER has long-supported `-renderproject filename.rpp` as a command-line render-and-quit entry point.
- SWS provides per-project startup actions and a global startup action.

### ReaScript API surface
Confirmed:
- `TrackFX_AddByName()` can add or query a named FX and can instantiate a plugin if not found.
- `TrackFX_SetParam()` and `TrackFX_SetParamNormalized()` exist for host-side parameter control.
- `TrackFX_GetPresetIndex()` exists for preset introspection.
- `MIDI_InsertNote()` and `MIDI_InsertCC()` exist for scripted MIDI event insertion.
- REAPER's generated API docs are current enough to include these functions in the v7.66-generated help page.

### GUI virtualization / X11 automation
Confirmed:
- Xvfb is a virtual X server with no physical display requirement.
- `xvfb-run` is the standard wrapper for launching commands under Xvfb.
- xdotool is not a reliable Wayland automation path; its docs/issues explicitly say typing, window search, and many functions do not work correctly on Wayland.

## 3.2 Still-open unknowns

These remain open and should be treated as explicit discovery tasks, not assumptions:

1. Whether the exact CLI form `reaper project.rpp script.lua` works unchanged on the target Ubuntu machine and target REAPER build.
2. Whether the better bootstrap path is **direct CLI script launch** or **SWS startup action**.
3. Whether C700's Linux build exposes all required workflows through host-visible parameters, or whether some critical workflows remain GUI-only.
4. Whether REAPER's render path should be driven by:
   - a command-line `-renderproject` invocation,
   - a ReaScript-triggered render action,
   - or a preconfigured test project with deterministic render settings.
5. Whether the JUCE editor appears as a separately discoverable X11 window under REAPER, or only as an embedded child in the FX chain window.
6. Which subset of C700's behavior is stable enough for audio regression baselines right now.

---

## 4. Product decision

Build the harness in layers, but ship value from the inside out:

### Required first layers
- **Layer 0:** pluginval
- **Layer 1:** in-process/plugin-side tests if cheap enough
- **Layer 2:** REAPER + ReaScript harness

### Deferred layers
- **Layer 3:** Xvfb + xdotool GUI automation
- **Layer 4:** AI vision exploratory testing

Rationale:
- pluginval catches catastrophic plugin-host compatibility failures cheaply.
- ReaScript gives realistic host coverage without GUI fragility.
- X11 GUI automation is valuable, but it is more brittle and should not block the first usable system. pluginval is explicitly positioned for CLI/CI-style validation, and ReaScript is a supported automation surface inside REAPER.
- Layers 3–4 test UI-specific behavior. The current editor is interim (bitmap reconstruction). The modernized UI with scalable rendering is the product worth testing. GUI automation investment is deferred until that UI exists.

---

## 5. Layer design

## 5.1 Layer 0 — pluginval

### Goal
Catch crashes, bad parameter/state behavior, and generic plugin-host compatibility problems before REAPER is even involved.

### Status
**Confirmed and ready to implement.**

### Minimum contract
The harness must be able to run pluginval against the installed C700 `.vst3` artifact and capture:
- exit code,
- strictness level used,
- log directory path,
- summary pass/fail,
- failure count and first failing test if available.

### Initial command shape
Example only; exact paths belong in scripts:

```bash
pluginval --validate ~/.vst3/C700.vst3 \
  --strictness-level 7 \
  --skip-gui-tests \
  --timeout-ms 60000 \
  --output-dir ./reports/pluginval
```

The flags above are documented in pluginval's CLI surface. Strictness 5 is the common baseline, but 7 is a reasonable stronger default for local regression catching.

### Notes
- `--skip-gui-tests` is appropriate for unattended/headless runs.
- `--validate-in-process` should be used for debugging only, not as the default safety path.
- If pluginval fails, the harness should still emit a report rather than just aborting silently.

---

## 5.2 Layer 1 — plugin-side tests

### Goal
Exercise the C700 engine and adapter logic without needing a DAW.

### Status
Desirable but optional for v0.1.

### Product stance
This layer should exist only if it can be added cheaply and cleanly. It is not the gating item for the first daily loop.

### Initial scope
If implemented, it should focus on:
- adapter construction/destruction,
- state save/restore,
- parameter fuzzing at the adapter/kernel boundary,
- simple note render smoke tests,
- no-GUI regression checks.

### Reason
These tests are fast and deterministic, but they do not replace the host-level harness because the real integration risk lives in REAPER + VST3 host behavior.

---

## 5.3 Layer 2 — REAPER + ReaScript harness

### Goal
Exercise C700 in the real target host on Ubuntu.

### Status
Core v0.1 layer.

### Confirmed API building blocks
The following documented ReaScript APIs are enough for a serious first harness:
- `TrackFX_AddByName`
- `TrackFX_SetParam`
- `TrackFX_SetParamNormalized`
- `TrackFX_GetPresetIndex`
- `MIDI_InsertNote`
- `MIDI_InsertCC`

### First required behaviors
The first REAPER harness must:
1. create or open a test project,
2. add a track,
3. instantiate VST3:C700,
4. insert at least one MIDI note,
5. trigger playback or render,
6. verify that the result is not silent,
7. write structured output.

### Bootstrap options
Use one of these two supported entry paths:

**Option A — direct CLI script launch**
Cockos documented passing a project and a script directly on the command line.

**Option B — SWS startup action**
SWS documents project startup actions and a global startup action, which may be more reliable if CLI behavior is awkward on Linux.

### Product recommendation
Treat CLI launch and SWS startup action as two valid bootstrap strategies. The implementation should choose whichever is more deterministic on the target machine and document that choice in the decision log.

---

## 5.4 Layer 3 — Xvfb + xdotool GUI automation

### Goal
Exercise the custom editor and catch visible UI regressions.

### Status
Deferred until after Layer 2 works.

### Confirmed facts
- Xvfb is appropriate for headless X11 application execution.
- `xvfb-run` simplifies orchestration.
- xdotool should be considered X11/Xvfb-only for this project.

### Scope for first GUI test
The first GUI test should do only this:
1. launch REAPER under Xvfb,
2. open the C700 editor,
3. capture one screenshot,
4. close it cleanly.

Do not start with full UI clicking flows.

---

## 5.5 Layer 4 — AI vision exploratory testing

### Goal
Use a vision-capable agent for UI-specific exploratory testing.

### Status
Explicitly non-blocking and late-phase.

### Product stance
This layer should only be considered after:
- pluginval is stable,
- the REAPER harness works daily,
- GUI screenshots are reproducible,
- and there is a real unmet need that scripted tests cannot cover.

---

## 6. Daily orchestration product (Phase 2+)

This section defines the target daily loop. It is **not part of M1**. M1 is a manual safety net. This becomes relevant after the modernized UI ships.

### 6.1 Required daily loop

The morning automation should do this, in order:
1. update the repo,
2. rebuild/install the plugin,
3. run pluginval,
4. run the REAPER smoke harness,
5. optionally run additional tests,
6. write one structured report file,
7. optionally notify or surface the report to the evening dev session.

### 6.2 Required output artifact

The harness must emit one JSON report per run.

#### Minimum report contract

```json
{
  "date": "",
  "commit": "",
  "build": {
    "ok": true,
    "duration_sec": 0,
    "artifact_path": "",
    "log_path": ""
  },
  "pluginval": {
    "ok": true,
    "strictness": 7,
    "exit_code": 0,
    "log_dir": "",
    "summary": "",
    "failures": []
  },
  "reaper_smoke": {
    "ok": true,
    "bootstrap_method": "",
    "project_path": "",
    "plugin_instantiated": true,
    "midi_note_sent": true,
    "audio_non_silent": true,
    "render_path": "",
    "notes": []
  },
  "regressions": [],
  "new_issues": [],
  "summary": ""
}
```

The point of the report is not perfect detail. The point is that the evening dev session can answer, immediately:
- did it build,
- did pluginval pass,
- did REAPER load it,
- did it make sound,
- what newly broke.

---

## 7. Recommended repository layout

```
snes_music/
  docs/testing/
    TEST_HARNESS_PRD.md
    reports/                     (Phase 2+)
    fixtures/                    (Phase 2+)
    notes/
  scripts/testing/
    run_pluginval.sh             (Phase 1 — now)
    run_smoke.sh                 (Phase 1 — now)
    run_daily_tests.sh           (Phase 2+)
  tools/reaper/
    snes_c700_setup.lua          (existing)
    c700_smoke_test.lua          (Phase 1 — now)
    startup/                     (Phase 2+)
```

### Notes
- `reports/` should be machine-written.
- `fixtures/` should contain small deterministic artifacts only.
- `notes/` should contain machine-specific setup details, not normative product requirements.
- `tools/reaper/startup/` can hold SWS/bootstrap-specific scripts if that path wins.
- The C700 fork repo stays focused on plugin source; a pointer in its CLAUDE.md references this harness.

---

## 8. Phased rollout

### Phase 1 — smoke test safety net ✓ ACTIVE

**Goal:** Catch catastrophic regressions after agent sessions.

**Activation:** Now (during M8 bitmap reconstruction and beyond).

**Deliverables:**
- pluginval invocation script
- ReaScript smoke test
- minimal orchestrator script

**Exit criteria:**
- one command runs pluginval + smoke,
- the loop fails loudly on build/pluginval/host errors,
- the REAPER harness proves non-silent output.

**Note:** This is a manual safety net, not a daily cron job. Run it after Codex sessions or before committing to accept a large rebuild pass.

### Phase 2 — host-level functional coverage

**Goal:** Catch real workflow regressions.

**Activation:** After modernized UI ships and the feature surface is stable.

**Additions:**
- daily cron/systemd orchestration
- JSON report per run
- preset/state persistence test
- multi-channel / multi-timbral test
- parameter sweep test
- render regression test
- crash/timeout watchdog

### Phase 3 — GUI coverage

**Goal:** Catch editor regressions.

**Activation:** After modernized UI layout is finalized (control positions, resize behavior, panel structure are stable).

**Additions:**
- Xvfb launch path
- screenshot capture
- one or two stable xdotool scripts
- visual diff or screenshot review support

### Phase 4 — exploratory automation

**Goal:** Discover regressions humans did not think to script.

**Activation:** After Phases 2–3 hit diminishing returns and there is a demonstrated unmet need.

**Additions:**
- vision-agent experiments
- guided exploratory flows
- anomaly triage layer

---

## 9. First milestone

### Milestone M1 — Pluginval + REAPER smoke

This is the only milestone active during M8 reconstruction.

**It is complete when:**
1. `run_pluginval.sh` runs pluginval against the installed Linux VST3,
2. `c700_smoke_test.lua` instantiates C700 in REAPER by script,
3. one scripted MIDI note is played or rendered,
4. the output is confirmed non-silent,
5. `run_smoke.sh` orchestrates both and reports pass/fail.

**It is not required yet that:**
- a JSON report is written (plain exit codes and console output are fine for Phase 1),
- daily automation exists,
- GUI automation works,
- SPC export is covered,
- sample import is covered,
- full preset/state parity is proven,
- audio output is bit-perfect against a gold master.

---

## 10. Explicit open questions

These remain research/implementation questions:

1. Which bootstrap path is more reliable on Ubuntu for unattended runs: direct REAPER CLI script launch, or SWS startup action?
2. What is the cleanest non-silence assertion for the REAPER smoke test: rendered-file analysis, track-peak API, or another host-visible signal?
3. Which C700 behaviors are reachable entirely through host APIs, and which require GUI automation later?
4. Does C700's Linux editor appear as an independently discoverable X11 window under REAPER/Xvfb?
5. What is the minimal stable fixture set for regression testing?

These questions should be closed in `docs/decisions/active.md` as they are resolved.

---

## 11. Source-of-truth policy

Priority order:
1. `TEST_HARNESS_PRD.md`
2. `docs/decisions/active.md`
3. harness scripts
4. test reports
5. chat history

If the implementation diverges from this document, update the document or log the deviation explicitly.

---

## 12. Suggested first implementation prompt for Claude Code

```
Read docs/testing/TEST_HARNESS_PRD.md.

Goal: complete Milestone M1 only.

Tasks:
1. Create scripts/testing/run_pluginval.sh.
2. Create scripts/testing/run_smoke.sh that calls pluginval + launches the ReaScript test.
3. Create a minimal tools/reaper/c700_smoke_test.lua that:
   - creates or opens a test project,
   - adds a track,
   - instantiates VST3:C700,
   - inserts one MIDI note,
   - triggers playback/render or equivalent validation,
   - records whether output is non-silent.
4. Document the chosen REAPER bootstrap method in a brief note at docs/testing/notes/.

Constraints:
- No GUI automation.
- No AI vision work.
- No daily cron/systemd orchestration.
- No JSON report format yet — exit codes and console output are sufficient.
- Keep the harness deterministic and minimal.

Deliverables:
- run_smoke.sh runs pluginval + ReaScript smoke in one command,
- c700_smoke_test.lua proves C700 loads and makes sound,
- bootstrap method is documented.
```
