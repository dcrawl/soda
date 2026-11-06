// perf_image.ms -- PERF_TEST_PLAN.md §4.8 workloads (Image.ms).
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_image.ms [runIndex]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

for sz in [64, 512]
	im = Image.create(sz, sz, "#4080C0FF")
	perf.timeit "img_pixel", sz, function(); x = im.pixel(10, 10); end function, 2000
	perf.timeit "img_setPixel", sz, function(); im.setPixel 10, 10, "#FF0000FF"; end function, 2000
	perf.timeit "img_pixelLoop_full", sz * sz, function()
		for y in range(0, sz - 1)
			for x in range(0, sz - 1)
				c = im.pixel(x, y)
			end for
		end for
	end function, 1
	perf.timeit "img_setPixelLoop_full", sz * sz, function()
		for y in range(0, sz - 1)
			for x in range(0, sz - 1)
				im.setPixel x, y, "#102030FF"
			end for
		end for
	end function, 1
	perf.timeit "img_flip", sz, function(); im.flip; end function, 20
	perf.timeit "img_rotate90", sz, function(); im.rotate 90; end function, 20
end for

// getImage: slice a 512x512 sheet into 256 32x32 frames
sheet = Image.create(512, 512, "#4080C0FF")
perf.timeit "img_getImage_256frames", 256, function()
	for fy in range(0, 15)
		for fx in range(0, 15)
			f = sheet.getImage(fx * 32, fy * 32, 32, 32)
		end for
	end for
end function, 3
perf.timeit "img_getImage_single", 1, function(); f = sheet.getImage(0, 0, 32, 32); end function, 500

// First .texture access after a change
im = Image.create(256, 256, "#4080C0FF")
t = im.texture
perf.timeit "img_texture_cached", 256, function(); t = im.texture; end function, 2000
perf.timeit "img_texture_afterSetPixel", 256, function()
	im.setPixel 1, 1, "#FF0000FF"
	t = im.texture
end function, 200

// S-I1: edit k pixels, then draw as a sprite (forces re-upload) -- cost of the edit+upload cycle
for k in [1, 10, 100, 1000, 10000]
	perf.timeit "img_editK_thenTexture", k, function()
		for i in range(1, k)
			im.setPixel i % 256, floor(i / 256) % 256, "#FF0000FF"
		end for
		t = im.texture
	end function, 3
end for

// Leak check: many getImage calls + GC
before = resourceCounts
for i in range(1, 10000)
	f = sheet.getImage(0, 0, 8, 8)
end for
f = null
perf.resources "after10000getImage"
perf.timeit "img_gc_flush", 1, function(); intrinsics.yield; end function, 10
perf.resources "after-gc"

perf.finish "perf_results/perf_image.run" + runIdx + ".csv"
