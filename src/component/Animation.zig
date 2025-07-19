const Engine = @import("../Engine.zig");
const Sprite = @import("../component/Sprite.zig");
const Time = @import("../resource/Time.zig");

const Animation = @This();

frame: usize = 0,
timer: f32 = 0,
speed: f32 = 0.1,
horizontal_frames: usize = 0,
vertical_frames: usize = 0,

pub fn update(self: *Animation, dt: f32) void {
    self.timer += dt;
    if (self.timer > self.speed) {
        self.timer -= self.speed;
        self.frame += 1;
        if (self.frame >= self.horizontal_frames * self.vertical_frames) {
            self.frame = 0;
        }
    }
}
