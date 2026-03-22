#+build js wasm32, js wasm64p32
package game

import "base:runtime"
import "core:sys/wasm/js"
import "vendor:wgpu"

@(export)
step :: proc(dt: f32) -> (keep_going: bool) {
	defer free_all(context.temp_allocator)

	update(dt)

	if g_state.device_ready {
		draw_scene()
	}

	return true
}

os_init :: proc() {
	ok := js.add_window_event_listener(.Resize, nil, size_callback); assert(ok)
	ok = js.add_window_event_listener(.Key_Down, nil, on_key_down); assert(ok)
}

os_get_framebuffer_size :: proc() -> (width, height: u32) {
	rect := js.get_bounding_client_rect("canvas-1")
	dpi := js.device_pixel_ratio()
	return u32(f64(rect.width) * dpi), u32(f64(rect.height) * dpi)
}

os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return wgpu.InstanceCreateSurface(
		instance,
		&wgpu.SurfaceDescriptor {
			nextInChain = &wgpu.SurfaceSourceCanvasHTMLSelector {
				sType = .SurfaceSourceCanvasHTMLSelector,
				selector = "#canvas-1",
			},
		},
	)
}

@(private = "file")
size_callback :: proc(e: js.Event) {
	resize()
}

@(private = "file")
on_key_down :: proc(e: js.Event) {
	if e.key.repeat {
		return
	}
	if e.key.code == "KeyA" {
		event_add(EventToggleTextureAddressModeU{})
	} else if e.key.code == "KeyS" {
		event_add(EventToggleTextureAddressModeV{})
	} else if e.key.code == "KeyD" {
		event_add(EventToggleTextureMagFilterMode{})
	} else if e.key.code == "KeyF" {
		event_add(EventToggleTextureMinFilterMode{})
	} else if e.key.code == "KeyQ" {
		event_add(EventChangeScale{-0.25})
	} else if e.key.code == "KeyW" {
		event_add(EventChangeScale{0.25})
	}
}

@(private = "file", fini)
os_fini :: proc "contextless" () {
	context = runtime.default_context()
	js.remove_window_event_listener(.Resize, nil, size_callback)

	finish()
}

