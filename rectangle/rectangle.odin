package rectangle

// import "../shared/resize"
import "../shared/text"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:sys/wasm/js"
import "vendor:wgpu"


main :: proc() {}


TempArena :: struct {
	allocator: mem.Allocator,
	buffer:    []byte,
	arena:     mem.Arena,
}
temp_arena_init :: proc(ta: ^TempArena) {
	ta.buffer = make_slice([]byte, mem.Megabyte)
	ta.arena = {
		data = ta.buffer[:],
	}
	ta.allocator = mem.arena_allocator(&ta.arena)
}

State :: struct {
	started:         bool,
	rotation:        f32,
	ctx:             runtime.Context,
	os:              OS,
	instance:        wgpu.Instance,
	surface:         wgpu.Surface,
	adapter:         wgpu.Adapter,
	device:          wgpu.Device,
	config:          wgpu.SurfaceConfiguration,
	queue:           wgpu.Queue,
	module:          wgpu.ShaderModule,
	pipeline_layout: wgpu.PipelineLayout,
	pipeline:        wgpu.RenderPipeline,
	// w:               i32,
	// h:               i32,
	// canvas_w:        i32,
	// canvas_h:        i32,
	// dpr:             f32,
	// window_w:        i32,
	// window_h:        i32,
	debug_text:      text.Batch,
	temp_arena:      TempArena,
}
g_state: State = {}

start :: proc(state: ^State) -> (ok: bool) {
	fmt.println("start")
	state.started = true
	os_init()

	state.instance = wgpu.CreateInstance(nil)
	if state.instance == nil {
		panic("WebGPU is not supported")
	}
	state.surface = os_get_surface(state.instance)
	fmt.println("back in start")

	wgpu.InstanceRequestAdapter(
		state.instance,
		&{compatibleSurface = state.surface},
		{callback = on_adapter},
	)

	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		adapter: wgpu.Adapter,
		message: string,
		userdata1: rawptr,
		userdata2: rawptr,
	) {
		state := &g_state
		context = state.ctx
		fmt.println("on_adapter")
		if status != .Success || adapter == nil {
			fmt.panicf("request device failure [%v] %s", status, message)
		}
		state.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, {callback = on_device})
	}
	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		device: wgpu.Device,
		message: string,
		userdata1: rawptr,
		userdata2: rawptr,
	) {
		state := &g_state
		context = state.ctx
		if status != .Success || device == nil {
			fmt.panicf("request device failure [%v] %s", status, message)
		}
		fmt.println("on_device")
		state.device = device
		width, height := os_get_framebuffer_size()
		state.config = wgpu.SurfaceConfiguration {
			device      = state.device,
			usage       = {.RenderAttachment},
			format      = .BGRA8Unorm,
			width       = width,
			height      = height,
			presentMode = .Fifo,
			alphaMode   = .Opaque,
		}
		wgpu.SurfaceConfigure(state.surface, &state.config)
		state.queue = wgpu.DeviceGetQueue(state.device)
		shader :: `
	@vertex
	fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4<f32> {
		let pos = array(
			vec2f( 0.0,  0.5), // tp center
			vec2f(-0.5, -0.5), // bt left
			vec2f( 0.5, -0.5), // bt right
		);
		return vec4f(pos[in_vertex_index], 0.0, 1.0);
	}

	@fragment
	fn fs_main() -> @location(0) vec4<f32> {
		return vec4<f32>(0.9, 0.3, 0.3, 1.0);
	}`
		state.module = wgpu.DeviceCreateShaderModule(
			state.device,
			&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = shader}},
		)
		state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(state.device, &{})
		state.pipeline = wgpu.DeviceCreateRenderPipeline(
			state.device,
			&{
				label = "red tri pipeline",
				layout = state.pipeline_layout,
				vertex = {module = state.module, entryPoint = "vs_main"},
				fragment = &{
					module = state.module,
					entryPoint = "fs_main",
					targetCount = 1,
					targets = &wgpu.ColorTargetState {
						format = .BGRA8Unorm,
						writeMask = wgpu.ColorWriteMaskFlags_All,
					},
				},
				primitive = {topology = .TriangleList},
				multisample = {count = 1, mask = 0xFFFFFFFF},
			},
		)
		fmt.println("before os_run", state.os.initialized)
		os_run(&g_state.os)
		fmt.println("after os_run", state.os.initialized)
	}

	fmt.println("done with start")

	return true
}

resize :: proc "c" () {
	context = g_state.ctx
	g_state.config.width, g_state.config.height = os_get_framebuffer_size()
	wgpu.SurfaceConfigure(g_state.surface, &g_state.config)
	fmt.println("resize", g_state.config.width, g_state.config.height)
}


draw_scene :: proc(state: ^State) {
	if !state.os.initialized {
		return
	}
	surface_texture := wgpu.SurfaceGetCurrentTexture(state.surface)
	switch surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	case .Timeout, .Outdated, .Lost:
		if surface_texture.texture != nil {
			wgpu.TextureRelease(surface_texture.texture)
		}
		resize()
		return
	case .OutOfMemory, .DeviceLost, .Error:
		fmt.panicf("[rectangle] get_current_texture status=%v", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	frame := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(frame)

	command_encoder := wgpu.DeviceCreateCommandEncoder(state.device, &{label = "encoder"})
	defer wgpu.CommandEncoderRelease(command_encoder)

	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&{
			label = "basic canvas renderPass",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = frame,
				loadOp = .Clear,
				storeOp = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = {0.1, 0.2, 0.2, 1},
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.pipeline)
	wgpu.RenderPassEncoderDraw(
		render_pass_encoder,
		vertexCount = 3,
		instanceCount = 1,
		firstVertex = 0,
		firstInstance = 0,
	)

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, {command_buffer})
	wgpu.SurfacePresent(state.surface)

	// gl.Viewport(0, 0, state.w, state.h)

	// fov: f32 = (45.0 * math.PI) / 180.0
	// aspect: f32 = f32(state.w) / f32(state.h)
	// z_near: f32 = 0.1
	// z_far: f32 = 100.0
	// projection_mat := glm.mat4Perspective(fov, aspect, z_near, z_far)
	// model_view_mat := glm.mat4Translate({-0, 0, -6}) * glm.mat4Rotate({0, 0, 1}, state.rotation)

	// {
	// 	text_projection := glm.mat4Ortho3d(0, f32(state.w), f32(state.h), 0, -1, 1)
	// 	spacing: int = 4
	// 	scale: int = math.max(1, cast(int)math.round(state.dpr))
	// 	text.batch_start(
	// 		&state.debug_text,
	// 		.A30,
	// 		{1, 1, 1},
	// 		text_projection,
	// 		64,
	// 		spacing = spacing,
	// 		scale = scale,
	// 	)
	// 	h: int = text.debug_get_height()
	// 	line_gap: int = h / 2
	// 	total_h: int = h * 3 + line_gap * 2

	// 	str: string = fmt.tprintf("canvas: %d x %d", state.canvas_w, state.canvas_h)
	// 	w: int = text.debug_get_width(str)
	// 	x: int = int(state.w) / 2 - w / 2
	// 	y: int = int(state.h) / 2 - total_h / 2
	// 	text.debug({x, y}, str)

	// 	str = fmt.tprintf("dpr: %.2f", state.dpr)
	// 	w = text.debug_get_width(str)
	// 	x = int(state.w) / 2 - w / 2
	// 	y += h + line_gap
	// 	text.debug({x, y}, str)

	// 	str = fmt.tprintf("window: %d x %d", state.window_w, state.window_h)
	// 	w = text.debug_get_width(str)
	// 	x = int(state.w) / 2 - w / 2
	// 	y += h + line_gap
	// 	text.debug({x, y}, str)
	// }
}

update :: proc(state: ^State, dt: f32) {
	// resize_state: resize.ResizeState
	// resize.resize(&resize_state)
	// state.canvas_w = resize_state.canvas_res.x
	// state.canvas_h = resize_state.canvas_res.y
	// state.window_w = resize_state.window_size.x
	// state.window_h = resize_state.window_size.y
	// size := resize.get()
	// state.w = size.w
	// state.h = size.h
	// state.dpr = size.dpr
	state.rotation += dt
}

@(export)
step :: proc(dt: f32) -> (keep_going: bool) {
	ok: bool
	if !g_state.started {
		g_state.ctx = runtime.default_context()
		context = g_state.ctx
		temp_arena_init(&g_state.temp_arena)
		context.temp_allocator = g_state.temp_arena.allocator
		fmt.println("first step")
		g_state.started = true
		if ok = start(&g_state); !ok {
			fmt.println("start !ok")
			return false
		}
	}
	context = g_state.ctx
	context.temp_allocator = g_state.temp_arena.allocator
	defer free_all(context.temp_allocator)

	update(&g_state, dt)

	draw_scene(&g_state)

	return true
}


// ---


OS :: struct {
	initialized: bool,
}

os_init :: proc() {
	ok := js.add_window_event_listener(.Resize, nil, size_callback)
	assert(ok)
}

os_run :: proc(os: ^OS) {
	os.initialized = true
	fmt.println("os_run")
}

os_get_framebuffer_size :: proc() -> (width, height: u32) {
	rect := js.get_bounding_client_rect("canvas-1")
	dpi := js.device_pixel_ratio()
	return u32(f64(rect.width) * dpi), u32(f64(rect.height) * dpi)
}

os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	fmt.println("os_get_surface")
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

