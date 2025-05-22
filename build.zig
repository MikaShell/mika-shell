const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dynamic_link_opts: std.Build.Module.LinkSystemLibraryOptions = .{
        .preferred_link_mode = .dynamic,
        .search_strategy = .mode_first,
    };
    var gtk_mod: *std.Build.Module = undefined;
    var layershell_mod: *std.Build.Module = undefined;
    var webkit_mod: *std.Build.Module = undefined;
    // pkgs
    {
        gtk_mod = b.createModule(.{
            .root_source_file = b.path("pkgs/gtk.zig"),
            .target = target,
            .optimize = optimize,
        });
        layershell_mod = b.createModule(.{
            .root_source_file = b.path("pkgs/layershell.zig"),
            .target = target,
            .optimize = optimize,
        });
        webkit_mod = b.createModule(.{
            .root_source_file = b.path("pkgs/webkit.zig"),
            .target = target,
            .optimize = optimize,
        });
        // Linking
        gtk_mod.linkSystemLibrary("gtk4", dynamic_link_opts);
        layershell_mod.linkSystemLibrary("gtk4-layer-shell-0", dynamic_link_opts);
        layershell_mod.linkSystemLibrary("gtk4", dynamic_link_opts);
        webkit_mod.linkSystemLibrary("webkitgtk-6.0", dynamic_link_opts);
        webkit_mod.linkSystemLibrary("gtk4", dynamic_link_opts);
        webkit_mod.addImport("gtk", gtk_mod);
    }
    // EXE
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "mikami",
        .root_module = exe_mod,
    });
    exe_mod.linkSystemLibrary("gtk4", dynamic_link_opts);
    exe_mod.linkSystemLibrary("webkitgtk-6.0", dynamic_link_opts);
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("httpz", httpz.module("httpz"));
    exe_mod.addImport("gtk", gtk_mod);
    exe_mod.addImport("layershell", layershell_mod);
    exe_mod.addImport("webkit", webkit_mod);
    exe_mod.link_libc = true;

    b.installArtifact(exe);
    // CMD
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    // TEST
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
