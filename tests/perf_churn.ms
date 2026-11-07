// perf_churn.ms -- PERF_TEST_PLAN.md §6 churn: create/drop many resources, force GC,
// check resourceCounts / hostMemory return to baseline.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_churn.ms [runIndex] [N]
import "perfHarness"
import "soda"
runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]
N = 10000
if shellArgs.len > 2 then N = val(shellArgs[2])

gc = function()
	for i in range(1, 6); intrinsics.yield; end for
end function
phase = function(label, f)
	gc
	perf.resources "base:" + label
	t0 = time
	f
	t1 = time
	print "CHURN," + label + ",seconds=" + round(t1 - t0, 2)
	gc
	perf.resources "after:" + label
end function

phase "images_nodraw", function()
	for i in range(1, N); im = Image.create(16, 16, "#FF0000FF"); end for
end function

phase "images_withTexture", function()
	for i in range(1, N)
		im = Image.create(16, 16, "#FF0000FF")
		t = im.texture
	end for
end function

phase "images_released", function()
	for i in range(1, N)
		im = Image.create(16, 16, "#FF0000FF")
		t = im.texture
		im.release
	end for
end function

phase "sprites_rendered", function()
	img = Image.create(16, 16, "#00FF00FF")
	for round in range(1, 10)
		sprs = []
		for i in range(1, N / 10)
			s = new Sprite; s.image = img; s.x = i % 900; s.y = 300; sprs.push s
		end for
		display(4).sprites = sprs
		intrinsics.yield
	end for
	display(4).sprites = []
end function

phase "pixelDisplays", function()
	for i in range(1, N)
		px = new PixelDisplay
		px.clear "#FF0000FF"
		px.line 0, 0, 10, 10, "#FFFFFFFF"
		if i % 100 == 0 then intrinsics.yield
	end for
end function

phase "sounds_synth", function()
	for i in range(1, N / 5)
		s = new Sound
		s.init 0.05, 200 + i % 400
		s.play 0
		s.stop
	end for
end function

phase "displayModeSwitch", function()
	for i in range(1, N)
		d = display(i % 6 + 1)
		old = d.mode
		d.mode = displayMode.off
		d.mode = old
		if i % 50 == 0 then intrinsics.yield
	end for
end function

perf.finish "perf_results/perf_churn.run" + runIdx + ".csv"
