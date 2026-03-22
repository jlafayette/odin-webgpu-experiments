package game

import "core:fmt"
import "core:math"
import "vendor:wgpu"

EventToggleTextureAddressModeU :: struct {}
EventToggleTextureAddressModeV :: struct {}
EventToggleTextureMagFilterMode :: struct {}
EventToggleTextureMinFilterMode :: struct {}
EventChangeScale :: struct {
	value: f32,
}
Event :: union {
	EventToggleTextureAddressModeU,
	EventToggleTextureAddressModeV,
	EventToggleTextureMagFilterMode,
	EventToggleTextureMinFilterMode,
	EventChangeScale,
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
		case EventToggleTextureMinFilterMode:
			{
				if settings.min_filter == .Nearest {
					settings.min_filter = .Linear
				} else {
					settings.min_filter = .Nearest
				}
				fmt.println("min_filter:", settings.min_filter)
			}
		case EventChangeScale:
			{
				v := e.value + settings.scale
				settings.scale = math.clamp(v, 0.5, 6)
			}
		}
	}
	clear(&event_q)
}

