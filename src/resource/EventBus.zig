const std = @import("std");
const util = @import("../util.zig");

const EventBus = @This();

const EventBox = struct {
    type_id: usize,
    ptr: *anyopaque,
    clearFn: *const fn (ptr: *anyopaque) void,
    deinitFn: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,
};

allocator: std.mem.Allocator,
events: std.AutoHashMapUnmanaged(usize, EventBox) = .{},

pub fn init(allocator: std.mem.Allocator) EventBus {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *EventBus, _: std.mem.Allocator) void {
    var it = self.events.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinitFn(entry.value_ptr.ptr, self.allocator);
    }
    self.events.deinit(self.allocator);
}

pub fn emit(self: *EventBus, comptime T: type, value: T) void {
    const type_id = util.getTypeKey(T);

    var list: *std.ArrayListUnmanaged(T) = undefined;
    if (self.events.get(type_id)) |box| {
        list = @ptrCast(@alignCast(box.ptr));
    } else {
        list = self.allocator.create(std.ArrayListUnmanaged(T)) catch @panic("OOM");
        list.* = .{};
        const box = EventBox{
            .type_id = type_id,
            .ptr = list,
            .clearFn = struct {
                fn clearFn(ptr: *anyopaque) void {
                    const real_ptr: *std.ArrayListUnmanaged(T) = @ptrCast(@alignCast(ptr));
                    real_ptr.clearRetainingCapacity();
                }
            }.clearFn,
            .deinitFn = struct {
                fn deinitFn(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                    const real_ptr: *std.ArrayListUnmanaged(T) = @ptrCast(@alignCast(ptr));
                    real_ptr.deinit(allocator);
                    allocator.destroy(real_ptr);
                }
            }.deinitFn,
        };
        self.events.put(self.allocator, type_id, box) catch @panic("OOM");
    }

    list.append(self.allocator, value) catch @panic("OOM");
}

pub fn read(self: *EventBus, comptime T: type) []const T {
    const type_id = util.getTypeKey(T);
    if (self.events.get(type_id)) |box| {
        const list: *std.ArrayListUnmanaged(T) = @ptrCast(@alignCast(box.ptr));
        return list.items;
    }
    return &[_]T{};
}

pub fn clear(self: *EventBus) void {
    var it = self.events.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.clearFn(entry.value_ptr.ptr);
    }
}
