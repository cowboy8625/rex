const Asset = @import("generated_assets");
const Rect = @import("../render/rect.zig").Rect;
const Color = @import("../render/Color.zig");
const math = @import("../math.zig");

const Sprite = @This();

asset_name: Asset.AssetName,
src_rect: Rect(f32),
origin: math.Vec2f,
size: math.Vec2f,
pixels_per_unit: f32 = 1.0,
color: Color = Color.white,
flip_x: bool = false,
flip_y: bool = false,
