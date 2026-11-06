// perfHarness.ms -- shared timing harness for Soda benchmarks.
// Usage:  import "perfHarness"  (from a script in tests/)
import "soda"
raylib.SetTargetFPS 0

perf = {}
perf.lines = []

perf.stats = function(xs)
	s = xs[:]; s.sort
	n = s.len; total = 0
	for x in s; total += x; end for
	p95idx = floor(n*0.95); if p95idx > n-1 then p95idx = n-1
	return {"mean": total/n, "median": s[floor(n/2)],
	        "p95": s[p95idx], "max": s[-1]}
end function

perf.emit = function(bench, param, phase, st)
	line = ["RESULT", bench, param, phase,
	        round(st.mean*1000, 4), round(st.median*1000, 4),
	        round(st.p95*1000, 4), round(st.max*1000, 4)].join(",")
	print line
	perf.lines.push line
end function

// Empty-loop cost, subtracted from timeit results.
perf._loopCost = function(n)
	t0 = time
	for i in range(1, n); end for
	return (time - t0) / n
end function

// Pure-CPU micro-benchmark: average seconds per call of f (no rendering).
perf.timeit = function(bench, param, f, n=1000)
	f   // warm-up (also triggers any lazy init, which we want excluded)
	base = perf._loopCost(n)
	samples = []
	for rep in range(1, 5)
		t0 = time
		for i in range(1, n); f; end for
		samples.push (time - t0) / n - base
	end for
	perf.emit bench, param, "per-call", perf.stats(samples)
end function

// Frame benchmark: runs frameFn once per frame and times each phase
// of the frame separately.
perf.frames = function(bench, param, frameFn, nFrames=300, warmup=30)
	for i in range(1, warmup); frameFn; yield; end for
	ph = {"user":[], "render":[], "endDrawing":[], "callbacks":[], "yieldGC":[], "total":[]}
	for i in range(1, nFrames)
		t0 = time
		frameFn
		t1 = time
		raylib.BeginDrawing
		Display.RenderAll
		t2 = time
		raylib.EndDrawing
		t3 = time
		for f in soda.updateCallbacks; f; end for
		t4 = time
		intrinsics.yield
		t5 = time
		ph.user.push t1-t0;      ph.render.push t2-t1;    ph.endDrawing.push t3-t2
		ph.callbacks.push t4-t3; ph.yieldGC.push t5-t4;   ph.total.push t5-t0
	end for
	for k in ph.indexes; perf.emit bench, param, k, perf.stats(ph[k]); end for
end function

perf.resources = function(label)
	line = "RESOURCES," + label + "," + str(resourceCounts) + ",hostMemory=" + hostMemory
	print line; perf.lines.push line
end function

perf.finish = function(outPath)
	file.writeLines outPath, perf.lines
	exit
end function

// Export "perf" to globals so a script that does `import "perfHarness"`
// can refer to it as bare `perf`, matching lib/*.ms's own convention for
// names meant to be used without the module prefix (cf. Display.ms's
// `globals.clear = @clear`). Without this, `import "perfHarness"` only
// binds a local `perfHarness` map (containing `perfHarness.perf`), per
// MiniScript's normal import semantics.
globals.perf = perf
