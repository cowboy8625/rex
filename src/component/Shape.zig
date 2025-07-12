const sdl3 = @import("sdl3");
const math = @import("../math.zig");
const Color = @import("../render/Color.zig");

kind: enum { Rect },
color: Color,
size: math.Vec2f,
