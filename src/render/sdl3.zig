const std = @import("std");
const sdl3 = @import("sdl3");
const math = @import("../math.zig");

const Self = @This();

init_flags: sdl3.InitFlags,
window: sdl3.video.Window,
renderer: sdl3.render.Renderer,

pub fn init() !Self {
    const init_flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(init_flags);

    const displays = try sdl3.video.getDisplays();
    const bounds = try displays[0].getBounds();

    const window = try sdl3.video.Window.init("Hello SDL3", @intCast(bounds.w), @intCast(bounds.h), .{});
    errdefer window.deinit();

    const renderer = try sdl3.render.Renderer.init(window, null);
    errdefer renderer.deinit();
    try renderer.setDrawBlendMode(.blend);

    const surface = try window.getSurface();
    try surface.fillRect(null, surface.mapRgb(128, 30, 255));

    return .{
        .init_flags = init_flags,
        .window = window,
        .renderer = renderer,
    };
}

pub fn deinit(self: *Self) void {
    self.window.deinit();
    self.renderer.deinit();
    sdl3.quit(self.init_flags);
    sdl3.shutdown();
}

pub fn renderStart(self: *Self) anyerror!void {
    try self.renderer.setDrawColor(sdl3.pixels.Color{ .r = 0x28, .g = 0x2c, .b = 0x34, .a = 255 });
    try self.renderer.clear();
}

pub fn renderEnd(self: *Self) anyerror!void {
    try self.renderer.present();
    sdl3.timer.delayMilliseconds(16);
}

pub fn getWindowSize(self: *Self) anyerror!math.Vec(2, usize) {
    const size = try self.window.getSize();
    return .{ size.width, size.height };
}

pub fn rect(self: *Self, rectangle: sdl3.rect.FRect, color: sdl3.pixels.Color) anyerror!void {
    try self.renderer.setDrawColor(color);
    try self.renderer.renderFillRect(rectangle);
}
