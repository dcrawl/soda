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

perf.finish "perf_results/perf_soda.run" + runIdx + ".csv"
