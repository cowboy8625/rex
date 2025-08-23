pub const zm = @import("zm");
/// make your own vector
pub const Vec = zm.vec.Vec;
/// f32
pub const Vec2f = zm.vec.Vec2f;
/// f32
pub const Vec3f = zm.vec.Vec3f;
/// f64
pub const Vec2 = zm.vec.Vec2;
/// i32
pub const IVec2 = zm.vec.Vec(2, i32);
/// u32
pub const UVec2 = zm.vec.Vec(2, u32);

// i32
pub const AABB = zm.aabb.AABBBase(2, i32);
pub const AABBf = zm.aabb.AABBBase(2, f32);

pub fn initABBFromCenter(comptime T: type, center: Vec(3, T), size: Vec(2, T)) zm.aabb.AABBBase(2, T) {
    const half_size = zm.vec.scale(size, 0.5);
    return zm.aabb.AABBBase(2, T){
        .min = zm.vec.xy(center) - half_size,
        .max = zm.vec.xy(center) + half_size,
    };
}
