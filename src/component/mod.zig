const std = @import("std");
const math = @import("../math.zig");
const EventBus = @import("../resource/EventBus.zig");
const SpatialHashTable = @import("../SpatialHashTable.zig");
const entt = @import("entt");

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

pub const CollisionEvent = struct {
    pub const Side = enum { Left, Right, Top, Bottom };
    entity_1: entt.Entity,
    entity_2: entt.Entity,
    side: ?Side = null,
};

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
        const current_index = anim.currentFrameIndex();
        if (sprite.src_rect) |*rect| {
            const x_index: f32 = @floatFromInt(current_index % anim.horizontal_frames);
            const y_index: f32 = @floatFromInt(current_index / anim.horizontal_frames);
            rect.x = x_index * 12;
            rect.y = y_index * 12;
        }
    }
}

pub fn physicsSystem(engine: *Engine) void {
    const time = engine.getResource(Time) orelse return;
    const spatial_hash_table = engine.getResource(SpatialHashTable) orelse return;

    const friction: f32 = 0.9;
    const drag: @Vector(2, f32) = @splat(std.math.pow(f32, friction, time.delta * 60));

    const dt: @Vector(2, f32) = @splat(time.delta);
    var q = engine.registry.view(.{ Transform, Velocity }, .{});
    var iter = q.entityIterator();

    while (iter.next()) |entity| {
        const transform = engine.registry.get(Transform, entity);
        const old_pos = math.zm.vec.xy(transform.position);
        const velocity = engine.registry.get(Velocity, entity);

        velocity.* *= drag;

        const delta = math.zm.vec.xy(velocity.*) * dt;
        const new_pos = math.zm.vec.xy(transform.position) + delta;

        transform.position = math.Vec3f{ new_pos[0], new_pos[1], transform.position[2] };

        if (engine.registry.tryGetConst(Gravity, entity)) |gravity| {
            const scale = 400.0;
            velocity.*[0] += gravity.direction[0] * gravity.force * dt[0] * scale;
            velocity.*[1] += gravity.direction[1] * gravity.force * dt[0] * scale;
        }

        const new_transform_pos = math.zm.vec.xy(transform.position);
        if (spatial_hash_table.points_are_in_same_bucket(old_pos, new_transform_pos)) {
            continue;
        }
        const has_update_spatial_hash_table = engine.registry.has(SpatialHashTable.UpdateSpatialHashTable, entity);
        if (has_update_spatial_hash_table) continue;

        engine.registry.add(entity, SpatialHashTable.UpdateSpatialHashTable{});
    }
}

pub const Gravity = struct {
    direction: @Vector(2, f32) = @Vector(2, f32){ 0, 1 },
    force: f32 = 9.81,
};

pub const Collider = struct {
    size: math.Vec2f,
};

pub const StaticRigidBody = struct {};
pub const DynamicRigidBody = struct {};

fn projectVelocity(vel: *Velocity, normal: @Vector(2, f32)) void {
    const dot = vel.*[0] * normal[0] + vel.*[1] * normal[1];
    // only if moving into the surface
    if (dot < 0) {
        vel.*[0] -= dot * normal[0];
        vel.*[1] -= dot * normal[1];
    }
}

pub const PhysicsMaterial = struct {
    friction: f32, // 0.0 = ice, 1.0 = strong friction
};

fn applySurfaceFriction(vel: *Velocity, friction: f32, normal: @Vector(2, f32)) void {
    const tangent = if (normal[0] != 0)
        @Vector(2, f32){ 0, 1 }
    else
        @Vector(2, f32){ 1, 0 };

    const dot = vel.*[0] * tangent[0] + vel.*[1] * tangent[1];

    const friction_factor = std.math.clamp(1.0 - friction, 0.0, 1.0);
    const reduced = dot * friction_factor;

    vel.*[0] -= tangent[0] * (dot - reduced);
    vel.*[1] -= tangent[1] * (dot - reduced);
}

// I hate this code so much but it works and thats good enough for iteration one
// Idk, most of what i dont like about this function is the fact that it is so long
// BUT splitting it up would just make more call stacks.   I suppose you could inline them.
// Context is lost if you split it up maybe.
// TODO: Refactor into smaller functions but only if its the same speed or faster at run time.
pub fn collisionSystem(engine: *Engine) void {
    var query = engine.registry.view(.{ Transform, Collider, Velocity, DynamicRigidBody, PhysicsMaterial }, .{});
    var iter_a = query.entityIterator();
    var bus = engine.getResource(EventBus) orelse return;
    const spatial_hash_table = engine.getResource(SpatialHashTable) orelse return;

    while (iter_a.next()) |entity_a| {
        const transform_a = engine.registry.get(Transform, entity_a);
        const collider_a = engine.registry.get(Collider, entity_a);
        const vel_a = engine.registry.get(Velocity, entity_a);
        // const rb_a = engine.registry.get(DynamicRigidBody, entity_a);
        const mat_a = engine.registry.get(PhysicsMaterial, entity_a);

        const center_a = .{
            transform_a.position[0] + collider_a.size[0] / 2,
            transform_a.position[1] + collider_a.size[1] / 2,
            0,
        };
        const aabb_a = math.initABBFromCenter(f32, center_a, collider_a.size);
        const pos = math.zm.vec.xy(transform_a.position);
        const iter_b = spatial_hash_table.getBucketsAndNeighbors(pos) orelse continue;
        for (iter_b) |bucket| {
            if (bucket == null) continue;
            for (bucket.?) |entity_b| {
                if (entity_a == entity_b) continue;

                const transform_b = engine.registry.get(Transform, entity_b);
                const collider_b = engine.registry.get(Collider, entity_b);
                // const vel_b = engine.registry.get(Velocity, entity_b);
                // const rb_b = engine.registry.get(StaticRigidBody, entity_b);
                const mat_b = engine.registry.get(PhysicsMaterial, entity_b);

                const center_b = .{
                    transform_b.position[0] + collider_b.size[0] / 2,
                    transform_b.position[1] + collider_b.size[1] / 2,
                    0,
                };
                const aabb_b = math.initABBFromCenter(f32, center_b, collider_b.size);

                if (!aabb_a.intersects(aabb_b)) continue;

                const overlap_x = @min(aabb_a.max[0], aabb_b.max[0]) - @max(aabb_a.min[0], aabb_b.min[0]);
                const overlap_y = @min(aabb_a.max[1], aabb_b.max[1]) - @max(aabb_a.min[1], aabb_b.min[1]);

                // --- Helper: apply position + velocity fix ---
                const resolve = struct {
                    fn apply(
                        transform: *Transform,
                        vel: *Velocity,
                        mat: *const PhysicsMaterial,
                        other_mat: *const PhysicsMaterial,
                        center: @Vector(3, f32),
                        other_center: @Vector(3, f32),
                        olx: f32,
                        oly: f32,
                    ) void {
                        var normal: @Vector(2, f32) = .{ 0, 0 };

                        if (olx < oly) {
                            // --- Resolve X ---
                            if (center[0] < other_center[0]) {
                                transform.position[0] -= olx;
                                normal = .{ -1, 0 }; // hit from left
                            } else {
                                transform.position[0] += olx;
                                normal = .{ 1, 0 };
                            }
                        } else {
                            // --- Resolve Y ---
                            if (center[1] < other_center[1]) {
                                transform.position[1] -= oly;
                                normal = .{ 0, -1 }; // hit from below
                            } else {
                                transform.position[1] += oly;
                                normal = .{ 0, 1 };
                            }
                        }

                        projectVelocity(vel, normal);

                        // --- Apply friction along tangent ---
                        const combined_friction = (mat.friction + other_mat.friction) * 0.5;
                        applySurfaceFriction(vel, combined_friction, normal);
                    }
                }.apply;

                // --- resolution rules ---
                // if (rb_a.body_type == .static and rb_b.body_type == .static) {
                //     continue;
                // } else if (rb_a.body_type == .dynamic and rb_b.body_type == .static) {
                resolve(transform_a, vel_a, mat_a, mat_b, center_a, center_b, overlap_x, overlap_y);
                // } else if (rb_a.body_type == .static and rb_b.body_type == .dynamic) {
                // resolve(transform_b, vel_b, mat_b, mat_a, center_b, center_a, overlap_x, overlap_y);
                // } else if (rb_a.body_type == .dynamic and rb_b.body_type == .dynamic) {
                //
                //     // --- Split correction & clamp both velocities ---
                //     const half_x = overlap_x / 2;
                //     const half_y = overlap_y / 2;
                //
                //     if (overlap_x < overlap_y) {
                //         if (center_a[0] < center_b[0]) {
                //             transform_a.position[0] -= half_x;
                //             transform_b.position[0] += half_x;
                //             vel_a.*[0] = @max(vel_a.*[0], 0);
                //             vel_b.*[0] = @min(vel_b.*[0], 0);
                //             const combined_friction = (mat_a.friction + mat_b.friction) * 0.5;
                //             applySurfaceFriction(vel_a, combined_friction, .{ -1, 0 });
                //             applySurfaceFriction(vel_b, combined_friction, .{ 1, 0 });
                //         } else {
                //             transform_a.position[0] += half_x;
                //             transform_b.position[0] -= half_x;
                //             vel_a.*[0] = @min(vel_a.*[0], 0);
                //             vel_b.*[0] = @max(vel_b.*[0], 0);
                //             const combined_friction = (mat_a.friction + mat_b.friction) * 0.5;
                //             applySurfaceFriction(vel_a, combined_friction, .{ 1, 0 });
                //             applySurfaceFriction(vel_b, combined_friction, .{ -1, 0 });
                //         }
                //     } else {
                //         if (center_a[1] < center_b[1]) {
                //             transform_a.position[1] -= half_y;
                //             transform_b.position[1] += half_y;
                //             vel_a.*[1] = @max(vel_a.*[1], 0);
                //             vel_b.*[1] = @min(vel_b.*[1], 0);
                //             const combined_friction = (mat_a.friction + mat_b.friction) * 0.5;
                //             applySurfaceFriction(vel_a, combined_friction, .{ 0, -1 });
                //             applySurfaceFriction(vel_b, combined_friction, .{ 0, 1 });
                //         } else {
                //             transform_a.position[1] += half_y;
                //             transform_b.position[1] -= half_y;
                //             vel_a.*[1] = @min(vel_a.*[1], 0);
                //             vel_b.*[1] = @max(vel_b.*[1], 0);
                //             const combined_friction = (mat_a.friction + mat_b.friction) * 0.5;
                //             applySurfaceFriction(vel_a, combined_friction, .{ 0, 1 });
                //             applySurfaceFriction(vel_b, combined_friction, .{ 0, -1 });
                //         }
                //     }
                // }
                bus.emit(CollisionEvent, .{
                    .entity_1 = entity_a,
                    .entity_2 = entity_b,
                });
            }
        }
    }
}
