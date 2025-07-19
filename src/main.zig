const std = @import("std");
const rex = @import("rex");

const Player = struct {};

fn setup(engine: *rex.Engine) void {
    const window = engine.getResourceConst(rex.Window) orelse return;
    const asset_server = engine.getResource(rex.AssetServer) orelse @panic("no asset server");

    asset_server.load(&engine.renderer.renderer, .idle) catch @panic("asset load failed");

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
            Animation{
                .horizontal_frames = 2,
                .vertical_frames = 1,
            },
            Player{},
        },
    );

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
    _ = engine.spawn(
        .{
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
            rex.Shape{
                .kind = .Rect,
                .color = rex.Color{ .r = 255, .g = 0, .b = 0, .a = 255 },
                .size = rex.math.Vec2f{ 100, 100 },
            },
            rex.Collider{
                .size = rex.math.Vec2f{ 100, 100 },
            },
        },
    );

    _ = engine.spawn(
        .{
            rex.Transform{
                .position = rex.math.Vec3f{
                    @floatFromInt(window.size[0] / 3),
                    @floatFromInt(window.size[1] / 3),
                    0,
                },
                .rotation = 0,
                .scale = rex.math.Vec2f{ 1, 1 },
            },
            rex.Velocity{ 0, 0 },
            rex.Shape{
                .kind = .Rect,
                .color = rex.Color{ .r = 0, .g = 128, .b = 128, .a = 255 },
                .size = rex.math.Vec2f{ 100, 100 },
            },
            rex.Collider{
                .size = rex.math.Vec2f{ 100, 100 },
            },
        },
    );
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
            const new_pos = rex.math.zm.vec.lerp(current, target, 0.1);
            cam_transform.position = rex.math.Vec3f{ new_pos[0], new_pos[1], cam_transform.position[2] };
        }
    }
}

fn controlPlayerSystem(engine: *rex.Engine) void {
    var v = rex.Velocity{ 0, 0 };
    if (engine.isKeyPressed(.w)) {
        v[1] -= 1;
    }
    if (engine.isKeyPressed(.s)) {
        v[1] += 1;
    }
    if (engine.isKeyPressed(.a)) {
        v[0] -= 1;
    }
    if (engine.isKeyPressed(.d)) {
        v[0] += 1;
    }

    if (engine.isKeyPressed(.space)) {
        var q = engine.registry.view(.{
            rex.Velocity,
            Player,
        }, .{});

        var q_iter = q.entityIterator();
        while (q_iter.next()) |e| {
            const vel = engine.registry.get(rex.Velocity, e);
            vel.* = v;
        }
        return;
    }

    if (v[0] == 0 and v[1] == 0) {
        return;
    }

    var q = engine.registry.view(.{
        rex.Velocity,
        Player,
    }, .{});

    var q_iter = q.entityIterator();
    while (q_iter.next()) |e| {
        const vel = engine.registry.get(rex.Velocity, e);
        vel.* += v;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var engine = rex.Engine.init(allocator);
    defer engine.deinit();

    engine.addSystem(.Startup, .{setup});
    engine.addSystem(.Update, .{
        controlPlayerSystem,
        cameraFollowPlayerSystem,
        animateSystem,
    });

    try engine.run();
}
