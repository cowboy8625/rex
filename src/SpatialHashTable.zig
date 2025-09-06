const std = @import("std");
const math = @import("math.zig");
const entt = @import("entt");
const Engine = @import("Engine.zig");
const Transform = @import("component/Transform.zig");

const Self = @This();

pub const UpdateSpatialHashTable = struct {};
pub const SpatialTag = struct {
    bucket: math.IVec2,
};

const PREALLOCATED_BUCKET_SIZE = 16;
const BUCKET_SIZE = 4;

const Container = std.AutoHashMap(math.IVec2, std.ArrayList(entt.Entity));

data: Container,
cell_size: math.IVec2,

pub fn init(allocator: std.mem.Allocator, cell_size: math.IVec2) Self {
    return .{
        .data = Container.init(allocator),
        .cell_size = cell_size,
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    var it = self.data.valueIterator();
    while (it.next()) |b| {
        b.deinit(allocator);
    }
    self.data.deinit();
}

fn get_bucket_size(self: *const Self) math.IVec2 {
    return math.splat(2, i32, BUCKET_SIZE) * self.cell_size;
}

pub fn hash(self: *const Self, key: math.Vec2f) math.IVec2 {
    const ukey: math.IVec2 = math.IVec2{ @intFromFloat(key[0]), @intFromFloat(key[1]) };
    const bucket_size: math.IVec2 = self.get_bucket_size();
    const hashed_key: math.IVec2 = ukey / bucket_size;
    return hashed_key;
}

pub fn insert(
    self: *Self,
    allocator: std.mem.Allocator,
    key: math.Vec2f,
    value: entt.Entity,
) !void {
    const hashed_key = self.hash(key);
    const bucket = self.data.getPtr(hashed_key);
    if (bucket) |b| {
        try b.append(allocator, value);
        return;
    }

    var new_bucket = try std.ArrayList(entt.Entity).initCapacity(allocator, PREALLOCATED_BUCKET_SIZE);
    errdefer new_bucket.deinit(allocator);
    try new_bucket.append(allocator, value);
    try self.data.put(hashed_key, new_bucket);
}

pub fn remove(
    self: *Self,
    tag: *const SpatialTag,
    value: entt.Entity,
) !void {
    const bucket = self.data.getPtr(tag.bucket) orelse return;
    for (bucket.items, 0..) |b, i| {
        if (b == value) {
            _ = bucket.swapRemove(i);
            return;
        }
    }
}

pub fn get(self: *const Self, point: math.Vec2f) ?[]const entt.Entity {
    const hashed_key: math.IVec2 = self.hash(point);
    const bucket = self.data.getPtr(hashed_key);
    if (bucket) |b| {
        return b.items;
    }
    return null;
}

pub fn getBucketsAndNeighbors(self: *const Self, point: math.Vec2f) ?[9]?[]const entt.Entity {
    var buckets: [9]?[]const entt.Entity = [9]?[]const entt.Entity{ null, null, null, null, null, null, null, null, null };
    var y: usize = 0;
    var x: usize = 0;
    const width: usize = 3;
    const hashed_key: math.IVec2 = self.hash(point);
    var inserted: bool = false;

    for (0..width) |y_offset| {
        for (0..width) |x_offset| {
            const bucket_key: math.IVec2 = math.IVec2{
                hashed_key[0] + @as(i32, @intCast(x_offset)) - 1,
                hashed_key[1] + @as(i32, @intCast(y_offset)) - 1,
            };
            if (self.data.getPtr(bucket_key)) |bucket| {
                buckets[y * width + x] = bucket.items;
                inserted = true;
            }
            x += 1;
        }
        y += 1;
        x = 0;
    }
    if (!inserted) {
        return null;
    }
    return buckets;
}

pub fn points_are_in_same_bucket(self: *const Self, a: math.Vec2f, b: math.Vec2f) bool {
    const hashed_key_a: math.IVec2 = self.hash(a);
    const hashed_key_b: math.IVec2 = self.hash(b);
    return hashed_key_a[0] == hashed_key_b[0] and hashed_key_a[1] == hashed_key_b[1];
}

pub fn spatialUpdateSystem(engine: *Engine) void {
    var query = engine.registry.view(.{ Transform, SpatialTag, UpdateSpatialHashTable }, .{});
    var iter = query.entityIterator();
    const spatial_hash_table = engine.getResource(Self) orelse return;
    while (iter.next()) |e| {
        const transform = engine.registry.get(Transform, e);
        const spatial_tag = engine.registry.get(SpatialTag, e);
        const key = math.zm.vec.xy(transform.position);
        spatial_hash_table.remove(spatial_tag, e) catch {
            @panic("failed to update spatial hash table in spatial update system");
        };
        spatial_hash_table.insert(engine.allocator, key, e) catch {
            @panic("failed to update spatial hash table in spatial update system");
        };
        const new_bucket_id = spatial_hash_table.hash(key);
        spatial_tag.bucket = new_bucket_id;
    }
}

test "spatial hash table" {
    const CELL_SIZE = math.splat(2, u32, 12);
    const allocator = std.testing.allocator;
    var table = Self.init(allocator, CELL_SIZE);
    defer table.deinit(allocator);
    var index: u20 = 0;

    const tf = struct {
        fn e(ii: *u20) entt.Entity {
            const i = ii.*;
            ii.* += 1;
            return entt.Entity{
                .index = i,
                .version = 0,
            };
        }

        fn pos(x: f32, y: f32) math.Vec2f {
            return math.Vec2f{ x, y } * math.Vec2f{
                @floatFromInt(CELL_SIZE[0]),
                @floatFromInt(CELL_SIZE[1]),
            };
        }

        fn eq_count(t: *const Self, p: math.Vec2f, actual: []const entt.Entity, expected: usize) !void {
            std.testing.expect(actual.len == expected) catch |err| {
                std.debug.print("total returned entities found for {any}:\nlen: {d}\n", .{ p, actual.len });
                std.log.err("-- ERROR: {any} --", .{err});
                var it = t.data.iterator();
                while (it.next()) |kv| {
                    std.debug.print("key: {any}, value: {any}\n", .{ kv.key_ptr.*, kv.value_ptr.* });
                }
                return error.NoEntitiesFound;
            };
        }
    };

    try table.insert(allocator, tf.pos(0, 0), tf.e(&index));
    try table.insert(allocator, tf.pos(1, 1), tf.e(&index));
    try table.insert(allocator, tf.pos(1, 2), tf.e(&index));

    try table.insert(allocator, tf.pos(4, 4), tf.e(&index));
    try table.insert(allocator, tf.pos(4, 5), tf.e(&index));
    try table.insert(allocator, tf.pos(5, 4), tf.e(&index));
    try table.insert(allocator, tf.pos(5, 5), tf.e(&index));
    try table.insert(allocator, tf.pos(5, 6), tf.e(&index));

    {
        const pos = tf.pos(0, 0);
        const out = table.get(pos) orelse return error.NoEntitiesFound;
        try tf.eq_count(&table, pos, out, 3);
    }
    {
        const pos = tf.pos(5, 7);
        const out = table.get(pos) orelse return error.NoEntitiesFound;
        try tf.eq_count(&table, pos, out, 5);
    }
}
