const Engine = @import("../Engine.zig");
const Sprite = @import("../component/Sprite.zig");
const Time = @import("../resource/Time.zig");

const Animation = @This();

frame: usize = 0,
timer: f32 = 0,
speed: f32 = 0.1,
horizontal_frames: usize = 0,
vertical_frames: usize = 0,
range_start: ?usize = null,
range_end: ?usize = null,

pub fn update(self: *Animation, dt: f32) void {
    self.timer += dt;

    const total_frames = self.horizontal_frames * self.vertical_frames;

    const start = self.range_start orelse 0;
    const end = self.range_end orelse total_frames - 1;
    const frame_count = end - start + 1;

    if (self.timer > self.speed) {
        self.timer -= self.speed;

        self.frame += 1;
        if (self.frame >= frame_count) {
            self.frame = 0;
        }
    }
}

pub fn currentFrameIndex(self: *Animation) usize {
    const start = self.range_start orelse 0;
    return start + self.frame;
}
