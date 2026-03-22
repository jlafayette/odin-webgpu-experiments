package game

// import "core:fmt"
import "core:math"

RgbaU8 :: [4]u8
Mipmap :: struct {
	data: [][4]u8,
	dim:  [2]int,
}

@(private = "file")
get_pixel :: proc(m: Mipmap, x, y: int) -> RgbaU8 {
	i := (y * m.dim.x) + x
	assert(i >= 0 && i < len(m.data))

	return m.data[i]
}

@(private = "file")
array_lerp :: proc(c1, c2: RgbaU8, t: f32) -> RgbaU8 {

	r := math.lerp(f32(c1.r), f32(c2.r), t)
	g := math.lerp(f32(c1.g), f32(c2.g), t)
	b := math.lerp(f32(c1.b), f32(c2.b), t)
	a := math.lerp(f32(c1.a), f32(c2.a), t)
	return RgbaU8 {
		cast(u8)math.round(r),
		cast(u8)math.round(g),
		cast(u8)math.round(b),
		cast(u8)math.round(a),
	}
}

@(private = "file")
bilinear_filter :: proc(tl, tr, bl, br: RgbaU8, t1, t2: f32) -> RgbaU8 {
	t := array_lerp(tl, tr, t1)
	b := array_lerp(bl, br, t1)
	return array_lerp(t, b, t2)
}

@(private = "file")
create_next_mip_level_rgba8unorm :: proc(src: Mipmap) -> Mipmap {
	dst: Mipmap
	// compute the size of the next mip
	dst.dim = {
		math.max(1, src.dim.x / 2), //
		math.max(1, src.dim.y / 2), //
	}
	dst.data = make_slice([]RgbaU8, dst.dim.x * dst.dim.y)

	for y := 0; y < dst.dim.y; y += 1 {
		for x := 0; x < dst.dim.x; x += 1 {
			// compute texcoord of the center of the destination texel
			u := (f32(x) + 0.5) / f32(dst.dim.x)
			v := (f32(y) + 0.5) / f32(dst.dim.y)

			// compute the same texcoord in the source (- 0.5 a pixel)
			au := u * f32(src.dim.x) - 0.5
			av := v * f32(src.dim.y) - 0.5

			// compute the src top left texel coord (not texcoord)
			tx := math.floor(au)
			ty := math.floor(av)

			// compute the mix amounts between pixels
			// (this is the fractional part)
			t1 := au - tx
			t2 := av - ty

			// debug
			//
			// fmt.printfln(
			// 	"(%d,%d) u,v=(%.2f,%.2f) au,av=(%.2f,%.2f) tx,ty=(%.2f,%.2f) t1,t2=(%.2f,%.2f)",
			// 	x, y, u, v, au, av, tx, ty, t1, t2,
			// )
			// {
			// 	x := int(tx)
			// 	y := int(ty)
			// 	fmt.printfln(
			// 		"  (%d,%d)(%d,%d)(%d,%d)(%d,%d)",
			// 		x, y, x + 1, y, x, y + 1, x + 1, y + 1,
			// 	)
			// }

			// get the 4 pixels to sample between
			tl := get_pixel(src, int(tx), int(ty))
			tr := get_pixel(src, int(tx + 1), int(ty))
			bl := get_pixel(src, int(tx), int(ty + 1))
			br := get_pixel(src, int(tx + 1), int(ty + 1))

			dst_index := (y * dst.dim.x) + x
			dst.data[dst_index] = bilinear_filter(tl, tr, bl, br, t1, t2)
		}
	}

	return dst
}

generate_mips :: proc(src: Mipmap) -> [dynamic]Mipmap {
	mip := src
	mips: [dynamic]Mipmap
	append(&mips, mip)
	for mip.dim.x > 1 || mip.dim.y > 1 {
		mip = create_next_mip_level_rgba8unorm(mip)
		append(&mips, mip)
	}
	return mips
}

