// qa_display_install.ms -- regression test for two Display.install bugs
// (PERF_TEST_PLAN.md §4.2):
//   BUG-01: Display.install line 101 reads disps[slotNum].mode instead of
//           disps[0].mode, so installing into any slot other than 0 either
//           reads the wrong "current mode" or (when slotNum >= disps.len)
//           crashes with an Index Error.
//   BUG-02: Display.install line 104 calls disps[i].remove i on the
//           *display* at that index (a map) instead of disps.remove i on
//           the *list*, so the old display is never actually removed from
//           the slot -- duplicates accumulate.
//
// Before the fix: this script crashes with a Runtime Error on Test 1.
// After the fix: it runs to completion and prints "ALL PASSED".
import "soda"
import "qa"

print "=== Test 1 (BUG-01): install into a slot whose _installed list is shorter than slotNum+1 ==="
// Display.Initialize only pushes 2 displays (modes 0 and 3) into each slot,
// so slotNum 2 reliably reproduces disps[slotNum] indexing out of range.
d = PixelDisplay.Make
d.install 2
qa.assertEqual display(2).mode, displayMode.pixel, "slot 2 should now show the pixel display"
print "  OK: install into slot 2 did not crash, and the new display is active."

print "=== Test 2 (BUG-02): installing a second display of the same mode should replace, not duplicate ==="
lenBefore = Display._installed[0].len
p1 = PixelDisplay.Make
p1.install 0
p2 = PixelDisplay.Make
p2.install 0
qa.assertEqual Display._installed[0].len, lenBefore, "installing a same-mode display should replace the old one, not add a duplicate"
qa.assert display(0) == p2, "the most recently installed display should be active in the slot"
foundP1 = false
for dd in Display._installed[0]
	if refEquals(dd, p1) then foundP1 = true
end for
qa.assert not foundP1, "the old same-mode display (p1) should have been removed from the slot's list"
print "  OK: no duplicate left behind."

print "ALL PASSED"
exit
