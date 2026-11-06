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
`qa_sound_stopall.ms` now reports `ALL PASSED`. Merged (fast-forward) into
`Fixes` at the user's request; `perf/bug-sound-stopall` deleted. Not pushed
to `origin`, and not yet proposed upstream to `main`/JoeStrout.

### §4.3 PixelDisplay — re-verification of S-P1–S-P5 against the synced code

The sync pulled in four of JoeStrout's own pixel/color optimization commits
(`fe30532`, `67ba779`, `e24b598`, `2d1abbc`, all 2026-11-04) that directly
touch three of the five plan suspects. Re-read `lib/PixelDisplay.ms` and
`lib/color.ms` against those diffs, then measured all five with a new
benchmark, `tests/perf_pixelDisplay.ms` (`perf.timeit`, `soda` host,
`build-release`). Raw numbers: `perf_results/perf_pixelDisplay.run1.csv`.

- **S-P3 (`pixel()` full-texture readback) — closed, fixed upstream.**
  `fe30532`/`2d1abbc` added `_pixCache`: a lazily-rebuilt `RawData` CPU copy
  of the render texture (`rl.rlReadTexturePixels`, not `LoadImageFromTexture`
  + `GetImageColor`), read directly with `.int(...)` and a 4096-entry
  int→hex-string memo (`_intToHex`). Measured: repeated `pixel()` reads
  **0.0024 ms/call**; `pixel()` interleaved with `setPixel()` (the
  flood-fill pattern this cache exists for) **0.0049 ms/call**. Both
  negligible. No further action.
- **S-P4 (`colorToList` parsing every call) — closed, fixed upstream.**
  `e24b598`/`2d1abbc` removed `colorToList`/`colorFromList` entirely from
  `PixelDisplay.ms`'s hot paths; `color.ms`'s `fromList`/`rgb`/`rgba` now use
  a frozen 256-entry `_hexByte` lookup table instead of per-channel
  `floor`/`%`/string-concat, and `PixelDisplay.pixel`'s int→hex conversion
  reuses the same table via `_intToHex`. Not independently re-measured
  (S-P3's numbers already include whatever's left of this path) — no
  further action.
- **S-P1 (per-call `BeginTextureMode`/`EndTextureMode`) — confirmed still
  open by the sync, then prototyped and fixed on `perf/fix-pixelDisplay-batch`
  (commit pending).** `2d1abbc` added a cache fast path to `setPixel` that
  skips the GPU bracket entirely — but only once `_pixCache` is non-null,
  which only happens after a `pixel()` call. A plain loop of consecutive
  `setPixel` calls (the plan's literal workload: "a loop of 10 000 `setPixel`
  calls") never populates the cache, so it still took the full
  `_beginDraw`/`_endDraw` bracket every call: measured **~0.098 ms/call**,
  flat across N = 1/100/1 000/10 000 (no amortization) — for N = 10 000
  that's **~1 second** of wall time for one `setPixel` loop. `fillRect`
  (which has no cache path at all) measured identically, ~0.097–0.098
  ms/call.

  **Root cause was narrower than the plan's hypothesis.** A raw isolation
  test (`rl.BeginTextureMode`/`rl.EndTextureMode` with nothing drawn in
  between) measured **0.0011 ms/call** — cheap. `rl.DrawPixel` alone, with
  no texture-mode bracket, measured **0.0006 ms/call** — also cheap.
  Only the *combination* — a draw call issued between `BeginTextureMode`
  and `EndTextureMode` — was expensive. Narrowing further: the blend-mode
  bracket (`rl.BeginBlendMode`/`rl.EndBlendMode`, which every `PixelDisplay`
  draw call also opens and closes around itself) produces the same effect
  on its own, independent of texture mode. Both are session-ending GPU
  state changes that force raylib's internal render batch to flush
  immediately whenever a draw happened since the bracket opened; with
  nothing drawn, there's nothing to flush, so the bracket itself is cheap.
  **Both brackets, not just the texture-mode one, needed batching.**

  Fixed by adding `PixelDisplay.beginBatch([alphaBlend])` /
  `PixelDisplay.endBatch()`: while a batch is open, `_beginDraw`/`_endDraw`
  skip re-issuing `BeginTextureMode`/`EndTextureMode` *and*
  `BeginBlendMode`/`EndBlendMode` (falls back to a normal, correctness-safe
  per-call blend-mode switch if one call's `alphaBlend` doesn't match what
  the batch set up — e.g. mixing `print` into a non-alpha batch). Calls
  nest (only the outermost pair opens/closes the brackets). Verified
  correct with a new regression test, `tests/qa_pixelDisplay_batch.ms`:
  `PixelDisplay.runUnitTests` still passes, and a batched sequence of
  `setPixel`/`fillRect`/`line` draws the identical pixels (compared via
  `pixel()`) as the same calls unbatched, including a stray unmatched
  `endBatch` (no-op) and nested `beginBatch`/`endBatch` pairs.

  Measured: wrapping the same `setPixel`/`fillRect` loops in
  `beginBatch`/`endBatch` dropped **~0.098 ms/call → ~0.0028 ms/call**, a
  **~35×** speedup, flat across N — for N = 10 000, ~1 s → **~28 ms**.
  Consistent across 3 runs. This was the top-priority target per §8 step
  3's ordering (S-T1 → **S-P1** → ...).

  Prototyped on `perf/fix-pixelDisplay-batch` (off `perf/00-harness-setup`,
  commit `8df7753`), together with the benchmark and this writeup. The fix
  itself (`lib/PixelDisplay.ms`'s `beginBatch`/`endBatch`) plus its
  regression test (`tests/qa_pixelDisplay_batch.ms`) were then cherry-picked
  — at the user's request, to keep `Fixes` free of the perf-testing
  harness/benchmarks/plan doc this branch also carries — onto a short-lived
  branch off `Fixes` and fast-forward-merged in (commit `16e6ced`). Pushed
  to `origin/Fixes`. Not yet proposed upstream to JoeStrout's `main`.
  No `lib/*.ms` caller wired up to use it yet (e.g. a future `TileDisplay`/
  `SpriteDisplay` hot loop, or Soda user code) — that's a follow-up, not
  part of this prototype.
- **S-P2 (`drawImage`/`patternFill` upload-per-call) — fixed and verified.**
  Baseline (before this fix): **~0.08–0.10 ms/call for 16×16**,
  **~0.12–0.14 ms/call for 256×256**, flat across N = 1/10/100 (no
  amortization — nothing was cached).

  **Root cause had two independent parts, both contributing.** An isolated
  benchmark separated them: (1) `rl.LoadTextureFromImage` +
  `rl.UnloadTexture` alone cost **~0.010 ms/call for 16×16** but
  **~0.064 ms/call for 256×256** — this part *does* scale with upload size,
  unlike what the pre-fix measurement's flatness suggested. (2) The
  remaining ~0.085–0.09 ms, present even for a *pre-existing* cached texture
  used once per call, is the same per-call GPU-bracket-flush cost S-P1
  found (`_drawTexture` calls `_beginDraw true`/`_endDraw` around
  `DrawTexturePro`, same as any other draw call) — confirmed by timing
  `DrawTexturePro` on an already-loaded texture with the texture-mode/
  blend-mode brackets opened once outside the loop vs. once per call:
  ~0.0011 ms/call vs. ~0.097 ms/call, matching S-P1's ~0.098 ms bracket-flush
  finding almost exactly.

  Fixed both parts: `PixelDisplay.drawImage`/`patternFill` now call
  `img.texture` (the `Image` class's own lazily-created, cached GPU
  texture, invalidated automatically on `setPixel`/`flip`/`rotate`) instead
  of `rl.LoadTextureFromImage`/`rl.UnloadTexture` on every call.
  `patternFill` still sets `TEXTURE_WRAP_REPEAT` for the tiled draw, but now
  resets it back to `TEXTURE_WRAP_CLAMP` afterward so a later `drawImage`
  call reusing the same cached texture isn't left in REPEAT mode. This
  alone removes the LoadTextureFromImage/UnloadTexture churn (part 1), but
  callers still need `beginBatch(true)`/`endBatch()` around repeated calls
  to amortize the bracket-flush cost (part 2) — `true` because
  `drawImage`/`patternFill` always draw with alpha blending internally, so
  the batch's `alphaBlend` must match or every call still falls back to a
  per-call blend-mode switch (itself a flush).

  Verified correct with a new regression test,
  `tests/qa_pixelDisplay_drawImage.ms`: `drawImage` draws the right pixels
  on a fresh `Image`, repeated `drawImage` calls on the same `Image` all
  draw correctly (confirming the cached texture isn't stale), a `setPixel`
  edit after a draw is correctly picked up by a later `drawImage` call
  (confirming `Image`'s existing cache-invalidation path still works
  through the new caller), `patternFill` tiles correctly and doesn't leak
  `TEXTURE_WRAP_REPEAT` into a later plain `drawImage` call on the same
  `Image`, and a manual old-style (`LoadTextureFromImage`+`DrawTexturePro`+
  `UnloadTexture`) draw produces pixel-identical output to the new
  `drawImage` call.

  Measured (3 repeat runs, consistent):
  - Unbatched (texture-caching fix only, no `beginBatch`): 16×16 roughly
    unchanged (~0.10–0.14 ms/call — the avoided upload was only
    ~0.01 ms out of a ~0.1 ms total, within run-to-run noise); 256×256
    improved from ~0.13 ms to **~0.10–0.105 ms/call**, consistent with
    removing the size-scaled upload cost. The bracket-flush cost (part 2)
    still dominates either way without batching.
  - Batched (`beginBatch true` around the whole measurement, both fix
    parts in effect): `drawImage` **16×16: ~0.10 ms → ~0.0058 ms/call**
    and **256×256: ~0.10–0.13 ms → ~0.0057 ms/call** — both a **~17×**
    speedup, flat across N. `patternFill` (8×8 tile): **~0.06–0.10 ms →
    ~0.0064 ms/call**, a **~15×** speedup.

  Prototyped on `perf/fix-pixelDisplay-drawImage` (off `perf/00-harness-setup`,
  commit `66d4ce9`), together with the benchmark and this writeup. The fix
  itself (`lib/PixelDisplay.ms`'s `drawImage`/`patternFill`) plus its
  regression test (`tests/qa_pixelDisplay_drawImage.ms`) were then
  cherry-picked onto a short-lived branch off `Fixes` and fast-forward-merged
  in (commit `58741fe`), same pattern as S-P1. Not pushed to `origin`, not
  proposed upstream. No `lib/*.ms` caller has been updated to wrap its
  `drawImage`/`patternFill` calls in `beginBatch`/`endBatch` yet — same
  opt-in-API caveat as S-P1.
- **S-P5 (`_triangulate` O(n²) or worse) — fixed and verified for
  convex-heavy inputs.** Baseline (before this fix), regular convex
  polygons: 5 verts **0.090–0.11 ms**, 20 verts **0.24–0.27 ms**, 100 verts
  **1.0–1.6 ms**, 500 verts **4.8–18.4 ms**, 1000 verts **9.6–62.8 ms** per
  call (two figures where the fixed-code and reverted-code benchmark runs
  disagreed — see below; the reverted-code numbers match the original
  session's ~18.29 ms-at-500-verts measurement closely).

  **Root cause: a per-candidate-ear scan that's O(n) even when there's
  nothing in it to find.** `_triangulate` is textbook ear-clipping: repeatedly
  find a convex corner whose triangle contains no other vertex (an "ear"),
  clip it, repeat. For each candidate convex corner, the code scanned *all*
  n current vertices to see if any reflex one pokes into the candidate's
  triangle — `for j in range(0, n - 1) ... if cross[j] > 0 ... then continue`.
  For a convex polygon there are *zero* reflex vertices, so this scan always
  finds nothing — but it still costs O(n) per candidate, because the loop
  iterates over every vertex only to skip almost all of them via `continue`.
  Since the very first candidate in a convex polygon is always an immediate
  ear (no reflex vertex can ever disqualify it), this turns what should be
  an O(1) check per removal into an O(n) one, for O(n²) total across all n
  removals — explaining why even non-adversarial, perfectly ordinary convex
  shapes paid a quadratic cost with nothing concave to blame it on.

  Fixed by maintaining `reflexCount` — a running count of how many current
  corners are reflex — incrementally alongside the existing `cross` array
  (which already tracked each corner's convexity and was already updated
  incrementally on each vertex removal; `reflexCount` just tracks net sign
  flips in the same two neighbor updates `cross` already recomputes). When
  `reflexCount == 0`, the entire per-candidate reflex-vertex scan is skipped
  outright (behavior-preserving: with zero reflex vertices, that scan could
  never have found one to block the ear anyway). For a convex polygon,
  `reflexCount` is 0 from the start and for the whole triangulation, so this
  turns the O(n) per-candidate scan into O(1), and the overall cost from
  O(n²) into O(n). For a concave polygon, the fix only helps once enough
  reflex corners have been resolved into convex ones that `reflexCount`
  actually reaches 0 — a polygon whose reflex-vertex count scales with n
  (e.g. a star shape, deliberately used as a control below) sees no
  asymptotic improvement, by design: there's real reflex-vertex work left to
  do there, not a redundant scan.

  Verified correct by extending `PixelDisplay.runUnitTests`'s existing
  area-covering check (the triangles' total area must exactly match the
  polygon's) with new cases: convex 3/7/13-gons (`reflexCount` stays 0
  throughout — the fast path is exercised for the whole run), star-shaped
  polygons with 3/5/8 points (`reflexCount` stays well above 0 throughout —
  confirms the fix doesn't change behavior on the un-sped-up path), and a
  comb shape with several notches (`reflexCount` starts above 0 and drops to
  0 partway through clipping — exercises the incremental bookkeeping across
  that transition). All pass, alongside the pre-existing square/L-shape/
  collinear-edge/2dVis-regression/degenerate-input cases.

  Measured (3 repeat runs, consistent; also cross-checked by reverting the
  fix and re-running the identical benchmark for a direct before/after on
  the same machine state, not just against the earlier session's numbers):
  convex regular polygons — 500 verts **18.4 ms → 4.8 ms** (**~3.9×**),
  1000 verts **62.8 ms → 9.6 ms** (**~6.5×**, growing with n as expected
  since the asymptotic complexity itself changed, not just a constant
  factor). Star-shaped (concave, reflex-vertex count scales with n, used as
  a control): 500 verts **40.8 ms → 41.0 ms**, 1000 verts **152.1 ms →
  153.1 ms** — unchanged within noise, confirming the fix adds no overhead
  on inputs it can't speed up and doesn't just look fast by triangulating
  incorrectly.

  Prototyped on `perf/fix-pixelDisplay-triangulate` (off
  `perf/00-harness-setup`, commit `8727cf4`). The fix itself
  (`lib/PixelDisplay.ms`'s `_triangulate` plus the new `runUnitTests` cases
  it was verified against) was then cherry-picked onto a short-lived branch
  off `Fixes` and fast-forward-merged in (commit `45005a1`), same pattern
  as S-P1/S-P2 — no separate regression-test file was needed this time,
  since `_triangulate` is module-private and its correctness tests live
  inside `PixelDisplay.runUnitTests` itself, in the same file as the fix.
  Not pushed to `origin`, not proposed upstream. With S-P1, S-P2, and S-P5
  now all fixed, the only §4.3 items still open are the bug checks noted
  below.

### §4.3 bug checks

Four suspects from the plan's original PixelDisplay read-through (§4.3),
investigated this session:

- **`clear`'s possible double-free of an `autoUnload`-created render
  texture on resize — not a bug.** `clear` calls
  `rl.UnloadRenderTexture self._renderTex` by hand on a texture that was
  originally wrapped with `autoUnload`, raising the question of whether the
  GC later unloads it a second time when it collects the (by-then-orphaned)
  old texture object. Read `raylib-miniscript`'s binding layer
  (`RaylibTypes.h`'s `TakeResource`, used by every `Unload*` intrinsic): a
  manual unload empties the resource box and sets `box->live = false`;
  the `autoUnload` finalizer (`FinalizeResource`, `RaylibTypes.cpp`) only
  queues a real GPU unload when `box->live && box->autoUnload` — so a
  manually-unloaded-then-GC'd box is just freed as a C++ wrapper, never
  double-unloaded at the GPU level. Verified empirically too: created a
  `PixelDisplay`, forced its texture into existence, called `clear` with a
  different size 20 times in a row (every call hits the resize-and-replace
  path), forced GC pressure, and checked `resourceCounts.RenderTexture`
  throughout — stayed at exactly 1 (plus the 8 baseline render textures
  already in use) the whole time: no leak, no crash, no double-free.
- **`clear(color)` with no size resets a non-960×640 display to 960×640 —
  confirmed real bug, now fixed.** `PixelDisplay.clear = function(color=null,
  width=960, height=640)` hardcoded the Mini-Micro-screen-sized default
  instead of defaulting to the display's *current* size. Reproduced: a
  `PixelDisplay.Make(100, 50)` instance, after a bare `d.clear` with no
  arguments, reported `d.width`/`d.height` as `960`/`640` — silently
  resizing (and blanking) any custom-sized display the moment code called
  `clear` to, say, just change the background color.

  Fixed by defaulting `width`/`height` to `null` and falling back to
  `self.width`/`self.height` when not given, matching how every other
  optional-dimension method in this file already behaves; an explicit
  `width`/`height` still resizes exactly as before. Verified with a new
  regression test, `tests/qa_pixelDisplay_clear.ms`: a bare `clear()` and a
  `clear(color)` both preserve the display's current (non-default) size, an
  explicit `clear(color, width, height)` still resizes, and `clear()` on an
  already-960×640 display is unaffected.

  Fixed directly on a branch off `Fixes` (`fix/pixelDisplay-clear-resize-
  default`, commit `812d398`) and fast-forward-merged in — no cherry-pick
  needed this time, since (unlike the PixelDisplay perf fixes) this branch
  never carried any perf-harness files to leave behind. Also merged into
  `perf/00-harness-setup` (a regular merge, since the two branches had
  diverged — this also pulled in the earlier Sound.StopAll fix and its
  `qa_sound_stopall.ms` test, which `perf/00-harness-setup` hadn't had
  merged in before). Not pushed to `origin`, not proposed upstream.
- **`render`'s "NULL `_renderTex`!" print-then-dereference — already
  fixed upstream, not reproducible.** The plan's note refers to a specific
  line in the pre-sync code snapshot; the current `render` (after the
  Session 1 upstream sync) simply does `if self._renderTex == null then
  return` with no print statement and no dereference afterward. Closed,
  same as S-P3/S-P4.
- **`setClip`/`clearClip` edge behavior — no crashes or corruption found.**
  Tried: a clip with negative width/height (no crash; the fillRect painted
  through unclipped rather than being hidden or erroring — raylib's
  `BeginScissorMode` evidently treats a degenerate scissor rect as a no-op
  rather than clipping everything, which isn't obviously wrong but isn't
  specified anywhere either), a clip rectangle placed entirely outside the
  display (correctly blocks all drawing, no crash), a clip covering exactly
  the whole display (draws normally, including the corner pixels), `line`
  with `penSize` 0 and negative (no crash either way), and drawing
  (`fillRect`/`setPixel`) with coordinates entirely off-display (no
  crash). No fix needed; the negative-size-clip behavior is a minor
  unspecified edge case, not a correctness bug, and isn't pursued further
  without a Mini Micro reference to compare against.

### Not yet done (left for next session)

- §4.1's "idle display stack" cost and the `display(5).mode = displayMode.off`
  fill-rate-floor comparison, and the `wait` timing-accuracy checks (0.1s/1s/5s),
  are additional 4.1 workloads not yet built — only the fixed per-frame engine
  cost via `perf.frames` was covered this session.
- Baselines for the rest of Tier A (§4.2, §4.4–§4.11) and the §5 integration
  scenarios: next session, per §8 step 2. (§4.3 PixelDisplay is now
  re-verified and measured, above, ahead of the rest of Tier A.)
- §9 binding overhead and §10 VM profiling: later sessions, per §8 steps 5–6.
- §4.3's bug checks are done (see above): three closed (double-free isn't
  real, the NULL-dereference print was already fixed upstream, setClip/
  clearClip edges don't crash), one confirmed real and now fixed —
  `clear`'s hardcoded 960×640 default silently resizing any custom-sized
  display, merged into `Fixes` (commit `812d398`).
- All five fixes accumulated on `Fixes` this session (Sound.StopAll,
  S-P1/S-P2/S-P5, and the `clear` resize-default bug) are now **proposed
  upstream**, as a single batch rather than one PR apiece — easier for Joe
  to review as one coherent chunk of work than five separate PRs or one
  giant PR mixing them with everything else `Fixes` might later
  accumulate. Built as a fresh branch,
  `upstream-pr/pixelDisplay-perf-and-bugfixes`, cherry-picked straight onto
  `upstream/main` (clean — no merge commits, no unrelated pre-existing
  commits like the older `bmfFonts.ms` `hex2` fix that was also sitting on
  `Fixes`), pushed to `origin`, and opened as
  [JoeStrout/soda#27](https://github.com/JoeStrout/soda/pull/27).
  All four regression tests re-verified passing on that clean branch
  before pushing.
- To avoid piling further work onto a branch that's now the base of an
  open PR, future fixes merge into a new branch, **`Fixes2`** (branched
  from `Fixes`'s tip, commit `812d398`, and pushed to `origin`), not
  `Fixes` itself. `Fixes` stays as it is until PR #27 is resolved.

## Session 2 — Tier A baselines: §4.2, §4.4–§4.11

Scripts: `tests/perf_{display,sprites,text,tile,image,sound,input}.ms` (input also covers §4.11 color). Each run 3x, CSVs in this folder; run-to-run spread under ~5%. Run from `tests/` with `../../raylib-miniscript/build-release/raylib-miniscript <script> <runIdx>`.

### Headline numbers (median of 3 runs, ms)
| Area | Workload | Result |
|---|---|---|
| §4.5 text | full 68x26 screen (1768 cells), shader path | ~415-435 ms/frame (~240 us/glyph), same for clear/opaque/alternating colors |
| §4.5 text | same screen, forced no-shader fallback (S-T3) | ~32 ms/frame (**~13x faster**) |
| §4.5 text | 160x100 full | ~4000+ ms/frame |
| §4.6 tile | scrolled map 10 / 50 / 200 / 1000 square | 1.7 / 18.4 / 273 / 6830 ms/frame (S-L1 confirmed: ~6.7 us per cell, visible or not) |
| §4.6 tile | half-empty 200x200 | ~140 ms (empties still cost iteration) |
| §4.4 sprites | plain 1 / 100 / 1000 / 5000 | ~1 / 1.5 / 6.4 / 28.5 ms/frame (~5.5 us/sprite) |
| §4.4 sprites | setUVs / setCorners quad path, 1000 | ~6.0 ms, same as plain: S-S2 not visible at these counts |
| §4.4 Bounds | `overlaps` single call | ~31 us (all-pairs among 200 sprites: 432 ms) |
| §4.2 display | 8 empty text displays RenderAll | ~5.5 ms/frame (each empty TextDisplay ~0.68 ms: render still walks every cell) |
| §4.2 display | mode switch / display(n) | ~4 us / ~1 us |
| §4.9 sound | synth cost | ~24 ms per second of audio (S-A1), lands on first `play`; 8-way mix of 1 s: ~200 ms |
| §4.9 sound | UpdateAll 10 / 100 playing | 0.008 / 0.084 ms |
| §4.8 image | pixel / setPixel | ~5 / ~6.7 us each; 512x512 full loop ~1.3 / 1.7 s |
| §4.8 image | edit k pixels + re-upload (S-I1), 256x256 | 0.07 ms (k=1) ... 69 ms (k=10000), dominated by setPixel cost at large k |
| §4.8 image | 10,000 getImage then GC | Image count back to 2: **no leak** |
| §4.10/4.11 | key.pressed, axis, update, mouse, color.* | all 0.0002-0.009 ms per call, well under the 0.1 ms bar |

### Bugs
- **BUG: `color.fromList(list)` crashed** (`s.append`, lists have no append). Same on upstream/main. Fixed on `fix/color-fromList-list` (off `Fixes2`) with `tests/qa_color_fromList.ms`. Not pushed.
- **BUG (confirmed, not fixed): `key.pressed("notAKey")` and `key.pressed("mouse ")` print an error and `exit`**, killing the program.
- **Gotcha:** a user-script global named `list` shadows the type inside lib code (`sp isa list` in SpriteDisplay broke). Likely any lib relying on built-in type names is exposed.
- `Display` edges (`display(-1)`, `display(8)`, `display("a")`) return non-displays, no crash: `tests/qa_display_edges.ms`.
- Display.install bugs were already fixed upstream (Session 1).

### Next fix candidates (ranked by impact)
1. S-T1: ScreenFont.drawChar shader bracket per glyph (13x available just by using the fallback path; a single bracket around render or vertex-color approach should do better).
2. S-L1: TileDisplay.render culling.
3. S-S3/S-A1/S-T4: collision cost, first-play synthesis hitch, empty-text-display cost.

### Not yet done
Unrun: remaining §4.1 leftovers, §4.12-4.13, §5 integration scenarios, bug probes for sprites (zero/negative scale, mutation during iteration), §9, §10.

### S-T1 fix: ScreenFont.drawChar batchable path (on `Fixes2`, commit 0f142c0)
Root cause: the glyph shader takes fore/back colors as uniforms, so it was bound (BeginShaderMode/EndShaderMode = batch flush) around every glyph. Fix: when fore is opaque and back is fully opaque or fully transparent, draw `DrawRectangle(back)` + `DrawTexturePro` tinted with fore, which is pixel-identical to `mix(back, fore, mask)` for the binary-alpha font sheet and batches normally. Translucent fore or partly transparent back still use the shader.
- Verified: `tests/qa_screenfont_draw.ms` compares drawn pixels with the font mask for all four color cases; passes on both old and new code, so the output is unchanged.
- Measured (`perf_results/perf_text.afterSP-T1.csv`): full 68x26 screen 420 -> 28-33 ms/frame (~13-15x); 160x100 grid 4000 -> 250 ms (~16x). Remaining ~17 us/glyph is the MiniScript render loop (S-T2 color.toList per glyph, srcRect list, S-T4 no dirty flag) - next candidates.
- Not pushed, no PR yet. Also on `Fixes2`: the `color.fromList` fix (1135063).

### TextDisplay wrap-up (§4.5) — S-T2 fixed, S-T4 deliberately not done
- **S-T2 fixed** (`Fixes2` c8e17a6): `ScreenFont.drawChar` cached `color.toList` results per color string (a string parse cost ~6 us, twice per glyph) and glyph source rects per code point; `TextDisplay.render` tests for blank/transparent cells first and hoists loop invariants. Output unchanged (`qa_screenfont_draw.ms` passes). Full 68x26 screen: 33 -> 8-12 ms; 160x100: 250 -> 63 ms; empty TextDisplay ~0.68 -> ~0.47 ms. Cumulative since baseline: ~420 -> ~8-12 ms (35-50x) and 4000 -> 63 ms (160x100). Data: `perf_text.afterSP-T1.csv`, `perf_text.afterSP-T2.csv`.
- **S-T4 (dirty flag / offscreen cache) not done, on purpose:** a cache would take full-screen text from ~10 ms to ~0.1 ms, but cells are plain public maps that callers (e.g. the console) mutate directly (`c.color`, `c.inverse`), so any dirty tracking can miss writes and show stale text. Revisit only with an agreed API (e.g. cell mutators that mark dirty, plus a documented `markDirty`).
- **S-T3** (no-shader fallback) was measured; it is now effectively the default path for opaque colors.
- **Bug probes** (`tests/qa_textDisplay_edges.ms`, all pass, no bugs found): `delimiter=""`, default delimiter, `row=`/`column=` clamping, `scroll` at 1 row, scroll row aliasing, unicode outside the font, out-of-range `setCell`/`cell`, cursor show/hide restoring colors, tab/backspace. `lib/TextDisplay.ms` self-test passes. `tests/text.ms` is a visual demo and was not run.

### Upstream PR #28
S-T1, S-T2 and the `color.fromList` fix are proposed as [JoeStrout/soda#28](https://github.com/JoeStrout/soda/pull/28), a clean 3-commit branch (`upstream-pr/text-perf-and-color-fix`) off `upstream/main`, independent of #27.
