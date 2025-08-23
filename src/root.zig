const sdl3 = @import("sdl3");
const entt = @import("entt");
const std = @import("std");
pub const component = @import("component/mod.zig");
pub const math = @import("math.zig");

pub const Asset = @import("generated_assets");

pub const Entity = entt.Entity;

pub const Color = sdl3.pixels.Color;

pub const Animation = component.Animation;
pub const Sprite = component.Sprite;
pub const Transform = component.Transform;
pub const Shape = component.Shape;
pub const Camera = component.Camera;
pub const VisibleEntities = component.VisibleEntities;
pub const Velocity = component.Velocity;
pub const Collider = component.Collider;
pub const RigidBody = component.RigidBody;

pub const Time = @import("resource/Time.zig");
pub const Window = @import("resource/Window.zig");
pub const AssetServer = @import("resource/AssetServer.zig");

pub const Engine = @import("Engine.zig");

test {
    _ = @import("component/mod.zig");
    _ = @import("resource/mod.zig");
    _ = @import("Engine.zig");
    _ = @import("math.zig");
}
