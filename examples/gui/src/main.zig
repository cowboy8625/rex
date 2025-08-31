const std = @import("std");
const rex = @import("rex");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var engine = try rex.Engine.init(allocator);
    defer engine.deinit();

    // engine.addSystem(.Startup, .{});
    // engine.addSystem(.Update, .{});

    try engine.run(.{
        .renderColliders = false,
    });
}
