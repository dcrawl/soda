# Soda Performance Test — Findings

## Session 1 — Pre-flight and harness setup

Date: 2026-11-05. Commit: e065041 (soda, branch perf/00-harness-setup). raylib-miniscript commit: 9429286 (branch profiler).

### Pre-flight

1. **Debug build.** Confirmed `raylib-miniscript/build/` is `CMAKE_BUILD_TYPE=Debug`,
   generator Ninja, compiler `/usr/bin/clang` / `/usr/bin/clang++` (Apple clang
   21.0.0). No raylib/platform-specific CMake *cache* variables exist (the
   Darwin/Desktop backend is selected unconditionally in `CMakeLists.txt`), so
   the new build dirs only needed to differ in `CMAKE_BUILD_TYPE`. Created:
   - `build-release/` — `-DCMAKE_BUILD_TYPE=Release`
   - `build-profile/` — `-DCMAKE_BUILD_TYPE=RelWithDebInfo`

   Both configured with the same compiler and generator as `build/`, both
   built clean (72 translation units). A cache diff against `build/` (ignoring
   path and internal-advanced noise) showed only the build-dir path and one
   cosmetic `CMAKE_EXPORT_COMPILE_COMMANDS` difference (set on `build/` for
   clangd; irrelevant to timing) — no raylib/platform options diverge.

   Added `build-release/` and `build-profile/` to `raylib-miniscript/.gitignore`
   (previously only `build/` was ignored); committed there (9429286).

2. **Host link.** Created
   `soda/raylib-miniscript -> ../raylib-miniscript/build-release/raylib-miniscript`.
   Already covered by `soda/.gitignore` (`/raylib-miniscript`), no gitignore
   change needed in this repo.

   Note for future sessions: this symlink points at a **file** (the
   executable), not a directory — don't write paths like
   `soda/raylib-miniscript/build-release/...` expecting it to resolve; call
   the host binary directly by its real path, or invoke `./soda` from the
   soda repo root, which resolves the symlink itself.

3. **Fonts.** Confirmed `lib/*.png` contains only `ScreenFont.png`. The small/
   medium/large PixelDisplay fonts are not present, so they fall back to the
   normal font — future `PixelDisplay.print` benchmarks (§4.3) will only be
   measuring that one font. No action needed, just noted per the plan.

4. **Smoke test / reliable stop mechanism.** `tests/balls.ms` runs an
   unbounded `while true` + `yield` loop and never calls `exit` on a normal
   path.

   **Correction to plan doc §2:** `balls.ms` must be run with the **soda repo
   root** as the working directory, not `tests/` as §2's general instruction
   suggests for path resolution (`cd tests ... perf_<unit>.ms`). `balls.ms`
   loads from `file.child("assets", folderName)`, i.e. `assets/sounds` and
   `assets/images` relative to cwd, and those live at the soda repo root
   (`soda/assets/`), not under `tests/`. Running it from `tests/` makes it hit
   `file.exists` failures and `exit` immediately (confirmed: a first attempt
   from `tests/` produced a 0.41s profile dominated entirely by `soda.ms`
   overhead, with the console printing `Folder "assets/sounds" not found.`
   before the script exited on its own — not a SIGINT-stop at all). This is
   specific to `balls.ms`'s own asset-loading code, not a harness or
   `perfHarness.ms` concern — the actual `perf_*.ms` benchmark scripts built
   in §3 are run from `tests/` as the plan intends and don't load `assets/`.

   Confirmed from `raylib-miniscript/src/main.cpp` + `src/Profiler.cpp`: when
   `--profile` is passed, a `SIGINT` handler is installed. The first `SIGINT`
   breaks the main loop gracefully (profile files are still written via
   `profiler::Finish()`); a second `SIGINT` within 0.5s restores the default
   handler (force-kill). Without `--profile`, there's no custom handler, so a
   default `SIGINT`/`SIGTERM` just kills the process — irrelevant in practice
   since every `perf_<unit>.ms` script is required to call `perf.finish` →
   `exit` itself.

   Verified end-to-end, run from repo root:
   ```
   ./raylib-miniscript --profile tests/perf_results/smoke tests/balls.ms &
   PID=$!; sleep 5; kill -INT $PID; wait $PID
   ```
   Ran for ~4.8s, exited cleanly on the first `SIGINT` (exit code 0), and
   produced non-trivial `smoke.txt` (8.5 KB), `smoke.speedscope.json`
   (25 KB), `smoke.folded` (12 KB). Top self-time in the profile:
   `[raylib.EndDrawing]` 82.1%, `TextDisplay.render` 10.8% — expected, since
   `EndDrawing` is uncapped-FPS idle/GPU-flush time here (no
   `raylib.SetTargetFPS 0` was set for this ad hoc smoke run — the real
   benchmarks via `perfHarness.ms` do set it per §1.3).

   This SIGINT-first mechanism is `run_perf.sh`'s stop fallback for any
   script that doesn't exit on its own (used only as a safety net — see
   Harness section below).

5. **Profiling tools.** `xcrun xctrace` 27.2 (27B52) available; `samply` and
   `perf` are not installed on this Mac and are not needed (`xctrace` covers
   native profiling for the later §10 VM work). No install requested.

### Harness

Built `tests/perfHarness.ms` per PERF_TEST_PLAN.md §3, essentially as
specified in the plan's sketch. Validated against the actual host/lib source
before writing it:
- `soda.updateCallbacks` / implicit `soda.update` — confirmed as members of
  the `soda` module map (top-level assignments in `lib/soda.ms`, exposed via
  `import "soda"`).
- `file.writeLines(path, lines)` — confirmed signature matches
  `FileModule.cpp`'s `intrinsic_writeLines`.
- `print` — confirmed it goes to process stdout via a flushed `printf`
  (`main.cpp`'s `Print()`), not a Soda `TextDisplay`.
- `resourceCounts`, `hostMemory` — confirmed as bare global intrinsics
  (`MoreIntrinsics.cpp`), not module members.
- `intrinsics.yield` (not bare `yield`) is required in `perf.frames`'s manual
  per-phase loop, since `soda.ms` shadows global `yield` to also call
  `update` — using bare `yield` would double-render.

Built `tests/perf_soda.ms` (§4.1 empty-scene workload: `perf.frames` over
N = 0, 10, 100 extra no-op `updateCallbacks`, restoring the callback list
between N values so the three conditions don't compound).

Built `tests/run_perf.sh`: runs each benchmark 3× un-profiled (one CSV per
run index, via a `runIdx` argument threaded through `shellArgs`, so all three
runs' raw samples survive for the median-of-medians reporting §1.4 asks for)
plus once profiled for attribution, with a bounded SIGINT→SIGKILL timeout
fallback reusing the mechanism confirmed in pre-flight item 4 (only relevant
if a benchmark script has a bug and fails to call `exit`).

**Three corrections to the plan doc's §3 sketch, found only by actually
running it** (none are findings about Soda's performance — all are about how
this MiniScript2 host's `import` and builtins actually behave):

1. `import "X"` only binds a local named `X` in the *importing script's own
   scope* — it does not transitively expose whatever `X.ms` itself imported.
   So a benchmark script that does `import "perfHarness"` and then expects
   bare `soda.updateCallbacks` to work (as the plan's sketch implies by
   having `perfHarness.ms` do `import "soda"` once) gets
   `Undefined Identifier: 'soda'`. Every `perf_<unit>.ms` benchmark script
   must `import` whatever modules it directly references itself (e.g.
   `perf_soda.ms` needs both `import "perfHarness"` and `import "soda"`).
2. Likewise, `import "perfHarness"` only binds a local `perfHarness` (a map
   of perfHarness.ms's top-level names) — it does **not** put `perf` in
   scope as a bare name, the way the plan's `// Usage: import "perfHarness"`
   comment implies. Fixed by adding `globals.perf = perf` at the end of
   `perfHarness.ms`, matching the existing `lib/*.ms` convention for names
   meant to be used without a module prefix (e.g. `Display.ms`'s
   `globals.clear = @clear`).
3. `min(a, b)` is not a builtin in this MiniScript2 host/dialect — it only
   exists as a function defined inside `lib/mathUtil.ms`, which the harness
   doesn't import. `perf.stats`'s p95 calculation
   (`s[min(n-1, floor(n*0.95))]`) was rewritten as an explicit
   `if p95idx > n-1 then p95idx = n-1` instead.

The two runtime-only unknowns flagged during writing (`for k in ph.indexes`
map-key iteration, and `range(1, n)` inclusive-both-ends semantics including
`range(1, 0)` producing zero iterations for N=0) both turned out to work
exactly as the plan's sketch assumed — no changes needed there.

Verified end-to-end via `./run_perf.sh perf_soda.ms`: produced
`perf_soda.run1.csv`, `run2.csv`, `run3.csv` (timing) and
`perf_soda.runprofiled.csv` + `perf_soda_profile.{txt,speedscope.json,folded}`
(attribution). Sample un-profiled numbers (N=0 extra callbacks, ms, from
run1): user 0.0005 mean, render 0.636, endDrawing 0.378 (mean) /12.3 (max —
one outlier frame, likely a one-off driver/vsync hiccup, not investigated
further this session), callbacks 0.015, yieldGC 0.039, total 1.068. Numbers
were effectively flat across N=0/10/100 (no-op callbacks are cheap, as
expected). `RenderTexture` resource count dropped from 16 to 8 between
`before-N0` and `after-N0` in every run — worth investigating next session,
but not analyzed here (possibly orphaned render textures from the default
7-slot display stack's initial setup being freed on first GC/frame; file
this under "observed, not yet explained").

The profiled run's top self-time was dominated by `TextDisplay.render`
(48.3%) and `[raylib.EndDrawing]` (29.5%) even for a nominally "empty"
scene — consistent with §4.5's S-T1 suspect (shader bracket per glyph) being
worth prioritizing early, but this is only one profiled run of the harness
validation script, not a real baseline measurement; treat as a hint for
ordering next session's work, not a confirmed finding.

## Session 1 (continued) — unplanned upstream sync, and two §4.2/§4.9 bug checks

### Unplanned upstream sync

Partway through this session, `main` and `Fixes` were fast-forwarded by a
`git pull` outside this session (most likely VS Code's or GitHub Desktop's
background auto-sync, both of which were open against this project) —
confirmed via `git reflog`, timestamped during this session
(`main`: 19:59/20:42, `Fixes`: 21:25, all 2026-11-05). This was a clean
fast-forward — no local commits were lost — but it pulled in a large batch
of upstream (JoeStrout) commits that postdate the plan's reference commit
`0d6276b`, including several that bear directly on this plan:

- `4538499` "Add function notes to the lib modules" — besides docstrings,
  this also fixed the exact `Display.install`/`mode=` bugs §4.2 predicted
  (see below).
- `fe30532` "Improve `pixel` speed by caching the read-back texture",
  `67ba779`/`e24b598`/`2d1abbc` (pixel/color optimizations) — these look
  like they already address plan suspects S-P3 (and maybe parts of S-P4) in
  §4.3. **Not yet verified** — re-check these suspects against current code
  before baselining PixelDisplay in a future session; don't assume the plan's
  description of PixelDisplay's current behavior is accurate anymore.
- `2cf0de1` "Fix scrolling and offset bugs in SpriteDisplay and TileDisplay".

Decision (user): keep the fast-forward and continue against current code,
rather than reverting `main`/`Fixes` to the plan's original commit. Per
their direction, `perf/00-harness-setup` was merged with the (now-updated)
`Fixes` branch (merge commit `d3d31bd`) so this session's harness work and
all future sessions measure against current code. The merge was clean (no
conflicts) and `tests/run_perf.sh`'s re-run after merging reproduced
consistent `perf_soda` numbers (see Harness section above) — no regression
from the merge itself.

**Action for next session:** before trusting any §4 "Suspect" description
against the live code, read the relevant `lib/*.ms` fresh rather than
assuming the plan's prose (written against `0d6276b`) still matches.

### §4.2 Display.install/mode= bugs — already fixed upstream

Confirmed via a new regression test, `tests/qa_display_install.ms`:

- **BUG-01** (plan's suspected `Display.install` line 101 bug: reading
  `disps[slotNum].mode` instead of `disps[0].mode`) and
- **BUG-02** (line 104's `disps[i].remove i` calling `.remove` on the
  *display* instead of the list, leaving duplicates in a slot)

are **both already fixed** in the upstream commit `4538499` that came in via
the sync above. Verified: `tests/qa_display_install.ms` reproduced BUG-01 as
an uncaught `Index Error` when run against the pre-merge code, and passes
cleanly (`ALL PASSED`) after merging. No fix needed from this project; the
regression test is committed (`227f09d`) to guard against a future
regression.

### §4.9 Sound.StopAll — confirmed and fixed (BUG-03)

`Sound.StopAll` (`lib/Sound.ms`) iterated `for snd in _playingSounds` while
each `snd.stop` call removed an element from that same list — classic
skip-every-other-element bug. Confirmed with a new regression test,
`tests/qa_sound_stopall.ms`: started 4 synthesized sounds, called
`Sound.StopAll`, and checked each one's `isPlaying` afterward. Before the
fix, `snd2` and `snd4` (every other sound, as predicted) still reported
`isPlaying == true` — their raylib resources were never actually stopped,
even though `_playingSounds` itself ends up `[]` regardless (`StopAll`
unconditionally resets it at the end, which is why the *list* looks fine
even though some sounds were skipped).

Fixed on `perf/bug-sound-stopall` (commit `e4a8246`, branched from `Fixes`):
iterate a snapshot (`_playingSounds[:]`) instead of the live list. Verified:
`qa_sound_stopall.ms` now reports `ALL PASSED`. Not yet merged into
`Fixes`/`main` — that's the user's call, this is a prototyped fix on its own
branch per the plan's ground rules.

### Not yet done (left for next session)

- §4.1's "idle display stack" cost and the `display(5).mode = displayMode.off`
  fill-rate-floor comparison, and the `wait` timing-accuracy checks (0.1s/1s/5s),
  are additional 4.1 workloads not yet built — only the fixed per-frame engine
  cost via `perf.frames` was covered this session.
- Baselines for the rest of Tier A (§4.2–4.11) and the §5 integration
  scenarios: next session, per §8 step 2.
- §9 binding overhead and §10 VM profiling: later sessions, per §8 steps 5–6.
- Re-verify §4.3 PixelDisplay suspects (S-P1 through S-P5) against the
  current code before baselining — `fe30532`/`67ba779`/`e24b598`/`2d1abbc`
  (pulled in by the unplanned sync above) touch pixel/color code paths the
  plan's suspects were written against commit `0d6276b`, before those
  changes landed.
- Decide whether to merge `perf/bug-sound-stopall` into `Fixes`/`main`
  (not done this session — left for the user).
