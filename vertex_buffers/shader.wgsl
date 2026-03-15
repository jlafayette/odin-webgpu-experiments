struct Static {
    color: vec4f,
    offset: vec2f,
};
struct Dyn {
    scale: vec2f,
}
struct Vert {
    @location(0) position: vec2f,
};
struct VSOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec4f,
}

@group(0) @binding(0) var<storage, read> aStatic: array<Static>;
@group(0) @binding(1) var<storage, read> aDyn: array<Dyn>;

@vertex fn vs(
    vert: Vert,
    @builtin(instance_index) instanceIndex : u32,
) -> VSOutput {
    let s = aStatic[instanceIndex];
    let d = aDyn[instanceIndex];
    var vsOut: VSOutput;
    vsOut.position = vec4f(vert.position * d.scale + s.offset, 0.0, 1.0);
    vsOut.color = s.color;
    return vsOut;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
    return vsOut.color;
}
