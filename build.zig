const std = @import("std");
const cimgui = @import("cimgui_zig");

pub fn build(b: *std.Build) !void {
    const assets_dir = b.option(std.Build.LazyPath, "assets_dir", "Path to the assets directory (default: assets)") orelse b.path("assets");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var assets = std.StringHashMap(*std.ArrayList([]const u8)).init(allocator);
    defer freeAssets(&assets, allocator);

    try collectAssets(allocator, assets_dir.getPath(b), &assets);
    const stringEnum = try buildAssetsEnum(assets);

    const wf = b.addWriteFiles();
    const gen_assets_file = wf.add("src/generated_assets.zig", stringEnum);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Export Rex
    const exported_module = b.addModule("rex", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Generated assets module
    const gen_module = b.createModule(.{
        .root_source_file = gen_assets_file,
    });
    lib_mod.addImport("generated_assets", gen_module);
    exported_module.addImport("generated_assets", gen_module);

    const shared_options = b.addOptions();
    lib_mod.addOptions("build_options", shared_options);

    // Build library
    const lib = b.addLibrary(.{
        .name = "rex",
        .root_module = lib_mod,
        .linkage = .static,
    });

    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .callbacks = false,
        .ext_image = true,
        .c_sdl_sanitize_c = .off,
        .c_sdl_preferred_linkage = .static,
    });
    lib.root_module.addImport("sdl3", sdl3.module("sdl3"));
    exported_module.addImport("sdl3", sdl3.module("sdl3"));

    const entt = b.dependency("entt", .{ .target = target, .optimize = optimize });
    lib.root_module.addImport("entt", entt.module("zig-ecs"));
    exported_module.addImport("entt", entt.module("zig-ecs"));

    const zm = b.dependency("zm", .{ .target = target, .optimize = optimize });
    lib.root_module.addImport("zm", zm.module("zm"));
    exported_module.addImport("zm", zm.module("zm"));

    const cimgui_dep = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platform = cimgui.Platform.GLFW,
        .renderer = cimgui.Renderer.Vulkan,
    });
    lib.linkLibrary(cimgui_dep.artifact("cimgui"));
    exported_module.linkLibrary(cimgui_dep.artifact("cimgui"));

    b.installArtifact(lib);

    // Tests
    const lib_tests = b.addTest(.{ .root_module = lib_mod });

    const unit_test = b.step("test", "Run unit tests");
    unit_test.dependOn(&b.addRunArtifact(lib_tests).step);
}

fn freeAssets(assets: *std.StringHashMap(*std.ArrayList([]const u8)), allocator: std.mem.Allocator) void {
    var it = assets.iterator();
    while (it.next()) |entry| {
        for (entry.value_ptr.*.items) |f| {
            allocator.free(f);
        }
        entry.value_ptr.*.deinit(allocator);
        allocator.destroy(entry.value_ptr.*);
    }
    assets.deinit();
}

fn collectAssets(
    allocator: std.mem.Allocator,
    root: []const u8,
    map: *std.StringHashMap(*std.ArrayList([]const u8)),
) !void {
    var dir = std.fs.cwd().openDir(root, .{ .iterate = true }) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".png")) continue;

        var parts = std.mem.splitSequence(u8, entry.name, "/");

        var len: usize = 0;
        while (parts.next()) |_| len += 1;
        parts.reset();

        if (len == 0) continue;

        const folder = if (len >= 2) parts.next().? else "root";
        const name_full = parts.next().?;
        const name = std.mem.trimRight(u8, name_full, ".png");

        const list = map.get(folder) orelse blk: {
            const new_list = try allocator.create(std.ArrayList([]const u8));
            new_list.* = try std.ArrayList([]const u8).initCapacity(allocator, 14);
            try map.put(folder, new_list);
            break :blk new_list;
        };
        try list.*.append(allocator, try allocator.dupe(u8, name));
    }
}

fn buildAssetsEnum(assets: std.StringHashMap(*std.ArrayList([]const u8))) ![]const u8 {
    var buf = try std.ArrayList(u8).initCapacity(std.heap.page_allocator, 256);
    defer buf.deinit(std.heap.page_allocator);

    const w = buf.writer(std.heap.page_allocator);
    try w.writeAll(
        \\pub const AssetName = enum {
        \\    none,
    );

    var it = assets.iterator();
    while (it.next()) |entry| {
        const folder = entry.key_ptr.*;
        const files = entry.value_ptr.*;

        if (std.mem.eql(u8, folder, "root")) {
            for (files.items) |f| try w.print("\n    {s},", .{f});
        } else {
            try w.print("\n    const {s} = enum {{", .{folder});
            for (files.items) |f| try w.print("\n        {s},", .{f});
            try w.writeAll("\n    };");
        }
    }
    try w.writeAll("\n};\n");

    try w.writeAll(
        \\pub fn getAssetPath(asset: AssetName) []const u8 {
        \\    return switch (asset) {
    );

    it = assets.iterator();
    while (it.next()) |entry| {
        const folder = entry.key_ptr.*;
        const files = entry.value_ptr.*;

        if (std.mem.eql(u8, folder, "root")) {
            for (files.items) |f| {
                try w.print(
                    "\n        AssetName.{s} => \"assets/{s}.png\",",
                    .{ f, f },
                );
            }
        } else {
            for (files.items) |f| {
                try w.print(
                    "\n        AssetName.{s}.{s} => \"assets/{s}/{s}.png\",",
                    .{ folder, f, folder, f },
                );
            }
        }
    }

    const end =
        \\    else => @panic("unknown asset"),
        \\    };
        \\}
        \\
    ;

    try w.writeAll(end);
    return buf.toOwnedSlice(std.heap.page_allocator);
}
