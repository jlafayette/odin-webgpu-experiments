package game

import "base:runtime"
import "core:fmt"
import "core:math"
import glm "core:math/linalg/glsl"
import "vendor:wgpu"


SHADER :: #load("shader.wgsl")


Settings :: struct {
	n_textures:    int,
	texture_index: int,
}

// No padding necessary
// Use this site to check WGSL offsets
// https://webgpufundamentals.org/webgpu/lessons/resources/wgsl-offset-computer.html
//
Uniforms :: struct {
	mat: glm.mat4,
}

ObjectInfo :: struct {
	sampler:        wgpu.Sampler,
	uniform_buffer: wgpu.Buffer,
	uniform_values: []Uniforms,
	bind_groups:    [2]wgpu.BindGroup,
	mat:            glm.mat4,
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
	//
	object_infos:      []ObjectInfo,
	//
	textures:          [2]wgpu.Texture,
	texture_views:     [2]wgpu.TextureView,
	//
	bind_group_layout: wgpu.BindGroupLayout,
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
	for t in g_state.textures {
		wgpu.TextureRelease(t)
	}
	for tv in g_state.texture_views {
		wgpu.TextureViewRelease(tv)
	}
	for obj in g_state.object_infos {
		wgpu.SamplerRelease(obj.sampler)
		for v in obj.bind_groups {
			wgpu.BindGroupRelease(v)
		}
		for v in obj.bind_groups {
			wgpu.BindGroupRelease(v)
		}
		wgpu.BufferRelease(obj.uniform_buffer)
		delete(obj.uniform_values)
	}
	delete(g_state.object_infos)
	wgpu.BindGroupLayoutRelease(g_state.bind_group_layout)
}

create_texture_with_mips :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	mips: []Mipmap,
	label: string,
) -> wgpu.Texture {
	t := wgpu.DeviceCreateTexture(
		device,
		&{
			label = label,
			usage = {.TextureBinding, .CopyDst},
			size = {
				width = u32(mips[0].dim.x),
				height = u32(mips[0].dim.y),
				depthOrArrayLayers = 1,
			},
			format = .RGBA8Unorm,
			mipLevelCount = u32(len(mips)),
			sampleCount = 1,
		},
	)
	for mip, mip_level in mips {
		data_size: uint = size_of(mip.data[0]) * len(mip.data)
		bytes_per_row := u32(size_of(mip.data[0]) * mip.dim.x)
		wgpu.QueueWriteTexture(
			queue = queue,
			destination = &{texture = t, mipLevel = u32(mip_level)},
			data = raw_data(mip.data[:]),
			dataSize = data_size,
			dataLayout = &{bytesPerRow = bytes_per_row, rowsPerImage = u32(mip.dim.y)},
			writeSize = &{width = u32(mip.dim.x), height = u32(mip.dim.y), depthOrArrayLayers = 1},
		)
	}

	return t
}

main :: proc() {
	g_state.ctx = context

	os_init()
	g_state.settings.texture_index = 0
	g_state.settings.n_textures = len(g_state.textures)

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
		g_state.textures[0] = create_texture_with_mips(
			g_state.device,
			g_state.queue,
			create_mips1()[:],
			"blended",
		)
		g_state.textures[1] = create_texture_with_mips(
			g_state.device,
			g_state.queue,
			create_mips2()[:],
			"checker",
		)

		g_state.texture_views[0] = wgpu.TextureCreateView(g_state.textures[0], nil)
		g_state.texture_views[1] = wgpu.TextureCreateView(g_state.textures[1], nil)

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


		g_state.object_infos = make_slice([]ObjectInfo, 8)
		for &obj, i in g_state.object_infos {
			mag_filter: wgpu.FilterMode = .Nearest
			if (i & 1) > 0 {mag_filter = .Linear}
			min_filter: wgpu.FilterMode = .Nearest
			if (i & 2) > 0 {min_filter = .Linear}
			mipmap_filter: wgpu.MipmapFilterMode = .Nearest
			if (i & 4) > 0 {mipmap_filter = .Linear}
			obj.sampler = wgpu.DeviceCreateSampler(
				g_state.device,
				&{
					addressModeU = .Repeat,
					addressModeV = .Repeat,
					addressModeW = .Repeat,
					magFilter = mag_filter,
					minFilter = min_filter,
					mipmapFilter = mipmap_filter,
					lodMinClamp = 0,
					lodMaxClamp = 32,
					compare = nil,
					maxAnisotropy = 1,
				},
			)
			obj.uniform_buffer = wgpu.DeviceCreateBuffer(
				g_state.device,
				&{
					label = "uniforms for quad",
					size = size_of(Uniforms),
					usage = {.Uniform, .CopyDst},
				},
			)
			assert(len(obj.bind_groups) == len(g_state.textures))
			assert(len(g_state.textures) == len(g_state.texture_views))
			for tex, i in g_state.textures {
				obj.bind_groups[i] = wgpu.DeviceCreateBindGroup(
					g_state.device,
					&{
						label = "textures bind group",
						layout = g_state.bind_group_layout,
						entryCount = 3,
						entries = raw_data(
							[]wgpu.BindGroupEntry {
								{binding = 0, sampler = obj.sampler},
								{binding = 1, textureView = g_state.texture_views[i]},
								{
									binding = 2,
									buffer = obj.uniform_buffer,
									size = size_of(Uniforms),
								},
							},
						),
					},
				)
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

resize :: proc "c" () {
	context = g_state.ctx
	g_state.config.width, g_state.config.height = os_get_framebuffer_size()
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

	fov: f32 = 60 * math.PI / 180 // 60 degrees in radians
	aspect: f32 = f32(g_state.config.width) / f32(g_state.config.height)
	z_near :: 0.1
	z_far :: 2000

	proj_matrix := glm.mat4Perspective(fov, aspect, z_near, z_far)
	camera_pos: [3]f32 = {0, 0, 2}
	up: [3]f32 = {0, 1, 0}
	target: [3]f32 = {0, 0, 0}
	camera_matrix := glm.mat4LookAt(camera_pos, target, up)

	view_matrix := glm.inverse_mat4(camera_matrix)
	view_proj_matrix := proj_matrix * view_matrix

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

	for obj, i in g_state.object_infos {

		x_spacing :: 1.2
		y_spacing :: 0.7
		z_depth :: 50
		x: f32 = f32(i % 4) - 1.5
		y: f32 = -1
		if i < 4 {y = 1}

		mat := view_proj_matrix
		mat *= glm.mat4Translate({x * x_spacing, y * y_spacing, -z_depth * 0.5})
		mat *= glm.mat4Rotate({1, 0, 0}, 0.5 * math.PI)
		mat *= glm.mat4Scale({1, z_depth * 2, 1})
		mat *= glm.mat4Translate({-0.5, -0.5, 0})

		wgpu.QueueWriteBuffer(g_state.queue, obj.uniform_buffer, 0, &mat, size_of(glm.mat4))

		wgpu.RenderPassEncoderSetBindGroup(
			render_pass_encoder,
			0,
			obj.bind_groups[g_state.settings.texture_index],
		)
		wgpu.RenderPassEncoderDraw(
			render_pass_encoder,
			vertexCount = 6,
			instanceCount = 1,
			firstVertex = 0,
			firstInstance = 0,
		)
	}

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, {command_buffer})
	wgpu.SurfacePresent(state.surface)
}

