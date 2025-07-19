const Engine = @import("../Engine.zig");
const Sprite = @import("../component/Sprite.zig");
const Time = @import("../resource/Time.zig");

const Animation = struct {
    frame: usize = 0,
    timer: f32 = 0,
    speed: f32 = 0.1,
    horizontal_frames: usize = 0,
    vertical_frames: usize = 0,

    fn update(self: *@This(), dt: f32) void {
        self.timer += dt;
        if (self.timer > self.speed) {
            self.timer -= self.speed;
            self.frame += 1;
            if (self.frame >= self.horizontal_frames * self.vertical_frames) {
                self.frame = 0;
            }
        }
    }
};

fn animateSystem(engine: *Engine) void {
    const time = engine.getResourceConst(Time) orelse return;
    var q = engine.registry.view(.{ Animation, Sprite }, .{});
    var q_iter = q.entityIterator();
    while (q_iter.next()) |e| {
        const anim = engine.registry.get(Animation, e);
        anim.update(time.delta);
        const sprite = engine.registry.get(Sprite, e);
        if (sprite.src_rect) |*rect| {
            const x_index: f32 = @floatFromInt(anim.frame % anim.horizontal_frames);
            const y_index: f32 = @floatFromInt(anim.frame / anim.horizontal_frames);
            rect.x = x_index * rect.w;
            rect.y = y_index * rect.h;
        }
    }
}
