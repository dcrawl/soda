# Soda Performance & Bug Test Plan

A plan for Claude Code to work through, one unit at a time. It looks for **frame-time
hogs, CPU-heavy paths and things that scale badly** in Soda's `lib/`, plus the bugs
that turn up along the way. It uses the raylib-miniscript profiler (`--profile`).

> **To Claude Code:** read this whole file first. Then work through the phases in
> order. Measure before you change anything. Each "Suspect" below is a **guess**
> from reading the code. Confirm it or rule it out with numbers. Never report one as
> a finding without evidence. Keep a running log in `tests/perf_results/FINDINGS.md`
> (format in §7).
>
> **Session setup:** start Claude Code in the parent `forks/` folder, or in `soda/`
> with `--add-dir ../raylib-miniscript --add-dir ../miniscript2`. §9 and §10 need
> all three repos. Run on the Mac itself: every benchmark opens a window. The plan
> is too big for one session, so work one phase (§8) per session. Commit results
> at the end of each session, and start the next session by reading `FINDINGS.md`.

---

## Pre-flight: fix these before any measurement

Each of these was true when this plan was written (Nov 2026). Check each one, fix
it, and record what you did at the top of `FINDINGS.md`.

1. **The host is a Debug build.** `raylib-miniscript/build/CMakeCache.txt` has
   `CMAKE_BUILD_TYPE=Debug`, so any timing taken with it is meaningless. Leave
   `build/` as it is, and make two more build folders next to it:
   - `build-release/`, built with `-DCMAKE_BUILD_TYPE=Release`, for all timings;
   - `build-profile/`, built with `-DCMAKE_BUILD_TYPE=RelWithDebInfo`
     (`-O2 -g -DNDEBUG`), for native profiling in §10.1.

   Check how the existing `build/` was configured (generator, raylib options)
   before configuring these, so all three differ only in build type. Record the
   compiler version and the flags you used.
2. **Soda's host link is missing.** `soda/raylib-miniscript` doesn't exist. With
   no link, `./soda` stops at an **interactive prompt**, which would hang an
   unattended run. Create the link yourself:
   `ln -s ../raylib-miniscript/build-release/raylib-miniscript soda/raylib-miniscript`.
   To switch builds, re-point the link, or call the host binary directly with the
   same arguments.
3. **Only `lib/ScreenFont.png` ships.** The small, medium and large PixelDisplay
   fonts fall back to the normal font, so `PixelDisplay.print` benchmarks measure
   only that font. Note this in the results.
4. **Check that a run works end to end.** Run `tests/balls.ms` through
   `./soda --profile perf_results/smoke balls.ms` from `tests/`, let it run for a
   few seconds, and check that all three profile files appear. If the script
   never exits on its own, find the reliable way to stop it (closing the window,
   or Ctrl-C), and use that in `run_perf.sh`.
5. **Look for profiling tools on the Mac.**
   - Check for `xcrun xctrace`, the command-line front end to Instruments, which
     Claude Code can drive, e.g.
     `xcrun xctrace record --template 'Time Profiler' --launch -- <host> <script>`.
   - Check for `samply`.
   - If neither is installed, **ask the user** before installing anything (e.g.
     `brew install samply`).

---

## 0. Scope

Soda is now pure MiniScript (`lib/*.ms`) on top of the raylib-miniscript host. Every
frame, `yield` → `soda.update` runs:

```
raylib.BeginDrawing
Display.RenderAll          // slots 7 → 0, each display's .render
raylib.EndDrawing          // GPU flush + swap (+ FPS-cap wait)
mouse.update, key.update, Sound.UpdateAll
intrinsics.yield           // GC runs here
```

So **anything a `render` method does per cell, per tile, per sprite or per glyph runs
every frame**, and that's where the big wins usually are. A second class of
problems is **one-off hitches**: work that runs once but takes long enough to drop
frames, such as sound synthesis, texture uploads, and GPU→CPU readbacks.

Units under test (all in `lib/`):

| Tier | Units |
|---|---|
| **A: per-frame engine** | `soda.ms`, `Display.ms`, `SolidColorDisplay.ms`, `PixelDisplay.ms`, `SpriteDisplay.ms` (Sprite, Bounds), `TextDisplay.ms`, `ScreenFont.ms`, `TileDisplay.ms`, `Sound.ms`, `key.ms`, `mouse.ms` |
| **B: on-demand engine** | `Image.ms`, `color.ms`, `bmfFonts.ms`, `ttFonts.ms`, `importUtil.ms` |
| **C: shared utilities** | `listUtil`, `stringUtil`, `mathUtil`, `matrixUtil`, `mapUtil`, `textUtil`, `json`, `grfon`, `tsv`, `base64`, `qa` |

Tier C files are kept in sync with other repos (`scripts/check-lib-sync.sh`). Report
problems in them, but **don't edit them in place**. Flag them for upstream instead.

---

## 1. Ground rules

1. **Baseline first.** Record numbers for every benchmark on unmodified code before
   you touch any `lib/` file. Commit the baseline CSVs.
2. **One change per measurement.** If you prototype a fix, measure it on its own
   against the baseline and record the delta. Do the fixes on a branch (`perf/...`),
   one commit per fix.
3. **Uncap the frame rate.** The host calls `SetTargetFPS(60)`, so
   `[raylib.EndDrawing]` in a profile is mostly idle waiting. Benchmarks call
   `raylib.SetTargetFPS 0`. Also check whether vsync is on (frame times pinned near
   16.7 ms or 8.3 ms even when uncapped). If it is, note it, and treat
   `EndDrawing` time as unreliable.
4. **Repeat runs.** Run each benchmark at least 3 times and report the median of the
   medians. Discard any run where the window was hidden or not focused. Some
   platforms throttle hidden windows.
5. **Scale everything.** Run each workload at several sizes (e.g. N = 1, 10, 100,
   1 000, 5 000). The shape of the cost-vs-N curve matters more than any single
   number: linear is expected, a jump means a flush or a cache miss, and
   superlinear means an O(n²) algorithm.
6. **Budget.** At 60 fps a frame is 16.7 ms. On a mid-range desktop, flag anything
   that takes **> 1 ms/frame at a realistic load**, or **> 5 ms in a single
   one-off call** (a visible hitch). Also note Raspberry Pi as a target. Anything
   fill-rate- or draw-call-bound will be several times worse there.

---

## 2. Tooling

### Running

The launcher forwards all arguments to the host, so this works:

```
cd tests                      # so lib/ScreenFont.png etc. resolve (paths are cwd-relative)
../soda --profile perf_results/<name> perf_<unit>.ms [args...]
```

Script arguments arrive in `shellArgs` (`shellArgs[0]` is the script path). Every
benchmark must **exit on its own** after its frame count (call `exit`), so runs can
be scripted without anyone at the keyboard.

### Profiler outputs (written relative to the launch folder)

- `<name>.txt`: self/total time per function plus the hottest lines. **Read this
  first.**
- `<name>.speedscope.json`: open in speedscope.app or with
  `raylib-miniscript tools/profview.ms <file>`. Use *By line* + Sandwich to find
  hot lines.
- `<name>.folded`: for `flamegraph.pl` or for diffing two runs.

How to read the profile (from the profiler README):

- Bracketed entries such as `[raylib.EndTextureMode]` and `[raylib.EndShaderMode]`
  are timed exactly. **A large total on a Begin/End-mode call means draw-batch
  flushes.** That's the signature of the draw-call problems suspected below.
- `(garbage collection)` is charged to the `yield` line. If it's a large share,
  the cause is per-frame allocation, so find the allocating code.
- Ordinary intrinsics are charged to the *end* of their batch. For line-level
  accuracy in a hot function, re-run with `--profile-interval 50`, which costs
  about 90% overhead, so don't compare its absolute times with other runs.
- Profiling itself adds ~20% at the default interval. Take **absolute timings from
  un-profiled runs** and **attribution from profiled runs**.

### Leak tracking

The host provides `resourceCounts` (a map of loaded raylib resources by type) and
`hostMemory`. Log both at the start and end of every benchmark. Also log them after
N create/destroy cycles. Any count that keeps rising is a leak.

---

## 3. Harness: `tests/perfHarness.ms`

Build this first and get it working. The sketch below is a starting point: check it
against the actual host and fix anything that doesn't run.

```
// perfHarness.ms -- shared timing harness for Soda benchmarks.
// Usage:  import "perfHarness"  (from a script in tests/)
import "soda"
raylib.SetTargetFPS 0

perf = {}
perf.lines = []

perf.stats = function(xs)
	s = xs[:]; s.sort
	n = s.len; total = 0
	for x in s; total += x; end for
	return {"mean": total/n, "median": s[floor(n/2)],
	        "p95": s[min(n-1, floor(n*0.95))], "max": s[-1]}
end function

perf.emit = function(bench, param, phase, st)
	line = ["RESULT", bench, param, phase,
	        round(st.mean*1000, 4), round(st.median*1000, 4),
	        round(st.p95*1000, 4), round(st.max*1000, 4)].join(",")
	print line
	perf.lines.push line
end function

// Empty-loop cost, subtracted from timeit results.
perf._loopCost = function(n)
	t0 = time
	for i in range(1, n); end for
	return (time - t0) / n
end function

// Pure-CPU micro-benchmark: average seconds per call of f (no rendering).
perf.timeit = function(bench, param, f, n=1000)
	f   // warm-up (also triggers any lazy init, which we want excluded)
	base = perf._loopCost(n)
	samples = []
	for rep in range(1, 5)
		t0 = time
		for i in range(1, n); f; end for
		samples.push (time - t0) / n - base
	end for
	perf.emit bench, param, "per-call", perf.stats(samples)
end function

// Frame benchmark: runs frameFn once per frame and times each phase
// of the frame separately.
perf.frames = function(bench, param, frameFn, nFrames=300, warmup=30)
	for i in range(1, warmup); frameFn; yield; end for
	ph = {"user":[], "render":[], "endDrawing":[], "callbacks":[], "yieldGC":[], "total":[]}
	for i in range(1, nFrames)
		t0 = time
		frameFn
		t1 = time
		raylib.BeginDrawing
		Display.RenderAll
		t2 = time
		raylib.EndDrawing
		t3 = time
		for f in soda.updateCallbacks; f; end for
		t4 = time
		intrinsics.yield
		t5 = time
		ph.user.push t1-t0;      ph.render.push t2-t1;    ph.endDrawing.push t3-t2
		ph.callbacks.push t4-t3; ph.yieldGC.push t5-t4;   ph.total.push t5-t0
	end for
	for k in ph.indexes; perf.emit bench, param, k, perf.stats(ph[k]); end for
end function

perf.resources = function(label)
	line = "RESOURCES," + label + "," + str(resourceCounts) + ",hostMemory=" + hostMemory
	print line; perf.lines.push line
end function

perf.finish = function(outPath)
	file.writeLines outPath, perf.lines
	exit
end function
```

Check: does `print` go to stdout or to Soda's text display? If it goes to the
display, rely on `perf.finish` writing the CSV. Times are in **ms** in the output.

Each benchmark script is named `tests/perf_<unit>.ms`. It loops over its N values,
calls `clear` between cases, and ends with
`perf.finish "perf_results/<unit>.csv"`. Add `tests/run_perf.sh` to run every
benchmark: once un-profiled (3×) for timings, once with `--profile` for attribution.

---

## 4. Per-unit test matrix

For each unit: **(a)** workloads to benchmark, **(b)** suspects to confirm or rule
out, **(c)** correctness and bug checks. Line numbers are from commit `0d6276b` and
may drift.

### 4.1 `soda.ms`: the frame loop

- **Workloads:** an empty scene (all displays default) through `perf.frames`. This
  is the fixed cost every game pays. Repeat with `updateCallbacks` holding 0, 10 and
  100 extra no-op callbacks.
- **Suspects:**
  - The default display stack draws a full 960×640 render texture (slot 5
    PixelDisplay) and the SolidColor backdrop (slot 7) every frame, even when they're
    empty. Measure the cost of an idle stack. Then measure it with
    `display(5).mode = displayMode.off`, which shows the fill-rate floor (matters on
    RPi).
  - `wait` (line 98) calls `intrinsics.yield` **before** `update`, while `yield`
    does it the other way round. Check `wait 0`, `wait 0.001`, and whether `wait`
    renders at least one frame. Check its timing accuracy for 0.1 s, 1 s and 5 s.
- **Bugs:** `window.width=`, `height=`, `fullScreen=` and `title=` round-trip.
  `fullScreen = 1` twice shouldn't toggle back. The `version` shadow
  shouldn't break a second `import "soda"`.

### 4.2 `Display.ms`

- **Workloads:** `Display.RenderAll` with every slot set to each mode in turn.
  Switching `display(n).mode` 1 000× (`FindOrMakeDisplay` does a linear scan;
  `mode=` does `insert 0`).
- **Bugs (read first, then write a `qa` test for each):**
  - **`Display.install` line 101:** `curMode = disps[slotNum].mode` indexes the
    *slot's list* with the *slot number*. It almost certainly should be `disps[0]`.
    Expect wrong behaviour or an index error for `slotNum` ≥ the list length.
  - **Line 104:** `disps[i].remove i` calls `remove` on a *display* (a map), not on
    the list. It probably should be `disps.remove i`. Expect duplicate displays in a
    slot after `install`.
  - Test `install` with `asActiveMode` true and false, into an empty slot and into
    an occupied one, and installing the same display twice. Then check
    `display(n)` and `Display._installed` for duplicates.
  - `display(-1)`, `display(8)`, `display("a")` should return an error, not crash.

### 4.3 `PixelDisplay.ms`: high priority

Every drawing call brackets itself with `_beginDraw` and `_endDraw`. That means
`BeginTextureMode`, blend-mode setup, the draw, then `EndTextureMode`. Each call is
a **full draw-batch flush and framebuffer rebind**.

- **Workloads** (each at N = 1, 100, 1 000, 10 000 calls per frame): `setPixel`,
  `line`, `fillRect`, `drawRect`, `fillEllipse`, `drawEllipse`, `drawPoly` and
  `fillPoly` (5-, 20- and 100-vertex polygons, convex and concave), `print`
  (10-char and 100-char strings), `drawImage` (16×16 and 256×256), `patternFill`,
  `pixel` (reads), `getImage` (full and partial).
- **Suspects:**
  - **S-P1:** the per-call `BeginTextureMode`/`EndTextureMode` (lines 35–57). A
    loop of 10 000 `setPixel` calls is probably catastrophic. Look for
    `[raylib.EndTextureMode]` dominating the profile. A fix could batch
    consecutive calls, or provide `beginBatch`/`endBatch`.
  - **S-P2:** `drawImage` and `patternFill` (lines 444–461) call
    `LoadTextureFromImage` + `UnloadTexture` **on every call**: a CPU→GPU upload
    each time. Compare against reusing `img.texture`, which is cached.
  - **S-P3:** `pixel(x,y)` (line 95) reads back the **entire render texture** for
    one pixel (a GPU stall). This is documented, but measure it so it can be
    documented with numbers. Same for `getImage`.
  - **S-P4:** `colorToList` on every call (string parsing). Measure separately with
    `perf.timeit`.
  - **S-P5:** `_triangulate` (line 229) is O(n²) or worse in MiniScript. Test the
    scaling of `fillPoly` from 5 to 500 vertices.
- **Bugs:**
  - `clear` (line 72) calls `UnloadRenderTexture` on a texture that was created
    with `autoUnload`. Check whether that **double-frees** when the GC later
    collects it: resize repeatedly, force GC, watch `resourceCounts` and check for
    crashes.
  - `clear(color)` with no size given resets a non-960×640 display to 960×640.
    Check whether that matches Mini Micro or is a bug.
  - `render` (line 477) prints "NULL _renderTex!" and then dereferences it anyway.
  - Behaviour of `setClip`/`clearClip` at edges and with negative sizes. Drawing
    fully off-display. `penSize` 0 or negative. Degenerate polygons (already
    partly covered by `runUnitTests`, so run that too).

### 4.4 `SpriteDisplay.ms`: Sprite and Bounds, high priority

- **Workloads** (N sprites = 1, 100, 1 000, 5 000):
  1. plain sprites, same image, no rotation;
  2. with rotation and scale changing every frame;
  3. a mix of 10 different images (texture switches break batching);
  4. tint as a string, as a list, and as a map;
  5. `localCorners`/`setUVs` sprites, which go down the `_drawQuad` shader path;
  6. nested sprite lists (`_renderSprites` recursion);
  7. collision: `overlaps` with every pair at N = 10, 50, 200, plus `contains`.
- **Suspects:**
  - **S-S1:** `Sprite.draw` (line 379) allocates 4–5 lists per sprite per frame
    (srcRect copy, `_scaleXY`, destRect, origin). Look for GC share rising with N.
  - **S-S2:** the `_drawQuad` path (line 326) runs `BeginShaderMode` and
    `EndShaderMode` **per sprite** (flushes). It rebuilds `tuv` every frame, and
    then the cache check on line 346 does a deep list compare every frame.
    `_tintRGBA` (line 203) parses hex with `indexOf` on every frame. Compare the
    cost per sprite with the plain `draw` path.
  - **S-S3:** `Bounds.overlaps` (line 44) is an SAT test written in MiniScript, and
    `worldBounds` allocates a new Bounds every call. Measure µs per `overlaps` call.
    That figure tells users how many collision checks a frame can afford.
  - **S-S4:** check how `self.tint` (a string such as `"#FF0000"`) reaches
    `DrawTexturePro`. If the host parses it on every call, a cached list would be
    cheaper.
- **Bugs:** zero, negative and list `scale` (flip). `srcRect` outside the image.
  `image = null` mid-run. Sprite in two displays at once. Removing sprites from
  `display.sprites` during iteration (common in game code). `overlaps` with
  rotation at 0/90/45°, touching edges, one box inside the other, against the
  shipped `testBounds`, `tests/bounds.ms` and `tests/spriteBounds.ms`.

### 4.5 `TextDisplay.ms` + `ScreenFont.ms`: high priority

- **Workloads:**
  1. an empty text display (should cost close to nothing thanks to the skip on
     line 472);
  2. a full screen of characters on a transparent background;
  3. a full screen with non-clear background colours;
  4. alternating fore/back colours per cell (defeats the `_lastFore`/`_lastBack`
     cache);
  5. `print` throughput: 1 000 lines, which forces `scroll`;
  6. `setCell`, `setCellColor` and `setCellBackColor` over ranges;
  7. `setSize` to 160×100.
- **Suspects:**
  - **S-T1:** `ScreenFont.drawChar` (line 227) runs `BeginShaderMode` and
    `EndShaderMode` **around every glyph**. A full screen means one batch flush per
    cell, every frame. This is likely the single biggest per-frame cost in Soda for
    text-heavy programs. Look for `[raylib.EndShaderMode]` in the profile. A fix
    could put one shader bracket around the whole `render`, or pass colours as
    vertex colours or a texture so the shader doesn't have to be re-bound.
  - **S-T2:** `drawChar` calls `color.toList` twice per glyph (hex string parsing)
    and `srcRect` allocates a list per glyph. Measure with `perf.timeit`. A cache
    of colour string → list would help.
  - **S-T3:** the fallback path (no shader): `DrawRectangle` + `DrawTexturePro`
    per cell. Force it and measure it as well, because it's what GL ES/RPi might
    get.
  - **S-T4:** `render` re-walks every cell every frame even when nothing changed.
    Measure how much a dirty flag or an offscreen-texture cache would save.
- **Bugs:** cursor blink/inverse handling. `print` with `delimiter=""`. Unicode
  outside the font (`UNKNOWN_CHAR_POS`). `row=` and `column=` clamping. `scroll` at
  1 row. Run the module's own self-test (`if locals == globals`) and
  `tests/text.ms`.

### 4.6 `TileDisplay.ms`: high priority

- **Workloads:** map sizes of 10×10, 50×50, 200×200 and 1 000×1 000, viewed through
  a 960×640 window, scrolled every frame. Fill levels: all tiles set, half null,
  hex offsets on, all 8 transforms in use, tints in use.
- **Suspects:**
  - **S-L1:** `render` (line 157) loops over **every cell in the map**, with no
    culling to the visible area. The cost grows with map size, not screen size, so
    a 200×200 map draws 40 000 tiles to show about 600.
  - **S-L2:** `_tileGeometry` (line 137) allocates **one map and four lists per
    tile per frame**, and `_srcRectFor` does a floor/mod for each tile. Expect a
    large GC share.
- **Bugs:** `extent=` resize keeps or clears data correctly. Tile indexes past the
  end of the tile set. Negative scroll. `overlap` > 0. Run the self-test block.

### 4.7 `SolidColorDisplay.ms`

- A single `DrawRectangle`. Benchmark it only as part of the stack in 4.1. Check
  colour changes, alpha, and window resize.

### 4.8 `Image.ms`

- **Workloads:** `pixel` and `setPixel` loops over a 64×64 and a 512×512 image.
  `getImage` to slice a sprite sheet into 256 frames. `flip`, `rotate`. The cost of
  the first `.texture` access after a change.
- **Suspects:**
  - **S-I1:** `setPixel` (line 100) invalidates the texture on every call, so an
    image that's edited per frame and drawn as a sprite re-uploads its whole
    texture every frame. Measure that pattern: edit k pixels, draw once, for
    k = 1 … 10 000.
  - **S-I2:** `Image.ms` and `color.ms` each have their own hex-parsing code. Check
    whether they agree, and time both.
- **Bugs:** out-of-range `pixel` and `setPixel` calls. `getImage` with a rect that
  partly falls outside the image. Short (`"#RGB"`) or malformed colour strings
  silently turn into white. Is that intended? `rotate` by non-multiples of 90.
  `resourceCounts` after 10 000 `getImage` calls followed by GC (are textures freed
  through `autoUnload`?).

### 4.9 `Sound.ms`

- **Workloads:**
  - synthesis: `Sound.init` for durations of 0.1, 1 and 5 s, with and without
    `mix` (2 and 8 sub-sounds);
  - `UpdateAll` with 0, 10 and 100 playing sounds;
  - a streamed music file playing while other benchmarks run (`UpdateMusicStream`
    cost);
  - rapid re-triggering of one sound (the `tests/balls.ms` pattern).
- **Suspects:**
  - **S-A1:** `_addSamples` (line 298) is a per-sample MiniScript loop with two
    `_lookupLUT` calls per sample. One second at 44.1 kHz is about 44 000
    iterations, and it runs **lazily on the first `play`**, so the hitch lands on
    the frame where the sound is first used. Report ms per second of audio. A fix
    could pre-synthesize at `init`, or move the per-sample work into an intrinsic or
    a matrix op.
  - **S-A2:** the `_invalidate` setters force a full re-synthesis when any one
    parameter changes. Check for repeated re-synthesis in loops.
- **Bugs:**
  - **`Sound.StopAll` (line 131):** it iterates over `_playingSounds` while each
    `stop` removes an element from that same list, so it probably **skips every
    other sound**. The skipped sounds keep playing, but they're dropped from the
    list, so music streams stop being updated and `isPlaying` stays `true`. Test:
    start 4 sounds, call `StopAll`, check each `isPlaying` and `IsSoundPlaying`.
  - `unload` (line 124) explicitly unloads resources that were also flagged with
    `autoUnload`. Same double-free check as `PixelDisplay.clear`.
  - Looping one-shot sounds, `adjust` while playing, `play` on an unloaded sound,
    `file.loadSound` on a missing file. Run `tests/soundTest.ms`.

### 4.10 `key.ms` and `mouse.ms`

- **Workloads:** time `key.pressed` with a key name, `"mouse 0"`,
  `"joystick button 3"` and `"joystick 2 button 3"` (the joystick forms split
  strings on every call). Time `key.axis`, plus `key.update` and `mouse.update` per
  frame. All of these should come out well under 0.1 ms per frame. Flag anything
  that doesn't.
- **Bugs:** `key.pressed("notAKey")` calls `exit` and **kills the program**. Mini
  Micro behaviour is probably an error or false; check which, and treat the
  difference as a bug. Also test `"mouse "` with no number, `key.get` blocking
  behaviour, and that `keyQueue` doesn't grow without bound when nobody reads it.
  Check the gamepad scripts on real hardware if it's available.

### 4.11 `color.ms`

- `perf.timeit` for `toList` (string and list input), `fromList`, `rgba` and
  `lerp`. These are called inside the hot loops above, so their per-call cost
  multiplies. Round-trip `fromList(toList(c)) == c` for all named colours and for
  random 8-digit hex.

### 4.12 Fonts: `bmfFonts.ms`, `ttFonts.ms`

- **Workloads:** load each sample font. `print` of 100 and 1 000 characters per
  frame. `width`, `lenToFit`, `printJustified`.
- **Suspects:** `renderChar` and `findColorsFromImage` (lines 389 and 51) loop over
  every pixel in MiniScript. Check whether glyph images are cached
  (`getCharImage`) or rebuilt per print. Font load time.
- **Bugs:** kerning pairs, missing glyphs, the lowercase→uppercase fallback, a
  save/load round-trip. Run both self-test blocks.

### 4.13 Tier C utilities

- Run every module's built-in tests: `qa.runUnitTests`, the
  `if locals == globals` blocks in `json`, `grfon`, `tsv` and `textUtil`, and any
  `runUnitTests` functions. Record pass/fail.
- **Scaling micro-benchmarks** for anything a game might call per frame or on
  large data:
  - `json.parse`/`toJSON` and `grfon` on 1 KB, 100 KB and 1 MB documents;
  - `tsv` on 10 000 rows;
  - `base64` on 1 MB;
  - `listUtil` sort, shuffle, uniq and similar on 10⁴ and 10⁵ elements;
  - `stringUtil` and `textUtil` wrap and split on large text;
  - `matrixUtil` multiply on 10×10 and 100×100.
- Look for accidental O(n²): string building by repeated `+=` in a loop, `indexOf`
  inside a loop, `insert 0` in a loop.
- Report findings for upstream; **don't patch these files here.**

---

## 5. Integration scenarios

These are realistic games, so you can see which of the unit costs actually matter.
Run each one for 600 frames un-profiled and once profiled:

1. **Bouncing balls ×N:** `tests/balls.ms` adapted to N = 100, 1 000, 5 000,
   including sounds.
2. **Text adventure:** a full TextDisplay with continuous `print` and scrolling.
3. **Scrolling platformer:** a 200×50 TileDisplay scrolling, 50 sprites,
   per-frame `overlaps` checks against 20 enemies, and an HUD drawn with
   `PixelDisplay.print` every frame.
4. **Paint program:** 200 `PixelDisplay.line`/`fillEllipse` calls per frame, which
   follows a mouse-drag workload.
5. **Everything at once:** all display types active together, plus music.

For each scenario, report: fps (uncapped), the phase breakdown from
`perf.frames`, the top 10 self-time lines from the profile, and the GC share.

---

## 6. Robustness and leak soak tests

- **Leak soak:** run scenario 5 for 10 minutes, logging `resourceCounts` and
  `hostMemory` every 30 s. Every count should be flat.
- **Churn:**
  - create and drop 10 000 Images, Sprites and PixelDisplays, synthesized Sounds,
    and `Display.mode` switches, then force GC (several `yield`s) and check the
    counts go back to the baseline;
  - resize the window and toggle fullscreen during rendering;
  - switch display modes during rendering.
- **Hostile inputs:** pass `null`, negative numbers, NaN, huge values (1e9) and
  wrong types to every public method listed in §4. Any crash of the **host**
  (as opposed to a MiniScript runtime error) is a critical finding.

---

## 7. Reporting

Write `tests/perf_results/FINDINGS.md` with one entry per confirmed issue:

```
### [PERF|BUG|BIND|VM]-NN  <short title>
- Unit / location: lib/X.ms:LINE (function)
- Severity: Critical (crash/leak) | High (>1 ms/frame at realistic load, or superlinear)
            | Medium (one-off hitch >5 ms, or 0.1–1 ms/frame) | Low
- Evidence: benchmark name + numbers (median, p95), profile excerpt (top lines),
            scaling table across N
- Root cause: one or two sentences
- Proposed fix: description; if prototyped, branch/commit + before/after numbers
- Mini Micro compatibility impact: none / API change (explain)
```

Also keep:

- `tests/perf_results/baseline/*.csv`: the untouched-code numbers;
- `tests/perf_results/SUMMARY.md`: a table with one row per benchmark and N,
  showing the baseline ms/frame, the after-fix ms/frame and the speed-up, sorted by
  absolute ms saved.

Record suspects that turned out *not* to matter as well, with numbers ("S-P4:
colorToList 0.6 µs/call, negligible"). Negative results save the next person time.

---

## 8. Order of work

0. The pre-flight steps (top of this file).
1. §3 harness + `run_perf.sh`; verify it on an empty scene (4.1).
2. Baselines for all of §4 Tier A, then §5 scenarios. Commit the results.
3. Triage the confirmed hot spots in this order, which is roughly how likely each is
   to be the biggest win: **S-T1** (shader per glyph) → **S-P1** (texture mode per
   primitive) → **S-L1/S-L2** (tile culling and allocation) → **S-S1/S-S2**
   (sprite allocation and quad path) → **S-P2** (texture upload per drawImage) →
   **S-A1** (synthesis hitch) → the rest.
4. The bug checks in §4 and §6 (the Display.install and StopAll checks are quick
   and likely real bugs, so they're good early wins).
5. Binding overhead (§9). Do this as soon as you have the Tier A baselines. Its
   results decide whether a hot spot gets fixed in Soda's `lib/` or in
   raylib-miniscript, so it shapes how step 8 is done.
6. The MiniScript 2 VM (§10). Start the native profiling (§10.1) at the same time
   as step 2, since it uses the same benchmarks. Do the VM experiments after the
   Soda baselines exist, so their gains can be measured on real workloads.
7. Tier B, then Tier C.
8. Prototype fixes for the top findings, re-measure, and fill in `SUMMARY.md`.

---

## 9. Binding overhead: MiniScript → raylib vs. native C

**Goal:** for the cheap raylib calls Soda makes thousands of times per frame, find
out how much of each call's cost is the MiniScript binding (intrinsic dispatch +
converting arguments into raylib structs) and how much is raylib itself. The answer
decides **where a fix belongs**:

- binding cost ≪ Soda's own MiniScript work around the call → optimize `lib/`
  (§4);
- binding cost is a large share → fix it in **raylib-miniscript**: cheaper
  conversions, cached values, or new batch intrinsics. That speeds up every
  program on the host, not just Soda.

**Don't bother** with expensive calls (`LoadTexture*`, `LoadImage*`, `EndDrawing`,
`UpdateMusicStream`, `Image*` operations, `GenImage*`). Raylib's own work there is
far larger than any binding overhead, so the comparison tells you nothing.

### 9.1 How the host converts arguments (`raylib-miniscript/src/RaylibTypes.cpp`)

- `ValueToColor` (line 701) accepts a **`"#RRGGBB[AA]"` string** (parsed in C on
  every call), a **list** `[r,g,b,a]`, or a **map** `{r,g,b,a}` (four lookups by
  key name, with `String("r")` etc. built on every call).
- `ValueToRectangle` (line 781) and `ValueToVector2` (line 823) accept a list or a
  map. The map form again builds a `String` for each key name and looks it up.
- `ValueToTexture` (line 471) resolves a resource handle out of a map on every
  call.
- `ColorToValue` and `RectangleToValue` build a **new map** for each return value,
  which creates garbage. The `raylib.WHITE`-style constants are maps of this kind.
  Note that `Sprite.tint` defaults to `raylib.WHITE`, so every untinted sprite takes
  the **map** path.

Each of these is a hypothesis to measure, not a finding. In particular, check
whether `String("x")` allocates on MiniScript 2's GC heap. If it does, **every
map-form argument creates garbage on every call**, and that would show up as GC
time in Soda's frames.

### 9.2 What to measure: three layers per call

| Layer | How | What it isolates |
|---|---|---|
| **L0: native floor** | a small C program (§9.4) looping the same raylib call with the same arguments | raylib's own CPU cost |
| **L1: dispatch floor** | `perf.timeit` on a near-empty intrinsic (`raylib.GetScreenWidth`, `raylib.IsKeyDown 65`) and on an empty MiniScript function | the fixed cost of crossing the binding at all |
| **L2: real calls** | `perf.timeit` on each call below, with each argument form | dispatch + argument conversion + raylib |

From these: **binding overhead = L2 − L0**, and **conversion cost ≈ L2 − L1 − L0**.
Report results in ns per call. Then multiply by Soda's real call counts per frame
from the §5 scenarios: for example, sprites × 1 `DrawTexturePro`, or text cells ×
(`BeginShaderMode` + `SetShaderValue` ×≤2 + `DrawTexturePro` + `EndShaderMode`).
That gives **ms per frame** spent in the binding, which can be compared directly
with the §4 numbers.

### 9.3 Calls and argument forms to test

Run each call inside `BeginDrawing`/`EndDrawing` (or `BeginTextureMode` where Soda
uses it), and **time only the loop of calls, not the End call**. Raylib defers the
GPU work to the flush, so timing the End call measures the GPU, not the binding.
Keep the batch from overflowing mid-loop, or report where it does: raylib flushes
automatically every few thousand quads, which shows up as periodic spikes.

| Call | Used by | Argument forms to compare |
|---|---|---|
| `DrawTexturePro tex, src, dest, origin, rot, tint` | Sprite.draw, TileDisplay, ScreenFont, PixelDisplay | rect/vector **list vs. map**; tint as **string vs. list vs. map** (`raylib.WHITE`) vs. **omitted** (uses the default) |
| `DrawTexture` / `DrawTextureV` | reference: the simplest textured draw | colour forms as above |
| `DrawPixel x, y, color` / `DrawPixelV` | PixelDisplay.setPixel | colour string vs. list vs. map |
| `DrawLineEx start, end, thick, color` | PixelDisplay.line | vector list vs. map |
| `DrawRectangle` / `DrawRectangleRec` | SolidColorDisplay, ScreenFont fallback | ints vs. rect list vs. rect map |
| `rlVertex2f`, `rlTexCoord2f`, `rlColor4ub` | Sprite._drawQuad (8+ calls per sprite) | plain numbers, so this is pure dispatch cost |
| `SetShaderValue shader, loc, [f,f,f,f], type` | ScreenFont colour uniforms | list of 4 floats |
| `BeginShaderMode` / `EndShaderMode` pair, nothing drawn | ScreenFont.drawChar, Sprite._drawQuad | measures the batch flush on its own; compare with the same pair in C |
| `IsKeyDown`, `IsGamepadButtonDown`, `GetMouseX` | key, mouse | the dispatch floor for a trivial query |
| `GetImageColor img, x, y` | Image.pixel | returns a **new map** per call: measure the allocation and GC cost |

Also time the **same call with arguments built inline vs. reused**:
`DrawTexturePro tex, [0,0,16,16], [x,y,16,16], ...` builds new lists every call,
whereas reusing preallocated lists only changes their elements. This shows how much
of Soda's per-sprite cost is MiniScript allocation as opposed to the binding.

### 9.4 Native C benchmark

Add `tools/bench_native.c` to raylib-miniscript. Build it as a CMake target with
`EXCLUDE_FROM_ALL`, like the existing `fs_tests`/`interp_tests`, linked against the
**same raylib build** with the same flags (Release, the same GL backend). It should:

- open a window of the same size, `SetTargetFPS(0)`;
- for each call in §9.3, run warm-up + 5 × N iterations inside
  `BeginDrawing`/`EndDrawing`, timing only the call loop with `GetTime()` (or a
  monotonic clock in ns);
- print `RESULT,native,<call>,<N>,per-call,...` in the same CSV format as
  `perfHarness.ms`, so the two outputs join on `<call>,<N>`.

Use the **same N values, texture sizes and source/destination rects** in both
benchmarks, so the vertex work is identical.

The MiniScript side is `tests/perf_binding.ms`: one `perf.timeit` per call ×
argument form. Run it from Soda's `tests/` folder like the other benchmarks.

### 9.5 Reporting

Add a table to `SUMMARY.md`:

```
call | arg form | native ns | MiniScript ns | overhead ns | ×native | Soda calls/frame (scenario) | binding ms/frame
```

For each entry where the binding takes **> 0.5 ms/frame** in a §5 scenario, write
a `BIND-NN` finding in `FINDINGS.md` that names the fix and the repo it belongs
in. Candidate fixes to evaluate:

- intern the key-name `String`s used by map conversions (create them once, as
  statics);
- add a fast path for lists of exactly the expected length;
- have Soda pass colours as lists instead of strings or maps (a fix in `lib/`);
- cache parsed colour strings;
- add **batch intrinsics** such as `DrawTexturesPro(tex, listOfRects…)`, or a
  host-side `DrawSprites`/`DrawTileGrid` that takes a whole list per call (the
  biggest possible win for SpriteDisplay, TileDisplay and TextDisplay);
- skip `BeginShaderMode` when the shader is already active.

As with the other findings, record the calls whose binding cost turned out
negligible, with their numbers.

---

## 10. The MiniScript 2 VM (`../miniscript2`)

Most of Soda's script time is spent inside the MiniScript 2 VM: instruction
dispatch, map and list access, method lookup along `__isa` chains, and GC. Your
MiniScript profiler can't see inside those. This section covers profiling the VM
natively and checking a few specific suspects found by reading its source
(commit `a5a546a`).

**Rules for this repo.** `miniscript2/CLAUDE.md` governs this repo and overrides
this plan wherever they differ. Read it at the start of any session that touches
miniscript2. The rules that matter here:
- **Profiling and measuring are read-only and always fine.**
- **Edit C# in `cs/`, never `generated/`.** The one exception that `CLAUDE.md`
  allows is hacking generated C++ to *understand* a C++-only problem. S-V1 below
  is one: the `shared_ptr` copies are an artifact of transpiling. **Ask the user
  before** making even a throwaway change to `generated/` or `cpp/core/`. Do it on
  a scratch branch, and revert it afterwards.
- **Don't run the transpiler** (`tools/build.sh transpile`/`all`) unless the user
  says to: it's expensive, and it's the user's call. Make the C# change, then
  **tell the user it's ready for transpilation and testing**, and wait. Only
  continue with the C++ build and benchmarks once the user has done that or
  asked you to.
- **Never edit `notes/DEV_LOG.md`.** Other files in `notes/` are fine to edit.
- **Report in a calm tone, and don't claim success early.** Say plainly what you
  believe is done, and what is still unverified.
- When you're unsure what's wanted, stop and ask.
- This is a fork of Joe Strout's project. Prepare confirmed fixes as a branch +
  PR for upstream, with the benchmark numbers in the description.
- raylib-miniscript compiles MiniScript2 from source through its `MiniScript2`
  symlink (`../miniscript2`). So once miniscript2's C++ has been regenerated,
  rebuild `build-release/` and `build-profile/`, then re-run the Soda benchmarks.

### 10.1 Native profiling of the host

1. Use the `build-profile/` RelWithDebInfo host from pre-flight step 1. A Debug
   build gives meaningless profiles.
2. Profile the §5 scenarios and the §9 binding benchmark with
   `xcrun xctrace record --template 'Time Profiler'` (macOS) or `samply record`,
   pointed at the `build-profile/` host binary. On Linux or RPi, use
   `perf record -g`.
3. Sort the native time into buckets, and add a table of them to `SUMMARY.md`
   for each scenario:

| Bucket | Typical symbols |
|---|---|
| VM dispatch | `VM::Execute` / the computed-goto body |
| Map lookup | `LookupWithOrigin`, `TryGet`, `findEntry`, `value_hash`, `DictKeyEqual` |
| List access | `ListGet`, `ListSet`, `GCListSet::Get` |
| **Refcounting** | `__shared_weak_count`, `__release_shared`, `__add_shared`, atomic ops (see §10.2 S-V1) |
| String building | `make_string`, `String::operator+`, `StringStorage` |
| GC | `CollectGarbage`, `Mark*`, `Sweep` |
| Binding conversion | `ValueToColor`, `ValueToRectangle`, `ValueToVector2`, `ResourceBoxOf` |
| raylib / GL driver | `rlDrawRenderBatch`, `glDraw*`, driver libraries |

4. Run the VM's own benchmark suite (`tools/benchmark.sh`) before and after each
   VM change. That catches regressions on non-Soda code too.

### 10.2 Suspects found by reading the code (verify each one)

- **S-V1: map and list lookups copy a struct full of `shared_ptr`s.**
  - `GCMapSetStorage::Get(idx)` (`generated/GCSet.g.h:556`) returns a `GCMap`
    **by value**. `GCListSet::Get` does the same for `GCList`.
  - `GCMap` holds a `Dictionary` (`Items`), a `List` (`_order`), `VarMapBacking`,
    `Globals` and a second `Dictionary` (`_pos`). In C++ each of these is a
    `shared_ptr` handle. So every copy does an atomic reference-count increment
    on each non-null member, and a decrement when the copy goes out of scope.
  - That copy happens in `Value::TryGet`, at every level of
    `Value::LookupWithOrigin` (`cpp/core/value_map.cpp:82`), in `Value::ListGet`
    (`value_list.cpp:46`), and in `ChainHasSetter`, which copies the whole struct
    just to read `_setterStatus`.
  - So every `self.x`, `obj.method`, `row[col]` and `for x in list` likely pays
    several atomic read-modify-write operations. Each one also writes to the
    control block's cache line.
  - **Test:** micro-benchmark `x = obj.field` on a 1-, 2- and 3-level `__isa`
    chain, plus `x = list[i]`, natively profiled. Look for refcount symbols near
    the top.
  - **Prototype:** make `Get` return `const GCMap&` / `const GCList&` (or add a
    `GetRef` used on the read-only hot paths), then re-measure.
  - **Real fix:** this has to be expressed in C# so the transpiler keeps it, e.g.
    `ref readonly`, or a `// CPP:` override if the transpiler supports one. Check
    `tools/CLAUDE.md` for how it handles `ref`.
  - This affects **every MiniScript program**, not just Soda.
- **S-V2: property setters make member assignments slow.**
  - `SETRFIND` runs before every map member assignment (`cs/VM.cs:~2410`). If the
    object's `__isa` chain contains any `"name="` key, `ChainHasSetter` returns
    true. The VM then calls `SetterKey()` (`cs/Value.cs:191`).
  - For any key longer than 4 bytes, `SetterKey()` builds a **new heap string**
    `key + "="`. That's an allocation, plus a hash computed from scratch because
    the string is fresh, plus a lookup at every level of the chain.
  - Soda puts setters on `Display` (`mode=`), `TextDisplay` (`row=`, `column=`),
    `TileDisplay` (`extent=`) and `window`. So **every display instance** pays
    this on assignments like `self.scrollX = …` or `self._cursorBlinking = …`.
    That includes the text display's `print`/`put` path, which runs per
    character.
  - **Test:** time `self.someLongName = 1` on a plain map, and on an instance of a
    class that has one setter. Compare GC counts as well.
  - **Fixes to evaluate:**
    - cache setter keys (key → `key+"="`, built once per distinct key);
    - keep, on each map that holds setters, a small set of the base names it has
      setters for, so the check needs no string building at all;
    - (on the Soda side) avoid setters on hot classes, or bypass them with
      `super.x =` writes, which TextDisplay already does in places.
- **S-V3: `__isa` chain misses cost a full lookup at every level.**
  - Calling a method on a deep class (instance → TextDisplay → Display) misses on
    the instance and on each class before it hits. Each miss is a struct copy
    (S-V1) + a hash + a bucket probe, then the same again for `__isa`.
  - **Test:** method-call cost against chain depth (1–5).
  - **Fix to evaluate:** per-instruction **inline caches** on
    `METHFIND`/`INDEX`. Cache (container map identity or class map, key) → (value,
    origin), invalidated by a global "map mutated" generation counter, like the
    existing `SetterGeneration` scheme. This is a bigger change: only pursue it if
    lookups dominate after S-V1 is fixed.
- **S-V4: GC pauses.**
  - Collection is a **full, non-generational** mark/sweep. It runs every 60
    `yield`s, at most every 30 once 64 or more host handles are alive
    (`GCIntervalTicks`, `GCMinIntervalTicks`, `GCHandlesForMinInterval` in
    `cs/GCManager.cs:79–113`), or sooner when allocation grows past a threshold.
  - Every raylib texture, image, sound and render texture is a handle. So any
    real Soda game hits the 30-frame interval, and each collection marks the
    **whole live heap**.
  - Soda's live heap is large: one map per TextDisplay cell, a 2-D list per
    TileDisplay layer, font data.
  - **Test:** in the §5 scenarios, look for frame-time spikes every ~30 frames in
    the `perf.frames` max/p95. Time `CollectGarbage` natively against live-object
    count (e.g. TextDisplay sizes from 40×25 up to 160×100).
  - **Fixes to evaluate:**
    - on the Soda side: reduce live objects, e.g. TextDisplay cells stored as
      parallel lists instead of one map per cell;
    - on the VM side: incremental marking, or a policy that doesn't shorten the
      interval just because handles are alive.
- **S-V5: the cost of a function call.**
  - `notes/CALL_OPT_ATTEMPT.md` measures MS2 calls at ~4× slower than Lua, while
    its loops are faster.
  - Soda is call-heavy per object per frame: `Sprite.draw` → `_scaleXY`, and
    `TileDisplay.render` → `_tileGeometry` → `_srcRectFor`.
  - Measure Soda's calls per frame. Combined with the per-call cost, that tells you
    whether inlining small helpers in Soda's hot loops is worth doing. Don't
    re-attempt the VM call optimisation without reading that note first.
- **S-V6: smaller items, measure only if the profile points at them.**
  - Tiny strings (≤5 bytes) are re-hashed (FNV) on every lookup instead of hashing
    their bits.
  - `Dictionary` uses `%` (an integer division) per lookup rather than a
    power-of-two mask.
  - Every `GCMap` is a separate heap allocation for its dictionary storage plus
    its `_order` list, so one map access chases 4–5 pointers.
  - The `notes/OFI.md` loop items (constant `LOAD`s, `LOADC` copies) are already
    tracked there. Cross-reference, don't duplicate.

### 10.3 Order of work and reporting

1. Native-profile two scenarios: §5.1 (sprites) and §5.2 (text). Fill in the
   bucket table.
2. S-V1 first: once the native profile confirms it, ask the user whether to
   prototype it in the generated C++, as the rules above require. The prototype
   is a small change, and it may speed up everything. Measure it with the VM
   benchmark suite and the Soda scenarios.
3. Then S-V2, S-V4 and S-V3, in whatever order the bucket table suggests.
4. Report each one as a `VM-NN` finding in `FINDINGS.md`. Give the native
   evidence (the symbol and its % of samples), MiniScript-level micro-benchmark
   numbers, Soda scenario before/after, and `tools/benchmark.sh` before/after.
   State whether the fix is upstream-ready (C# source, tests pass) or still a
   generated-code prototype.
