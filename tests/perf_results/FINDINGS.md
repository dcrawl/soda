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
| §4.4 sprites | setUVs / setCorners quad path, 1 / 100 / 1000 | 1.1 / 25 / 234 ms/frame (**~240 us/sprite, ~40x plain**: S-S2 confirmed; this row originally said "same as plain", which was wrong — see S-S2 fix below) |
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
- **NOTE (intentional, not a bug): `key.pressed("notAKey")` and `key.pressed("mouse ")` print an error and `exit`**, killing the program.
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

### S-L1 fix: TileDisplay.render culls off-screen cells (on `Fixes2`, commit 226e3dc)
`render` now computes the column/row window that can touch the screen (padded for rotation, stagger offsets, non-square cells) and loops only over that. Falls back to the full grid when the per-axis spacing is <= 0 (overlap >= cell size).

| Map (scrolled, 32px cells, 960x640) | Before | After |
|---|---|---|
| 10x10 | 1.7 ms | ~1.2 ms render |
| 50x50 | 18.4 ms | ~7 ms |
| 200x200 | 267 ms | ~7 ms |
| 1000x1000 | 6788 ms | ~9 ms total |

Frame cost is now bounded by the visible tile count (~6.5 ms for ~600-700 tiles, i.e. ~10 us/tile), which is the S-L2 per-tile allocation cost (`_tileGeometry` builds a map and rects per cell). Raw data: `perf_tile.afterSL1.csv`.
Regression test: `tests/qa_tile_cull.ms` (counts `DrawTexturePro` calls against a brute-force visible-cell bound across scrolls, stagger, non-square cells, overlap, rotation, and the overlap==size fallback).
Note: MiniScript has no global `max`/`min`; the first draft failed on that.
Next: S-L2 (remove per-tile geometry allocation) would take the visible-tile cost down further.

### S-L2 fix: TileDisplay.render inlines tile geometry
`render` hoists every loop invariant (tile-set size, origin, offsets, grids, screen height) and computes src/dest rects inline, instead of calling `_tileGeometry` (a map + several lists per tile). `_tileGeometry` is kept for callers/tests.

| Scrolled map | After S-L1 (render) | After S-L2 (render) |
|---|---|---|
| ~600 visible tiles (50/200/1000 maps) | ~6.4 ms | ~1.7 ms |
| half-empty | ~3.4 ms | ~1.1 ms |

Total frame at 1000x1000: 6788 ms originally -> ~4.6 ms. Data: `perf_tile.afterSL2.csv`. Regression test `tests/qa_tile_args.ms` checks every draw argument against `_tileGeometry` across stagger, overlap, non-square cells, all 8 transforms and tints.

### S-A1 fix: Sound synthesis loop inlined; key.pressed exit documented
- **S-A1:** `Sound._addSamples` inlines the waveform/envelope look-ups (`_lookupLUT` was 2 calls per sample) and hoists invariants. Synthesis 24.7 -> 12.2 ms per second of audio (8-way mix of 1 s: 200 -> 101 ms); a 1 s first `play` is now 13 ms, under one 16.7 ms frame. Remaining ~1.2 us/sample is the interpreter loop itself; a faster result would need synthesis chunked across frames or moved to the host. Data: `perf_sound.afterSA1.csv`. Test `tests/qa_sound_synth.ms` compares against the original loop over 210 waveform x envelope x freq combinations (tolerance 1e-9) plus a mix.
- **key.pressed bad name: left as is.** `key.pressed("notAKey")` prints the valid names and a stack trace, then calls `exit`. That is deliberate fail-loudly behavior, not a bug, so a warn-and-return-false change was tried and reverted (not in `Fixes2`). Worth knowing: a typo in a key name kills the program, including `"mouse "` style names. The probe that found it is retained in the earlier baseline notes.

### S-S2 / S-S3 / S-S1 fix: sprite drawing and collision (on `Fixes2`)
**S-S2 (confirmed, the big one).** Warped (`setUVs`/`setCorners`) sprites ran `BeginShaderMode`/`EndShaderMode` around every sprite, and set a per-sprite `uH` uniform. A batch flush on this machine costs ~250-370 us (measured directly: quad + `rlDrawRenderBatchActive` = 370 us, `Begin/EndShaderMode` + one quad = 249 us, same quad without a flush = 6 us), so every warped sprite paid that. The homography solve was already cached (cache hits confirmed) and was not the problem.
- Fix: compute the homogeneous texcoord `H*[x,y,1]` per vertex on the CPU and send it as vertex data (u*w, v*w in the texcoord, w in the otherwise unused vertex z) with a tiny custom vertex shader, so nothing varies per sprite except vertex data. `SpriteDisplay.render` then holds one shader bracket open across consecutive warped sprites and closes it before any plain sprite, so draw order is unchanged. `Sprite.draw` called directly (outside a display) still brackets its own sprite.
- Result (`perf_sprites.afterSS.csv`): 100 warped sprites 25.1 -> 4.6 ms, 1000: 234 -> 36 ms/frame (**6.5x**; setCorners the same). Remaining ~36 us/sprite is MiniScript (`corners`, `uvs`, `tuv`, list compares, `_tintRGBA`), a candidate for caching if anyone needs thousands of warped sprites.

**S-S3 (confirmed).** `Bounds.overlaps` built both corner lists and ran four projections of four corners each (~31 us). Rewritten as the equivalent rectangle-vs-rectangle separating-axis test on center distance and projected half-extents (4 axes, no allocation), with a trig-free path when neither box is rotated; `Bounds.contains` also skips trig when unrotated. Single `overlaps` 31 -> 8 us; all pairs among 200 sprites 433 -> 124 ms (the remainder is `worldBounds` allocation plus the test loop); `contains` over 200 sprites 1.0 -> 0.8 ms. Touching edges still count as overlapping. One behavioral difference: a zero-width or zero-height box now takes part in the test on all four axes (the old code skipped the degenerate axis and could report an overlap with a segment that was actually apart).

**S-S1 (real, small).** `Sprite.draw` allocated about 5 lists per call; now 3 (src, dest, origin) with no `_scaleXY`/`srcRect` copies. Measured gain only ~5% (1000 plain sprites 7.2 -> 6.8 ms/frame, 5000: 29.1 -> 27.9): the ~5.5 us/sprite is dominated by the MiniScript call and property lookups, not allocation. Kept because it is tested and harmless, but this is not a hotspot.

**Tests.** `tests/qa_sprite_render.ms` renders a fixed scene (plain, rotated, flipped, tinted, srcRect, warped sprites interleaved with plain ones, nested lists) offscreen and compares it with `tests/qa_sprite_render_ref.png`, recorded from the *old* code before any change. Warped quads sample on texel boundaries with slightly different float rounding (~127 single pixels differ), so it compares 8x8 block means; a swapped-UV mutation fails it with ~200 bad blocks. `tests/qa_bounds_overlaps.ms` checks the new `overlaps`/`contains` against the original SAT (kept as the reference) on edge cases plus 3000 random pairs. Both pass.

**Sprite bug probes (done, no bugs found).** Scale 0 / `[0,2]` draw nothing; negative and list scales flip; `srcRect` outside or partly outside the image, `image = null`, `tint` null or garbage, degenerate UVs/corners, `setCorners` with scale 0, the same sprite twice in a list, a sprite in two displays, empty and nested-empty lists, and a non-Sprite object with its own `draw` all render without error and sensibly. Removing from a list while iterating it is plain MiniScript `for` semantics (one element skipped), not a display issue. A `null` entry in `display.sprites` raises "Can't index into null" in `_renderSprites`, same as before these changes; left alone as a user error. Pinned by `tests/qa_sprite_edges.ms`.

## Session 3 — §4.1 leftovers, §4.12 fonts, §4.13 Tier C utilities

### §4.1 soda.ms frame loop (`perf_soda.ms`, `qa_window.ms`): no bugs
- Idle display stack (default): render ~0.51 ms/frame; with slot 5 (PixelDisplay) off: 0.51 (no saving — PixelDisplay is not the cost; the empty TextDisplay is, see S-T4); all displays off: 0.004 ms. So the floor is cheap; ~0.5 ms is the default stack.
- `wait()`: accuracy fine (0.1 s -> 0.101, 1 s -> 1.002, 5 s -> 5.015 at 60 fps, frames rendered ~60/s). **NOTE:** `wait 0` renders zero frames (the loop condition is false immediately) and `wait 0.001` renders one; `wait` also calls `intrinsics.yield` before `update`, the reverse of `yield`. Harmless, not changed.
- `window.width/height/title` round-trip, `fullScreen = 1` twice does not toggle back (checked with raylib's toggle stubbed), and a second `import "soda"` does not break the `version` shadow. Pinned by `tests/qa_window.ms`.

### §4.12 Fonts (`perf_fonts.ms`, `qa_bmfFonts.ms`)
Sample BMF fonts come from the Mini Micro system disk checkout (`study/minimicro-sysdisk/sys/fonts`); the TrueType test uses `raylib-miniscript/assets/Merkin.ttf`.
- **BUG (fixed): 24 of the 34 sample fonts crashed on load**, e.g. `NotoSansBold-24.bmf`: "list index 1020 out of range" in `color.rgb`. The loader builds palette colors as `byte*4`; these fonts have palette bytes above 63, so channels exceeded 255. Mini Micro's `color.rgb`/`rgba` clamp to 0-255; Soda indexed a 256-entry hex table with the raw value, crashing above 255 and **silently wrapping below 0** (`color.rgb(-1,0,0)` gave `#FF0000`). Fixed in `color.ms` (`rgb`, `rgba`, `fromList` list and map forms) with a fast in-range check, ~0.1 us per call; `tests/qa_color_clamp.ms`. All 34 fonts now load (8-126 ms each, 1.1-format fonts fastest).
- **S-F1 (fixed): `Font.print` drew every glyph with its own `gfx.drawImage`**, paying the PixelDisplay per-call GPU bracket each time: warm print of 1000 characters 77 ms/frame (77 us/char). It now holds one `gfx.beginBatch true`/`endBatch` across the string (only when `version.hostName == "Soda"`, since Mini Micro's gfx has none): 1000 chars 8.4-9.4 ms (**~8x**), 100 chars 8.5 -> 2.1 ms, `printJustified` 7.7 -> 2.2 ms. `qa_bmfFonts.ms` checks the batched output is pixel-identical to a per-glyph `printChar` loop.
- Glyph images are cached after the first print (`getCharImage`/`printChar`): first print of a string costs ~0.1-0.45 ms per distinct glyph (the pixel-by-pixel `renderChar`, ~1 ms for Arial14 'W', ~2.7 ms for a 24 pt glyph), then nothing. The first print of a 1000-character paragraph is 75 ms cold.
- `width` 0.12-0.19 ms per 100 chars; `lenToFit` of a 1000-char string 2.6-3.9 ms (binary search, each probe O(n)).
- TrueType (`ttFonts`): load 0.5 ms, print 100 chars 1.3 ms and 1000 chars 1.4 ms/frame, `width` 5 us per 100 chars. No problem.
- Bug probes, all pass (`qa_bmfFonts.ms`): lowercase falls back to the uppercase glyph; kerning (the font's own pairs plus `setKern`) applies in `width`; missing glyphs have zero width; `lenToFit` edge cases; `save`/`load` round-trip keeps glyph count, line height and widths. `printJustified` with one word or empty text does not crash. `Font` is reached as `bmfFonts.Font` (not a global). **NOTE:** `TTFont.Load` prints an error and `exit`s on a bad path (like `key.pressed`; assumed intentional).
- Not run: `bmfFonts` and `ttFonts` interactive demo blocks (need a user at the keyboard).

### §4.13 Tier C utilities (`perf_utils.ms`) — report only, nothing patched
- Built-in `runUnitTests` pass for json, grfon, tsv, stringUtil, listUtil, mapUtil, mathUtil, matrixUtil, base64 and qa. textUtil has no unit tests, only an interactive dialog demo (not run).
- Everything scales linearly; no accidental O(n^2) found. One-shot ms (`perf_utils.run1.csv`):
  | Op | Small | Medium | Large |
  |---|---|---|---|
  | json toJSON / parse | 1.8 KB: 1.0 / 1.7 | 169 KB: 90 / 159 | 1.7 MB: 910 / 1615 |
  | grfon toGRFON / parse | 1.2 KB: 1.2 / 2.1 | 115 KB: 116 / 201 | 1.2 MB: 1170 / 2042 |
  | tsv parse (rows) | 100: 0.6 | 1000: 6.1 | 10,000: 64 (keyed: 46) |
  | base64 toRaw / toString | 1.3 KB: 1.2 | 133 KB: 122 | 1.3 MB: 1225 |
  | list distinct / counts / filtered / applied | 1e4: 3.6 / 3.4 / 3.1 / 2.8 | 1e5: 34 / 34 / 31 / 28 | |
  | list sort / shuffle (native) | 1e4: 0.6 / 0.06 | 1e5: 5.1 / 0.5 | |
  | string wrap(67) | 10 KB: 0.35 | 100 KB: 11 | 400 KB: 138 |
  | matrix times | 10x10: 0.005 | 100x100: 0.105 | |
  Rule of thumb: json parse ~1 us/byte, grfon ~1.7 us/byte, base64 ~0.9 us/char, so a 1 MB document costs 1-2 s: fine at load time, far too slow per frame.
- `string.wrap` is mildly superlinear (4x more text costs 12x, from `s = s[i+1:]` re-slicing the remainder each line); fine up to a few hundred KB. `editDistance` is O(n^2) as expected (1000 chars: 276 ms). Matrix operations are native and fast. `list.distinct`/`counts` cost ~0.34 us per element, 5-10x `sort`.
- Nothing here blocks a game; the useful finding for users is the 1-2 s/MB figure for json/grfon/base64.


## Session 4 — §5 integration scenarios (`perf_scenarios.ms`)

600 frames each, uncapped, Release host, on Fixes2+perf. Means, ms/frame (run1; paint-batched is run2):

| Scenario | user | render | endDrawing | total | ≈fps |
|---|---|---|---|---|---|
| 1 balls ×100 (with bongo sounds) | 0.15 | 1.07 | 0.48 | 1.8 | 560 |
| 1 balls ×1000 | 1.4 | 6.0 | 0.76 | 8.3 | 120 |
| 1 balls ×5000 | 7.1 | 28.2 | 1.0 | 36.9 | 27 |
| 2 text adventure (print + scroll) | 0.25 | 2.8 | 0.61 | 3.8 | 260 |
| 3 platformer (200×50 tiles, 50 sprites, 20 overlaps, PixelDisplay HUD) | 0.37 | 1.75 | 0.56 | 2.9 | 350 |
| 4 paint, 200 line/fillEllipse per frame | 18.3 | 0.59 | 0.96 | 20.0 | 50 |
| 4b paint, same calls inside `beginBatch`/`endBatch` | 1.0 | 0.59 | 0.99 | 2.1 | 480 |
| 5 everything (500 balls, tiles, text, pixel, music) | 2.0 | 5.0 | 1.0 | 8.3 | 120 |

Findings:
- **Nothing in the realistic scenarios is a frame-budget problem** except the paint program, and balls ≥5000 (render-dominated: ~5.6 µs/sprite render, ~1.4 µs/sprite user).
- **Paint (scenario 4)** profile: 80% of time is `BeginBlendMode`/`EndBlendMode` (~0.027 + 0.079 ms per call), i.e. the per-primitive blend/framebuffer bracket. Wrapping the frame's draws in one `px.beginBatch`/`px.endBatch` (non-alpha, matching line/fillEllipse) cuts user time 18.3 → 1.0 ms (18×). So the S-P1 fix (PR #27) is effective, but only for callers that batch. Note `beginBatch true` (alpha) gave **no** gain here: line/fillEllipse use replace mode, so every call mismatches the batch and falls back to per-call blend setup. A caller must match the primitive's blend mode, which is easy to get wrong.
- Resource counts after each balls run are flat (12 total, same as baseline); no leaks seen across scenarios.
- Not done: 10-minute soak (§6), profiles for scenarios 1–3, 5 (only paint profiled; `scn4_profile.*`).

Possible follow-up: make unbatched PixelDisplay primitives cheaper automatically (e.g. defer EndBlendMode/EndTextureMode to render time), so paint-style programs need no explicit batching.

### Auto-batching prototype (branch `perf/autobatch`, commit on top of Fixes2)
Unbatched PixelDisplay calls now leave the BeginTextureMode/BlendMode bracket open (Soda host only) and `PixelDisplay._closeOpen` closes it before anything else touches the GPU: another display's draw or `beginBatch`, `pixel`/`getImage` readbacks, `clear` resize, `_ensureTex`, `render`, `soda.update` (before `BeginDrawing`), ttFonts, and texture frees in `Image`/`ScreenFont`.

| Scenario (user ms/frame) | before | after |
|---|---|---|
| 4 paint, unbatched | 18.3 | 1.04 (18×) |
| 3 platformer (HUD print) | 0.37 | 0.25 |
| 5 everything | 2.0 | 0.9 |
| others | unchanged | unchanged |

Hazard: any code that uses raw raylib framebuffer/texture calls (`BeginTextureMode`, `UnloadTexture` of a texture a PixelDisplay just drew, its own `BeginDrawing`) must call `PixelDisplay._closeOpen` first, else its output lands in the display or draws are lost. Three existing qa tests that do this needed a one-line `_closeOpen`. All qa_* tests pass, plus new `qa_pixelDisplay_autobatch.ms`.

Update: auto-batching is now **opt-in** (`PixelDisplay.autoBatch = true`, default false; still Soda-host only). Default numbers are therefore back to baseline (paint unbatched 18.3 ms); with the flag on, `scn4_paint_auto` = 1.05 ms. `qa_pixelDisplay_autobatch.ms` runs both ways (`off` arg) and asserts the default is off; all other qa tests pass with the flag off.

## Session 5 — §9 binding overhead (`perf_binding.ms` vs `raylib-miniscript/tools/bench_native.c`)

ns per call (median of 5 reps × 2000 calls, Release host, closure-call cost subtracted; native = same raylib build, same args, in a C loop). Raw: `perf_binding.run1.csv`, `perf_binding.native.csv`.

| Call | arg form | native | MiniScript | overhead | ×native |
|---|---|---|---|---|---|
| (dispatch floor) GetScreenWidth / GetMouseX / IsKeyDown | – | 1 | 216 / 233 / 250 | ~215–250 | 220× |
| rlTexCoord2f / rlColor4ub / rlVertex2f | numbers | 1 / 1 / 12 | 259 / 290 / 283 | ~260–290 | – |
| DrawTexturePro | lists, tint list | 55 | 683 | 628 | 12× |
| DrawTexturePro | lists, tint string | 55 | 672 | 617 | 12× |
| DrawTexturePro | lists, tint `raylib.WHITE` (map) | 55 | 857 | 802 | 16× |
| DrawTexturePro | maps (rect, rect, vec), tint list | 55 | 1502 | 1447 | 27× |
| DrawTexturePro | maps, tint map | 55 | 1670 | 1615 | 30× |
| DrawTexturePro | lists built inline each call | 55 | 923 | 868 | – |
| DrawTexture | tint list / str / map | 56 | 542 / 516 / 723 | ~460–670 | 10–13× |
| DrawPixel | color str / list / map | 54 | 457 / 455 / 927 | 400 / 400 / 870 | – |
| DrawLineEx | lists / maps | 75 | 669 / 1318 | 594 / 1243 | 9× / 18× |
| DrawRectangle | ints, str / list | 55 | 463 / 477 | ~410 | 8× |
| DrawRectangleRec | rect list / map | 55 | 526 / 1218 | 471 / 1163 | – |
| SetShaderValue | vec4 list (preallocated / inline) | 156 | 648 / 740 | 492 / 584 | 4× |
| Begin/EndShaderMode (nothing drawn) | – | 439 | 915 | 476 | 2× |
| GetImageColor | returns a map | 3.8 | 914 | 910 | 240× |

Findings:
- **Dispatch floor is ~220 ns per intrinsic call**; argument conversion adds ~200–400 ns for list forms. Binding overhead is 8–30× the native cost of cheap calls but only ~0.4–0.9 µs absolute.
- **Map-form arguments are ~2× a list form** (each rect/vector map ≈ +270 ns; a color map ≈ +175 ns): consistent with the key-name `String`s being rebuilt per call (§9.1). Color *strings* cost the same as lists (no parse penalty).
- **Reusing vs building lists inline** costs ~240 ns for three lists — the MiniScript allocation side, not the binding.
- **`Sprite.tint` defaults to `raylib.WHITE` (a map)**: +175 ns per untinted sprite (≈0.17 ms per 1000 sprites, ~3% of sprite render). Candidate lib fix: default `[255,255,255,255]`.
- `GetImageColor` allocates a map per call (~0.9 µs) — only matters for per-pixel `Image.pixel` loops.

Binding cost per frame at the §5 scenario call counts (calls × MiniScript ns):
| Workload | calls/frame | binding ms/frame | share of frame |
|---|---|---|---|
| 1000 plain sprites (DrawTexturePro, map tint) | 1000 | 0.86 (0.63 floor-excluded) | ~13% of 6.8 ms |
| 1000 warped sprites (~11 rl calls each) | 11000 | ~3.1 | ~9% of 36 ms |
| 600-cell tile grid (DrawTexturePro) | 600 | ~0.4 | – |
| paint, 200 draws (batched) | 200 | ~0.14 | ~14% of 1.0 ms |
| 5000 balls | 5000 | ~4.3 | ~12% of 37 ms |

**BIND-01 (sprites ≥1000, borderline >0.5 ms):** the binding is ~12% of sprite render; the rest is MiniScript list building and property reads. Fixes by repo: (a) `lib/`: default tint to a list (−0.17 ms/1000); reuse lists (only when Sprite.draw can avoid allocating, −0.24 µs each); (b) `raylib-miniscript`: intern key `String`s in the map converters (would halve map-form cost, but Soda barely passes maps once the tint default is fixed); (c) a host batch intrinsic (`DrawTexturesPro` taking parallel lists) would remove ~0.6 µs × N dispatch+conversion, the largest remaining prize (~10% of 1000-sprite frames), but is an API addition and was not prototyped.
Negligible: key/mouse queries (0.25 µs), rlgl immediate calls (0.28 µs each), DrawPixel/DrawRectangle/DrawLineEx with list or string args (≤0.7 µs), SetShaderValue.

Native benchmark: `raylib-miniscript/tools/bench_native.c` + `bench_native` CMake target (EXCLUDE_FROM_ALL; branch `perf/bench-native`, not pushed).

### BIND-01 prototype: `Sprite.tint` defaults to `[255,255,255,255]` (branch `perf/tint-default`)
Plain untinted sprites, render ms/frame (mean of 2 runs): 1000 sprites 5.63 → 5.32 (−5.5%); 5000 sprites 26.0 → 24.6 (−5.4%). Explicit `tint = raylib.WHITE` (map) stays at 5.56 / 25.9, confirming the saving is the map→list conversion (~0.3 µs/sprite, a bit more than the 175 ns microbenchmark predicted). qa_sprite_render/edges/bounds pass.

## Session 6 — §6 robustness and leak soak

Scripts: `perf_churn.ms`, `perf_soak.ms`, `perf_hostile.ms` + `run_hostile.sh`.

### Churn (N=10000; sounds 2000)
Images (with/without texture, released), Sprites, PixelDisplays, synthesized Sounds and
Display.mode switches: after GC, every `resourceCounts` entry returns to baseline (the only
residual is the RenderTexture held by the last live `px` variable). Caveat: the sprite phase
only yielded without rendering, so it does not exercise sprite draw churn.

### Soak (scenario 5, 600 s, 71,778 frames)
`resourceCounts` flat for the whole run (RenderTexture 8, total 17, Texture 4, Sound 1).
**`hostMemory` grew 14.6 MB -> 38.9 MB (~+2.4 MB/min), no plateau.** Not yet attributed:
candidates are MiniScript heap growth awaiting GC, per-call map/string garbage from the
host converters, or a real leak. Follow-up: repeat with sprites/sound/text/pixel each
disabled in turn to bisect the source.

### Hostile inputs (null, -1, 1e9, -1e9, "abc", list, map, NaN; all args the same value)
134 public methods x 8 values = 1072 runs, one process each.
- **Host crashes: none** (an earlier pass showed 248 SIGSEGVs for mouse/key/color/ScreenFont;
  they did not reproduce in isolation or on rerun and are attributed to the sweep running
  concurrently with the soak process).
- 957 ok; 272 are MiniScript runtime errors (mostly "Can't index into null" and
  "can't compare number and X": unvalidated arguments, not crashes).
- **Hangs with 1e9 (3):** `Sound.noiseWave`, `TextDisplay.setSize`, `TileDisplay.extent=`
  with a huge size run an enormous loop/allocation (> 10 s). Expected-ish, low priority.
- Note: after a runtime error in a script run this way the host stays alive rather than
  exiting; the driver kills it when it sees "Runtime Error".
Raw results: `perf_hostile.csv` (`hostile.csv`).

### Soak bisect (180 s each, five runs concurrently, one component disabled per run)
`hostMemory` growth over the run (MB, frames, MB per 1000 frames):

| disabled | start -> end | frames | MB/1000 fr |
|---|---|---|---|
| none (baseline) | 14.8 -> 24.3 | 15504 | 0.61 |
| sprites | 14.8 -> 25.3 | 23530 | 0.45 |
| sound | 14.6 -> 23.9 | 15512 | 0.60 |
| text | 14.6 -> 22.4 | 16663 | 0.47 |
| pixel | 14.6 -> 19.5 | 21906 | 0.22 |

Disabling pixel drawing (20 `px.line` + 1 `px.print` per frame) cuts growth by ~60% and, unlike
every other configuration, the series stops climbing: 17.6, 17.7, 19.2, 18.7, 17.3, 19.2 MB
(a sawtooth, i.e. garbage collected). Text accounts for a smaller share (~25%); sprites ~25%;
sound ~0. Resource counts stayed flat in all runs. All runs also show a ~6 MB step in the first
30 s (warm-up). Interpretation: the monotone growth is mainly allocation churn from PixelDisplay
draw calls (colour-string/map conversions in the host or temp lists in PixelDisplay.ms) that the
collector reclaims lazily, not a proven leak. To confirm: a pixel-only soak for >=30 min; if it
still has no plateau, profile allocations in `PixelDisplay.line`/`print`.

### VM-01  Unique short strings leak host memory (found via the 30-min soak)
**Soak:** pixel-only scenario, 30 min / 553,070 frames: `hostMemory` 14.7 MB -> 179 MB, no
plateau (steps at heap growth), resource counts flat. So the earlier "sawtooth" reading was wrong.
**Bisect** (4 min runs, one op per frame; MB over the run): empty loop, `px.line`, `px.clear`,
batched line: flat (+1 MB warm-up). `px.print "N " + n`: +25 MB / 124k frames. `px.print`
with a constant string: flat. A bare `t = "N " + n` with no drawing: +12 MB / 77k frames.
Cause is **not** PixelDisplay or ScreenFont: it is creating a new short string every frame.
**Minimal repro (no Soda):** `perf_stringleak.ms`, 200,000 unique strings (`"N " + n`):
| mode | growth per string | after final full GC |
|---|---|---|
| none | 240 B | 49 MB retained (no change) |
| `gc.collect` every 2000 | 240 B | 51 MB retained |
| `gc.collect true` every 2000 | 84 B | 18 MB retained |
**Mechanism (miniscript2/generated/GCManager.g.cpp):** heap strings shorter than
`InternThreshold` (128) go through `GCManager::InternString` into `InternedStrings` plus the
`_internTable` dictionary. "Interned strings are semi-immortal": the automatic and plain
`gc.collect` never sweep them; only a *full* collection does, and nothing triggers a full
collection automatically. Even after a full GC the memory stays high (final full GC
did not shrink anything), so the intern set / dictionary capacity is also never released.
**Impact:** any program that builds changing strings every frame (score text, "frame N",
FPS counters, coordinates) leaks ~240 B per distinct string: ~120 MB per 500k strings.
Soda-level workaround is not clean (periodic `gc.collect true` cuts it by ~65%).
**Fix belongs in miniscript2:** (a) have MaybeCollect do an occasional full collection,
(b) free/shrink the table after a full sweep, and/or (c) don't intern strings created by
concatenation (only literals), or intern only on hash-key use.

### §6 completion: resize, fullscreen, mode switches, sprite churn, mixed-argument hostile inputs
Scripts: `perf_resize.ms` (modes resize | fullscreen | modes | rendersprites),
`run_hostile_mixed.sh` (one hostile argument position, others = 2).
- **Resize** (SetWindowSize every 5 frames across 7 sizes incl. 320x240 and 1920x1080, 600 frames,
  2000 rotating sprites + tiles + text + pixel drawing): no crash, RenderTexture count steady (8),
  hostMemory steady (22-26 MB, no trend).
- **Fullscreen toggle** every 30 frames, 600 frames: no crash, same steady counts.
- **Display.mode switches** (off / solid / text / pixel / sprite / tile) while rendering,
  600 frames: no crash, counts flat, hostMemory flat (~19 MB).
- **Rendered sprite churn** (200 fresh Sprites per frame, a fresh Image+texture for each on
  every 10th frame, 3000 frames): resource counts and hostMemory flat (~20.5 -> 21 MB).
- **Mixed-argument hostile inputs** (50 methods with >=2 params, each position x 8 bad values,
  1152 runs): 

  **[BUG-HOST-01] `Image.create` with a huge size crashes the host** (SIGSEGV/SIGBUS):
  `Image.create(1e9, 2)`, `Image.create(2, 1e9)`, `Image.create(1e5, 1e5)` (~40 GB). Presumably
  `GenImageColor`'s allocation fails and the NULL result is written to / used. Not a MiniScript
  error, so a script cannot catch it. Candidate fixes: validate `width*height` in
  `Image.create` (lib), and/or make the raylib-miniscript `GenImageColor` binding return null on
  allocation failure (host). `Image.create(-1, 5)` and `(0, 0)` are accepted silently.
  Other hangs (only at 1e9): `TextDisplay.setSize` (both args), `Sound.noiseWave` (2nd arg).
  No other crash: every other combination is `ok` or an ordinary runtime error.
- **Test-harness caveat:** running two raylib-miniscript processes at the same time can make
  one SEGV at startup (the first sweep, run next to the soak, showed 248 spurious crashes; the
  mixed sweep, overlapped by a few resize runs, showed 159, in contiguous blocks of methods).
  All of them passed when rerun alone. Run the hostile sweeps with nothing else running.

### BIND-02  Cache map keys in the raylib-miniscript value converters (fixed)
Cause of the ~2x map-argument cost measured in BIND-01: every `ValueTo*` reader did
`map.Lookup(String("r"), ...)`, building a String and converting it to a Value per lookup
(and "height", longer than the 5-byte tiny-string limit, also allocated on the GC heap).
Fix (raylib-miniscript branch `perf/intern-keys`, commit 04ce1d3, not pushed): `CACHED_KEY("r")`
builds each key Value once per call site, rooted via `GCManager::AddRoot`; all 184
`Lookup(String("..."))` calls use it, plus the Color/Rectangle/Vector2/etc. map writers.
Closure-subtracted ns per call (release build, `perf_binding.cachedKeys.csv`):
| call | before | after |
|---|---|---|
| DrawTexturePro, map src/dst/origin + WHITE map tint | 1806 | 617 |
| DrawTexturePro, map src/dst/origin + list tint | 1591 | 708 |
| DrawTexturePro, list args + WHITE map tint | 884 | 580 |
| DrawTexture, WHITE map tint | 724 | 469 |
| DrawLineEx, map endpoints | 1325 | 1028 |
| DrawRectangleRec, map rect | 1146 | 916 |
| GetImageColor (returns a color map) | 892 | 655 |
List and string argument forms unchanged. Verified: host `handle_tests` (32 checks) and
`interp_tests` (133 checks) pass, all 19 Soda `qa_*` tests pass, and a GC stress loop (full and
normal collections every 37-100 iterations around map conversions) gives correct values.
Map args are now ~1.1x the list form instead of ~2x, so lib code no longer pays for them.

### BUG-HOST-01 fix
`Image.create` now returns null with a message for non-numeric, negative or over-1-GiB sizes
instead of crashing the host (Fixes2 c817862; `tests/qa_image_create.ms`).

### BIND-03 — spritebatch plugin prototype (batch DrawTexturePro): NOT worthwhile as a flat-list call

Prototype: raylib-miniscript branch `perf/batch-draw-plugin` (local), `plugins/spritebatch/plugin.cpp`,
`spritebatch.drawTextures texture, flatList, tint` (9 numbers per sprite). Bench: `tests/perf_spritebatch.ms`
(ms per frame, median of 7, 32x32 sprite, rotation varying).

| N | per-sprite DrawTexturePro | batch, prebuilt list | batch, list built in MS each frame | MS loop floor (no draw) |
|---|---|---|---|---|
| 100 | 0.111 | 0.009 | 0.234 | 0.048 |
| 1000 | 1.035 | 0.070 | 2.234 | 0.444 |
| 5000 | 5.238 | 0.348 | 11.369 | 1.982 |

Findings:
- The native call itself is nearly free (0.35 ms for 5000). But a batch API must be fed a list, and building it
  in MiniScript (9 pushes/sprite) costs MORE than the three small lists + DrawTexturePro call it replaces
  (11.4 vs 5.2 ms at 5000). A flat-list batch only wins if the data is persistent between frames (sprites that never move).
- The whole `Sprite.draw` render phase is ~26 ms at 5000 sprites (`perf_sprites` spr_plain); the DrawTexturePro
  loop is only ~5 ms of that. The other ~20 ms is Sprite.draw's MiniScript logic (inherited-field lookups via
  the __isa chain, srcRect/scale branching, arithmetic). A draw-call batch cannot touch it.
- Only a plugin that walks the sprite maps natively (reading x, y, rotation, scale, tint, image, srcRect, with
  isa-chain defaults) could remove that ~20 ms. That couples the host to Soda's Sprite field semantics, so it is
  a bigger, more contentious design than "batch draw". Not prototyped.
Decision: do not propose spritebatch.drawTextures. Revisit only if a native sprite-walker is wanted.

### BUG-HANG-01 fix: size caps for TextDisplay.setSize, TileDisplay.extent=, Sound.noiseWave

The three hostile-input TIMEOUTs (1e9 columns/rows/samples looped for minutes) now return immediately:
`TextDisplay.MAX_CELLS` (250000; setSize prints a message and returns, like Image.create), `TileDisplay.MAX_CELLS`
(4000000; `.extent=` ignores it, per its existing "anything else is ignored" contract), `Sound.MAX_NOISE_SAMPLES`
(4194304; returns an empty list). Non-numeric/negative sizes are rejected too. Test: `tests/qa_hostile_sizes.ms`.
Re-ran all six hostile cases (all-args and mixed): HOSTILE_OK. The remaining null/typed-argument cases in
hostile.csv are ordinary MiniScript runtime errors (script ends, host survives), not crashes or hangs; left as is.

### Scenario 1 profile: 5000 bouncing balls (build-profile host, 300 frames, `perf_sprite_profile.ms`)

Files: `scn1_5000_profile.{txt,speedscope.json,folded}`. 37 ms/frame under the profiler (about 36.6 unprofiled).
95% of time is MiniScript code; raylib calls are only 3.4% (and that is EndDrawing's frame wait); GC 1.2%.

| Function | self % | notes |
|---|---|---|
| Sprite.draw | 45.9 | per-sprite draw |
| SpriteDisplay._renderSprites | 20.6 | per-sprite dispatch loop |
| Ball.update (user code) | 17.5 | the scenario's own physics |
| Image.texture | 3.9 | a function call per sprite just to return `_tex` |
| Display.screenHeight | 1.7 | a function call per sprite, same value every time |

Hottest lines (self ms of 11,200):
- SpriteDisplay.ms:476 `raylib.DrawTexturePro ...` 2235 (20%): builds 3 lists, calls image.texture, looks up tint/x/y/rotation, then the call.
- :542 `if sp isa Sprite and sp.image != null and (sp.localCorners or sp._uvs)` 1169 (10.4%): three inherited lookups + `isa` walk, per sprite.
- :547 `sp.draw -self.scrollX, -self.scrollY` 636 (5.7%): call overhead.
- :464/:455 (srcRect default path using `image.width/height`; the repeated `localCorners or _uvs` check) 502 + 485 (~9%).

Candidate fixes (not implemented), ordered by confidence:
1. `_renderSprites` already tests `localCorners or _uvs`; `Sprite.draw` repeats it (:455). Give `_renderSprites` a private fast path (`_drawFlat`) so the plain case does it once.
2. Hoist `Display.screenHeight` out of the per-sprite path (read once per render).
3. Use `image._tex` directly when set, skipping the `Image.texture` call.
4. Cache `image.width/height` lookups when `srcRect` is null.
Expected total gain roughly 15-25% of render time; the draw-call batching tested in BIND-03 would not help.

### PERF-SPR-DRAW: Sprite.draw fast path (screen height cached per render, texture read directly)

Implemented fixes 2 and 3 from the scenario-1 profile: `SpriteDisplay.render` caches `Display.screenHeight` in
`Sprite._frameHeight` for the duration of the render (null again afterwards, so a lone `sprite.draw` still reads
it live), and `Sprite.draw` uses `image._tex` directly, calling `image.texture` only when it is not yet built.
Fix 1 (skip the repeated warp check) and fix 4 were not done: there is no safe way to tell a possibly-overridden
`draw` that the check already happened, and the width/height lookups are already single property reads.

Render ms/frame, 3 runs each, release host:
| Workload | Before | After |
|---|---|---|
| scn1 balls, 1000 | 5.66 | 4.88 |
| scn1 balls, 5000 | 26.7 | 22.6 (-15%) |
| spr_plain 5000 (perf_sprites) | 27.7 | 20.6 (-25%) |
| spr_10images 5000 | n/a | 25.0 |

qa_sprite_render, qa_sprite_edges, qa_display_edges, qa_display_install, qa_bounds_overlaps all pass.

## §10.1 Native profile of the host: scenario 1 (5000 bouncing balls)

Method: `xcrun xctrace record --template 'Time Profiler'` on the `build-profile/` (RelWithDebInfo) host running
`perf_sprite_profile.ms`; time-profile table exported to XML and bucketed by `tests/analyze_trace.py`
(summary: `perf_results/xctrace/scn1_summary.txt`; the 8.8 MB .trace bundle is not kept). 9,511 samples at 1 ms.
miniscript2 at a5a546a. Read-only; nothing in miniscript2 was changed.

| Bucket (self time) | % |
|---|---|
| Refcounting / struct copies (shared_ptr copy+release, GCMap/Context copies) | 24.0 |
| Map lookup (findEntry, GCMap::TryGet, LookupWithOrigin, RecursiveEqual) | 16.3 |
| VM dispatch (`VMStorage::RunInner`) | 14.1 |
| String/value hashing | 11.4 |
| Value inline wrappers (`Boolean::operator bool`, `IsMap`, ...) | 7.7 |
| malloc/free | 5.9 |
| raylib / GL | 1.4 |
| GC | 1.1 |
| List access | 0.4 |
| Binding conversion | 0.2 |
| other (unclassified) | 17.5 |

Inclusive: `LookupMember` 27.7% (of which `LookupWithOrigin` 24.2%, `GCMap::TryGet` 22.6%, `findEntry` 18.3%);
`Hash(Value)` 12.7%; native intrinsic callbacks (`InvokeNativeCallback`) 17.4%.

Confirmed suspects:
- **S-V1 (refcount / struct copies on every lookup): confirmed, the largest bucket at ~24% of native time.**
  `__release_shared` is the #3 self symbol (5.2%), with `shared_ptr<vector<Value>>` copy/get/dtor,
  `shared_ptr<GlobalsStorage>`, `shared_ptr<VarMapBackingStorage>`, `shared_ptr<FuncDefStorage>`,
  `GCMap::GCMap(const GCMap&)`, `GCMap::~GCMap` and `Context::Context` copies all in the top 40.
  Map access is ~28% inclusive, so member lookup (`self.x`, method lookup along `__isa`) is the dominant script cost.
- **New suspect S-V4: tiny strings are re-hashed on every lookup.** `get_string_hash` is 6.2% self and
  `string_hash` 4.1% (about 10% together, 12.3% inclusive). Heap strings cache their hash (`ss_hash`), but
  strings up to 5 bytes (`x`, `y`, `scale`, `image`, `vx`, ...) are inline Values: `get_string_hash` unpacks them to a buffer and hashes
  each time. Most Soda property names are tiny, so almost every field access pays it. Candidate fix: hash tiny strings straight from
  the `bits` word (no unpack, no loop), or precompute. Needs a micro-benchmark first.
- **Not a problem:** GC (1.1%), list access (0.4%), argument conversion (0.2%) and raylib/GL (1.4%).

Implication: with ~95% of frame time in the VM and ~50% of that in lookup + refcount + hashing, the biggest remaining
speedup for Soda is in miniscript2 (return `const GCMap&` on hot paths; cheaper tiny-string hashing), not in `lib/*.ms`.

Not done: the same profile for the other scenarios and the §9 binding benchmark; micro-benchmarks for S-V1..S-V4
(`x = obj.field` at isa depth 1-3, setter cost); `tools/benchmark.sh` baselines; any VM change (needs the user's
go-ahead per miniscript2/CLAUDE.md).

### §10.2 VM micro-benchmarks (`tests/perf_vm.ms`, release host, ns/op, empty loop subtracted, two runs agree within 1-2%)

| Op | ns |
|---|---|
| field read, own map | 34 |
| field read, found 1 / 2 / 3 / 5 `__isa` levels up | 66 / 100 / 154 / 216 |
| tiny-key (`xx`, 4-5 bytes) read at depth 1 | 66-68 |
| 10 / 15 byte key read at depth 1 | 75-76 |
| `list[2]` | 45 |
| `map["a"]` | 27 |
| assign existing tiny key (`o.val = 1`), plain class instance | 46 |
| same, instance of class with a setter in the chain | 134 (2.9x) |
| assign long key (`o.someLongName = 1`), plain map or plain class instance | 137 |
| same, class with a setter in the chain | 494 (3.6x) |
| method call at depth 1 / 3 / 5 | 192 / 280 / 324 |
| plain function call | 130 |

- **S-V3 (isa-chain misses): confirmed.** Each extra `__isa` level costs ~33-45 ns per field read (a Soda `TextDisplay` instance
  reading a `Display` field pays two or three levels), and method calls grow 192 -> 324 ns from depth 1 to 5.
- **S-V2 (setters): confirmed, large.** Having ANY `name=` function in the chain makes every plain assignment on such an
  object 3-3.6x slower (+88 ns for a tiny key, +357 ns for a long one). Every Soda Display/TextDisplay/TileDisplay instance
  is in that situation. Separately, assigning a long key costs ~90 ns more than a tiny key even with no setter anywhere
  (137 vs 46); cause not verified, likely the `key + "="` string `SetterKey()` builds for keys over 4 bytes.
- **S-V4 (tiny strings re-hashed): not isolated.** Tiny keys are not slower than heap keys (66 vs 76 ns), so the re-hash is not
  visibly costly relative to heap-key compare cost; the 10% hashing in the native profile is spread over all lookups, not a
  tiny-string penalty. Downgraded from "suspect" to "unconfirmed, low priority".
- **S-V1 (refcount copies): not separable from MiniScript.** It is part of the 34 ns base field read; it needs the C++
  prototype (`const GCMap&` on the read paths) to measure, which requires the user's go-ahead on a scratch branch.

Soda-side implications (no VM change needed): avoid assigning to long-named fields on setter-bearing objects in hot paths
(use `super.x =` or write on a helper map), and keep hot instances shallow. Recommended VM-side fix to propose to Joe: cache
the setter key / skip `SetterKey()` string building (S-V2), which also helps all non-Soda scripts with property setters.

### S-V2 prototype: cache `SetterKey()` for names over 4 bytes — works in isolation, no Soda gain; NOT proposed

Reading the code first: `SetterKey()` already does pure bit arithmetic for names of up to 4 bytes, and `ChainHasSetter` already
stamps clean chains, so the VM's setter path was more optimized than the plan assumed. What remained was the >4-byte fallback
(`make_string(name + "=")`: allocate + intern a fresh string on every assignment to an object whose chain has a setter).

Prototype (scratch branch of miniscript2, reverted; diff kept as `perf_results/setterkey_cache.patch`): a 1024-slot
open-addressed cache of key bits -> setter Value in `Value::SetterKeySlow()` (cpp/core), key and setter both GC-rooted,
capped at 512 entries. It edits hand-written `cpp/core` only; a real fix would also need the C# side (`cs/Value.cs`) and the transpiler.

| Op (ns) | before | after |
|---|---|---|
| assign long key, class with setter in chain | 492 | 226 (-54%) |
| assign tiny key, setter class | 133 | 136 |
| assign plain class / plain map | 135-138 | 137 |
| field read, method call at all depths | unchanged | unchanged |

End to end (release host, 2 runs each): scn2 text adventure 3.75/3.85 -> 3.94/3.86 ms; scn5 everything 8.15/7.82 -> 7.93/7.89 ms.
**No measurable change**: Soda's hot text paths already write through `super.x =` or tiny keys, so they don't hit the slow path.
Decision: do not propose to Joe; the remaining 226 ns is the setter lookup miss up the chain, a different (bigger) change.
The real hot cost stays in S-V1 (refcount copies on every lookup, ~24% of native time), which needs a C# `ref readonly`-style
change plus transpiler support and is a larger conversation for Joe.

### S-V1 prototype: read paths borrow the GCMap/GCList instead of copying it — 5-12% faster Soda frames

Prototype (scratch branch of miniscript2, reverted; diff kept as `perf_results/gcmap_constref.patch`, 111 lines): add
`GetRef(idx)` returning `GCMap&` / `GCList&` to `GCMapSet`/`GCListSet` (generated/GCSet.g.h), and use it in the read-only paths:
`Value::MapGet`, `TryGet`, `Lookup`, `LookupWithOrigin`, `HasKey` (cpp/core/value_map.cpp), `Value::ListGet`
(value_list.cpp) and `VMStorage::ChainHasSetter` (generated/VM.g.cpp). Mutating paths (`MapSet`, `Push`, ...) are unchanged.
No other code was touched. Built as a separate release host (`build-scratch`) and compared with the unmodified release host.

VM micro-benchmarks (ns/op, `perf_vm.ms`):
| Op | before | after |
|---|---|---|
| field read, own map | 32 | 35 |
| field read, 1 / 2 / 3 / 5 isa levels | 66 / 99 / 154 / 215 | 60 / 81 / 102 / 175 |
| method call, depth 1 / 3 / 5 | 191 / 271 / 324 | 182 / 221 / 298 |
| `list[2]` | 44 | 31 (-29%) |
| assign tiny key, setter class | 134 | 98 |
| `map["a"]` | 26 | 32 (slower, unexplained; this path is not one I changed) |

Soda scenarios (total ms/frame):
| Scenario | before | after |
|---|---|---|
| scn1 balls 1000 | 7.45 | 6.73 (-10%) |
| scn1 balls 5000 | 32.5 | 28.6 (-12%) |
| scn2 text adventure | 3.79 | 3.54 (-7%) |
| scn3 platformer | 2.80 | 2.67 (-5%) |
| scn5 everything | 8.07 | 7.27 (-10%) |

Correctness: raylib-miniscript `interp_tests` (133 checks) and `handle_tests` (32 checks) pass; all 40-odd `tests/qa_*.ms` pass on the
prototype host. NOT run: miniscript2's own test suite and `tools/benchmark.sh`.

Caveats / why this is not a finished fix:
- The gain is smaller than the 24% refcount share suggested: only the map/list `Get` copies were removed. Other copies remain
  (`Context` copies, `FuncDef` shared_ptr copies in call setup, GCMap copies inside `LookupMember`'s callers).
- It is a hack on `generated/`. The real fix has to be written in C# (`cs/GCSet.cs` etc.) in a form the transpiler can express as a
  reference return; I did not check whether the transpiler supports `ref`/`ref readonly`. That needs Joe's input.
- A reference into `_items` is invalidated if the list grows. The changed paths allocate nothing, but a C# version must keep that invariant.
- `map["a"]` got slower (26 -> 32 ns) for a reason I did not find; worth a look before proposing.
Recommended next step: open a miniscript2 issue with the patch and these numbers, and let Joe decide how to express it in C#.

## Profiles for scenarios 2, 3 and 5 (MiniScript profiler + native xctrace)

Both profiles per scenario via `tests/run_scn_profiles.sh 2 3 5` (build-profile host, 600 frames, one process at a time).
Files: `scn{2,3,5}_profile.{txt,speedscope.json,folded}` and `xctrace/scn{2,3,5}_summary.txt`. Frame times below are under the profiler.

| | scn2 text adventure | scn3 platformer | scn5 everything |
|---|---|---|---|
| ms/frame (profiled) | 4.5 | 3.4 | 8.4 |
| MiniScript code | 80% | 75% | 73% |
| timed raylib calls | 18% (mostly EndDrawing wait) | 23% | 26% |
| GC | 1.1% | 2.2% | 1.6% |

### scn2 text adventure (printing 1-2 lines per frame)
- `ScreenFont.drawChar` is 39.6% self, `TextDisplay.render` 23.7% self (63% total): text drawing is the frame.
- drawChar hot lines: the per-character source-rect validity test (:272, 7.8%), the alpha/shader test with `fore[3]`/`back[3]` list reads (:288, 7.5%), and the `rl.DrawTexturePro` call itself (:290, 4.8%). Every character does a list build, 4-6 list reads and a binding call even though the font's source rects never change.
- **Correction (checked afterwards):** the caching I first listed as a candidate is already in place. S-T1 (batchable rect + tinted-glyph path, 0f142c0) and S-T2 (glyph source-rect cache `_srcRects`, parsed-colour cache `_colorCache`, blank/transparent cells tested first in `TextDisplay.render`, c8e17a6) are both in PR #28 and in the code that was profiled. What the profile shows is therefore the *residue* of those fixes: ~17 us/glyph of dictionary lookups (`hasIndex` + index, twice for colours), the per-glyph `dest` list, the `src` validity test and two raylib calls. The only remaining large lever is S-T4 (dirty flag / offscreen cache, ~10 ms -> ~0.1 ms for a full screen), which was deliberately not done because cells are public maps that callers mutate directly; it needs an agreed API.
- Native: refcounting 21%, VM dispatch 14%, map lookup 10%, hashing 6%.

### scn3 platformer (tiles + 51 sprites + pixel HUD)
- `TileDisplay.render` is 30.4% self: :295 builds a `src` list per visible tile (6%) and :300 builds `dest` and calls `DrawTexturePro` (10% of the frame in raylib time alone). It is the biggest item, at 3.4 ms/frame for a 200x50 map with scrolling.
- `TextDisplay.render` is still 14.9% (0.5 ms/frame) although the platformer prints no text: a mostly blank text display is not free. Worth checking that blank cells are skipped before any per-cell work.
- `PixelDisplay` HUD (`clear`+2 `print` per frame): 4.2% in `EndBlendMode`, small here.
- Native: refcounting 14%, VM dispatch 12%; 40% "other" is mostly the main-thread wait in the display driver (`mach_msg2_trap`, `start_wqthread`).

### scn5 everything (500 balls + tiles + text + pixel lines/print + music)
- `Sprite.draw` 19.3% + `_renderSprites` 8.0% = 27% for 500 sprites, matching the scn1 analysis (these numbers already include PR #37's fast path).
- `PixelDisplay` per-call blend brackets: `raylib.EndBlendMode` is 12.6% (648 ms) from ~21 unbatched `line`/`print` calls per frame, the same S-P1 cost found in the paint scenario. `PixelDisplay.autoBatch = true` (PR #34, opt-in) addresses it; this scenario was not re-run with the flag.
- `TileDisplay.render` 13.1%, `TextDisplay.render` 8.2% (14.2% total), `ScreenFont.drawChar` 6.2%, `Ball.update` 8.0% (user code).
- Native: refcounting 18%, map lookup 10%, VM dispatch 12%, hashing 7%.

### Cross-scenario conclusions
1. Across all four scenarios the VM's refcounting/copy overhead is 14-24% and map lookup + hashing another 12-17%; this is the common ceiling and it is being handled upstream (miniscript2#30).
2. The remaining Soda-side hot spots are all "one DrawTexturePro per cell/glyph/sprite with fresh lists": text (`drawChar`), tiles (`TileDisplay.render`) and sprites. All three have already had their first round of fixes (text: PR #28; tiles: PR #29 culling + inline geometry; sprites: #32, #37), and these profiles are of the code after those fixes, so they show diminishing returns. The only big untaken Soda-side lever is S-T4 (text dirty flag / offscreen cache), which needs an API decision from Joe. A tile-level equivalent has not been investigated.
3. Re-run scn5 with `PixelDisplay.autoBatch = true` to quantify the 12.6% EndBlendMode cost.

### PixelDisplay.autoBatch on scenarios 3 and 5 (PR #34's opt-in flag)

`perf_scenarios.ms <run> <scenario> auto` sets `PixelDisplay.autoBatch = true` for the whole run. Release host, 3 runs each (ms/frame):

| Scenario | user | endDrawing | total | change |
|---|---|---|---|---|
| scn3 platformer, off | 0.376 | 0.58 | 2.80 | |
| scn3 platformer, auto | 0.250 | 0.55 | 2.68 | -4% |
| scn5 everything, off | 2.04 | 1.22 | 7.91 | |
| scn5 everything, auto | 0.91 | 0.78 | 6.37 | **-19%** |

Render time is unchanged (4.45 vs 4.51 in scn5, 1.71 vs 1.75 in scn3): the saving is entirely in the `user` phase (the per-call
`BeginBlendMode`/`EndBlendMode` brackets) plus a smaller `endDrawing` time. Runs are stable to ~1%. `qa_pixelDisplay_autobatch.ms` passes with
the flag on and off. So autoBatch does what #34 promises on a mixed scene, not just the paint-only case (18x there); the gain scales with how many unbatched
pixel-display calls a frame makes (about 21 in scn5, 3 in scn3). The 12.6% `EndBlendMode` share from the scenario-5 profile shows up as the 1.1 ms user drop.
