const std = @import("std");
const math = @import("../math.zig");

pub fn Rect(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,
        width: T,
        height: T,

        const Self = @This();

        pub fn init(x: T, y: T, width: T, height: T) Rect(T) {
            return .{ .x = x, .y = y, .width = width, .height = height };
        }

        pub fn from2vec2(point: math.Vec2(T), size: math.Vec2(T)) Rect(T) {
            return .{ .x = point[0], .y = point[1], .width = size[0], .height = size[0] };
        }

        pub fn center(self: *const Self) math.Vec2(T) {
            return self.getPos().add(self.getSize().div(@as(T, 2)));
        }

        pub fn top(self: *const Self) T {
            return self.y;
        }

        pub fn bottom(self: *const Self) T {
            return self.y + self.height;
        }

        pub fn left(self: *const Self) T {
            return self.x;
        }

        pub fn right(self: *const Self) T {
            return self.x + self.width;
        }

        pub fn contains(self: Self, point: math.Vec2(T)) bool {
            return point[0] >= self.x and point[0] <= self.x + self.width and point[1] >= self.y and point[1] <= self.y + self.height;
        }

        /// Same as calling `topLeft`
        pub fn pos(self: Self, comptime U: type) math.Vec2(U) {
            return .{ .x = self.x, .y = self.y };
        }

        /// Same as calling `pos`
        pub fn topLeft(self: *const Self) math.Vec2(T) {
            return .{ .x = self.x, .y = self.y };
        }

        pub fn bottomRight(self: *const Self) math.Vec2(T) {
            return .{ .x = self.x + self.width, .y = self.y + self.height };
        }

        pub fn eq(self: Self, other: Self) bool {
            return std.meta.eql(self, other);
        }

        pub fn addPoint(self: Self, point: math.Vec2(T)) Self {
            return .{
                .x = self.x + point.x,
                .y = self.y + point.y,
                .width = self.width,
                .height = self.height,
            };
        }

        pub fn scale(self: Self, value: anytype) Self {
            const size = self.getSize();
            const scale_factor = size.div(value);
            const local_pos = self.getPos().sub(scale_factor);
            return Self.from2vec2(local_pos, size.add(scale_factor.mul(value)));
        }

        pub fn expand(self: Self, value: math.Vec2(T)) Self {
            const half_value = value.div(@as(T, 2));

            const new_pos = self.getPos().sub(half_value);
            const new_size = self.getSize().add(value);
            return Self.from2vec2(new_pos, new_size);
        }

        pub fn getPos(self: Self) math.Vec2(T) {
            return .{ .x = self.x, .y = self.y };
        }

        pub fn getSize(self: Self) math.Vec2(T) {
            return .{ .x = self.width, .y = self.height };
        }

        pub fn sizeDiv(self: Self, value: anytype) Self {
            const local_pos = self.getPos();
            const size = self.getSize().div(value);
            return Self.from2vec2(local_pos, size);
        }

        pub fn as(self: Self, comptime U: type) Rect(U) {
            const x: U = numberCast(T, U, self.x);
            const y: U = numberCast(T, U, self.y);
            const width: U = numberCast(T, U, self.width);
            const height: U = numberCast(T, U, self.height);
            return .{ .x = x, .y = y, .width = width, .height = height };
        }
    };
}

pub fn numberCast(comptime T: type, comptime U: type, num: T) U {
    if (T == U) return num;
    return switch (@typeInfo(T)) {
        .Int => switch (@typeInfo(U)) {
            .Int => @as(U, @intCast(num)),
            .Float => @as(U, @floatFromInt(num)),
            .Bool => castToBool(T, num),
            else => @compileError("Unsupported type " ++ @typeName(U)),
        },
        .Float => switch (@typeInfo(U)) {
            .Int => @as(U, @intFromFloat(num)),
            .Float => @as(U, @floatCast(num)),
            .Bool => castToBool(T, num),
            else => @compileError("Unsupported type " ++ @typeName(U)),
        },
        .ComptimeInt, .ComptimeFloat => switch (@typeInfo(U)) {
            .Int => @as(U, @intFromFloat(num)),
            .Float => @as(U, @floatFromInt(num)),
            .Bool => castToBool(T, num),
            else => @compileError("Unsupported type " ++ @typeName(U)),
        },
        .Bool => switch (@typeInfo(U)) {
            .Int => @intFromBool(num),
            .Float => @as(U, @floatFromInt(@intFromBool(num))),
            .Bool => castToBool(T, num),
            else => @compileError("Unsupported type " ++ @typeName(U)),
        },
        .Enum => switch (@typeInfo(U)) {
            .Int => @intFromEnum(num),
            .Float => @as(U, @floatFromInt(@intFromEnum(num))),
            .Bool => castToBool(T, num),
            else => @compileError("Unsupported type " ++ @typeName(U)),
        },
        else => @compileError("Unsupported type " ++ @typeName(T)),
    };
}

fn castToBool(comptime T: type, item: T) bool {
    return switch (@typeInfo(T)) {
        .Int => item != 0,
        .Float => item != 0.0,
        .Bool => item,
        else => @compileError("Unsupported type"),
    };
}

pub fn cast(comptime T: type, item: anytype) T {
    switch (@typeInfo(@TypeOf(item))) {
        .Int, .Float, .Bool => return numberCast(@TypeOf(item), T, item),
        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(item))),
    }
}
