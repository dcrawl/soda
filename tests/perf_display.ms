// perf_display.ms -- PERF_TEST_PLAN.md §4.2 workloads (Display.ms).
//   RenderAll with every slot set to each mode in turn;
//   display(n).mode= switching cost (FindOrMakeDisplay linear scan + insert 0);
//   display(n) lookup cost.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_display.ms [runIndex]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

noop = function(); end function

// --- RenderAll with every slot in one mode (frame cost, fixed engine cost included) ---
for mode in [0, 1, 2, 3, 4, 5]
	clear
	for s in range(0, 7)
		display(s).mode = mode
	end for
	perf.frames "display_renderAll_mode" + mode, 8, @noop, 200
end for
clear

// --- mode switching ---
perf.timeit "display_modeSwitch_toggle", 1000, function()
	display(3).mode = 2
	display(3).mode = 3
end function, 1000

perf.timeit "display_modeSwitch_8slots", 1000, function()
	for s in range(0, 7)
		display(s).mode = 3
	end for
end function, 100

// --- display(n) lookup ---
perf.timeit "display_lookup", 1, function()
	x = display(3)
end function, 10000

// --- RenderAll alone (CPU side), default configuration ---
clear
perf.timeit "display_renderAll_default_cpu", 1, function()
	Display.RenderAll
end function, 200

perf.finish "perf_results/perf_display.run" + runIdx + ".csv"
