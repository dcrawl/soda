// perf_fonts.ms -- PERF_TEST_PLAN.md §4.12 workloads (bmfFonts.ms, ttFonts.ms).
// Needs sample BMF fonts (Mini Micro system disk) and a TrueType file; paths
// below are the ones on the author's machine, skipped with a note if absent.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_fonts.ms [runIndex]
import "perfHarness"
import "soda"
import "bmfFonts"
import "ttFonts"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

bmfDir = "/Users/redspark/Documents/GitHub/study/minimicro-sysdisk/sys/fonts/"
ttfPath = "../../raylib-miniscript/assets/Merkin.ttf"

text100 = ("The quick brown fox jumps over the lazy dog. " * 3)[:100]
text1000 = (text100 * 10)

// --- load time ---
for name in ["Arial14.bmf", "minimicro-mono-12.bmf", "NotoSansBold-24.bmf", "Lcars-64.bmf"]
	if not file.exists(bmfDir + name) then continue
	perf.timeit "font_bmf_load_" + name, 1, function(); f = bmfFonts.Font.load(bmfDir + name); end function, 3
end for

// --- print per frame, cold (first print builds glyph images) vs warm ---
for name in ["Arial14.bmf", "NotoSansBold-24.bmf"]
	if not file.exists(bmfDir + name) then continue
	f = bmfFonts.Font.load(bmfDir + name)
	for n in [100, 1000]
		if n == 100 then s = text100 else s = text1000
		clear
		t0 = time
		f.print s, 10, 300
		coldMs = (time - t0) * 1000
		line = ["RESULT", "font_bmf_print_cold_" + name, n, "first-call", round(coldMs, 3), "", "", ""].join(",")
		print line; perf.lines.push line
		perf.frames "font_bmf_print_" + name, n, function(); gfx.clear; f.print s, 10, 300; end function, 60, 5
	end for
	perf.timeit "font_bmf_width_" + name, 100, function(); w = f.width(text100); end function, 200
	perf.timeit "font_bmf_lenToFit_" + name, 1000, function(); w = f.lenToFit(text1000, 400); end function, 100
	perf.timeit "font_bmf_printJustified_" + name, 100, function(); gfx.clear; f.printJustified text100, 10, 300, 900; end function, 20
	// pixel-by-pixel glyph build (what a cold print pays per glyph)
	img = Image.create(40, 40, color.clear)
	perf.timeit "font_bmf_renderChar_" + name, 1, function(); f.renderChar "W", img; end function, 20
end for

// --- TrueType ---
if file.exists(ttfPath) then
	perf.timeit "font_tt_load", 24, function(); tf = ttFonts.TTFont.Load(ttfPath, 24); end function, 3
	tf = ttFonts.TTFont.Load(ttfPath, 24)
	for n in [100, 1000]
		if n == 100 then s = text100 else s = text1000
		perf.frames "font_tt_print", n, function(); gfx.clear; tf.print s, 10, 300; end function, 60, 5
	end for
	perf.timeit "font_tt_width", 100, function(); w = tf.width(text100); end function, 200
	perf.timeit "font_tt_lenToFit", 1000, function(); w = tf.lenToFit(text1000, 400); end function, 100
else
	print "NOTE: " + ttfPath + " not found; TrueType benchmarks skipped"
end if

perf.finish "perf_results/perf_fonts.run" + runIdx + ".csv"
