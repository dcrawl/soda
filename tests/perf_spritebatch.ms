// perf_spritebatch.ms -- BIND-03: spritebatch.drawTextures vs per-sprite DrawTexturePro.
// Output: BATCH,variant,N,ms_per_frame (median of 7 frames, draw inside Begin/EndDrawing, End untimed)
import "perfHarness"
import "soda"
rl = raylib
if not (plugins.hasIndex("spritebatch") and plugins.spritebatch.loaded) then
	print "spritebatch plugin not loaded"; exit
end if
img = Image.create(32, 32, "#8080FFFF")
tex = img.texture
white = "#FFFFFFFF"
xs = []; ys = []
for i in range(0, 4999); xs.push 50 + (i*37) % 860; ys.push 50 + (i*53) % 540; end for

median = function(s); s.sort; return s[s.len/2]; end function
bench = function(name, n, f)
	f  // warm
	s = []
	for r in range(1, 7)
		rl.BeginDrawing
		t0 = time; f; t1 = time
		rl.EndDrawing
		s.push (t1 - t0) * 1000
	end for
	line = ["BATCH", name, n, round(median(s), 3)].join(",")
	print line; perf.lines.push line
end function

for n in [100, 1000, 5000]
	// A: current Sprite.draw-style loop (builds 3 lists per sprite)
	bench "perSprite", n, function()
		for i in range(0, n-1)
			rl.DrawTexturePro tex, [0, 0, 32, 32], [xs[i], 640 - ys[i], 32, 32], [16, 16], -(i%360), white
		end for
	end function
	// B: prebuilt flat list, one call (native upper bound)
	flat = []
	for i in range(0, n-1); flat = flat + [0,0,32,32, xs[i], 640-ys[i], 32,32, -(i%360)]; end for
	bench "batchPrebuilt", n, function()
		spritebatch.drawTextures tex, flat, white
	end function
	// C: build the flat list per frame in MiniScript, then one call
	bench "batchBuilt", n, function()
		d = []
		for i in range(0, n-1)
			d.push 0; d.push 0; d.push 32; d.push 32
			d.push xs[i]; d.push 640 - ys[i]; d.push 32; d.push 32; d.push -(i%360)
		end for
		spritebatch.drawTextures tex, d, white
	end function
	// D: only the MiniScript-side loop work, no draw call (cost floor)
	bench "loopOnlyNoDraw", n, function()
		for i in range(0, n-1)
			a = [0, 0, 32, 32]; b = [xs[i], 640 - ys[i], 32, 32]; c = [16, 16]
		end for
	end function
end for
perf.finish "perf_results/perf_spritebatch.run1.csv"
