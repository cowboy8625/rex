const std = @import("std");
const Rect = @import("rect.zig").Rect;
const Color = @import("Color.zig");
const RenderTrait = @This();
const math = @import("../math.zig");

ptr: *anyopaque,

deinitFn: *const fn (*anyopaque, std.mem.Allocator) void,
renderStartFn: *const fn (*anyopaque) anyerror!void,
renderEndFn: *const fn (*anyopaque) anyerror!void,
rectFn: *const fn (*anyopaque, Rect(f32), Color) anyerror!void,
getWindowSizeFn: *const fn (*anyopaque) anyerror!math.Vec(2, usize),

pub fn init(allocator: std.mem.Allocator, graphics: anytype) RenderTrait {
    const Type = @TypeOf(graphics);
    const Ptr = *Type;

    const ptr = allocator.create(Type) catch @panic("OOM");
    ptr.* = graphics;

    const gen = struct {
        pub fn deinit(pointer: *anyopaque, a: std.mem.Allocator) void {
            const self: Ptr = @alignCast(@ptrCast(pointer));
            @call(.always_inline, Type.deinit, .{self});
            a.destroy(self);
        }

        pub fn renderStart(pointer: *anyopaque) anyerror!void {
            const self: Ptr = @alignCast(@ptrCast(pointer));
            try @call(.always_inline, Type.renderStart, .{self});
        }

        pub fn renderEnd(pointer: *anyopaque) anyerror!void {
            const self: Ptr = @alignCast(@ptrCast(pointer));
            try @call(.always_inline, Type.renderEnd, .{self});
        }

        pub fn rect(pointer: *anyopaque, rectangle: Rect(f32), color: Color) anyerror!void {
            const self: Ptr = @alignCast(@ptrCast(pointer));
            try @call(.always_inline, Type.rect, .{ self, rectangle, color });
        }

        pub fn getWindowSize(pointer: *anyopaque) anyerror!math.Vec(2, usize) {
            const self: Ptr = @alignCast(@ptrCast(pointer));
            return try @call(.always_inline, Type.getWindowSize, .{self});
        }
    };

    return .{
        .ptr = ptr,
        .deinitFn = gen.deinit,
        .renderStartFn = gen.renderStart,
        .renderEndFn = gen.renderEnd,
        .rectFn = gen.rect,
        .getWindowSizeFn = gen.getWindowSize,
    };
}

pub inline fn deinit(self: RenderTrait, allocator: std.mem.Allocator) void {
    self.deinitFn(self.ptr, allocator);
}

pub inline fn renderStart(self: RenderTrait) anyerror!void {
    try self.renderStartFn(self.ptr);
}

pub inline fn renderEnd(self: RenderTrait) anyerror!void {
    try self.renderEndFn(self.ptr);
}

pub inline fn rect(self: RenderTrait, rectangle: Rect(f32), color: Color) anyerror!void {
    try self.rectFn(self.ptr, rectangle, color);
}

pub inline fn getWindowSize(self: RenderTrait) anyerror!math.Vec(2, usize) {
    return try self.getWindowSizeFn(self.ptr);
}
