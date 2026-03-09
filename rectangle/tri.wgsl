struct VertShaderOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec4f,
};

@vertex fn vs(
    @builtin(vertex_index) vertexIndex : u32
) -> VertShaderOutput {
    let pos = array(
		vec2f( 0.0,  0.5), // tp center
		vec2f(-0.5, -0.5), // bt left
		vec2f( 0.5, -0.5), // bt right
    );
    var color = array<vec4f, 3>(
        vec4f(1, 0, 0, 1),
        vec4f(0, 1, 0, 1),
        vec4f(0, 0, 1, 1),
    );
    var vsOutput: VertShaderOutput;
    vsOutput.position = vec4f(pos[vertexIndex], 0.0, 1.0);
    vsOutput.color = color[vertexIndex];
    return vsOutput;
}

@fragment fn fs(fsInput: VertShaderOutput) -> @location(0) vec4f {
    return fsInput.color;
}
