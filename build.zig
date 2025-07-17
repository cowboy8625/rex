const Renderer = enum {
    sdl3,
    raylib,
};

const std = @import("std");

pub fn build(b: *std.Build) !void {
    // try generateAssetEnum(b);

    const assets_dir = "assets";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var assets = std.StringHashMap(*std.ArrayList([]const u8)).init(allocator);
    defer {
        var it = assets.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.*.items) |f| {
                allocator.free(f);
            }
            entry.value_ptr.*.deinit();
            allocator.destroy(entry.value_ptr.*);
        }
        assets.deinit();
    }
    try collectAssets(allocator, assets_dir, &assets);

    const stringEnum = try buildAssetsEnum(assets);

    const wf = b.addWriteFiles();
    const f = wf.add("src/generated_assets.zig", stringEnum);

    const renderer = b.option(Renderer, "renderer", "pick a renderer") orelse .sdl3;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gen_module = b.createModule(.{
        .root_source_file = f,
    });

    lib_mod.addImport("generated_assets", gen_module);

    const shared_options = b.addOptions();

    shared_options.addOption(Renderer, "RENDERER", renderer);
    lib_mod.addOptions("build_options", shared_options);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("rex_lib", lib_mod);

    const lib = b.addLibrary(.{
        .name = "rex",
        .root_module = lib_mod,
        .linkage = .static,
    });

    if (renderer == .raylib) {
        const raylib_dep = b.dependency("rlz", .{
            .target = target,
            .optimize = optimize,
        });
        lib.root_module.addImport("rlz", raylib_dep.module("raylib"));
        lib.root_module.addImport("raygui", raylib_dep.module("raygui"));
        lib.root_module.linkLibrary(raylib_dep.artifact("raylib"));
    }

    if (renderer == .sdl3) {
        const sdl3 = b.dependency("sdl3", .{
            .target = target,
            .optimize = optimize,
            .callbacks = false,
            .ext_image = true,
        });
        lib.root_module.addImport("sdl3", sdl3.module("sdl3"));
    }

    const entt = b.dependency("entt", .{ .target = target, .optimize = optimize });
    lib.root_module.addImport("entt", entt.module("zig-ecs"));

    const zm = b.dependency("zm", .{ .target = target, .optimize = optimize });
    lib.root_module.addImport("zm", zm.module("zm"));

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "rex",
        .root_module = exe_mod,
    });
    exe.root_module.addImport("rex", lib_mod);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the app").dependOn(&run_cmd.step);

    const lib_tests = b.addTest(.{ .root_module = lib_mod });
    const exe_tests = b.addTest(.{ .root_module = exe_mod });
    const unit_test = b.step("test", "Run unit tests");
    unit_test.dependOn(&b.addRunArtifact(lib_tests).step);
    unit_test.dependOn(&b.addRunArtifact(exe_tests).step);
}

pub fn generateAssetEnum(b: *std.Build) !void {
    const assets_dir = "assets";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const assets = try collectAssets(allocator, assets_dir);

    const stringEnum = try buildAssetsEnum(assets);
    // generate Zig source file
    const gen_file = b.addWriteFile("src/generated_assets.zig", stringEnum);
    _ = gen_file;
}

fn collectAssets(allocator: std.mem.Allocator, root: []const u8, map: *std.StringHashMap(*std.ArrayList([]const u8))) !void {
    var dir = try std.fs.cwd().openDir(root, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .file) {
            const path = entry.name;
            if (std.mem.endsWith(u8, path, ".png")) {
                var parts = std.mem.splitSequence(u8, path, "/");

                var len: usize = 0;
                while (parts.next()) |_| len += 1;
                parts.reset();

                if (len >= 2) {
                    const folder = parts.next().?;
                    const name_full = parts.next().?;
                    const name = std.mem.trimRight(u8, name_full, ".png");

                    const list = map.get(folder) orelse blk: {
                        const new_list = try allocator.create(std.ArrayList([]const u8));
                        new_list.* = std.ArrayList([]const u8).init(allocator);
                        try map.put(folder, new_list);
                        break :blk new_list;
                    };
                    try list.*.append(try allocator.dupe(u8, name));
                } else if (len == 1) {
                    const name_full = parts.next().?;
                    const name = std.mem.trimRight(u8, name_full, ".png");

                    const list = map.get("root") orelse blk: {
                        const new_list = try allocator.create(std.ArrayList([]const u8));
                        new_list.* = std.ArrayList([]const u8).init(allocator);
                        try map.put("root", new_list);
                        break :blk new_list;
                    };
                    try list.*.append(try allocator.dupe(u8, name));
                }
            }
        }
    }
}

fn buildAssetsEnum(assets: std.StringHashMap(*std.ArrayList([]const u8))) ![]const u8 {
    var list = std.ArrayList(u8).init(std.heap.page_allocator);
    defer list.deinit();

    try list.appendSlice(
        \\pub const AssetName = enum {
    );

    {
        var it = assets.iterator();
        while (it.next()) |entry| {
            const folder = entry.key_ptr.*;
            const files = entry.value_ptr.*;

            if (std.mem.eql(u8, folder, "root")) {
                // top-level files: emit directly as enum fields
                for (files.items) |f| {
                    try list.writer().print("\n    {s},", .{f});
                }
            } else {
                // subfolder: emit nested enum
                try list.writer().print("\n    const {s} = enum {{", .{folder});
                for (files.items) |f| {
                    try list.writer().print("\n        {s},", .{f});
                }
                try list.appendSlice("\n    };");
            }
        }
    }

    try list.appendSlice("\n};\n");

    try list.appendSlice(
        \\pub fn getAssetPath(asset: AssetName) []const u8 {
        \\    return switch (asset) {
    );

    var it = assets.iterator();
    while (it.next()) |entry| {
        const folder = entry.key_ptr.*;
        const files = entry.value_ptr.*;

        if (std.mem.eql(u8, folder, "root")) {
            for (files.items) |f| {
                try list.writer().print("\n        AssetName.{s} => \"assets/{s}.png\",", .{ f, f });
            }
        } else {
            for (files.items) |f| {
                try list.writer().print("\n        AssetName.{s}.{s} => \"assets/{s}/{s}.png\",", .{ folder, f, folder, f });
            }
        }
    }

    try list.appendSlice("\n    };\n}\n");

    return list.toOwnedSlice();
}
// pub fn build(b: *std.Build) void {
//     const renderer = b.option(Renderer, "renderer", "pick a renderer") orelse .sdl3;
//     const target = b.standardTargetOptions(.{});
//     const optimize = b.standardOptimizeOption(.{});
//     const lib_mod = b.createModule(.{
//         .root_source_file = b.path("src/root.zig"),
//         .target = target,
//         .optimize = optimize,
//     });
//
//     const shared_options = b.addOptions();
//
//     shared_options.addOption(Renderer, "RENDERER", renderer);
//     lib_mod.addOptions("build_options", shared_options);
//
//     const exe_mod = b.createModule(.{
//         .root_source_file = b.path("src/main.zig"),
//         .target = target,
//         .optimize = optimize,
//     });
//     exe_mod.addImport("rex_lib", lib_mod);
//     const lib = b.addLibrary(.{
//         .linkage = .static,
//         .name = "rex",
//         .root_module = lib_mod,
//     });
//
//     const sdl3 = b.dependency("sdl3", .{
//         .target = target,
//         .optimize = optimize,
//         .callbacks = false,
//         .ext_image = true,
//         // Options passed directly to https://github.com/castholm/SDL (SDL3 C Bindings):
//         //.c_sdl_preferred_linkage = .static,
//         //.c_sdl_strip = false,
//         //.c_sdl_sanitize_c = .off,
//         //.c_sdl_lto = .none,
//         //.c_sdl_emscripten_pthreads = false,
//         //.c_sdl_install_build_config_h = false,
//     });
//     lib.root_module.addImport("sdl3", sdl3.module("sdl3"));
//
//     // https://github.com/Not-Nik/raylib-zig
//     // const raylib_dep = b.dependency("rlz", .{
//     //     .target = target,
//     //     .optimize = optimize,
//     // });
//     // const raylib = raylib_dep.module("raylib"); // main raylib module
//     // const raygui = raylib_dep.module("raygui"); // raygui module
//     // const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library
//     // lib.root_module.linkLibrary(raylib_artifact);
//     // lib.root_module.addImport("rlz", raylib);
//     // lib.root_module.addImport("raygui", raygui);
//
//     const entt_dep = b.dependency("entt", .{
//         .target = target,
//         .optimize = optimize,
//     });
//     lib.root_module.addImport("entt", entt_dep.module("zig-ecs"));
//
//     const zm = b.dependency("zm", .{
//         .target = target,
//         .optimize = optimize,
//     });
//     lib.root_module.addImport("zm", zm.module("zm"));
//
//     b.installArtifact(lib);
//
//     const exe = b.addExecutable(.{
//         .name = "rex",
//         .root_module = exe_mod,
//     });
//
//     exe.root_module.addImport("rex", lib_mod);
//     b.installArtifact(exe);
//
//     const run_cmd = b.addRunArtifact(exe);
//     run_cmd.step.dependOn(b.getInstallStep());
//     if (b.args) |args| {
//         run_cmd.addArgs(args);
//     }
//     const run_step = b.step("run", "Run the app");
//     run_step.dependOn(&run_cmd.step);
//     const lib_unit_tests = b.addTest(.{
//         .root_module = lib_mod,
//     });
//
//     const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
//
//     const exe_unit_tests = b.addTest(.{
//         .root_module = exe_mod,
//     });
//
//     const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
//     const test_step = b.step("test", "Run unit tests");
//     test_step.dependOn(&run_lib_unit_tests.step);
//     test_step.dependOn(&run_exe_unit_tests.step);
// }
