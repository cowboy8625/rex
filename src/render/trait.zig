pub fn RenderTrait(comptime T: type) type {
    return struct {
        renderStart: *const fn (self: *T) void,
        renderEnd: *const fn (self: *T) void,
    };
}
