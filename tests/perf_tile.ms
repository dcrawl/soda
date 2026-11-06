// perf_tile.ms -- PERF_TEST_PLAN.md §4.6 workloads (TileDisplay.ms).
// Map sizes viewed through a 960x640 window (30x20 = 600 visible 32px cells),
// scrolled every frame. S-L1: no culling, S-L2: per-tile allocation.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_tile.ms [runIndex]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

tileSheet = Image.create(128, 128, "#80C0FFFF")
for i in range(0, 127)
	tileSheet.setPixel i, i, "#FF0000FF"
end for

makeTD = function(size, fill="all")
	clear
	td = new TileDisplay
	td.tileSet = tileSheet
	td.tileSetTileSize = 32
	td.cellSize = 32
	td.extent = [size, size]
	display(4).mode = displayMode.tile
	if fill == "all" then
		td.clear 5
	else
		for y in range(0, size - 1)
			for x in range(0, size - 1)
				if (x + y) % 2 == 0 then td.setCell x, y, (x * 7 + y) % 16
			end for
		end for
	end if
	td.install 4
	return td
end function

state = {"n": 0}
scrollFrame = function(td)
	state.n = state.n + 1
	td.scrollX = state.n * 3 % 200
	td.scrollY = state.n * 2 % 200
end function

frames = {1000: 5, 200: 15}
for size in [10, 50, 200, 1000]
	td = makeTD(size)
	nf = 30
	if size == 200 then nf = 10
	if size == 1000 then nf = 3
	f = function(); scrollFrame td; end function
	perf.frames "tile_scrolled", size, @f, nf, 1
end for

// fill levels at 50x50 and 200x200
for size in [50, 200]
	nf = 30
	if size == 200 then nf = 10
	td = makeTD(size, "half")
	f = function(); scrollFrame td; end function
	perf.frames "tile_halfEmpty", size, @f, nf, 1

	td = makeTD(size)
	for y in range(0, size - 1)
		for x in range(0, size - 1)
			td.setCellTransform x, y, (x + y) % 8
		end for
	end for
	f = function(); scrollFrame td; end function
	perf.frames "tile_allTransforms", size, @f, nf, 1

	td = makeTD(size)
	for y in range(0, size - 1)
		for x in range(0, size - 1)
			td.setCellTint x, y, "#FF8080FF"
		end for
	end for
	f = function(); scrollFrame td; end function
	perf.frames "tile_tinted", size, @f, nf, 1

	td = makeTD(size)
	td.oddRowOffset = 0.5
	f = function(); scrollFrame td; end function
	perf.frames "tile_hexOffset", size, @f, nf, 1
end for

// per-tile cost of the geometry helper, in isolation
td = makeTD(10)
perf.timeit "tile_tileGeometry", 1, function(); g = td._tileGeometry(3, 3, 5); end function, 5000
perf.timeit "tile_srcRectFor", 1, function(); g = td._srcRectFor(5); end function, 5000

// setCell / clear / extent= costs
td = makeTD(200)
perf.timeit "tile_setCell", 1, function(); td.setCell 3, 3, 4; end function, 5000
perf.timeit "tile_clear_200x200", 40000, function(); td.clear 3; end function, 3
perf.timeit "tile_extent_200x200", 40000, function(); td.extent = [200, 201]; td.extent = [200, 200]; end function, 3

perf.finish "perf_results/perf_tile.run" + runIdx + ".csv"
