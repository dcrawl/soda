// perf_soda.ms -- PERF_TEST_PLAN.md §4.1 workload: empty-scene frame cost.
// Usage (from tests/): ../soda perf_soda.ms [runIndex]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

noop = function(); end function

for extraCallbacks in [0, 10, 100]
	clear
	savedCallbacks = soda.updateCallbacks[:]
	for i in range(1, extraCallbacks)
		soda.updateCallbacks.push @noop
	end for

	perf.resources "before-N" + extraCallbacks
	perf.frames "soda_emptyScene", extraCallbacks, function(); end function
	perf.resources "after-N" + extraCallbacks

	soda.updateCallbacks = savedCallbacks
end for

// --- idle display stack: default vs slot 5 off vs everything off (fill-rate floor) ---
clear
perf.frames "soda_idle_default", 0, function(); end function
display(5).mode = displayMode.off
perf.frames "soda_idle_pixelOff", 0, function(); end function
for i in range(0, 7); display(i).mode = displayMode.off; end for
perf.frames "soda_idle_allOff", 0, function(); end function
clear

// --- wait(): timing accuracy and frame rendering (uses a 60 fps cap, as a real game would) ---
raylib.SetTargetFPS 60
frameCount = {"n": 0}
countFrame = function(); frameCount.n = frameCount.n + 1; end function
soda.updateCallbacks.push @countFrame
for d in [0, 0.001, 0.1, 1, 5]
	frameCount.n = 0
	t0 = time
	wait d
	el = time - t0
	line = ["RESULT", "soda_wait", d, "elapsed_s_and_frames", round(el, 4), frameCount.n, "", ""].join(",")
	print line; perf.lines.push line
end for
soda.updateCallbacks.pop
raylib.SetTargetFPS 0

perf.finish "perf_results/perf_soda.run" + runIdx + ".csv"
