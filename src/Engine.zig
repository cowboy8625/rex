const std = @import("std");
const entt = @import("entt");
const sdl3 = @import("sdl3");
const math = @import("math.zig");
const cmp = @import("component/mod.zig");
const util = @import("util.zig");

pub const Color = sdl3.pixels.Color;

const Sprite = @import("component/mod.zig").Sprite;
const Transform = @import("component/mod.zig").Transform;
const Shape = @import("component/mod.zig").Shape;
const Camera = @import("component/mod.zig").Camera;
const VisibleEntities = @import("component/mod.zig").VisibleEntities;
const Collider = @import("component/mod.zig").Collider;
const StaticRigidBody = @import("component/mod.zig").StaticRigidBody;
const DynamicRigidBody = @import("component/mod.zig").DynamicRigidBody;

const AssetServer = @import("resource/mod.zig").AssetServer;
const EventBus = @import("resource/mod.zig").EventBus;
const Time = @import("resource/mod.zig").Time;
const Window = @import("resource/mod.zig").Window;
const SpatialHashTable = @import("SpatialHashTable.zig");

pub const Renderer = @import("render/sdl3.zig");

const Engine = @This();

pub const Options = struct {
    renderColliders: bool = false,
};

pub const Event = struct {
    pub const KeyReleased = struct {
        key: sdl3.keycode.Keycode,
    };
};

pub const SystemFn = *const fn (engine: *Engine) void;
pub const SystemType = enum {
    Update,
    Startup,
};

const ResourceBox = struct {
    type_id: usize,
    ptr: *anyopaque,
    deinitFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
};

// Required
allocator: std.mem.Allocator,
registry: entt.Registry,
renderer: Renderer,

// Defaults
update_systems: std.ArrayListUnmanaged(SystemFn) = .{},
startup_systems: std.ArrayListUnmanaged(SystemFn) = .{},

resources: std.AutoHashMapUnmanaged(usize, ResourceBox) = .{},

keys: [@typeInfo(sdl3.keycode.Keycode).@"enum".fields.len]bool =
    [_]bool{false} ** @typeInfo(sdl3.keycode.Keycode).@"enum".fields.len,

pub fn init(allocator: std.mem.Allocator) !Engine {
    var self = Engine{
        .allocator = allocator,
        .registry = entt.Registry.init(allocator),
        .renderer = Renderer.init() catch @panic("Failed to init renderer"),
    };

    self.addSystem(.Update, .{
        visibilitySystem,
        cmp.collisionSystem,
        cmp.physicsSystem,
        cmp.animateSystem,
        SpatialHashTable.spatialUpdateSystem,
    });

    try self.setupResources();

    return self;
}

pub fn deinit(self: *Engine) void {
    self.update_systems.deinit(self.allocator);
    self.startup_systems.deinit(self.allocator);

    var it = self.resources.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinitFn(entry.value_ptr.ptr, self.allocator);
    }
    self.resources.deinit(self.allocator);

    var entity_view = self.registry.view(.{VisibleEntities}, .{});
    var cam_iter = entity_view.entityIterator();
    while (cam_iter.next()) |e| {
        const visible = self.registry.get(VisibleEntities, e);
        visible.deinit(self.allocator);
    }
    self.registry.deinit();
    self.renderer.deinit();
}

pub fn spawn(self: *Engine, components: anytype) !entt.Entity {
    const entity = self.registry.create();
    inline for (components) |component| {
        if (@TypeOf(component) == Transform) {}
        self.registry.add(entity, component);
    }
    try self.add_to_spatial_hash_table(entity);
    return entity;
}

pub fn include(self: *Engine, entity: entt.Entity, components: anytype) !void {
    inline for (components) |component| {
        self.registry.add(entity, component);
    }
    try self.add_to_spatial_hash_table(entity);
}

fn add_to_spatial_hash_table(self: *Engine, entity: entt.Entity) !void {
    const has_camera = self.registry.has(Camera, entity);
    if (has_camera) return;

    const has_transform = self.registry.has(Transform, entity);
    if (!has_transform) return;

    const has_sprite = self.registry.has(Sprite, entity);
    const has_shape = self.registry.has(Shape, entity);
    if (!has_sprite and !has_shape) return;

    const has_collider = self.registry.has(Collider, entity);
    if (!has_collider) return;

    const has_dynamic_rigidbody = self.registry.has(DynamicRigidBody, entity);
    const has_static_rigidbody = self.registry.has(StaticRigidBody, entity);
    if (!has_dynamic_rigidbody and !has_static_rigidbody) return;

    const already_tagged = self.registry.has(SpatialHashTable.SpatialTag, entity);
    if (already_tagged) return;

    const spatial_hash_table = self.getResource(SpatialHashTable) orelse return error.MissingSpatialHashTableResource;
    const transform = self.registry.get(Transform, entity);
    const key = math.zm.vec.xy(transform.position);
    const bucket = spatial_hash_table.get(key);
    if (bucket) |b| {
        for (b) |e| {
            if (e == entity) return;
        }
    }

    try spatial_hash_table.insert(self.allocator, key, entity);
    self.registry.add(entity, SpatialHashTable.SpatialTag{
        .bucket = spatial_hash_table.hash(key),
    });
    // std.log.info("added entity {d} to spatial hash table", .{entity.index});
    //
    // var it = spatial_hash_table.data.iterator();
    // while (it.next()) |entry| {
    //     std.log.info("key: {any}, value: {any}", .{ entry.key_ptr.*, entry.value_ptr.* });
    // }
}

pub fn addSystem(self: *Engine, system_type: SystemType, systems: anytype) void {
    switch (system_type) {
        .Update => self.addUpdateSystem(systems),
        .Startup => self.addStartupSystem(systems),
    }
}

fn addUpdateSystem(self: *Engine, systems: anytype) void {
    const info = @typeInfo(@TypeOf(systems));
    switch (info) {
        .@"struct" => |s| {
            if (s.is_tuple) {
                inline for (systems) |system| {
                    self.update_systems.append(self.allocator, system) catch @panic("OOM");
                }
                return;
            }
        },
        else => {},
    }

    self.update_systems.append(self.allocator, systems) catch @panic("OOM");
}

fn addStartupSystem(self: *Engine, systems: anytype) void {
    const info = @typeInfo(@TypeOf(systems));
    switch (info) {
        .@"struct" => |s| {
            if (s.is_tuple) {
                inline for (systems) |system| {
                    self.startup_systems.append(self.allocator, system) catch @panic("OOM");
                }
                return;
            }
        },
        else => {},
    }

    self.startup_systems.append(self.allocator, systems) catch @panic("OOM");
}

pub fn insertResource(self: *Engine, value: anytype) void {
    const T = @TypeOf(value);
    const ptr = self.allocator.create(T) catch @panic("OOM");
    errdefer self.allocator.destroy(ptr);
    ptr.* = value;

    const type_id = util.getTypeKey(T);
    const box = ResourceBox{
        .type_id = type_id,
        .ptr = ptr,
        .deinitFn = struct {
            pub fn deinitFn(_ptr_: *anyopaque, allocator: std.mem.Allocator) void {
                const real_ptr: *T = @ptrCast(@alignCast(_ptr_));
                if (@hasDecl(T, "deinit")) {
                    real_ptr.deinit(allocator);
                }
                allocator.destroy(real_ptr);
            }
        }.deinitFn,
    };

    self.resources.put(self.allocator, type_id, box) catch @panic("OOM");
}

pub fn getResource(self: *Engine, comptime T: type) ?*T {
    const type_id = util.getTypeKey(T);
    if (self.resources.get(type_id)) |box| {
        return @ptrCast(@alignCast(box.ptr));
    }
    return null;
}

pub fn getResourceConst(self: *const Engine, comptime T: type) ?*const T {
    const type_id = util.getTypeKey(T);
    if (self.resources.get(type_id)) |box| {
        return @ptrCast(@alignCast(box.ptr));
    }
    return null;
}

fn runUpdateSystems(self: *Engine) void {
    for (self.update_systems.items) |system| {
        system(self);
    }
}

fn runStartupSystems(self: *Engine) void {
    for (self.startup_systems.items) |system| {
        system(self);
    }
}

pub fn isKeyPressed(self: *Engine, key: sdl3.keycode.Keycode) bool {
    return self.keys[@intFromEnum(key)];
}

fn setupResources(self: *Engine) !void {
    self.insertResource(Time{ .delta = 0, .total = 0 });
    const size = try self.renderer.getWindowSize();
    self.insertResource(Window{ .size = size });
    self.insertResource(AssetServer.init(self.allocator));
    self.insertResource(EventBus.init(self.allocator));
    self.insertResource(SpatialHashTable.init(self.allocator, .{ 12, 12 }));
}

pub fn run(self: *Engine, comptime options: Options) !void {
    var last_counter: u64 = sdl3.timer.getPerformanceCounter();
    const freq: u64 = sdl3.timer.getPerformanceFrequency();

    var is_running = true;

    self.runStartupSystems();

    while (is_running) {
        const current_counter = sdl3.timer.getPerformanceCounter();
        const delta: u64 = current_counter - last_counter;
        last_counter = current_counter;

        const dt = @as(f32, @floatFromInt(delta)) / @as(f32, @floatFromInt(freq));
        const time = self.getResource(Time) orelse return error.MissingResource;
        time.delta = dt;
        time.total += dt;

        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit, .terminating => {
                    is_running = false;
                    break;
                },
                .key_down => |key_down| if (key_down.key) |key| {
                    if (key == .escape) {
                        is_running = false;
                        break;
                    }
                    self.keys[@intFromEnum(key)] = true;
                },
                .key_up => |key_up| if (key_up.key) |key| {
                    self.keys[@intFromEnum(key)] = false;
                    const bus = self.getResource(EventBus) orelse return error.MissingResource;
                    bus.emit(Event.KeyReleased, .{ .key = key });
                },
                else => {},
            }
        }

        self.runUpdateSystems();

        try self.renderer.renderStart();

        try self.renderSystem(options);

        try self.renderer.renderEnd();

        var bus = self.getResource(EventBus) orelse return error.MissingResource;
        bus.clear();
    }
}

pub fn renderColliderSystem(engine: *Engine) !void {
    var cam_query = engine.registry.view(.{ Camera, Transform }, .{});
    var cam_iter = cam_query.entityIterator();
    const cam_entity = cam_iter.next() orelse return;
    const cam_transform = engine.registry.get(Transform, cam_entity);
    const cam = engine.registry.get(Camera, cam_entity);
    const screen_center = math.Vec2f{
        @floatFromInt(cam.size[0] / 2),
        @floatFromInt(cam.size[1] / 2),
    };

    var query = engine.registry.view(.{ Transform, Collider }, .{});
    var iter = query.entityIterator();

    while (iter.next()) |e| {
        const transform = engine.registry.get(Transform, e);
        const collider = engine.registry.get(Collider, e);

        const world_pos = transform.position;
        const cam_pos = cam_transform.position;
        const draw_pos = math.zm.vec.xy(world_pos - cam_pos) + screen_center;

        const rect = sdl3.rect.FRect{
            .x = draw_pos[0],
            .y = draw_pos[1],
            .w = collider.size[0],
            .h = collider.size[1],
        };

        const color = sdl3.pixels.Color{
            .r = 0,
            .g = 129,
            .b = 129,
            .a = 99,
        };

        try engine.renderer.rect(rect, color);
    }
}

fn drawCollider(
    engine: *Engine,
    e: entt.Entity,
    transform: *const Transform,
    cam_transform: *const Transform,
    screen_center: math.Vec2f,
) !void {
    if (!engine.registry.has(Collider, e)) return;

    const collider = engine.registry.get(Collider, e);
    const world_pos = transform.position;
    const cam_pos = cam_transform.position;
    const draw_pos = math.zm.vec.xy(world_pos - cam_pos) + screen_center;

    const rect = sdl3.rect.FRect{
        .x = draw_pos[0],
        .y = draw_pos[1],
        .w = collider.size[0],
        .h = collider.size[1],
    };

    const color = sdl3.pixels.Color{
        .r = 0,
        .g = 0,
        .b = 255,
        .a = 99,
    };

    try engine.renderer.rect(rect, color);
}

fn renderSystem(self: *Engine, comptime options: Options) !void {
    var cam_query = self.registry.view(.{ Camera, Transform, VisibleEntities }, .{});
    var cam_iter = cam_query.entityIterator();
    const cam_entity = cam_iter.next() orelse return;
    const cam_transform = self.registry.get(Transform, cam_entity);
    const cam = self.registry.get(Camera, cam_entity);
    const visible = self.registry.get(VisibleEntities, cam_entity);

    const screen_center = math.Vec2f{
        @floatFromInt(cam.size[0] / 2),
        @floatFromInt(cam.size[1] / 2),
    };

    const asset_server = self.getResourceConst(AssetServer) orelse return error.MissingResource;
    for (visible.list.items) |e| {
        if (self.registry.has(Sprite, e)) {
            const transform = self.registry.get(Transform, e);
            const sprite = self.registry.getConst(Sprite, e);

            const draw_pos = cam.worldToCamera2d(transform.position, cam_transform.position);

            const r = self.renderer.renderer;

            const texture = asset_server.get(sprite.asset_name) orelse {
                std.log.err("Texture not found: {s}", .{@tagName(sprite.asset_name)});
                @panic("Texture not found");
            };

            const size = sprite.size * transform.scale * @Vector(2, f32){ cam.zoom, cam.zoom };

            const rect = sdl3.rect.FRect{
                .x = draw_pos[0],
                .y = draw_pos[1],
                .w = size[0],
                .h = size[1],
            };

            try r.renderTexture(texture, sprite.src_rect, rect);

            if (options.renderColliders) try drawCollider(self, e, transform, cam_transform, screen_center);
        } else if (self.registry.has(Shape, e)) {
            const transform = self.registry.get(Transform, e);
            const shape = self.registry.getConst(Shape, e);

            const world_pos = transform.position;
            const cam_pos = cam_transform.position;
            const draw_pos = math.zm.vec.xy(world_pos - cam_pos) + screen_center;

            switch (shape.kind) {
                .Rect => {
                    const rect = sdl3.rect.FRect{
                        .x = draw_pos[0],
                        .y = draw_pos[1],
                        .w = shape.size[0],
                        .h = shape.size[1],
                    };
                    try self.renderer.rect(rect, shape.color);
                },
            }
            if (options.renderColliders) try drawCollider(self, e, transform, cam_transform, screen_center);
        }
    }
}

fn visibilitySystem(engine: *Engine) void {
    var cam_view = engine.registry.view(.{ Camera, Transform, VisibleEntities }, .{});
    var render_view = engine.registry.view(.{Transform}, .{});

    var cam_iter = cam_view.entityIterator();

    while (cam_iter.next()) |cam_entity| {
        const cam_transform = engine.registry.getConst(Transform, cam_entity);
        const camera = engine.registry.getConst(Camera, cam_entity);
        const visible = engine.registry.get(VisibleEntities, cam_entity);
        visible.list.clearRetainingCapacity();

        const camera_size = math.Vec2f{ @as(f32, @floatFromInt(camera.size[0])), @as(f32, @floatFromInt(camera.size[1])) };
        const cam_bounds = math.initABBFromCenter(f32, cam_transform.position, camera_size);

        var render_iter = render_view.entityIterator();
        while (render_iter.next()) |shape_entity| {
            const transform = engine.registry.get(Transform, shape_entity);
            const hasShape = engine.registry.has(Shape, shape_entity);
            const hasSprite = engine.registry.has(Sprite, shape_entity);

            if (!hasShape and !hasSprite) {
                continue;
            }

            const size = if (hasShape)
                engine.registry.getConst(Shape, shape_entity).size
            else
                engine.registry.getConst(Sprite, shape_entity).size;

            const shape_bounds = math.initABBFromCenter(f32, transform.position, size);
            if (!shape_bounds.intersects(cam_bounds)) {
                continue;
            }
            visible.list.append(engine.allocator, shape_entity) catch @panic("Out of memory");
        }

        std.mem.sort(entt.Entity, visible.list.items, engine, struct {
            fn lessThan(e: *Engine, a: entt.Entity, b: entt.Entity) bool {
                const a_z = e.registry.get(Transform, a).position[2];
                const b_z = e.registry.get(Transform, b).position[2];
                return a_z < b_z;
            }
        }.lessThan);
    }
}
