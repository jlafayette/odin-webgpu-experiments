package game

import "base:runtime"
import "core:fmt"
import "core:math"
import "vendor:wgpu"

SHADER :: #load("shader.wgsl")


Settings :: struct {
	address_mode_u: wgpu.AddressMode,
	address_mode_v: wgpu.AddressMode,
	mag_filter:     wgpu.FilterMode,
	min_filter:     wgpu.FilterMode,
	scale:          f32,
}
settings_to_index :: proc(s: Settings) -> int {
	// address_modes: [2]wgpu.AddressMode = {.ClampToEdge, .Repeat}
	u_i := 0
	if s.address_mode_u == .Repeat {u_i = 1}
	v_i := 0
	if s.address_mode_v == .Repeat {v_i = 1}
	// filters: [2]wgpu.FilterMode = {.Nearest, .Linear}
	mag_i := 0
	if s.mag_filter == .Linear {mag_i = 1}
	min_i := 0
	if s.min_filter == .Linear {min_i = 1}
	return u_i * 8 + v_i * 4 + mag_i * 2 + min_i
}

// No padding necessary
// Use this site to check WGSL offsets
// https://webgpufundamentals.org/webgpu/lessons/resources/wgsl-offset-computer.html
//
Uniforms :: struct {
	scale:  [2]f32,
	offset: [2]f32,
}

State :: struct {
	ctx:               runtime.Context,
	device_ready:      bool,
	settings:          Settings,
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
	samplers:          [16]wgpu.Sampler,
	bind_groups:       [16]wgpu.BindGroup,
	bind_group_layout: wgpu.BindGroupLayout,
	//
	uniform_buffer:    wgpu.Buffer,
	uniform_values:    Uniforms,
	//
	time:              f64,
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
	for v, i in g_state.samplers {
		wgpu.SamplerRelease(v)
	}
	for v in g_state.bind_groups {
		wgpu.BindGroupRelease(v)
	}
	wgpu.BindGroupLayoutRelease(g_state.bind_group_layout)
	wgpu.BufferRelease(g_state.uniform_buffer)
}

TEXTURE_DIM: [2]int : {5, 7}
TEXTURE_SIZE :: TEXTURE_DIM.x * TEXTURE_DIM.y
R: [4]u8 : {255, 0, 0, 255} // red
Y: [4]u8 : {255, 255, 0, 255} // yellow
B: [4]u8 : {0, 0, 255, 255} // blue
TEXTURE_DATA: [TEXTURE_DIM.y * TEXTURE_DIM.x][4]u8 = {
	R,
	R,
	R,
	R,
	R, //
	R,
	Y,
	R,
	R,
	R, //
	R,
	Y,
	R,
	R,
	R, //
	R,
	Y,
	Y,
	R,
	R, //
	R,
	Y,
	R,
	R,
	R, //
	R,
	Y,
	Y,
	Y,
	R, //
	B,
	R,
	R,
	R,
	R, //
}

main :: proc() {
	g_state.ctx = context

	os_init()
	g_state.settings.address_mode_u = .ClampToEdge
	g_state.settings.address_mode_v = .ClampToEdge
	g_state.settings.mag_filter = .Nearest
	g_state.settings.min_filter = .Nearest
	g_state.settings.scale = 1

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
		low_width, low_height := low_res_size(width, height)
		g_state.config = wgpu.SurfaceConfiguration {
			device      = g_state.device,
			usage       = {.RenderAttachment},
			format      = .BGRA8Unorm,
			width       = low_width,
			height      = low_height,
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
		first_mip: Mipmap = {
			data = TEXTURE_DATA[:],
			dim  = {TEXTURE_DIM.x, TEXTURE_DIM.y},
		}
		mips := generate_mips(first_mip)
		g_state.texture = wgpu.DeviceCreateTexture(
			g_state.device,
			&{
				label = "texture descriptor",
				usage = {.TextureBinding, .CopyDst},
				size = {
					width = u32(mips[0].dim.x),
					height = u32(mips[0].dim.y),
					depthOrArrayLayers = 1,
				},
				format = .RGBA8Unorm,
				sampleCount = 1,
				mipLevelCount = u32(len(mips)),
			},
		)
		g_state.texture_view = wgpu.TextureCreateView(g_state.texture, nil)
		for mip, mip_level in mips {
			data_size: uint = size_of(mip.data[0]) * len(mip.data)
			bytes_per_row := u32(size_of(mip.data[0]) * mip.dim.x)
			fmt.println("mip", mip)
			fmt.println("mipLevel", mip_level)
			fmt.println("- dataSize:", data_size)
			fmt.println("- bytesPerRow:", bytes_per_row)
			wgpu.QueueWriteTexture(
				queue = g_state.queue,
				destination = &{texture = g_state.texture, mipLevel = u32(mip_level)},
				data = raw_data(mip.data[:]),
				dataSize = data_size,
				dataLayout = &{bytesPerRow = bytes_per_row, rowsPerImage = u32(mip.dim.y)},
				writeSize = &{
					width = u32(mip.dim.x),
					height = u32(mip.dim.y),
					depthOrArrayLayers = 1,
				},
			)
		}

		g_state.uniform_buffer = wgpu.DeviceCreateBuffer(
			g_state.device,
			&{label = "uniforms buffer", usage = {.Uniform, .CopyDst}, size = size_of(Uniforms)},
		)

		g_state.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
			g_state.device,
			&{
				entryCount = 3,
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
						{
							binding = 2,
							visibility = {.Vertex},
							buffer = {type = .Uniform, minBindingSize = size_of(Uniforms)},
						},
					},
				),
			},
		)

		address_modes: [2]wgpu.AddressMode = {.ClampToEdge, .Repeat}
		filters: [2]wgpu.FilterMode = {.Nearest, .Linear}
		for address_mode_u, iu in address_modes {
			for address_mode_v, iv in address_modes {
				for mag_filter, i_mag in filters {
					for min_filter, i_min in filters {

						i := iu * 8 + iv * 4 + i_mag * 2 + i_min
						g_state.samplers[i] = wgpu.DeviceCreateSampler(
							g_state.device,
							&{
								addressModeU = address_mode_u,
								addressModeV = address_mode_v,
								addressModeW = .ClampToEdge,
								magFilter = mag_filter,
								minFilter = min_filter,
								mipmapFilter = .Nearest,
								lodMinClamp = 0,
								lodMaxClamp = 32,
								compare = nil,
								maxAnisotropy = 1,
							},
						)
						g_state.bind_groups[i] = wgpu.DeviceCreateBindGroup(
							g_state.device,
							&{
								label = "textures bind group",
								layout = g_state.bind_group_layout,
								entryCount = 3,
								entries = raw_data(
									[]wgpu.BindGroupEntry {
										{binding = 0, sampler = g_state.samplers[i]},
										{binding = 1, textureView = g_state.texture_view},
										{
											binding = 2,
											buffer = g_state.uniform_buffer,
											size = size_of(Uniforms),
										},
									},
								),
							},
						)
					}
				}
			}
		}

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

low_res_size :: proc(w, h: u32) -> (u32, u32) {
	return w / 64 | 0, h / 64 | 0
}

resize :: proc "c" () {
	context = g_state.ctx
	w, h := os_get_framebuffer_size()
	g_state.config.width, g_state.config.height = low_res_size(w, h)
	wgpu.SurfaceConfigure(g_state.surface, &g_state.config)
	// fmt.println("resize", g_state.config.width, g_state.config.height)
}

update :: proc(dt: f32) {
	handle_events(&g_state.settings)
	g_state.time += f64(dt)
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

	{
		scale_x: f32 = (4 / f32(g_state.config.width)) * g_state.settings.scale
		scale_y: f32 = (4 / f32(g_state.config.height)) * g_state.settings.scale
		g_state.uniform_values.scale = {scale_x, scale_y}
		offset_x := cast(f32)math.sin(g_state.time * 1.5) * 0.8 - (scale_x * 0.5)
		offset_y: f32 = -0.8
		g_state.uniform_values.offset = {offset_x, offset_y}
		wgpu.QueueWriteBuffer(
			g_state.queue,
			g_state.uniform_buffer,
			0,
			&g_state.uniform_values,
			size_of(Uniforms),
		)
	}

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
	wgpu.RenderPassEncoderSetBindGroup(
		render_pass_encoder,
		0,
		g_state.bind_groups[settings_to_index(g_state.settings)],
	)
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

