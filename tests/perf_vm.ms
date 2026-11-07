// perf_vm.ms -- PERF_TEST_PLAN.md §10.2 micro-benchmarks (S-V1..S-V4). Plain host script, no soda.
// Output: VM,name,ns_per_op (median of 5, empty-loop cost subtracted).
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_vm.ms
N = 200000
res = []
timeLoop = function(f)
	s = []
	for r in range(1, 5)
		t0 = time; f; s.push (time - t0)
		intrinsics.yield
	end for
	s.sort
	return s[2]
end function
emptyT = timeLoop(function(); for i in range(1, N); end for; end function)
report = function(name, f)
	t = timeLoop(@f)
	line = "VM," + name + "," + round((t - emptyT) / N * 1e9, 1)
	print line; res.push line
end function

// --- S-V1/S-V3: field read vs __isa depth ---
A = {"alpha": 1, "beta": 2, "xx": 3, "tiny": 4, "longername": 5, "other_long_name": 6}
B = new A; C = new B; D = new C; E = new D; F = new E
o0 = new A  // depth 1: field lives on parent
report "field_own_depth0", function(); o = {"alpha": 1}; for i in range(1, N); v = o.alpha; end for; end function
report "field_isa1", function(); o = new A; for i in range(1, N); v = o.alpha; end for; end function
report "field_isa2", function(); o = new B; for i in range(1, N); v = o.alpha; end for; end function
report "field_isa3", function(); o = new C; for i in range(1, N); v = o.alpha; end for; end function
report "field_isa5", function(); o = new E; for i in range(1, N); v = o.alpha; end for; end function
// --- S-V4: tiny (<=5 bytes) vs heap (>=6 bytes) key, same depth ---
report "key_tiny_xx", function(); o = new A; for i in range(1, N); v = o.xx; end for; end function
report "key_tiny_5bytes", function(); o = new A; for i in range(1, N); v = o.tiny; end for; end function
report "key_heap_alpha(5)", function(); o = new A; for i in range(1, N); v = o.alpha; end for; end function
report "key_heap_10bytes", function(); o = new A; for i in range(1, N); v = o.longername; end for; end function
report "key_heap_15bytes", function(); o = new A; for i in range(1, N); v = o.other_long_name; end for; end function
// --- S-V1: list index ---
report "list_index", function(); l = [1,2,3,4,5]; for i in range(1, N); v = l[2]; end for; end function
report "map_index_string", function(); m = {"a": 1}; for i in range(1, N); v = m["a"]; end for; end function
// --- S-V2: assignment cost, plain vs class with a setter in the chain ---
Plain = {"val": 0}
WithSetter = {"val": 0}
WithSetter["something="] = function(v); end function
report "assign_own_plainmap_longname", function(); o = {}; for i in range(1, N); o.someLongName = 1; end for; end function
report "assign_plain_class_inst", function(); o = new Plain; for i in range(1, N); o.someLongName = 1; end for; end function
report "assign_setter_class_inst_longname", function(); o = new WithSetter; for i in range(1, N); o.someLongName = 1; end for; end function
report "assign_setter_class_inst_tiny", function(); o = new WithSetter; for i in range(1, N); o.val = 1; end for; end function
report "assign_plain_class_inst_tiny", function(); o = new Plain; for i in range(1, N); o.val = 1; end for; end function
// --- S-V3: method call vs depth ---
A.m = function(); end function
report "method_call_depth1", function(); o = new A; for i in range(1, N); o.m; end for; end function
report "method_call_depth3", function(); o = new C; for i in range(1, N); o.m; end for; end function
report "method_call_depth5", function(); o = new E; for i in range(1, N); o.m; end for; end function
report "plain_func_call", function(); g = function(); end function; for i in range(1, N); g; end for; end function
file.writeLines "perf_results/perf_vm.csv", res
exit
