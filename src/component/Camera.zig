const math = @import("../math.zig");

const Camera = @This();

position: math.UVec2 = .{ 0, 0 },
size: math.UVec2 = .{ 0, 0 },
zoom: f32 = 1.0,

pub fn worldToCamera2d(self: *Camera, world_pos: math.Vec3f, cam_transform_pos: math.Vec3f) math.Vec2f {
    const screen_center = math.Vec2f{
        @floatFromInt(self.size[0] / 2),
        @floatFromInt(self.size[1] / 2),
    };

    const cam_pos = cam_transform_pos;
    return math.zm.vec.xy(world_pos - cam_pos) + screen_center;
}
