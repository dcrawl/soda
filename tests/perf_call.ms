best = function(fn)
	b = 1e9
	for r in range(1, 7)
		t = time; fn; t = time - t
		if t < b then b = t
	end for
	return b
end function
base = function()
	x = 3; v = 0
	for i in range(1, 300000)
		v = x; v = x; v = x; v = x; v = x; v = x; v = x; v = x
	end for
end function
inc = function(a); return a + 1; end function
noarg = function(); return 1; end function
call1 = function(f)
	x = 3; v = 0
	for i in range(1, 300000)
		v = f(x); v = f(x); v = f(x); v = f(x); v = f(x); v = f(x); v = f(x); v = f(x)
	end for
end function
call0 = function(f)
	for i in range(1, 300000)
		v = f; v = f; v = f; v = f; v = f; v = f; v = f; v = f
	end for
end function
sg = function(f)
	x = 3
	for i in range(1, 300000)
		v = f(x); v = f(x); v = f(x); v = f(x); v = f(x); v = f(x); v = f(x); v = f(x)
	end for
end function
sgDirect = function()
	x = 3
	for i in range(1, 300000)
		v = sign(x); v = sign(x); v = sign(x); v = sign(x); v = sign(x); v = sign(x); v = sign(x); v = sign(x)
	end for
end function
b = best(@base)
rep = function(name, fn, arg)
	r = round((best(function(); fn(@arg); end function) - b) / (300000 * 8) * 1e9, 1)
	print name + " ns/op: " + r
end function
rep "user call f(x), f local", @call1, @inc
rep "user call f() no args", @call0, @noarg
rep "intrinsic via local @sign", @sg, @sign
rep "intrinsic sign(x) global", @sgDirect, null
exit
