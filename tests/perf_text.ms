// perf_text.ms -- PERF_TEST_PLAN.md §4.5 workloads (TextDisplay.ms + ScreenFont.ms).
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_text.ms [runIndex]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

noop = function(); end function
nFrames = 60
t = display(3)
print "text size: " + t.columns + "x" + t.rows

fillScreen = function(td, fore, back, alternate=false)
	for r in range(0, td.rows - 1)
		for c in range(0, td.columns - 1)
			td.setCell c, r, char(65 + (r + c) % 26)
			if alternate and (r + c) % 2 == 0 then
				td.setCellColor c, r, "#FF0000FF"
				td.setCellBackColor c, r, "#0000FFFF"
			else
				td.setCellColor c, r, fore
				td.setCellBackColor c, r, back
			end if
		end for
	end for
end function

// 1. empty
clear
perf.frames "txt_empty", 1, @noop, nFrames, 5

// 2. full screen, transparent background
clear
fillScreen display(3), "#FFFFFFFF", "#00000000"
perf.frames "txt_full_clearBack", t.columns * t.rows, @noop, nFrames, 5

// 3. full screen, opaque background colors
clear
fillScreen display(3), "#FFFFFFFF", "#202040FF"
perf.frames "txt_full_opaqueBack", t.columns * t.rows, @noop, nFrames, 5

// 4. alternating colors per cell
clear
fillScreen display(3), "#FFFFFFFF", "#202040FF", true
perf.frames "txt_full_alternating", t.columns * t.rows, @noop, nFrames, 5

// 3b/S-T3. fallback path (no shader) on the opaque-background full screen
clear
fillScreen display(3), "#FFFFFFFF", "#202040FF"
realLoad = @ScreenFont.loadShader
ScreenFont.unloadShader
ScreenFont.loadShader = function(); return false; end function   // stub: drawChar falls back (adds one cheap call per glyph)
perf.frames "txt_full_opaqueBack_noShader", t.columns * t.rows, @noop, 20, 3
ScreenFont.loadShader = @realLoad
ScreenFont.loadShader

// 5. print throughput (forces scroll)
clear
perf.timeit "txt_print_1000lines", 1000, function()
	text.print "The quick brown fox jumps over the lazy dog 0123456789"
end function, 1000
clear
perf.timeit "txt_print_short", 1, function()
	text.print "x"
end function, 1000

// 6. setCell / setCellColor / setCellBackColor
clear
td = display(3)
perf.timeit "txt_setCell", 1, function(); td.setCell 5, 5, "Q"; end function, 5000
perf.timeit "txt_setCellColor", 1, function(); td.setCellColor 5, 5, "#FF0000FF"; end function, 5000
perf.timeit "txt_setCellBackColor", 1, function(); td.setCellBackColor 5, 5, "#00FF00FF"; end function, 5000
perf.timeit "txt_fillScreen_setCell", t.columns * t.rows, function(); fillScreen td, "#FFFFFFFF", "#00000000"; end function, 3

// 7. setSize
perf.timeit "txt_setSize_160x100", 160 * 100, function(); td.setSize 160, 100; end function, 5
td.setSize 160, 100
fillScreen td, "#FFFFFFFF", "#00000000"
perf.frames "txt_full_160x100", 160 * 100, @noop, 30, 3
td.setSize 96, 40

// S-T2: per-glyph helper costs
perf.timeit "txt_color_toList_string", 1, function(); x = color.toList("#FF8040FF"); end function, 5000
perf.timeit "txt_font_srcRect", 1, function(); x = ScreenFont.srcRect(65); end function, 5000

perf.finish "perf_results/perf_text.run" + runIdx + ".csv"
