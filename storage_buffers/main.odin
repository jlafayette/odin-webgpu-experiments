package game

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "vendor:wgpu"

SHADER :: #load("shader.wgsl")

StaticStorage :: struct {
	color:    [4]f32,
	offset:   [2]f32,
	_padding: [2]f32,
}
DynamicStorage :: struct {
	scale: [2]f32,
}

ObjectInfo :: struct {
	scale: f32,
}

NUM_OBJECTS :: 100
STATIC_STORAGE_SIZE :: size_of(StaticStorage) * NUM_OBJECTS
DYNAMIC_STORAGE_SIZE :: size_of(DynamicStorage) * NUM_OBJECTS

State :: struct {
	ctx:                    runtime.Context,
	device_ready:           bool,
	instance:               wgpu.Instance,
	surface:                wgpu.Surface,
	adapter:                wgpu.Adapter,
	device:                 wgpu.Device,
	config:                 wgpu.SurfaceConfiguration,
	queue:                  wgpu.Queue,
	module:                 wgpu.ShaderModule,
	pipeline:               wgpu.RenderPipeline,
	object_infos:           []ObjectInfo,
	//
	static_storage_buffer:  wgpu.Buffer,
	dynamic_storage_buffer: wgpu.Buffer,
	bind_group:             wgpu.BindGroup,
	static_values:          []StaticStorage,
	storage_values:         []DynamicStorage,
}
g_state: State = {}


main :: proc() {
	g_state.ctx = context

	os_init()

	g_state.instance = wgpu.CreateInstance(nil)
	if g_state.instance == nil {
		panic("WebGPU is not supported")
	}
	g_state.surface = os_get_surface(g_state.instance)

	wgpu.InstanceRequestAdapter(
		g_state.instance,
		&{compatibleSurface = g_state.surface},
		{callback = on_adapter},
	)

	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		adapter: wgpu.Adapter,
		message: string,
		userdata1: rawptr,
		userdata2: rawptr,
	) {
		context = g_state.ctx
		if status != .Success || adapter == nil {
			fmt.panicf("request device failure [%v] %s", status, message)
		}
		g_state.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, {callback = on_device})
	}
	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		device: wgpu.Device,
		message: string,
		userdata1: rawptr,
		userdata2: rawptr,
	) {
		context = g_state.ctx
		if status != .Success || device == nil {
			fmt.panicf("request device failure [%v] %s", status, message)
		}
		g_state.device = device
		width, height := os_get_framebuffer_size()
		g_state.config = wgpu.SurfaceConfiguration {
			device      = g_state.device,
			usage       = {.RenderAttachment},
			format      = .BGRA8Unorm,
			width       = width,
			height      = height,
			presentMode = .Fifo,
			alphaMode   = .Opaque,
		}
		wgpu.SurfaceConfigure(g_state.surface, &g_state.config)
		g_state.queue = wgpu.DeviceGetQueue(g_state.device)
		shader := string(SHADER)
		g_state.module = wgpu.DeviceCreateShaderModule(
			g_state.device,
			&{nextInChain = &wgpu.ShaderSourceWGSL{sType = .ShaderSourceWGSL, code = shader}},
		)
		g_state.pipeline = wgpu.DeviceCreateRenderPipeline(
			g_state.device,
			&{
				label = "storage pipeline",
				vertex = {module = g_state.module, entryPoint = "vs"},
				fragment = &{
					module = g_state.module,
					entryPoint = "fs",
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

		g_state.static_storage_buffer = wgpu.DeviceCreateBuffer(
			g_state.device,
			&{
				label = "static storage buffer",
				size = STATIC_STORAGE_SIZE,
				usage = {.Storage, .CopyDst},
			},
		)
		g_state.dynamic_storage_buffer = wgpu.DeviceCreateBuffer(
			g_state.device,
			&{
				label = "dynamic storage buffer",
				size = DYNAMIC_STORAGE_SIZE,
				usage = {.Storage, .CopyDst},
			},
		)

		g_state.object_infos = make_slice([]ObjectInfo, NUM_OBJECTS)

		// Static Storage
		g_state.static_values = make_slice([]StaticStorage, NUM_OBJECTS)
		for &v, i in g_state.static_values {
			v.color = {
				rand.float32_range(0, 1),
				rand.float32_range(0, 1),
				rand.float32_range(0, 1),
				1,
			}
			v.offset = {rand.float32_range(-0.9, 0.9), rand.float32_range(-0.9, 0.9)}
			g_state.object_infos[i].scale = rand.float32_range(0.05, 0.3)
		}
		wgpu.QueueWriteBuffer(
			g_state.queue,
			g_state.static_storage_buffer,
			0,
			raw_data(g_state.static_values),
			STATIC_STORAGE_SIZE,
		)

		g_state.storage_values = make_slice([]DynamicStorage, NUM_OBJECTS)

		g_state.bind_group = wgpu.DeviceCreateBindGroup(
			g_state.device,
			&{
				label = "bind group for objects",
				layout = wgpu.RenderPipelineGetBindGroupLayout(g_state.pipeline, 0),
				entryCount = 2,
				entries = raw_data(
					[]wgpu.BindGroupEntry {
						{
							binding = 0,
							buffer = g_state.static_storage_buffer,
							size = STATIC_STORAGE_SIZE,
						},
						{
							binding = 1,
							buffer = g_state.dynamic_storage_buffer,
							size = DYNAMIC_STORAGE_SIZE,
						},
					},
				),
			},
		)
		g_state.device_ready = true
	}
}

resize :: proc "c" () {
	context = g_state.ctx
	g_state.config.width, g_state.config.height = os_get_framebuffer_size()
	wgpu.SurfaceConfigure(g_state.surface, &g_state.config)
}

draw_scene :: proc() {
	state := g_state
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
				clearValue = {0.2, 0.2, 0.2, 1},
			},
		},
	)
	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.pipeline)

	aspect := f32(g_state.config.width) / f32(g_state.config.height)
	for obj, i in g_state.object_infos {
		g_state.storage_values[i].scale = {obj.scale / aspect, obj.scale}
	}
	wgpu.QueueWriteBuffer(
		g_state.queue,
		g_state.dynamic_storage_buffer,
		0,
		raw_data(g_state.storage_values),
		DYNAMIC_STORAGE_SIZE,
	)

	wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, g_state.bind_group)
	wgpu.RenderPassEncoderDraw(render_pass_encoder, 3, NUM_OBJECTS, 0, 0)
	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, {command_buffer})
	wgpu.SurfacePresent(state.surface)
}

