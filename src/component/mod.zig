const std = @import("std");
const math = @import("../math.zig");

const Vec2f = math.Vec2f;

pub const Sprite = @import("Sprite.zig");
pub const Camera = @import("Camera.zig");
pub const Shape = @import("Shape.zig");
pub const Transform = @import("Transform.zig");
pub const VisibleEntities = @import("VisibleEntities.zig");
pub const Velocity = math.Vec2f;

test {
    _ = @import("Camera.zig");
    _ = @import("Shape.zig");
    _ = @import("Transform.zig");
    _ = @import("VisibleEntities.zig");
}

const Engine = @import("../Engine.zig");
const Time = @import("../resource/Time.zig");

pub fn physicsSystem(engine: *Engine) void {
    const time = engine.getResource(Time) orelse return;
    const dt: @Vector(2, f32) = @splat(time.delta);
    var q = engine.registry.view(.{ Transform, Velocity }, .{});
    var iter = q.entityIterator();

    while (iter.next()) |entity| {
        const transform = engine.registry.get(Transform, entity);
        const velocity = engine.registry.get(Velocity, entity);

        transform.position += velocity.* * dt;
    }
}

pub const Collider = struct {
    size: math.Vec2f,
};

pub fn collisionSystem(engine: *Engine) void {
    var query = engine.registry.view(.{ Transform, Collider, Velocity }, .{});
    var iter_a = query.entityIterator();

    while (iter_a.next()) |entity_a| {
        const transform_a = engine.registry.get(Transform, entity_a);
        const collider_a = engine.registry.get(Collider, entity_a);

        const aabb = math.AABBf.init(transform_a.position, collider_a.size);
        var iter_b = query.entityIterator();
        while (iter_b.next()) |entity_b| {
            if (entity_a == entity_b) continue;

            const transform_b = engine.registry.get(Transform, entity_b);
            const collider_b = engine.registry.get(Collider, entity_b);

            if (aabb.intersects(math.AABBf.init(transform_b.position, collider_b.size))) {
                const vel_a = engine.registry.get(Velocity, entity_a);
                const vel_b = engine.registry.get(Velocity, entity_b);
                vel_a[0] = 0;
                vel_a[1] = 0;
                vel_b[0] = 0;
                vel_b[1] = 0;
            }
            // if (checkAabbCollision(transform_a, collider_a, transform_b, collider_b)) {
            //     const vel_a = engine.registry.get(Velocity, entity_a);
            //     const vel_b = engine.registry.get(Velocity, entity_b);
            //     vel_a[0] = 0;
            //     vel_a[1] = 0;
            //     vel_b[0] = 0;
            //     vel_b[1] = 0;
            // }
        }
    }
}

fn checkAabbCollision(
    transform_a: *const Transform,
    collider_a: *const Collider,
    transform_b: *const Transform,
    collider_b: *const Collider,
) bool {
    const a_min_x = transform_a.position[0];
    const a_max_x = a_min_x + collider_a.size[0];
    const a_min_y = transform_a.position[1];
    const a_max_y = a_min_y + collider_a.size[1];

    const b_min_x = transform_b.position[0];
    const b_max_x = b_min_x + collider_b.size[0];
    const b_min_y = transform_b.position[1];
    const b_max_y = b_min_y + collider_b.size[1];

    return !(a_max_x < b_min_x or a_min_x > b_max_x or
        a_max_y < b_min_y or a_min_y > b_max_y);
}

fn sweepAabb(
    moving_pos: Vec2f,
    moving_size: Vec2f,
    motion: Vec2f,
    static_pos: Vec2f,
    static_size: Vec2f,
) ?struct {
    t: f32, // time of impact (0..1)
    normal: Vec2f,
} {
    // Compute expanded target box (static box enlarged by moving box)
    const expanded_pos = static_pos - moving_size;
    const expanded_size = static_size + moving_size;

    // Raycast moving point (the origin of moving box) against expanded box
    return raycastAabb(moving_pos, motion, expanded_pos, expanded_size);
}

fn raycastAabb(
    origin: Vec2f,
    dir: Vec2f,
    box_pos: Vec2f,
    box_size: Vec2f,
) ?struct {
    t: f32,
    normal: Vec2f,
} {
    const inv_dir_x = if (dir[0] != 0) 1.0 / dir[0] else 1e32;
    const inv_dir_y = if (dir[1] != 0) 1.0 / dir[1] else 1e32;

    const t1 = (box_pos[0] - origin[0]) * inv_dir_x;
    const t2 = (box_pos[0] + box_size[0] - origin[0]) * inv_dir_x;
    const t3 = (box_pos[1] - origin[1]) * inv_dir_y;
    const t4 = (box_pos[1] + box_size[1] - origin[1]) * inv_dir_y;

    const tmin = @max(@min(t1, t2), @min(t3, t4));
    const tmax = @min(@max(t1, t2), @max(t3, t4));

    if (tmax < 0 or tmin > tmax or tmin > 1) return null;

    // zig fmt: off
    const normal =
        if (tmin == t1) Vec2f{ -1, 0 }
        else if (tmin == t2) Vec2f{ 1, 0 }
        else if (tmin == t3) Vec2f{ 0, -1 }
        else if (tmin == t4) Vec2f{ 0, 1 }
        else Vec2f{ 0, 0 };

    return .{ .t = tmin, .normal = normal };
}

test "raycastAabb hits on right edge" {
    const origin = Vec2f{ -1, 0.5 };
    const dir = Vec2f{ 2, 0 };
    const box_pos = Vec2f{ 0, 0 };
    const box_size = Vec2f{ 1, 1 };

    const result = raycastAabb(origin, dir, box_pos, box_size);
    std.debug.assert(result != null);

    const hit = result.?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), hit.t, 0.0001);
    try std.testing.expectEqual(Vec2f{-1, 0}, hit.normal);
}

test "raycastAabb hits top edge" {
    const origin = Vec2f{0.5, -1};
    const dir = Vec2f{0, 2};
    const box_pos = Vec2f{0, 0};
    const box_size = Vec2f{1, 1};

    const result = raycastAabb(origin, dir, box_pos, box_size);
    std.debug.assert(result != null);

    const hit = result.?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), hit.t, 0.0001);
    try std.testing.expectEqual(Vec2f{0, -1}, hit.normal);
}

test "raycastAabb misses box" {
    // Moving down away from box
    const origin = Vec2f{ 2, 2 };
    const dir = Vec2f{ 0, 1 };
    const box_pos = Vec2f{ 0, 0 };
    const box_size = Vec2f{ 1, 1 };

    const result = raycastAabb(origin, dir, box_pos, box_size);
    try std.testing.expect(result == null);
}
