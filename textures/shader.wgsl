struct VertShaderOutput {
    @builtin(position) position: vec4f,
    @location(0) texcoord: vec2f,
};

@vertex fn vs(
    @builtin(vertex_index) vertexIndex : u32
) -> VertShaderOutput {
    let pos = array(
        // triangle 1
		vec2f(0.0,  0.0), // center
		vec2f(1.0,  0.0), // right, center
		vec2f(0.0,  1.0), // center, top
        // triangle 2
		vec2f(0.0,  1.0), // center, top
		vec2f(1.0,  0.0), // right, center
		vec2f(1.0,  1.0), // right, top
    );
    var color = array<vec4f, 3>(
        vec4f(1, 0, 0, 1),
        vec4f(0, 1, 0, 1),
        vec4f(0, 0, 1, 1),
    );
    var vsOutput: VertShaderOutput;
    let xy = pos[vertexIndex];
    vsOutput.position = vec4f(xy, 0.0, 1.0);
    vsOutput.texcoord = xy;
    return vsOutput;
}

@group(0) @binding(0) var tSampler: sampler;
@group(0) @binding(1) var tTexture: texture_2d<f32>;

@fragment fn fs(fsInput: VertShaderOutput) -> @location(0) vec4f {
    return textureSample(tTexture, tSampler, fsInput.texcoord);
}
