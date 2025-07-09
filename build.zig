const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("rex_lib", lib_mod);
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "rex",
        .root_module = lib_mod,
    });

    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .callbacks = false,
        .ext_image = true,
        // Options passed directly to https://github.com/castholm/SDL (SDL3 C Bindings):
        //.c_sdl_preferred_linkage = .static,
        //.c_sdl_strip = false,
        //.c_sdl_sanitize_c = .off,
        //.c_sdl_lto = .none,
        //.c_sdl_emscripten_pthreads = false,
        //.c_sdl_install_build_config_h = false,
    });
    lib.root_module.addImport("sdl3", sdl3.module("sdl3"));

    const entt_dep = b.dependency("entt", .{
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("entt", entt_dep.module("zig-ecs"));

    const zm = b.dependency("zm", .{
        .target = target,
        .optimize = optimize,
    });
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
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
