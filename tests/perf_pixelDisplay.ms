// perf_pixelDisplay.ms -- PERF_TEST_PLAN.md §4.3 workloads, re-checked against
// the upstream pixel-optimization commits (fe30532, 67ba779, e24b598,
// 2d1abbc) that landed via the Session 1 upstream sync.
//   S-P1 (per-call BeginTextureMode/EndTextureMode): setPixel now has a
//     cache fast path (no GPU bracket per call) when consecutive calls hit
//     the same display with no clip; fillRect/line etc. still bracket every
//     call. This workload compares the two to see whether S-P1 is closed
//     for setPixel specifically, still open for other primitives.
//   S-P2 (drawImage/patternFill upload per call): unchanged upstream, still
//     calls LoadTextureFromImage + UnloadTexture every call. Measure it.
//   S-P3 (pixel() full-texture readback): now cached (RawData, lazy
//     rebuild). Measure to confirm it's cheap except for the first call
//     after a draw.
//   S-P5 (_triangulate O(n^2) or worse): unchanged upstream. Measure
//     fillPoly scaling from 5 to 500 vertices.
// Usage (from tests/): ../soda perf_pixelDisplay.ms [runIndex]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

d = PixelDisplay.Make

counter = {"x": 0, "y": 0}
bumpXY = function()
	counter.x = (counter.x + 1) % 960
	counter.y = (counter.y + 1) % 640
end function

// --- S-P1: setPixel (has the cache fast path) vs fillRect (no fast path) ---
for N in [1, 100, 1000, 10000]
	perf.timeit "px_setPixel", N, function()
		d.setPixel counter.x, counter.y, "#FF0000FF"
		bumpXY
	end function, N
end for

for N in [1, 100, 1000, 10000]
	perf.timeit "px_fillRect_1x1", N, function()
		d.fillRect counter.x, counter.y, 1, 1, "#00FF00FF"
		bumpXY
	end function, N
end for

// --- S-P1 fix: the same setPixel/fillRect calls, but wrapped in a single
// beginBatch/endBatch bracket spanning the whole measurement, so the
// framebuffer bind/unbind happens once instead of once per call. n=N here
// (not 1), so these are still genuine per-call numbers, comparable to the
// unbatched ones above -- just measured while one bracket stays open. ---
for N in [1, 100, 1000, 10000]
	d.beginBatch
	perf.timeit "px_setPixel_batched", N, function()
		d.setPixel counter.x, counter.y, "#FF0000FF"
		bumpXY
	end function, N
	d.endBatch
end for

for N in [1, 100, 1000, 10000]
	d.beginBatch
	perf.timeit "px_fillRect_1x1_batched", N, function()
		d.fillRect counter.x, counter.y, 1, 1, "#00FF00FF"
		bumpXY
	end function, N
	d.endBatch
end for

// --- S-P3: pixel() reads, after a draw invalidates the cache each time vs
// repeated reads that reuse one cached readback ---
perf.timeit "px_pixel_repeatedRead", 1000, function()
	x = d.pixel(10, 10)
end function, 1000

perf.timeit "px_pixel_afterEachDraw", 1000, function()
	d.setPixel 10, 10, "#FFFFFFFF"  // cache-path write -- doesn't itself drop cache
	x = d.pixel(11, 11)
end function, 1000

// --- S-P2: drawImage upload-per-call, small and large images ---
imgSmall = Image.create(16, 16, "#8080FFFF")
imgLarge = Image.create(256, 256, "#8080FFFF")
tileImg = Image.create(8, 8, "#FF80FFFF")

for N in [1, 10, 100]
	perf.timeit "px_drawImage_16x16", N, function()
		d.drawImage imgSmall, 0, 0
	end function, N
end for

for N in [1, 10, 100]
	perf.timeit "px_drawImage_256x256", N, function()
		d.drawImage imgLarge, 0, 0
	end function, N
end for

// --- S-P2 fix: same drawImage/patternFill calls, but (a) the image's own
// cached texture (Image.texture) is reused instead of a fresh
// LoadTextureFromImage/UnloadTexture pair every call, and (b) wrapped in a
// single beginBatch(true)/endBatch bracket spanning the whole measurement --
// alphaBlend must be true to match drawImage/patternFill's own internal
// _beginDraw(true) call, or every call still forces a blend-mode flush. ---
for N in [1, 10, 100]
	d.beginBatch true
	perf.timeit "px_drawImage_16x16_batched", N, function()
		d.drawImage imgSmall, 0, 0
	end function, N
	d.endBatch
end for

for N in [1, 10, 100]
	d.beginBatch true
	perf.timeit "px_drawImage_256x256_batched", N, function()
		d.drawImage imgLarge, 0, 0
	end function, N
	d.endBatch
end for

for N in [1, 10, 100]
	perf.timeit "px_patternFill_8x8", N, function()
		d.patternFill tileImg, 0, 0, 64, 64
	end function, N
end for

for N in [1, 10, 100]
	d.beginBatch true
	perf.timeit "px_patternFill_8x8_batched", N, function()
		d.patternFill tileImg, 0, 0, 64, 64
	end function, N
	d.endBatch
end for

// --- S-P5: fillPoly scaling with vertex count (convex regular polygons) ---
makePoly = function(n, radius=50)
	pts = []
	for i in range(0, n-1)
		a = 2 * pi * i / n
		pts.push [480 + radius * cos(a), 320 + radius * sin(a)]
	end for
	return pts
end function

for n in [5, 20, 100, 500, 1000]
	poly = makePoly(n)
	perf.timeit "px_fillPoly", n, function()
		d.fillPoly poly, "#0000FFFF"
	end function, 100
end for

// --- S-P5 fix check: a concave, star-shaped polygon (half the vertices
// reflex) as a control -- the fix skips the per-candidate reflex-vertex
// scan only when there are zero reflex corners, so a shape that has them by
// construction should see no speedup here, confirming the fix doesn't just
// look fast because it got the triangulation wrong. ---
makeStar = function(n, outerRadius=50, innerRadius=20)
	pts = []
	for i in range(0, 2*n-1)
		a = pi * i / n
		r = outerRadius
		if i % 2 == 1 then r = innerRadius
		pts.push [480 + r * cos(a), 320 + r * sin(a)]
	end for
	return pts
end function

for n in [5, 20, 100, 500, 1000]
	poly = makeStar(n / 2)
	perf.timeit "px_fillPoly_star", n, function()
		d.fillPoly poly, "#0000FFFF"
	end function, 100
end for

perf.finish "perf_results/perf_pixelDisplay.run" + runIdx + ".csv"
