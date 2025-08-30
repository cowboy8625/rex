const std = @import("std");

pub fn getTypeKey(comptime T: type) u64 {
    return std.hash.Wyhash.hash(0, @typeName(T));
}
