// perf_input.ms -- PERF_TEST_PLAN.md §4.10 (key.ms, mouse.ms) and §4.11 (color.ms) micro-benchmarks.
// Usage (from tests/): ../../raylib-miniscript/build-release/raylib-miniscript perf_input.ms [runIndex]
import "perfHarness"
import "soda"

runIdx = "1"
if shellArgs.len > 1 then runIdx = shellArgs[1]

// --- §4.10 key / mouse ---
perf.timeit "key_pressed_name", 1, function(); x = key.pressed("space"); end function, 5000
perf.timeit "key_pressed_mouse0", 1, function(); x = key.pressed("mouse 0"); end function, 5000
perf.timeit "key_pressed_joyButton", 1, function(); x = key.pressed("joystick button 3"); end function, 2000
perf.timeit "key_pressed_joy2Button", 1, function(); x = key.pressed("joystick 2 button 3"); end function, 2000
perf.timeit "key_axis_Horizontal", 1, function(); x = key.axis("Horizontal"); end function, 2000
perf.timeit "key_axis_Vertical", 1, function(); x = key.axis("Vertical"); end function, 2000
perf.timeit "key_axis_MouseX", 1, function(); x = key.axis("Mouse X"); end function, 2000
perf.timeit "key_axis_JoyAxis1", 1, function(); x = key.axis("JoyAxis1"); end function, 2000
perf.timeit "key_available", 1, function(); x = key.available; end function, 5000
perf.timeit "key_update", 1, function(); key.update; end function, 2000
perf.timeit "mouse_update", 1, function(); mouse.update; end function, 5000
perf.timeit "mouse_button", 1, function(); x = mouse.button(0); end function, 5000
perf.timeit "mouse_x", 1, function(); x = mouse.x; end function, 5000

// --- §4.11 color ---
perf.timeit "color_toList_string", 1, function(); x = color.toList("#FF8040FF"); end function, 10000
perf.timeit "color_toList_list", 1, function(); x = color.toList([255, 128, 64, 255]); end function, 10000
perf.timeit "color_fromList", 1, function(); x = color.fromList([255, 128, 64, 255]); end function, 10000
perf.timeit "color_rgba", 1, function(); x = color.rgba(255, 128, 64, 255); end function, 10000
perf.timeit "color_lerp", 1, function(); x = color.lerp("#FF0000", "#0000FF", 0.3); end function, 5000

perf.finish "perf_results/perf_input.run" + runIdx + ".csv"
