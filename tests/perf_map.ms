// perf_map.ms -- map lookup/insert cost by size, key type, hit/miss.
// Question: is the hash table itself the bottleneck, or the copying around it?
// Plain host script, no soda. Output: MAP,name,ns_per_op.
// Each row runs 8 lookups per loop iteration on LOCAL variables (registers, not
// the closure's outer-variable map), median of 5, minus the same loop with plain
// register moves in place of the lookups.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_map.ms
N = 100000
res = []
med = function(s)
	s.sort
	return s[2]
end function

// run `body` 5 times, return median seconds
bench = function(body, m, ks)
	s = []
	for r in range(1, 5)
		t0 = time; body(m, ks); s.push (time - t0)
		intrinsics.yield
	end for
	return med(s)
end function

// 8 reads of m[k0..k7]
readBody = function(m, ks)
	k0 = ks[0]; k1 = ks[1]; k2 = ks[2]; k3 = ks[3]
	k4 = ks[4 % ks.len]; k5 = ks[5 % ks.len]; k6 = ks[6 % ks.len]; k7 = ks[7 % ks.len]
	N = 100000
	for i in range(1, N)
		v = m[k0]; v = m[k1]; v = m[k2]; v = m[k3]
		v = m[k4]; v = m[k5]; v = m[k6]; v = m[k7]
	end for
end function
baseBody = function(m, ks)
	k0 = ks[0]; k1 = ks[1]; k2 = ks[2]; k3 = ks[3]
	k4 = ks[4 % ks.len]; k5 = ks[5 % ks.len]; k6 = ks[6 % ks.len]; k7 = ks[7 % ks.len]
	N = 100000
	for i in range(1, N)
		v = k0; v = k1; v = k2; v = k3
		v = k4; v = k5; v = k6; v = k7
	end for
end function
// 8 hasIndex calls (works for misses too)
hasBody = function(m, ks)
	k0 = ks[0]; k1 = ks[1]; k2 = ks[2]; k3 = ks[3]
	k4 = ks[4 % ks.len]; k5 = ks[5 % ks.len]; k6 = ks[6 % ks.len]; k7 = ks[7 % ks.len]
	N = 100000
	for i in range(1, N)
		v = m.hasIndex(k0); v = m.hasIndex(k1); v = m.hasIndex(k2); v = m.hasIndex(k3)
		v = m.hasIndex(k4); v = m.hasIndex(k5); v = m.hasIndex(k6); v = m.hasIndex(k7)
	end for
end function
// hasIndex call overhead on a 1-key map, as the floor for hasBody rows
// (so size/miss effects are the difference against this row)

report = function(name, t, b)
	line = "MAP," + name + "," + round((t - b) / (N * 8) * 1e9, 1)
	print line; res.push line
end function

// Key factory: key i of kind
keyOf = function(kind, i, tag)
	if kind == "tiny" then return tag + i                 // <= 3 bytes
	if kind == "heap" then return "fieldName_" + tag + i  // long string
	return i * 7 + (tag == "m") * 100000                  // number
end function
build = function(kind, size)
	m = {}
	for i in range(0, size - 1); m[keyOf(kind, i, "h")] = i; end for
	return m
end function
keysFor = function(kind, tag, n)
	ks = []
	for i in range(0, n - 1); ks.push keyOf(kind, i, tag); end for
	return ks
end function

baseT = {}
for kind in ["tiny", "heap", "num"]
	for size in [1, 2, 4, 8, 16, 64, 256, 4096]
		m = build(kind, size)
		hk = keysFor(kind, "h", (size * (size < 8) + 8 * (size >= 8)))
		// padded to 8 for simplicity: keys repeat via % in body setup
		if hk.len < 8 then
			while hk.len < 8; hk.push hk[hk.len % size]; end while
		end if
		b = bench(@baseBody, m, hk)
		report "get_hit_" + kind + "_n" + size, bench(@readBody, m, hk), b
	end for
end for

// hasIndex hit vs miss (miss via m[k] is an error in MiniScript)
for kind in ["tiny", "heap", "num"]
	for size in [4, 16, 256]
		m = build(kind, size)
		hk = keysFor(kind, "h", 8); while hk.len < 8; hk.push hk[0]; end while
		mk = keysFor(kind, "m", 8)
		for i in range(0, 7); if i >= size then hk[i] = hk[0]; end for
		floorT = bench(@hasBody, {"a": 1}, keysFor(kind, "m", 8))
		report "hasIndex_hit_" + kind + "_n" + size, bench(@hasBody, m, hk), floorT
		report "hasIndex_miss_" + kind + "_n" + size, bench(@hasBody, m, mk), floorT
	end for
end for

// Insert / update / delete, per op.
n16 = 16
hk = keysFor("heap", "h", 16)
upd = function(m, ks)
	for i in range(1, 100000)
		m[ks[0]] = i; m[ks[1]] = i; m[ks[2]] = i; m[ks[3]] = i
		m[ks[4]] = i; m[ks[5]] = i; m[ks[6]] = i; m[ks[7]] = i
	end for
end function
bUpd = function(m, ks)
	for i in range(1, 100000)
		v = ks[0]; v = ks[1]; v = ks[2]; v = ks[3]
		v = ks[4]; v = ks[5]; v = ks[6]; v = ks[7]
	end for
end function
report "set_existing_heap_n16", bench(@upd, build("heap", 16), hk), bench(@bUpd, null, hk)
fresh = function(m, ks)   // new 8-key map, 8 inserts, per iteration (includes the {} alloc)
	for i in range(1, 100000)
		o = {}
		o[ks[0]] = 1; o[ks[1]] = 1; o[ks[2]] = 1; o[ks[3]] = 1
		o[ks[4]] = 1; o[ks[5]] = 1; o[ks[6]] = 1; o[ks[7]] = 1
	end for
end function
report "fresh_map_8_inserts(incl alloc)", bench(@fresh, null, hk), bench(@bUpd, null, hk)
del = function(m, ks)     // insert then remove, 8 keys, in a persistent map
	m = {}
	for i in range(1, 100000)
		m[ks[0]] = 1; m[ks[1]] = 1; m[ks[2]] = 1; m[ks[3]] = 1
		m[ks[4]] = 1; m[ks[5]] = 1; m[ks[6]] = 1; m[ks[7]] = 1
		m.remove ks[0]; m.remove ks[1]; m.remove ks[2]; m.remove ks[3]
		m.remove ks[4]; m.remove ks[5]; m.remove ks[6]; m.remove ks[7]
	end for
end function
report "insert+remove_8(per pair)", bench(@del, null, hk) * 1, 0

// isa-chain read: field on the root, descendants don't have it
chainRead = function(o, ks)
	for i in range(1, 100000)
		v = o.alpha_long_name; v = o.alpha_long_name; v = o.alpha_long_name; v = o.alpha_long_name
		v = o.alpha_long_name; v = o.alpha_long_name; v = o.alpha_long_name; v = o.alpha_long_name
	end for
end function
A = {"alpha_long_name": 1}
chain = [A]
for d in range(1, 6); chain.push new chain[-1]; end for
b0 = bench(@baseBody, null, [1,2,3,4,5,6,7,8])
for d in [0, 1, 2, 4, 6]
	report "isa_depth" + d + "_field_read", bench(@chainRead, chain[d], null), b0
end for

file.writeLines "perf_results/perf_map.csv", res
exit
