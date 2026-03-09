package rectangle

// import "core:fmt"
// import "core:sys/wasm/js"
// import "vendor:wgpu"

// OS :: struct {
// 	initialized: bool,
// }

// os_init :: proc() {
// 	ok := js.add_window_event_listener(.Resize, nil, size_callback)
// 	assert(ok)
// }

// os_run :: proc(os: ^OS) {
// 	os.initialized = true
// 	fmt.println("os_run")
// }

// os_get_framebuffer_size :: proc() -> (width, height: u32) {
// 	rect := js.get_bounding_client_rect("body")
// 	dpi := js.device_pixel_ratio()
// 	return u32(f64(rect.width) * dpi), u32(f64(rect.height) * dpi)
// }

// os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
// 	fmt.println("os_get_surface")
// 	return wgpu.InstanceCreateSurface(
// 		instance,
// 		&wgpu.SurfaceDescriptor {
// 			nextInChain = &wgpu.SurfaceSourceCanvasHTMLSelector {
// 				sType = .SurfaceSourceCanvasHTMLSelector,
// 				selector = "#canvas-1",
// 			},
// 		},
// 	)
// }

// @(private = "file")
// size_callback :: proc(e: js.Event) {
// 	resize()
// }

