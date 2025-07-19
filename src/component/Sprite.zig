const Asset = @import("generated_assets");
const math = @import("../math.zig");
const sdl3 = @import("sdl3");

const Sprite = @This();

asset_name: Asset.AssetName,
origin: math.Vec2f,
size: math.Vec2f,
src_rect: ?sdl3.rect.FRect = null,
pixels_per_unit: f32 = 1.0,
color: sdl3.pixels.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 }, // white
flip_x: bool = false,
flip_y: bool = false,
