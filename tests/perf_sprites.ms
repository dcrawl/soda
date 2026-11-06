// perf_sprites.ms -- PERF_TEST_PLAN.md §4.4 workloads (SpriteDisplay.ms).
// Frame cost vs N sprites for: plain, rotating+scaling, 10 images, tint forms,
// quad (setUVs/localCorners) path, nested lists; plus Bounds overlaps/contains
// cost per call.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_sprites.ms [runIndex]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

imgs = []
for i in range(0, 9)
	imgs.push Image.create(32, 32, color.rgba(40 + i*20, 100, 255 - i*20, 255))
end for

noop = function(); end function
nFrames = 60

makeSprites = function(n, imageFor=null)
	sprs = []
	for i in range(1, n)
		sp = new Sprite
		if refEquals(@imageFor, null) then sp.image = imgs[0] else sp.image = imageFor(i)
		sp.x = 50 + (i * 37) % 860
		sp.y = 50 + (i * 53) % 540
		sprs.push sp
	end for
	return sprs
end function

withSprites = function(name, n, sprs, frameFn=null)
	clear
	display(4).sprites = sprs
	if frameFn == null then frameFn = @noop
	perf.frames name, n, @frameFn, nFrames, 5
	clear
end function

Ns = [1, 100, 1000, 5000]

// 1. plain
for n in Ns
	withSprites "spr_plain", n, makeSprites(n)
end for

// 2. rotation + scale changing every frame
for n in Ns
	sprs = makeSprites(n)
	t = {"v": 0}
	f = function()
		t.v = t.v + 1
		for sp in sprs
			sp.rotation = t.v * 3
			sp.scale = 1 + (t.v % 10) * 0.1
		end for
	end function
	withSprites "spr_rotScale_update", n, sprs, @f
end for
// ... rendering only (static rotation/scale)
for n in Ns
	sprs = makeSprites(n)
	for sp in sprs; sp.rotation = 33; sp.scale = 1.5; end for
	withSprites "spr_rotScale_static", n, sprs
end for

// 3. ten images
for n in Ns
	pick = function(i); return imgs[i % 10]; end function
	sprs = makeSprites(n, @pick)
	withSprites "spr_10images", n, sprs
end for

// 4. tint forms
for form in ["string", "list", "map"]
	for n in [100, 1000]
		sprs = makeSprites(n)
		for sp in sprs
			if form == "string" then sp.tint = "#FF8080FF"
			if form == "list" then sp.tint = [255, 128, 128, 255]
			if form == "map" then sp.tint = {"r":255, "g":128, "b":128, "a":255}
		end for
		withSprites "spr_tint_" + form, n, sprs
	end for
end for

// 5. quad path (setUVs and localCorners)
for n in [1, 100, 1000]
	sprs = makeSprites(n)
	for sp in sprs
		sp.setUVs [[0,0],[1,0],[1,1],[0,1]]
	end for
	withSprites "spr_quad_uvs", n, sprs
end for
for n in [1, 100, 1000]
	sprs = makeSprites(n)
	for sp in sprs
		sp.setCorners [[-16,-16],[16,-16],[16,16],[-16,16]]
	end for
	withSprites "spr_quad_corners", n, sprs
end for

// 6. nested lists, depth 3
for n in [100, 1000]
	flat = makeSprites(n)
	nested = [[flat[0:n/2]], [flat[n/2:]]]
	withSprites "spr_nested", n, nested
end for

// 7. collision: overlaps with every pair, contains
for n in [10, 50, 200]
	sprs = makeSprites(n)
	for sp in sprs; sp.localBounds = new Bounds; sp.localBounds.width = 32; sp.localBounds.height = 32; end for
	pairs = n * (n - 1) / 2
	perf.timeit "spr_overlaps_allPairs", n, function()
		for i in range(0, n - 2)
			a = sprs[i]
			for j in range(i + 1, n - 1)
				r = a.overlaps(sprs[j])
			end for
		end for
	end function, 3
	perf.timeit "spr_contains_all", n, function()
		for sp in sprs; r = sp.contains(400, 300); end for
	end function, 20
end for

// single-call costs
a = new Sprite; a.localBounds = new Bounds; a.localBounds.width = 32; a.localBounds.height = 32
b = new Sprite; b.localBounds = new Bounds; b.localBounds.width = 32; b.localBounds.height = 32
b.x = 20; b.y = 10
perf.timeit "spr_overlaps_single", 1, function(); r = a.overlaps(b); end function, 2000
a.rotation = 45; b.rotation = 20
perf.timeit "spr_overlaps_single_rotated", 1, function(); r = a.overlaps(b); end function, 2000
perf.timeit "spr_worldBounds", 1, function(); r = a.worldBounds; end function, 5000

perf.finish "perf_results/perf_sprites.run" + runIdx + ".csv"
