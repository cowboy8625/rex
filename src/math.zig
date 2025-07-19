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
