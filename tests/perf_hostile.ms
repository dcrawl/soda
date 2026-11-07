// perf_hostile.ms -- PERF_TEST_PLAN.md §6 hostile inputs, one call per process.
// Usage: perf_hostile.ms list                    -> prints "Class.method<TAB>nparams"
//        perf_hostile.ms run Class.method valueIdx [nargs]
// MiniScript has no try/catch, so a runtime error ends the process (reported by
// the driver); a host crash shows up as a signal exit code.
import "soda"
classes = {"Image":Image, "Sprite":Sprite, "Bounds":Bounds, "PixelDisplay":PixelDisplay,
  "TextDisplay":TextDisplay, "TileDisplay":TileDisplay, "SolidColorDisplay":SolidColorDisplay,
  "Sound":Sound, "key":key, "mouse":mouse, "color":color, "ScreenFont":ScreenFont}
skipNames = ["init"]  // none
nparams = function(f)
	s = str(@f)
	i = s.indexOf("(")
	j = s.indexOf(")")
	if i == null or j == null or j == i + 1 then return 0
	return s[i+1:j].split(",").len
end function
hostile = [null, -1, 1e9, -1e9, "abc", [1,2], {"a":1}, 0.5 / 0 * 0 ]
hostile[7] = 0 * 1e308 * 1e308   // NaN-ish
make = function(cn)
	if cn == "Image" then return Image.create(8, 8, "#FF0000FF")
	if cn == "PixelDisplay" then return new PixelDisplay
	if cn == "Sound" then
		s = new Sound; s.init 0.05, 440; return s
	end if
	if cn == "key" or cn == "mouse" or cn == "color" then return classes[cn]
	return new classes[cn]
end function
if shellArgs[1] == "list" then
	for cn in classes.indexes
		for k in classes[cn].indexes
			v = classes[cn][k]
			if @v isa funcRef then print cn + "." + k + char(9) + nparams(@v)
		end for
	end for
	exit
end if
parts = shellArgs[2].split(".")
cn = parts[0]; mn = parts[1]
vi = val(shellArgs[3])
obj = make(cn)
f = obj[mn]
n = nparams(@obj[mn])
if shellArgs.len > 4 then n = val(shellArgs[4])
v = hostile[vi]
if n == 0 then
	obj[mn]
else if n == 1 then
	obj[mn] v
else if n == 2 then
	obj[mn] v, v
else if n == 3 then
	obj[mn] v, v, v
else
	obj[mn] v, v, v, v
end if
intrinsics.yield
print "HOSTILE_OK"
exit
