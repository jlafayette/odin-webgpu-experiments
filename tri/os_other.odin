#+build !js
package game

import "vendor:wgpu"


os_init :: proc() {
	unimplemented()
}

os_get_framebuffer_size :: proc() -> (width, height: u32) {
	unimplemented()
}

os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	unimplemented()
}

