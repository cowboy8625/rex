const sdl3 = @import("sdl3");
const math = @import("../math.zig");

kind: enum { Rect },
color: sdl3.pixels.Color,
size: math.Vec2f,
