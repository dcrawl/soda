// qa_display_edges.ms -- §4.2: display() with bad indexes must return an error, not crash.
import "soda"
import "qa"

for bad in [-1, 8, 100, "a", null, [1]]
	r = display(bad)
	qa.assert r == null or not (r isa Display), "display(" + bad + ") should not return a real display"
end for
print "  OK: bad indexes return non-displays"

// mode switching keeps exactly one entry per mode in the slot list
clear
for i in range(1, 50)
	display(3).mode = 2
	display(3).mode = 3
end for
modes = []
for d in Display._installed[3]; modes.push d.mode; end for
seen = {}
for m in modes
	qa.assert not seen.hasIndex(m), "duplicate display of mode " + m + " in slot 3"
	seen[m] = true
end for
print "ALL PASSED"
exit
