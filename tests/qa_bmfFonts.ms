// qa_bmfFonts.ms -- bmfFonts.Font: loading, metrics, uppercase fallback, kerning,
// missing glyphs, save/load round-trip, and that Font.print (batched on Soda)
// draws exactly what a per-character printChar loop draws.
// Needs the Mini Micro system-disk fonts; skips with a note if absent.
import "soda"
import "qa"
import "bmfFonts"
Font = bmfFonts.Font

fontDir = "/Users/redspark/Documents/GitHub/study/minimicro-sysdisk/sys/fonts/"
if not file.exists(fontDir + "NotoSansBold-24.bmf") then
	print "SKIPPED: sample fonts not found at " + fontDir
	exit
end if

// --- every sample font loads (NotoSansBold-24 once crashed in color.rgb) ---
n = 0
for name in file.children(fontDir)
	if name[-4:] != ".bmf" then continue
	f = Font.load(fontDir + name)
	qa.assert f != null, "load " + name
	qa.assert f.chars.len > 90, name + " has glyphs"
	n = n + 1
end for
print "  OK: loaded " + n + " fonts"

f = Font.load(fontDir + "NotoSansBold-24.bmf")

// --- metrics, fallback, missing glyphs ---
qa.assertEqual f.charData("a") != null, true, "lowercase present"
qa.assertEqual f.width(""), 0, "empty width"
qa.assertEqual f.width("ab"), f.width("a") + f.width("b") + f.kern("a", "b"), "width adds, plus kerning"
qa.assertEqual f.width("a", 3), f.width("a") * 3, "width scales"
qa.assertEqual f.width(char(1)), 0, "missing glyph has no width"
qa.assertEqual f.lenToFit("Hello world", 100000), 11, "everything fits"
k = f.lenToFit("Hello world", f.width("Hello") )
qa.assert k >= 4 and k <= 6, "lenToFit near word end"
qa.assertEqual f.lenToFit(null), 0, "lenToFit null"
qa.assertEqual f.lenToFit("abc", 0) >= 0, true, "lenToFit zero width"
// lowercase -> uppercase fallback: remove lowercase "q" and ask for it
q = f.chars["q"]
f.chars.remove "q"
qa.assertEqual f.charData("q"), f.chars["Q"], "falls back to uppercase"
f.chars["q"] = q
print "  OK: metrics and fallback"

// --- kerning ---
w0 = f.width("AV") - f.kern("A", "V")   // width without any kerning
f.setKern "A", "V", -3
qa.assertEqual f.kern("A", "V"), -3, "kern stored"
qa.assertEqual f.width("AV"), w0 - 3, "kern applied to width"
f.setKern "|", "~", 0
qa.assertEqual f.kern("~", "|"), 0, "reverse pair untouched"
qa.assertEqual f.kern(char(1), char(2)), 0, "unknown pair has no kern"
print "  OK: kerning"

// --- Font.print == per-character printChar loop ---
region = function(x0, y0, w, h)
	out = []
	for y in range(y0, y0 + h - 1)
		for x in range(x0, x0 + w - 1)
			out.push gfx.pixel(x, y)
		end for
	end for
	return out
end function
f2 = Font.load(fontDir + "NotoSansBold-24.bmf")
s = "Hello, World"
gfx.clear color.clear
f2.print s, 20, 100, 1, "#FF8040"
a = region(10, 80, 220, 60)
gfx.clear color.clear
x = 20; lastc = ""
for c in s
	x = x + f2.kern(lastc, c)
	x = x + f2.printChar(c, x, 100, 1, "#FF8040") + f2.addSpace
	lastc = c
end for
b = region(10, 80, 220, 60)
bad = 0
for i in a.indexes
	if a[i] != b[i] then bad = bad + 1
end for
qa.assertEqual bad, 0, "Font.print pixels differ from printChar loop"
nonBlank = 0
for c in a; if c != "#00000000" then nonBlank = nonBlank + 1; end for
qa.assert nonBlank > 100, "text actually drew"
print "  OK: print matches printChar loop (" + nonBlank + " drawn pixels)"

// --- save / load round-trip ---
tmp = "_qa_font_tmp.bmf"
err = f2.save(tmp)
qa.assertEqual err, null, "save returns no error"
g = Font.load(tmp)
qa.assert g != null, "reload saved font"
file.delete tmp
qa.assertEqual g.chars.len, f2.chars.len, "same glyph count after round-trip"
qa.assertEqual g.lineHeight, f2.lineHeight, "lineHeight"
qa.assertEqual g.width("Hello, World"), f2.width("Hello, World"), "width after round-trip"
print "  OK: save/load round-trip"
print "ALL PASSED"
exit
