// perf_binding.ms -- PERF_TEST_PLAN.md §9: MiniScript -> raylib binding cost.
// Each case: warm-up, then 5 reps of N calls, each rep inside its own
// BeginDrawing/EndDrawing (End untimed). Closure-call overhead (the "empty
// fn" row) is subtracted from every other row, so results are per raylib call
// including argument conversion. Output: BIND,name,form,median_ns,min_ns,max_ns Results: ns per call.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_binding.ms [runIndex]
import "perfHarness"
import "soda"
rl = raylib

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]
N = 2000

img = Image.create(16, 16, "#8080FFFF")
tex = rl.LoadTextureFromImage(img._img)
shader = rl.LoadShaderFromMemory("", "#version 330" + char(10) + "in vec2 fragTexCoord; uniform sampler2D texture0; uniform vec4 colDiffuse; uniform vec4 foreColor; out vec4 finalColor; void main(){ finalColor = texture(texture0, fragTexCoord) * foreColor; }")
foreLoc = rl.GetShaderLocation(shader, "foreColor")
rot = 0

state = {"base": 0}
measure = function(name, form, f, n=2000, draw=true)
	f
	samples = []
	for rep in range(1, 5)
		if draw then rl.BeginDrawing
		t0 = time
		for i in range(1, n); f; end for
		t1 = time
		if draw then rl.EndDrawing
		samples.push (t1 - t0) / n
	end for
	samples.sort
	med = samples[2]
	// subtract the empty closure's loop+call cost (measured first)
	net = med - state.base
	if name != "emptyFn" then net = net else state.base = med
	line = ["BIND", name, form, round(net * 1e9, 1), round((samples[0] - (name != "emptyFn") * state.base) * 1e9, 1), round((samples[4] - (name != "emptyFn") * state.base) * 1e9, 1)].join(",")
	print line
	perf.lines.push line
end function

// ---- L1: dispatch floor ----
state.base = 0
empty = function(); end function
measure "emptyFn", "-", @empty, N, false
measure "GetScreenWidth", "-", function(); r = rl.GetScreenWidth; end function, N, false
measure "IsKeyDown", "65", function(); r = rl.IsKeyDown(65); end function, N, false
measure "GetMouseX", "-", function(); r = rl.GetMouseX; end function, N, false
measure "IsGamepadButtonDown", "0;0", function(); r = rl.IsGamepadButtonDown(0, 0); end function, N, false

// ---- L2: DrawTexturePro, argument forms ----
srcL = [0, 0, 16, 16]; dstL = [100, 100, 16, 16]; orgL = [8, 8]
srcM = {"x":0, "y":0, "width":16, "height":16}
dstM = {"x":100, "y":100, "width":16, "height":16}
orgM = {"x":8, "y":8}
white = rl.WHITE
measure "DrawTexturePro", "list;list;list;tintList", function(); rl.DrawTexturePro tex, srcL, dstL, orgL, 0, [255,255,255,255]; end function
measure "DrawTexturePro", "list;list;list;tintStr", function(); rl.DrawTexturePro tex, srcL, dstL, orgL, 0, "#FFFFFFFF"; end function
measure "DrawTexturePro", "list;list;list;tintMapWHITE", function(); rl.DrawTexturePro tex, srcL, dstL, orgL, 0, white; end function
measure "DrawTexturePro", "map;map;map;tintMapWHITE", function(); rl.DrawTexturePro tex, srcM, dstM, orgM, 0, white; end function
measure "DrawTexturePro", "map;map;map;tintList", function(); rl.DrawTexturePro tex, srcM, dstM, orgM, 0, [255,255,255,255]; end function
measure "DrawTexturePro", "inlineLists;tintList", function(); rl.DrawTexturePro tex, [0,0,16,16], [100,100,16,16], [8,8], 0, [255,255,255,255]; end function
measure "DrawTexturePro", "inlineLists;tintStr", function(); rl.DrawTexturePro tex, [0,0,16,16], [100,100,16,16], [8,8], 0, "#FFFFFFFF"; end function
measure "DrawTexture", "tintList", function(); rl.DrawTexture tex, 100, 100, [255,255,255,255]; end function
measure "DrawTexture", "tintStr", function(); rl.DrawTexture tex, 100, 100, "#FFFFFFFF"; end function
measure "DrawTexture", "tintMapWHITE", function(); rl.DrawTexture tex, 100, 100, white; end function
measure "DrawTextureV", "list;tintList", function(); rl.DrawTextureV tex, [100,100], [255,255,255,255]; end function

// ---- DrawPixel / lines / rects ----
measure "DrawPixel", "str", function(); rl.DrawPixel 10, 10, "#FF0000FF"; end function
measure "DrawPixel", "list", function(); rl.DrawPixel 10, 10, [255,0,0,255]; end function
measure "DrawPixel", "map", function(); rl.DrawPixel 10, 10, {"r":255,"g":0,"b":0,"a":255}; end function
measure "DrawPixelV", "list;list", function(); rl.DrawPixelV [10,10], [255,0,0,255]; end function
measure "DrawLineEx", "list;list;thick;colorList", function(); rl.DrawLineEx [10,10], [100,50], 2, [255,0,0,255]; end function
measure "DrawLineEx", "map;map;thick;colorList", function(); rl.DrawLineEx {"x":10,"y":10}, {"x":100,"y":50}, 2, [255,0,0,255]; end function
measure "DrawLineEx", "list;list;thick;colorStr", function(); rl.DrawLineEx [10,10], [100,50], 2, "#FF0000FF"; end function
measure "DrawRectangle", "ints;colorStr", function(); rl.DrawRectangle 10, 10, 20, 20, "#FF0000FF"; end function
measure "DrawRectangle", "ints;colorList", function(); rl.DrawRectangle 10, 10, 20, 20, [255,0,0,255]; end function
measure "DrawRectangleRec", "rectList;colorList", function(); rl.DrawRectangleRec [10,10,20,20], [255,0,0,255]; end function
measure "DrawRectangleRec", "rectMap;colorList", function(); rl.DrawRectangleRec {"x":10,"y":10,"width":20,"height":20}, [255,0,0,255]; end function

// ---- rlgl immediate-mode (Sprite._drawQuad) ----
measure "rlVertex2f", "-", function(); rl.rlVertex2f 10, 20; end function, 400
measure "rlTexCoord2f", "-", function(); rl.rlTexCoord2f 0.5, 0.5; end function
measure "rlColor4ub", "-", function(); rl.rlColor4ub 255, 255, 255, 255; end function

// ---- shader ----
vec = [1, 0.5, 0.25, 1]
measure "SetShaderValue", "vec4list", function(); rl.SetShaderValue shader, foreLoc, vec, rl.SHADER_UNIFORM_VEC4; end function
measure "SetShaderValue", "vec4inline", function(); rl.SetShaderValue shader, foreLoc, [1, 0.5, 0.25, 1], rl.SHADER_UNIFORM_VEC4; end function
measure "ShaderBracket", "empty", function(); rl.BeginShaderMode shader; rl.EndShaderMode; end function, 500

// ---- GetImageColor: returns a new map ----
measure "GetImageColor", "-", function(); c = rl.GetImageColor(img._img, 3, 3); end function, N, false

perf.finish "perf_results/perf_binding.run" + runIdx + ".csv"
