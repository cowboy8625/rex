const std = @import("std");

pub fn getTypeKey(comptime T: type) u64 {
    return std.hash.Wyhash.hash(0, @typeName(T));
}

test "getTypeKey" {
    try std.testing.expect(getTypeKey(u32) != getTypeKey(i32));
    try std.testing.expect(getTypeKey(u32) == getTypeKey(u32));
}
