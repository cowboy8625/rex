const std = @import("std");
const entt = @import("entt");

const VisibleEntities = @This();

list: std.ArrayListUnmanaged(entt.Entity) = .{},

pub fn deinit(self: *VisibleEntities, allocator: std.mem.Allocator) void {
    self.list.deinit(allocator);
}
