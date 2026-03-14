struct UStatic {
    color: vec4f,
    offset: vec2f,
};
struct UDyn {
    scale: vec2f,
}

@group(0) @binding(0) var<storage, read> uStatic: UStatic;
@group(0) @binding(1) var<storage, read> uDyn: UDyn;

@vertex fn vs(
    @builtin(vertex_index) vertexIndex : u32
) -> @builtin(position) vec4f {
    let pos = array(
		vec2f( 0.0,  0.5), // tp center
		vec2f(-0.5, -0.5), // bt left
		vec2f( 0.5, -0.5), // bt right
    );
    return vec4f(pos[vertexIndex] * uDyn.scale + uStatic.offset, 0.0, 1.0);
}

@fragment fn fs() -> @location(0) vec4f {
    return uStatic.color;
}
