const std = @import("std");
const sdl3 = @import("sdl3");
const Asset = @import("generated_assets");

const Self = @This();

map: std.EnumArray(Asset.AssetName, ?sdl3.render.Texture) = std.EnumArray(Asset.AssetName, ?sdl3.render.Texture).initFill(null),

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Self, _: std.mem.Allocator) void {
    for (self.map.values) |texture| {
        if (texture) |t| {
            t.deinit();
        }
    }
}

pub fn load(self: *Self, render: *sdl3.render.Renderer, name: Asset.AssetName) !void {
    const path = Asset.getAssetPath(name);
    const ctext: [:0]const u8 = @ptrCast(path);
    const image = try sdl3.image.loadTexture(render.*, ctext);
    try image.setScaleMode(.nearest);
    self.map.set(name, image);
}

pub fn get(self: *const Self, name: Asset.AssetName) ?sdl3.render.Texture {
    return self.map.get(name);
}
