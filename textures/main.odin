package game

import "base:runtime"
import "core:fmt"
import "vendor:wgpu"

SHADER :: #load("shader.wgsl")

State :: struct {
	ctx:               runtime.Context,
	device_ready:      bool,
	instance:          wgpu.Instance,
	surface:           wgpu.Surface,
	adapter:           wgpu.Adapter,
	device:            wgpu.Device,
	config:            wgpu.SurfaceConfiguration,
	queue:             wgpu.Queue,
	module:            wgpu.ShaderModule,
	pipeline:          wgpu.RenderPipeline,
	pipeline_layout:   wgpu.PipelineLayout,
	texture:           wgpu.Texture,
	texture_view:      wgpu.TextureView,
	sampler:           wgpu.Sampler,
	bind_group:        wgpu.BindGroup,
	bind_group_layout: wgpu.BindGroupLayout,
}
g_state: State = {}

finish :: proc() {
	wgpu.RenderPipelineRelease(g_state.pipeline)
	wgpu.PipelineLayoutRelease(g_state.pipeline_layout)
	wgpu.ShaderModuleRelease(g_state.module)
	wgpu.QueueRelease(g_state.queue)
	wgpu.DeviceRelease(g_state.device)
	wgpu.AdapterRelease(g_state.adapter)
	wgpu.SurfaceRelease(g_state.surface)
	wgpu.InstanceRelease(g_state.instance)
	wgpu.TextureRelease(g_state.texture)
	wgpu.TextureViewRelease(g_state.texture_view)
	wgpu.SamplerRelease(g_state.sampler)
	wgpu.BindGroupRelease(g_state.bind_group)
	wgpu.BindGroupLayoutRelease(g_state.bind_group_layout)
}

TEXTURE_DIM: [2]u32 : {5, 7}
TEXTURE_SIZE :: TEXTURE_DIM.x * TEXTURE_DIM.y
R: [4]u8 : {255, 0, 0, 255} // red
Y: [4]u8 : {255, 255, 0, 255} // yellow
B: [4]u8 : {0, 0, 255, 255} // blue
TEXTURE_DATA: [TEXTURE_DIM.y][TEXTURE_DIM.x][4]u8 = {
	{B, R, R, R, R},
	{R, Y, Y, Y, R},
	{R, Y, R, R, R},
	{R, Y, Y, R, R},
	{R, Y, R, R, R},
	{R, Y, R, R, R},
	{R, R, R, R, R},
}

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
		g_state.texture = wgpu.DeviceCreateTexture(
			g_state.device,
			&{
				label = "texture descriptor",
				usage = {.TextureBinding, .CopyDst},
				size = {width = TEXTURE_DIM.x, height = TEXTURE_DIM.y, depthOrArrayLayers = 1},
				format = .RGBA8Unorm,
				sampleCount = 1,
				mipLevelCount = 1,
			},
		)
		g_state.texture_view = wgpu.TextureCreateView(g_state.texture, nil)
		g_state.sampler = wgpu.DeviceCreateSampler(g_state.device, nil)
		g_state.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
			g_state.device,
			&{
				entryCount = 2,
				entries = raw_data(
					[]wgpu.BindGroupLayoutEntry {
						{binding = 0, visibility = {.Fragment}, sampler = {type = .Filtering}},
						{
							binding = 1,
							visibility = {.Fragment},
							texture = {
								sampleType = .Float,
								viewDimension = ._2D,
								multisampled = false,
							},
						},
					},
				),
			},
		)
		g_state.bind_group = wgpu.DeviceCreateBindGroup(
			g_state.device,
			&{
				label = "textures bind group",
				layout = g_state.bind_group_layout,
				entryCount = 2,
				entries = raw_data(
					[]wgpu.BindGroupEntry {
						{binding = 0, sampler = g_state.sampler},
						{binding = 1, textureView = g_state.texture_view},
					},
				),
			},
		)
		fmt.println("dataSize:", size_of(TEXTURE_DATA))
		fmt.println("bytesPerRow:", size_of(TEXTURE_DATA[0]))
		wgpu.QueueWriteTexture(
			queue = g_state.queue,
			destination = &{texture = g_state.texture},
			data = raw_data(TEXTURE_DATA[:]),
			dataSize = size_of(TEXTURE_DATA),
			dataLayout = &{bytesPerRow = size_of(TEXTURE_DATA[0]), rowsPerImage = TEXTURE_DIM.y},
			writeSize = &{width = TEXTURE_DIM.x, height = TEXTURE_DIM.y, depthOrArrayLayers = 1},
		)

		g_state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
			g_state.device,
			&{bindGroupLayoutCount = 1, bindGroupLayouts = &g_state.bind_group_layout},
		)

		g_state.pipeline = wgpu.DeviceCreateRenderPipeline(
			g_state.device,
			&{
				label = "textures pipeline",
				layout = g_state.pipeline_layout,
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
		g_state.device_ready = true
	}
}

resize :: proc "c" () {
	context = g_state.ctx
	g_state.config.width, g_state.config.height = os_get_framebuffer_size()
	wgpu.SurfaceConfigure(g_state.surface, &g_state.config)
	// fmt.println("resize", g_state.config.width, g_state.config.height)
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
	wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, g_state.bind_group)
	wgpu.RenderPassEncoderDraw(
		render_pass_encoder,
		vertexCount = 6,
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
}

