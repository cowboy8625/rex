const std = @import("std");
const entt = @import("entt");
const sdl3 = @import("sdl3");
const math = @import("math.zig");
const cmp = @import("component/mod.zig");

pub const Color = @import("render/Color.zig");
pub const Transform = @import("component/Transform.zig");
pub const Shape = @import("component/Shape.zig");
pub const Camera = @import("component/Camera.zig");
pub const VisibleEntities = @import("component/VisibleEntities.zig");
pub const Time = @import("resource/Time.zig");
pub const Window = @import("resource/Window.zig");
const Renderer = @import("render/sdl3.zig");
const Rect = @import("render/rect.zig").Rect;

const Engine = @This();

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

pub fn init(allocator: std.mem.Allocator) Engine {
    return Engine{
        .allocator = allocator,
        .registry = entt.Registry.init(allocator),
        .renderer = Renderer.init(allocator) catch @panic("Failed to init Renderer"),
    };
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
}

pub fn spawn(self: *Engine, components: anytype) entt.Entity {
    const entity = self.registry.create();
    inline for (components) |component| {
        self.registry.add(entity, component);
    }
    return entity;
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
    ptr.* = value;

    const type_id = getTypeKey(T);
    const box = ResourceBox{
        .type_id = type_id,
        .ptr = ptr,
        .deinitFn = struct {
            pub fn deinitFn(_ptr_: *anyopaque, allocator: std.mem.Allocator) void {
                const real_ptr: *T = @alignCast(@ptrCast(_ptr_));
                allocator.destroy(real_ptr);
            }
        }.deinitFn,
    };

    self.resources.put(self.allocator, type_id, box) catch @panic("OOM");
}

pub fn getResource(self: *Engine, comptime T: type) ?*T {
    const type_id = getTypeKey(T);
    if (self.resources.get(type_id)) |box| {
        return @alignCast(@ptrCast(box.ptr));
    }
    return null;
}

pub fn getResourceConst(self: *const Engine, comptime T: type) ?*const T {
    const type_id = getTypeKey(T);
    if (self.resources.get(type_id)) |box| {
        return @alignCast(@ptrCast(box.ptr));
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
    self.insertResource(Window{ .size = math.Vec(2, usize){ size.width, size.height } });
}

pub fn run(self: *Engine) !void {
    var last_counter: u64 = sdl3.timer.getPerformanceCounter();
    const freq: u64 = sdl3.timer.getPerformanceFrequency();

    self.addSystem(.Update, .{
        visibilitySystem,
        cmp.physicsSystem,
        cmp.collisionSystem,
    });

    try self.setupResources();
    self.runStartupSystems();
    while (true) {
        const current_counter = sdl3.timer.getPerformanceCounter();
        const delta: u64 = current_counter - last_counter;
        last_counter = current_counter;

        const dt = @as(f32, @floatFromInt(delta)) / @as(f32, @floatFromInt(freq));
        const time = self.getResource(Time) orelse return error.MissingResource;
        time.delta = dt;
        time.total += dt;

        if (sdl3.events.poll()) |event| {
            switch (event) {
                .quit => break,
                .terminating => break,
                .key_down => |key_down| if (key_down.key) |key| {
                    if (key == .escape) break;
                    self.keys[@intFromEnum(key)] = true;
                },
                .key_up => |key_up| if (key_up.key) |key| {
                    self.keys[@intFromEnum(key)] = false;
                },
                else => {},
            }
        }

        self.runUpdateSystems();

        try self.renderer.renderStart();

        try self.renderShapeSystem();

        try self.renderer.renderEnd();
    }
}

fn renderShapeSystem(self: *Engine) !void {
    var cam_query = self.registry.view(.{ Camera, Transform }, .{});
    var cam_iter = cam_query.entityIterator();
    const cam_entity = cam_iter.next() orelse return;
    const cam_transform = self.registry.get(Transform, cam_entity);
    const cam = self.registry.get(Camera, cam_entity);

    const screen_center = math.Vec2f{
        @floatFromInt(cam.size[0] / 2),
        @floatFromInt(cam.size[1] / 2),
    };

    // Draw shapes
    var q = self.registry.view(.{ Transform, Shape }, .{});
    var q_iter = q.entityIterator();
    while (q_iter.next()) |e| {
        const transform = self.registry.get(Transform, e);
        const shape = self.registry.getConst(Shape, e);

        // Compute position relative to camera
        const world_pos = transform.position;
        const cam_pos = cam_transform.position;
        const draw_pos = (world_pos - cam_pos) + screen_center;

        switch (shape.kind) {
            .Rect => {
                const rect = Rect(f32){
                    .x = draw_pos[0],
                    .y = draw_pos[1],
                    .width = shape.size[0],
                    .height = shape.size[1],
                };
                try self.renderer.rect(rect, shape.color);
            },
        }
    }
}

fn visibilitySystem(engine: *Engine) void {
    var cam_view = engine.registry.view(.{ Camera, Transform, VisibleEntities }, .{});
    var shape_view = engine.registry.view(.{ Transform, Shape }, .{});

    var cam_iter = cam_view.entityIterator();
    while (cam_iter.next()) |cam_entity| {
        const cam_transform = engine.registry.getConst(Transform, cam_entity);
        const camera = engine.registry.getConst(Camera, cam_entity);
        const visible = engine.registry.get(VisibleEntities, cam_entity);
        visible.list.clearRetainingCapacity();

        const camera_size = math.Vec2f{ @as(f32, @floatFromInt(camera.size[0])), @as(f32, @floatFromInt(camera.size[1])) };
        const cam_bounds = math.AABBf.init(cam_transform.position, camera_size);

        var shape_iter = shape_view.entityIterator();
        while (shape_iter.next()) |shape_entity| {
            if (engine.registry.has(@import("component/mod.zig").Collider, shape_entity)) {
                std.log.warn("Visibility system does not support colliders", .{});
            }
            const shape_transform = engine.registry.get(Transform, shape_entity);
            const shape = engine.registry.getConst(Shape, shape_entity);
            const shape_bounds = math.AABBf.init(shape_transform.position, shape.size);

            if (!cam_bounds.intersects(shape_bounds)) {
                continue;
            }
            visible.list.append(engine.allocator, shape_entity) catch {};
        }
    }
}

fn getTypeKey(comptime T: type) u64 {
    return std.hash.Wyhash.hash(0, @typeName(T));
}
