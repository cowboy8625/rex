// const RenderTrait = @import("trait.zig").RenderTrait;
const std = @import("std");
const sdl3 = @import("sdl3");
const Color = @import("Color.zig");
const Rect = @import("rect.zig").Rect;

const Self = @This();

init_flags: sdl3.InitFlags,
window: sdl3.video.Window,
renderer: sdl3.render.Renderer,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !Self {
    const init_flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(init_flags);

    const window = try sdl3.video.Window.init("Hello SDL3", 400, 400, .{});
    errdefer window.deinit();
    try window.setFullscreen(true);
    const renderer = try sdl3.render.Renderer.init(window, null);
    errdefer renderer.deinit();

    const surface = try window.getSurface();
    try surface.fillRect(null, surface.mapRgb(128, 30, 255));
    try window.updateSurface();

    for (0..4) |_| {
        window.sync() catch |e| {
            std.log.err("Failed to sync window: {any}", .{e});
            continue;
        };
        break;
    }

    return .{
        .init_flags = init_flags,
        .window = window,
        .renderer = renderer,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.window.deinit();
    self.renderer.deinit();
    sdl3.quit(self.init_flags);
    sdl3.shutdown();
}

pub fn renderStart(self: *Self) !void {
    try self.renderer.setDrawColor(sdl3.pixels.Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    try self.renderer.clear();
}

pub fn renderEnd(self: *Self) !void {
    try self.renderer.present();
    sdl3.timer.delayMilliseconds(16);
}

pub fn getWindowSize(self: *Self) !struct { width: usize, height: usize } {
    const size = try self.window.getSize();
    return .{ .width = size.width, .height = size.height };
}

pub fn rect(self: *Self, rectangle: Rect(f32), color: Color) !void {
    const sdl3_color = sdl3.pixels.Color{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = color.a,
    };
    try self.renderer.setDrawColor(sdl3_color);

    const sdl3_rect = sdl3.rect.FRect{
        .x = rectangle.x,
        .y = rectangle.y,
        .w = rectangle.width,
        .h = rectangle.height,
    };
    try self.renderer.renderFillRect(sdl3_rect);
}
