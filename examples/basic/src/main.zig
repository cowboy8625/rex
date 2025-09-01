const std = @import("std");
const rex = @import("rex");

// You could make a builder to make things a bit simpler when it
// comes to creating a complex set of entities
pub const EntityBuilder = struct {
    transform: rex.Transform = .{
        .position = .{ 0, 0, 0 },
        .rotation = 0,
        .scale = .{ 1, 1 },
    },
    velocity: rex.Velocity = .{ 0, 0 },
    shape: rex.Shape = .{
        .kind = .Rect,
        .color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .size = .{ 50, 50 },
    },
    collider: rex.Collider = .{
        .size = .{ 50, 50 },
    },
    rigid_body: rex.RigidBody = .{
        .body_type = .static,
    },
    material: rex.PhysicsMaterial = .{
        .friction = 0.5,
    },

    pub fn init() EntityBuilder {
        return EntityBuilder{};
    }

    pub fn setPosition(self: *EntityBuilder, pos: rex.math.Vec3f) void {
        self.transform.position = pos;
    }

    pub fn setSize(self: *EntityBuilder, size: rex.math.Vec2f) void {
        self.shape.size = size;
        self.collider.size = size;
    }

    pub fn setColor(self: *EntityBuilder, color: rex.Color) void {
        self.shape.color = color;
    }

    pub fn setBodyType(self: *EntityBuilder, body_type: rex.RigidBody.BodyType) void {
        self.rigid_body.body_type = body_type;
    }

    pub fn setFriction(self: *EntityBuilder, friction: f32) void {
        self.material.friction = friction;
    }

    pub fn setVelocity(self: *EntityBuilder, vel: rex.Velocity) void {
        self.velocity = vel;
    }

    pub fn build(self: *EntityBuilder, engine: *rex.Engine) void {
        _ = engine.spawn(.{
            self.transform,
            self.velocity,
            self.shape,
            self.collider,
            self.rigid_body,
            self.material,
        });
    }
};

const Player = struct {
    grounded: bool = false,
};

fn setup(engine: *rex.Engine) void {
    const window = engine.getResourceConst(rex.Window) orelse return;
    const asset_server = engine.getResource(rex.AssetServer) orelse @panic("no asset server");

    asset_server.load(&engine.renderer.renderer, .idle) catch @panic("asset load failed");

    // Player
    _ = engine.spawn(
        .{
            rex.Transform{
                .position = rex.math.Vec3f{
                    @floatFromInt(window.size[0] / 3),
                    @floatFromInt(window.size[1] / 2),
                    -1,
                },
                .rotation = 0,
                .scale = rex.math.Vec2f{ 1, 1 },
            },
            rex.Velocity{ 0, 0 },
            rex.Sprite{
                .asset_name = .idle,
                .origin = .{ 0, 0 },
                .src_rect = .{
                    .x = 0,
                    .y = 0,
                    .w = 32,
                    .h = 64,
                },
                .size = .{ 32, 64 },
            },
            rex.Animation{
                .horizontal_frames = 2,
                .vertical_frames = 1,
                .speed = 0.3,
            },
            rex.Collider{
                .size = rex.math.Vec2f{ 32, 64 },
            },
            rex.RigidBody{
                .body_type = .dynamic,
            },
            rex.PhysicsMaterial{
                .friction = 0.0,
            },
            Player{},
            rex.Gravity{},
        },
    );

    // Camera
    _ = engine.spawn(.{
        rex.Transform{
            .position = rex.math.Vec3f{
                @floatFromInt(window.size[0] / 2),
                @floatFromInt(window.size[1] / 2),
                0,
            },
            .rotation = 0,
            .scale = rex.math.Vec2f{ 1, 1 },
        },
        rex.Velocity{ 0, 0 },
        rex.Camera{
            .position = rex.math.Vec2f{ 0, 0 },
            .size = rex.math.UVec2{
                @intCast(window.size[0]),
                @intCast(window.size[1]),
            },
            .zoom = 1.0,
        },
        rex.VisibleEntities{},
    });

    var block1 = EntityBuilder.init();
    block1.setPosition(.{ @floatFromInt(window.size[0] / 2), @floatFromInt(window.size[1] / 2), 0 });
    block1.setSize(.{ 100, 100 });
    block1.setColor(.{ .r = 255, .g = 0, .b = 0, .a = 255 });
    block1.setBodyType(.static);
    block1.setFriction(1.0);
    block1.build(engine);

    var block2 = EntityBuilder.init();
    block2.setPosition(.{ @floatFromInt(window.size[0] / 3), @floatFromInt(window.size[1] / 3), 0 });
    block2.setSize(.{ 100, 100 });
    block2.setColor(.{ .r = 0, .g = 128, .b = 128, .a = 255 });
    block2.setBodyType(.static);
    block2.setFriction(0.0);
    block2.build(engine);

    var block3 = EntityBuilder.init();
    block3.setPosition(.{ @floatFromInt(window.size[0] / 8), @floatFromInt(window.size[1] / 3), 0 });
    block3.setSize(.{ 50, 50 });
    block3.setColor(.{ .r = 200, .g = 128, .b = 128, .a = 255 });
    block3.setBodyType(.dynamic);
    block3.setFriction(1.0);
    block3.build(engine);

    var block4 = EntityBuilder.init();
    block4.setPosition(.{ 0, 0, 0 });
    block4.setSize(.{ 50, 50 });
    block4.setColor(.{ .r = 250, .g = 188, .b = 188, .a = 255 });
    block4.setBodyType(.dynamic);
    block4.setFriction(1.0);
    block4.build(engine);

    var floor = EntityBuilder.init();
    floor.setPosition(.{
        0,
        @as(f32, @floatFromInt(window.size[1])) - 25,
        0,
    });
    floor.setSize(.{ @floatFromInt(window.size[0]), 50 });
    floor.setColor(.{ .r = 100, .g = 100, .b = 100, .a = 255 });
    floor.setBodyType(.static);
    floor.setFriction(0.0);
    floor.build(engine);
}

fn cameraFollowPlayerSystem(engine: *rex.Engine) void {
    var camera_query = engine.registry.view(.{ rex.Transform, rex.Camera }, .{});
    var player_query = engine.registry.view(.{ rex.Transform, Player }, .{});
    var cam_iter = camera_query.entityIterator();
    var player_iter = player_query.entityIterator();
    while (cam_iter.next()) |cam_entity| {
        const cam_transform = engine.registry.get(rex.Transform, cam_entity);
        const current = rex.math.zm.vec.xy(cam_transform.position);
        while (player_iter.next()) |player_entity| {
            const player_transform = engine.registry.get(rex.Transform, player_entity);
            const target = rex.math.zm.vec.xy(player_transform.position);
            const new_pos = rex.math.zm.vec.lerp(current, target, 0.08);
            cam_transform.position = rex.math.Vec3f{ new_pos[0], new_pos[1], cam_transform.position[2] };
        }
    }
}

fn controlPlayerSystem(engine: *rex.Engine) void {
    var player_query = engine.registry.view(.{
        rex.Velocity,
        Player,
    }, .{});
    var q_iter = player_query.entityIterator();
    const player_id = q_iter.next() orelse return;
    const player = engine.registry.get(Player, player_id);
    const vel = engine.registry.get(rex.Velocity, player_id);

    var v = rex.Velocity{ 0, 0 };

    if (engine.isKeyPressed(.w)) {
        v[1] -= 100;
    }

    if (engine.isKeyPressed(.s)) {
        v[1] += 100;
    }

    if (engine.isKeyPressed(.a)) {
        v[0] -= 100;
    }
    if (engine.isKeyPressed(.d)) {
        v[0] += 100;
    }

    if (engine.isKeyPressed(.space) and player.grounded) {
        vel.* = .{
            1,
            -1600,
        };
        return;
    }

    if (v[0] == 0 and v[1] == 0) {
        return;
    }

    vel.* += v;
}

fn updatePlayerIsGround(engine: *rex.Engine) void {
    var player_query = engine.registry.view(.{
        Player,
    }, .{});

    const bus = engine.getResource(rex.EventBus) orelse return;

    var q_iter = player_query.entityIterator();
    const player_id = q_iter.next() orelse return;
    var player = engine.registry.get(Player, player_id);

    player.grounded = false;
    for (bus.read(rex.CollisionEvent)) |event| {
        if (event.entity_1 != player_id and event.entity_2 != player_id) {
            continue;
        }
        player.grounded = true;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var engine = try rex.Engine.init(allocator);
    defer engine.deinit();

    engine.addSystem(.Startup, .{setup});
    engine.addSystem(.Update, .{
        controlPlayerSystem,
        // cameraFollowPlayerSystem,
        updatePlayerIsGround,
    });

    try engine.run(.{
        .renderColliders = false,
    });
}
