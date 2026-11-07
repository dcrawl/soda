// perf_stringleak.ms -- repro for VM-01: unique short strings are never reclaimed.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_stringleak.ms [none|norm|full]
// Needs no Soda. Prints bytes of host heap growth per unique string.
mode = "none"
if shellArgs.len > 1 then mode = shellArgs[1]
m0 = hostMemory
for n in range(1, 200000)
	t = "N " + n
	if mode == "full" and n % 2000 == 0 then gc.collect true
	if mode == "norm" and n % 2000 == 0 then gc.collect
end for
m1 = hostMemory
if mode != "none" then gc.collect true
print "RES " + mode + " before=" + m0 + " afterLoop=" + m1 + " afterFinalFullGC=" + hostMemory + " perString=" + round((m1-m0)/200000, 1)
exit
