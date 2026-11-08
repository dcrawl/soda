# Soda performance and robustness test: final report

Executes `PERF_TEST_PLAN.md`. Raw data and per-item detail are in `FINDINGS.md` and the CSVs in this folder.
Environment: macOS, Release host (`raylib-miniscript/build-release`), clang; profiles on the RelWithDebInfo host.

## Bottom line

- The plan is complete: every measurable item was run, and everything we confirmed was fixed in Soda, filed upstream, or deliberately left alone with reasons (below).
- No host crashes were found with ordinary or hostile arguments. Three 1e9-size hangs were fixed.
- Two real leaks/crashes were found and fixed or filed: BMF fonts crashed on load, and unique short strings leak host memory (VM-01).
- The remaining frame time in Soda scenes is mostly the VM itself: refcounting/copying 14-24%, map lookup and hashing another 12-17%. Further Soda-side gains are now small; the large gain is in miniscript2: a combined VM patch (below) makes 5000 balls -24% total frame time, and 28% less user time.

## What was fixed, with the measured gain

| Area | Problem | Result | Where |
|---|---|---|---|
| Text | `ScreenFont.drawChar` did a shader bracket per glyph; blank cells walked anyway (S-T1, S-T2) | full 68x26 screen 415-435 ms/frame before; about 35x faster per PR #28 | PR #28 |
| Tiles | every cell iterated and drawn, visible or not (S-L1, S-L2) | culling plus inline geometry; cost now scales with visible cells | PR #29 |
| Sound | synthesis loop (S-A1) | about 2x faster | PR #30 |
| Sprites | warped (quad) sprites 40x the cost of plain ones; `Bounds.overlaps` (S-S1..S3) | warped ~6x, overlaps ~4x | PR #32 |
| Sprite.draw | per-sprite screen-height lookup and texture accessor | 5000 balls render 26.7 to 22.6 ms (-15%); plain sprites -25% | PR #37 (stacked on #32) |
| PixelDisplay | per-call GPU bracket (S-P1..P5); opt-in `autoBatch` | paint loop 18x; everything-at-once scene -19% with `autoBatch` | PR #27, #34 |
| Fonts | 24 of 34 sample BMF fonts crashed on load (color clamping); `Font.print` did a draw call per glyph (S-F1) | loads fixed; print of 1000 chars 77 to ~9 ms (about 8x) | PR #33 |
| Sound.StopAll | BUG-03 | fixed | PR #27 |
| Image.create | oversized sizes crashed the host | rejected | PR #35 |
| Hostile sizes | `TextDisplay.setSize`, `TileDisplay.extent=`, `Sound.noiseWave` with 1e9 hung for 10+ s (BUG-HANG-01) | capped and validated; `qa_hostile_sizes.ms` | PR #36 |
| raylib-miniscript | value converters rebuilt map-key strings per lookup (BIND-02) | map-argument calls about 2x cheaper | raylib-miniscript PR #28 |

All PRs are open and waiting on Joe. #34 sits on #27 and #37 on #32, so each needs a rebase when its base merges.

## Investigated, measured, and not proposed

| Item | Finding | Decision |
|---|---|---|
| BIND-03 batch draw plugin | a flat-list `DrawTexturePro` batch gives no gain: building the list in MiniScript costs more than the calls it saves (11.4 vs 5.24 ms/frame; 0.35 only with a prebuilt list) | dropped, per your call |
| S-V2 setter-key cache (VM) | assignments 3-3.6x slower when a setter exists in the chain; a cache cut 492 to 226 ns for long keys, but no end-to-end Soda gain | not proposed |
| S-V3 isa depth | about 33-45 ns per inheritance level | now fixable: see "VM patch ready to file" (14 ns per level) |
| S-V4 tiny-string re-hash | no penalty measured | low priority |
| S-T4 text dirty flag / offscreen cache | an idle `TextDisplay.render` costs ~0.5 ms/frame, but cells are public maps mutated directly, so a cache needs an API decision | left for Joe |
| `tint` default (BIND-01) | prototyped on branch `perf/tint-default`; see FINDINGS | not proposed |
| Null/wrong-type argument validation across the library | 272 of 1072 hostile calls end in an ordinary MiniScript runtime error, not a crash | skipped on purpose |
| Bytecode optimization / opcode fusion | fusing all cheap opcodes is worth at most about 3% of the scenario 1 frame; but a call costs 137-180 ns (60x a cheap instruction), and the two calls in `Ball.update` are about a quarter of its cost | not pursued; the call-path cost turned out to be fixable: next section |

## Filed upstream (miniscript2)

- **#29 (VM-01):** unique short strings are interned and never swept by automatic GC: about 240 B leaked per distinct string, 14.7 to 179 MB over a 30 min soak of a scene that only prints `"N " + n`. Any HUD counter hits this. Soda cannot fix it cleanly (`gc.collect true` periodically recovers ~65%).
- **#31 (map writes and isa walks):** see "VM patch" below; filed after #30 was open.
- **#30 (S-V1):** `GCMapSet::Get` returns a struct by value, so every lookup copies `shared_ptr` members (atomic refcounts). A const-ref prototype made Soda frames 5-12% faster (scn1 5000: 32.5 to 28.6 ms). Joe decides how to express it in C#.

## VM patch (miniscript2) — filed as miniscript2#31

Prompted by "is there a faster map?": a replacement table is not worth it (reads are flat from 1 to 4096 keys; a perfect table saves ~5-8 ns of a ~25 ns lookup), but profiling the write and inheritance paths found three VM problems. Patch: `perf_results/map_write_combined.patch` (on unmodified main; details and caveats in FINDINGS "Map replacement question").

1. **`IsIsaKey` allocates on every write to a map with a 5+ byte field name** (`key == magicIsA` goes through `string_equals`, which mallocs and frees a temporary). Writes to `self.rotation` etc. were ~150 ns; ~90% of a write-only loop was in this call. Plain C# fix (compare length, then bytes).
2. **Inheritance walks rehash both the key and `__isa` at every level.** Hashing them once per lookup cuts the cost per `__isa` level from 34 to 14 ns.
3. **#30 widened:** also `IsFrozen`, `MapSet` and the heap-string accessor copy a struct by value.

| ns/op | base | patched |
|---|---|---|
| write existing key, long name | 149 | 52 |
| field read through 6 isa levels | 272 | 107 |
| `perf_vm` method call, depth 5 | 315 | 222 |

| Scenario (ms/frame, total) | base | patched |
|---|---|---|
| scn1, 5000 balls | 33.0 | 25.1 (-24%) |
| scn3 platformer | 2.89 | 2.52 (-13%) |
| scn5 everything | 7.82 | 6.58 (-16%) |

miniscript2's own test suite passes on the patched build (914/914). Not yet run on it: raylib-miniscript `interp_tests`/`handle_tests` and Soda's `qa_*.ms`. The patch edits transpiled output; Joe must express it in C#.

## Call-path patch (miniscript2) — ready to file

The C++ VM passes `FuncDef`, the native callback and `List` by value on every call, so each call pays atomic refcounts and a `std::function`
clone (same defect class as #30). Passing them by reference (`perf_results/call_path_byref.patch`, 3 generated files, no logic change) cuts a
user call from 171 to 94 ns, an intrinsic call from 180 to 82 ns, and `Ball.update` by 10%. Soda total frame: scn1 -16%, scn3 -11%, scn5 -14%
alone; with the map patch (#31) -36%, -19%, -31%. miniscript2's 914 tests pass and Soda `qa_*.ms` output is unchanged. Not yet filed;
not run: C# build, raylib-miniscript `interp_tests`/`handle_tests`. Details in FINDINGS.


## Where the time goes now (scenario profiles)

| Scenario | ms/frame | MiniScript code | raylib calls | Notes |
|---|---|---|---|---|
| 1: 5000 balls | 22.6 render + update | ~80% | 1.4% native | refcounting 24%, map lookup 16%, VM dispatch 14%, hashing 11% |
| 2: text adventure | 4.5 | 80% | 18% | text path already optimized |
| 3: platformer | 3.4 | 75% | 23% | idle `TextDisplay.render` ~0.5 ms |
| 5: everything | 8.4 | 73% | 26% | `autoBatch` takes it to 6.4 (-19%) |

Binding overhead (§9): about 215-250 ns dispatch floor per raylib call, and `DrawTexturePro` costs 12x its native cost. That is fixed by the host, not by Soda code.

## Robustness (§6)

- Churn (10,000 images/sprites/pixel displays/sounds/mode switches): every resource count returns to baseline.
- Soak (scenario 5, 10 min, 71,778 frames): resource counts flat; host memory growth is VM-01, not a Soda leak.
- Hostile inputs: 134 methods x 8 values = 1072 runs; no host crashes after the three hang fixes.

## Utilities, fonts, textUtil (§4.12, §4.13)

- Built-in unit tests pass for json, grfon, tsv, stringUtil, listUtil, mapUtil, mathUtil, matrixUtil, base64 and qa. Everything scales linearly. Rule of thumb: json parse about 1 us/byte, grfon 1.7 us/byte, base64 0.9 us/char, so a 1 MB document costs 1-2 s (fine at load time, not per frame). `string.wrap` is mildly superlinear (4x text costs 12x); fine to a few hundred KB.
- **Font demos (new):** the `ttFonts` and `bmfFonts` demo blocks and the `textUtil` dialog demo all run to completion under Soda without runtime errors. They are written for Mini Micro and fail if run bare, because they expect `soda` to be imported first (the demo uses `clear`/`color`), so they were driven through small wrappers.
- **textUtil (new): `tests/qa_textUtil.ms`, ALL PASSED.** It covers the pixel-to-cell conversion, `printWrap` return values, `clearRow`/`clearRect`/`clearToEOL` (including colors), `button`, `getContent`/`setContent`/`getState`/`setState` round-trips, and `Dialog.make`/`draw`/`FileDialog.make`.
- **Finding (textUtil, not patched; Tier C is report-only):** textUtil is a Mini Micro port that calls bare `print`, which in Soda is the host's stdout intrinsic. So `printAt`, `printCenteredAt`, `printWrap`, `drawButton`, `Dialog` and `FileDialog` write to the terminal, not to the text display. Only the cell-level helpers (`clear*`, `getContent`, `setContent`, `button`) work on the screen. The dialog classes need `text.print` (or a `print = @text.print` shim) to be usable. It also hard-codes 68x26 cells. `qa_textUtil.ms` pins this as a NOTE so a future fix shows up.

## Not done, on purpose

- S-T4 (text dirty flag), Sprite.draw fixes 1 and 4, null/wrong-type validation: reasons above.
- Native sprite-walker plugin: dropped.

## Branches and state

- soda: `perf/00-harness-setup` holds the harness, benchmarks, FINDINGS and this report (local). `Fixes2` holds the landed fixes; PRs #27-#30 and #32-#37 are open.
- raylib-miniscript: PR #28 open; `perf/batch-draw-plugin` is a local prototype only.
- miniscript2: issues #29, #30 and #31 open; no code changes (the combined patch is kept in `perf_results/map_write_combined.patch`, tree reverted).
