// qa_textUtil.ms -- textUtil's non-interactive helpers: printWrap, textCol/textRow,
// printAt, clearRow/clearRect/clearToEOL, button, getContent/setContent and
// getState/setState round-trips, plus Dialog.make/draw not crashing.
import "soda"
import "qa"
import "textUtil"

rowStr = function(r)
	s = ""
	for c in range(0, 67); s = s + (text.cell(c, r) + " ")[0]; end for
	return s.replace("  ", " ")
end function
rowText = function(r, n=67)
	s = ""
	for c in range(0, n); ch = text.cell(c, r); if ch == "" then ch = " "; s = s + ch; end for
	return s
end function

fill = function(r)
	for i in range(0,9); text.setCell i, r, "abcdefghij"[i]; end for
end function

// --- pixel <-> cell conversion ---
qa.assertEqual textUtil.textCol(5), 0
qa.assertEqual textUtil.textCol(19), 1
qa.assertEqual textUtil.textRow(6), 0
qa.assertEqual textUtil.textRow(30), 1
print "  OK: textCol/textRow"

// --- print-based helpers: under Soda the global `print` is the host's stdout
// intrinsic (the Mini Micro text-display print is TextDisplay.print), so
// printAt/printWrap/drawButton/Dialog write to the terminal, not display 3.
// Pin the behavior as a NOTE (not a failure) so a future fix shows up here.
clear
textUtil.printAt 10, 5, "HELLO"
if rowText(5)[10:15] == "HELLO" then
	print "  NOTE: printAt now writes to the text display (textUtil print fixed upstream?)"
else
	print "  NOTE: printAt wrote to stdout, not the text display (known: textUtil uses bare `print`)"
end if
rem = textUtil.printWrap("the quick brown fox jumps over the lazy dog", 12)
qa.assertEqual rem, null
rem = textUtil.printWrap("aaaa bbbb cccc dddd eeee", 9, 2)
qa.assertEqual rem, "eeee", "maxLines returns the remainder"
rem = textUtil.printWrap("x" * 25, 10)
qa.assertEqual rem, null
qa.assertEqual textUtil.printWrap(""), null
print "  OK: printWrap return values (word wrap, maxLines remainder, hard cut, empty)"

// --- clearRow / clearRect / clearToEOL ---
clear
text.color = "#FF0000FF"; text.backColor = "#00FF00FF"
fill 3
textUtil.clearRow 3
qa.assertEqual rowText(3).trim, ""
qa.assertEqual text.cellColor(5, 3).upper, "#FF0000FF"
qa.assertEqual text.cellBackColor(5, 3).upper, "#00FF00FF"
fill 4
fill 5
textUtil.clearRect 2, 4, 3, 2, "."
qa.assertEqual rowText(4)[:10], "ab...fghij"
qa.assertEqual rowText(5)[:10], "ab...fghij"
fill 6
text.row = 6; text.column = 3
textUtil.clearToEOL
qa.assertEqual rowText(6)[:5].trim, "abc"
qa.assertEqual rowText(6)[3:].trim, ""
textUtil.clearRow [7, 8]
text.color = "#FFFFFFFF"; text.backColor = "#00000000"
print "  OK: clearRow/clearRect/clearToEOL (incl. colors, list of rows)"

// --- button ---
b = textUtil.button("OK", 6)
qa.assertEqual b, textUtil.buttonLeft + "  OK  " + textUtil.buttonRight
qa.assertEqual textUtil.button("Hello"), textUtil.buttonLeft + "Hello" + textUtil.buttonRight
print "  OK: button padding"

// --- content / state round-trip ---
clear
for i in range(0,9); text.setCell 3+i, 10, "SAVED TEXT"[i]; end for
text.setCellColor 3, 10, "#123456FF"
saved = textUtil.getContent
qa.assertEqual saved.len, 26
qa.assertEqual saved[0].len, 68
clear
qa.assertEqual rowText(10)[3:13].trim, ""
textUtil.setContent saved
qa.assertEqual rowText(10)[3:13], "SAVED TEXT"
qa.assertEqual text.cellColor(3, 10).upper, "#123456FF"
st = textUtil.getState
text.row = 2; text.column = 9
textUtil.setState st
qa.assertEqual text.row, st.row
qa.assertEqual text.column, st.column
print "  OK: getContent/setContent/getState/setState round-trip"

// --- Dialog builds and draws ---
clear
d = textUtil.Dialog.make("Title", "A message that is long enough to need to wrap onto a second line in the dialog box.")
d.cancelBtn.visible = true
d.draw
qa.assert d.width > 0 and d.height > 0, "dialog has size"
qa.assert d.left < d.right and d.bottom < d.top, "dialog has bounds"
fd = textUtil.FileDialog.make
qa.assert fd != null
print "  OK: Dialog.make/draw, FileDialog.make"
clear
print "textUtil: ALL PASSED"
exit
