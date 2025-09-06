const sdl3 = @import("sdl3");
const entt = @import("entt");
const std = @import("std");
pub const component = @import("component/mod.zig");
pub const math = @import("math.zig");

pub const Asset = @import("generated_assets");

pub const Entity = entt.Entity;

pub const Color = sdl3.pixels.Color;

pub const Animation = component.Animation;
pub const Camera = component.Camera;
pub const Collider = component.Collider;
pub const Gravity = component.Gravity;
pub const PhysicsMaterial = component.PhysicsMaterial;
pub const StaticRigidBody = component.StaticRigidBody;
pub const DynamicRigidBody = component.DynamicRigidBody;
pub const Shape = component.Shape;
pub const Sprite = component.Sprite;
pub const Transform = component.Transform;
pub const Velocity = component.Velocity;
pub const VisibleEntities = component.VisibleEntities;

// TODO: Move to eventbus or something
pub const CollisionEvent = component.CollisionEvent;

pub const AssetServer = @import("resource/AssetServer.zig");
pub const EventBus = @import("resource/EventBus.zig");
pub const Time = @import("resource/Time.zig");
pub const Window = @import("resource/Window.zig");

pub const Engine = @import("Engine.zig");

test {
    _ = @import("Engine.zig");
    _ = @import("SpatialHashTable.zig");
    _ = @import("component/mod.zig");
    _ = @import("math.zig");
    _ = @import("resource/mod.zig");
    _ = @import("util.zig");
}
