const std = @import("std");
const math = @import("../math.zig");

const Vec2f = math.Vec2f;

pub const Animation = @import("Animation.zig");
pub const Camera = @import("Camera.zig");
pub const Shape = @import("Shape.zig");
pub const Sprite = @import("Sprite.zig");
pub const Transform = @import("Transform.zig");
pub const VisibleEntities = @import("VisibleEntities.zig");
pub const Velocity = math.Vec2f;

test {
    _ = @import("Animation.zig");
    _ = @import("Camera.zig");
    _ = @import("Shape.zig");
    _ = @import("Sprite.zig");
    _ = @import("Transform.zig");
    _ = @import("VisibleEntities.zig");
}

const Engine = @import("../Engine.zig");
const Time = @import("../resource/Time.zig");

pub fn animateSystem(engine: *Engine) void {
    const time = engine.getResourceConst(Time) orelse return;
    var q = engine.registry.view(.{ Animation, Sprite }, .{});
    var q_iter = q.entityIterator();
    while (q_iter.next()) |e| {
        const anim = engine.registry.get(Animation, e);
        anim.update(time.delta);
        const sprite = engine.registry.get(Sprite, e);
        if (sprite.src_rect) |*rect| {
            const x_index: f32 = @floatFromInt(anim.frame % anim.horizontal_frames);
            const y_index: f32 = @floatFromInt(anim.frame / anim.horizontal_frames);
            rect.x = x_index * rect.w;
            rect.y = y_index * rect.h;
        }
    }
}

pub fn physicsSystem(engine: *Engine) void {
    const time = engine.getResource(Time) orelse return;
    const dt: @Vector(2, f32) = @splat(time.delta);
    var q = engine.registry.view(.{ Transform, Velocity }, .{});
    var iter = q.entityIterator();

    while (iter.next()) |entity| {
        const transform = engine.registry.get(Transform, entity);
        const velocity = engine.registry.get(Velocity, entity);

        const delta = math.zm.vec.xy(velocity.*) * dt;
        const new_pos = math.zm.vec.xy(transform.position) + delta;

        transform.position = math.Vec3f{ new_pos[0], new_pos[1], transform.position[2] };
    }
}

pub const Collider = struct {
    size: math.Vec2f,
};

pub const RigidBody = struct {
    pub const BodyType = enum { static, dynamic };
    body_type: BodyType,
};

fn projectVelocity(vel: *Velocity, normal: @Vector(2, f32)) void {
    const dot = vel.*[0] * normal[0] + vel.*[1] * normal[1];
    // only if moving into the surface
    if (dot < 0) {
        vel.*[0] -= dot * normal[0];
        vel.*[1] -= dot * normal[1];
    }
}

// I hate this code so much but it works and thats good enough for iteration one
pub fn collisionSystem(engine: *Engine) void {
    var query = engine.registry.view(.{ Transform, Collider, Velocity, RigidBody }, .{});
    var iter_a = query.entityIterator();

    while (iter_a.next()) |entity_a| {
        const transform_a = engine.registry.get(Transform, entity_a);
        const collider_a = engine.registry.get(Collider, entity_a);
        const vel_a = engine.registry.get(Velocity, entity_a);
        const rb_a = engine.registry.get(RigidBody, entity_a);

        const center_a = .{
            transform_a.position[0] + collider_a.size[0] / 2,
            transform_a.position[1] + collider_a.size[1] / 2,
            0,
        };
        const aabb_a = math.initABBFromCenter(f32, center_a, collider_a.size);

        var iter_b = query.entityIterator();
        while (iter_b.next()) |entity_b| {
            if (entity_a == entity_b) continue;

            const transform_b = engine.registry.get(Transform, entity_b);
            const collider_b = engine.registry.get(Collider, entity_b);
            const vel_b = engine.registry.get(Velocity, entity_b);
            const rb_b = engine.registry.get(RigidBody, entity_b);

            const center_b = .{
                transform_b.position[0] + collider_b.size[0] / 2,
                transform_b.position[1] + collider_b.size[1] / 2,
                0,
            };
            const aabb_b = math.initABBFromCenter(f32, center_b, collider_b.size);

            if (!aabb_a.intersects(aabb_b)) continue;

            const overlap_x = @min(aabb_a.max[0], aabb_b.max[0]) - @max(aabb_a.min[0], aabb_b.min[0]);
            const overlap_y = @min(aabb_a.max[1], aabb_b.max[1]) - @max(aabb_a.min[1], aabb_b.min[1]);

            // Helper: apply position + velocity fix
            const resolve = struct {
                fn apply(transform: *Transform, vel: *Velocity, center: @Vector(3, f32), other_center: @Vector(3, f32), olx: f32, oly: f32) void {
                    if (olx < oly) {
                        // Resolve X
                        if (center[0] < other_center[0]) {
                            transform.position[0] -= olx;
                            projectVelocity(vel, .{ -1, 0 }); // hit from left, normal = (-1,0)
                        } else {
                            transform.position[0] += olx;
                            projectVelocity(vel, .{ 1, 0 });
                        }
                    } else {
                        // Resolve Y
                        if (center[1] < other_center[1]) {
                            transform.position[1] -= oly;
                            projectVelocity(vel, .{ 0, -1 }); // hit from below
                        } else {
                            transform.position[1] += oly;
                            projectVelocity(vel, .{ 0, 1 }); // hit from above
                        }
                    }
                }
            }.apply;

            // --- resolution rules ---
            if (rb_a.body_type == .static and rb_b.body_type == .static) {
                continue;
            } else if (rb_a.body_type == .dynamic and rb_b.body_type == .static) {
                resolve(transform_a, vel_a, center_a, center_b, overlap_x, overlap_y);
            } else if (rb_a.body_type == .static and rb_b.body_type == .dynamic) {
                resolve(transform_b, vel_b, center_b, center_a, overlap_x, overlap_y);
            } else if (rb_a.body_type == .dynamic and rb_b.body_type == .dynamic) {
                // Split correction & clamp both velocities
                const half_x = overlap_x / 2;
                const half_y = overlap_y / 2;

                if (overlap_x < overlap_y) {
                    if (center_a[0] < center_b[0]) {
                        transform_a.position[0] -= half_x;
                        transform_b.position[0] += half_x;
                        vel_a.*[0] = @max(vel_a.*[0], 0);
                        vel_b.*[0] = @min(vel_b.*[0], 0);
                    } else {
                        transform_a.position[0] += half_x;
                        transform_b.position[0] -= half_x;
                        vel_a.*[0] = @min(vel_a.*[0], 0);
                        vel_b.*[0] = @max(vel_b.*[0], 0);
                    }
                } else {
                    if (center_a[1] < center_b[1]) {
                        transform_a.position[1] -= half_y;
                        transform_b.position[1] += half_y;
                        vel_a.*[1] = @max(vel_a.*[1], 0);
                        vel_b.*[1] = @min(vel_b.*[1], 0);
                    } else {
                        transform_a.position[1] += half_y;
                        transform_b.position[1] -= half_y;
                        vel_a.*[1] = @min(vel_a.*[1], 0);
                        vel_b.*[1] = @max(vel_b.*[1], 0);
                    }
                }
            }
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
