const sdl3 = @import("sdl3");
const entt = @import("entt");
const std = @import("std");
pub const component = @import("component/mod.zig");
pub const math = @import("math.zig");

pub const Color = sdl3.pixels.Color;

pub const Transform = component.Transform;
pub const Shape = component.Shape;
pub const Camera = component.Camera;
pub const VisibleEntities = component.VisibleEntities;
pub const Velocity = component.Velocity;

pub const Time = @import("resource/Time.zig");
pub const Window = @import("resource/Window.zig");
pub const Engine = @import("Engine.zig");
