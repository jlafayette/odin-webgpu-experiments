package rectangle

import "base:runtime"
import "core:sys/wasm/js"
import "vendor:wgpu"

OS :: struct {
	initialized: bool,
}

os_init :: proc() {
	// ok := js.add_window_event_listener(.Resize, nil, size_callback)
	// assert(ok)
}

os_run :: proc(os: ^OS) {
	os.initialized = true
}

// @(private = "file", export)
// step :: proc(os: OS, dt: f32) -> bool {
// 	if !os.initialized {
// 		return true
// 	}
// 	frame(dt)
// 	return true
// }

