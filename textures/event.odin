package game

import "core:fmt"
import "vendor:wgpu"

EventToggleTextureAddressModeU :: struct {}
EventToggleTextureAddressModeV :: struct {}
EventToggleTextureMagFilterMode :: struct {}
Event :: union {
	EventToggleTextureAddressModeU,
	EventToggleTextureAddressModeV,
	EventToggleTextureMagFilterMode,
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
		case EventToggleTextureAddressModeU:
			{
				if settings.address_mode_u == .Repeat {
					settings.address_mode_u = .ClampToEdge
				} else {
					settings.address_mode_u = .Repeat
				}
				fmt.println("address_mode_u:", settings.address_mode_u)
			}
		case EventToggleTextureAddressModeV:
			{
				if settings.address_mode_v == .Repeat {
					settings.address_mode_v = .ClampToEdge
				} else {
					settings.address_mode_v = .Repeat
				}
				fmt.println("address_mode_v:", settings.address_mode_v)
			}
		case EventToggleTextureMagFilterMode:
			{
				if settings.mag_filter == .Nearest {
					settings.mag_filter = .Linear
				} else {
					settings.mag_filter = .Nearest
				}
				fmt.println("mag_filter:", settings.mag_filter)
			}
		}
	}
	clear(&event_q)
}

