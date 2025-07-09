const math = @import("../math.zig");
pub const Camera = @import("Camera.zig");
pub const Shape = @import("Shape.zig");
pub const Transform = @import("Transform.zig");
pub const VisibleEntities = @import("VisibleEntities.zig");
pub const Velocity = math.Vec2f;

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
