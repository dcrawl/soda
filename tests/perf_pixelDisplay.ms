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

// --- S-P5: fillPoly scaling with vertex count (convex regular polygons) ---
makePoly = function(n, radius=50)
	pts = []
	for i in range(0, n-1)
		a = 2 * pi * i / n
		pts.push [480 + radius * cos(a), 320 + radius * sin(a)]
	end for
	return pts
end function

for n in [5, 20, 100, 500]
	poly = makePoly(n)
	perf.timeit "px_fillPoly", n, function()
		d.fillPoly poly, "#0000FFFF"
	end function, 100
end for

perf.finish "perf_results/perf_pixelDisplay.run" + runIdx + ".csv"
