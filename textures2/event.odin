package game

import "core:fmt"
import "core:math"
import "vendor:wgpu"

EventToggleTexture :: struct {}
Event :: union {
	EventToggleTexture,
}

event_q: [dynamic]Event
event_q_init :: proc() -> bool {
	err := reserve(&event_q, 12)
	return err == .None
}
event_q_destroy :: proc() {
	delete(event_q)
}
event_add :: proc(e: Event) {
	if e != nil {
		append(&event_q, e)
	}
}

handle_events :: proc(settings: ^Settings) {
	for event in event_q {
		switch e in event {
		case EventToggleTexture:
			{
				settings.texture_index = (settings.texture_index + 1) % settings.n_textures
				fmt.println("texture index:", settings.texture_index)
			}
		}
	}
	clear(&event_q)
}

