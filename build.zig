const std = @import("std");
const Scanner = @import("wayland").Scanner;
const generate = @import("generate.zig");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dynamic_link_opts: std.Build.Module.LinkSystemLibraryOptions = .{
        .preferred_link_mode = .dynamic,
        .search_strategy = .mode_first,
    };

    const gobject = b.dependency("gobject", .{ .target = target, .optimize = optimize });
    var layershell_mod: *std.Build.Module = undefined;
    var dbus_mod: *std.Build.Module = undefined;
    var wayland_mod: *std.Build.Module = undefined;
    // pkgs
    {
        layershell_mod = b.createModule(.{
            .root_source_file = b.path("pkgs/layershell.zig"),
            .target = target,
            .optimize = optimize,
        });
        dbus_mod = b.createModule(.{
            .root_source_file = b.path("pkgs/dbus/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        wayland_mod = b.createModule(.{
            .root_source_file = b.path("pkgs/wayland.zig"),
            .target = target,
            .optimize = optimize,
        });
        // WAYLAND
        {
            const scanner = Scanner.create(b, .{
                // Just to clear the error of scanner not finding wayland-protocols
                .wayland_protocols = b.path("."),
            });
            const zig_wayland = b.createModule(.{ .root_source_file = scanner.result });

            const wlr_protocols = b.dependency("wlr-protocols", .{});
            const wayland_protocols = b.dependency("wayland-protocols", .{});
            _ = wayland_protocols;
            scanner.addCustomProtocol(wlr_protocols.path("unstable/wlr-foreign-toplevel-management-unstable-v1.xml"));
            scanner.addCustomProtocol(wlr_protocols.path("unstable/wlr-screencopy-unstable-v1.xml"));
            scanner.generate("zwlr_foreign_toplevel_manager_v1", 3);
            scanner.generate("zwlr_screencopy_manager_v1", 3);
            scanner.generate("wl_output", 4);
            scanner.generate("wl_seat", 9);
            scanner.generate("wl_shm", 2);

            wayland_mod.addImport("zig-wayland", zig_wayland);
            wayland_mod.linkSystemLibrary("gtk4-wayland", dynamic_link_opts);
            wayland_mod.linkSystemLibrary("libwebp", dynamic_link_opts);
        }
        // Linking
        layershell_mod.linkSystemLibrary("gtk4-layer-shell-0", dynamic_link_opts);
        layershell_mod.addImport("gdk", gobject.module("gdk4"));
        layershell_mod.addImport("gtk", gobject.module("gtk4"));

        dbus_mod.linkSystemLibrary("dbus-1", dynamic_link_opts);
        dbus_mod.addImport("glib", gobject.module("glib2"));

        wayland_mod.addImport("glib", gobject.module("glib2"));
        wayland_mod.addImport("gobject", gobject.module("gobject2"));
        wayland_mod.addImport("gio", gobject.module("gio2"));
        wayland_mod.linkSystemLibrary("libpng", dynamic_link_opts);
    }

    // EXAMPLE
    const example_mod = b.createModule(.{
        .root_source_file = b.path("example.zig"),
        .target = target,
        .optimize = optimize,
    });
    // EXE
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const exe = b.addExecutable(.{
        .name = "mika-shell",
        .root_module = exe_mod,
        .optimize = optimize,
    });
    const generate_js_binding_step = generate.js_binding(b, optimize, "src/bindings.js");
    const generate_extra_js_binding_step = generate.extra_js_binding(b, "example/example/extra.js");
    const generate_events_step = generate.events(b, "npm-package/core/events-define.ts");

    exe.step.dependOn(generate_js_binding_step);
    exe.step.dependOn(generate_extra_js_binding_step);
    exe.step.dependOn(generate_events_step);

    exe_mod.linkSystemLibrary("libwebp", dynamic_link_opts);
    exe_mod.linkSystemLibrary("libudev", dynamic_link_opts);
    exe_mod.linkSystemLibrary("libinput", dynamic_link_opts);
    const httpz = b.dependency("httpz", .{ .target = target, .optimize = optimize });
    const cli = b.dependency("cli", .{ .target = target, .optimize = optimize });
    const ini = b.dependency("ini", .{ .target = target, .optimize = optimize });

    exe_mod.addImport("example", example_mod);
    exe_mod.addImport("httpz", httpz.module("httpz"));
    exe_mod.addImport("cli", cli.module("cli"));
    exe_mod.addImport("ini", ini.module("ini"));
    exe_mod.addImport("layershell", layershell_mod); // layershell must be imported before gtk4
    exe_mod.addImport("dbus", dbus_mod);
    exe_mod.addImport("wayland", wayland_mod);

    exe_mod.addImport("gtk", gobject.module("gtk4"));
    exe_mod.addImport("glib", gobject.module("glib2"));
    exe_mod.addImport("webkit", gobject.module("webkit6"));
    exe_mod.addImport("gobject", gobject.module("gobject2"));
    exe_mod.addImport("jsc", gobject.module("javascriptcore6"));
    exe_mod.addImport("cairo", gobject.module("cairo1"));
    exe_mod.addImport("gdk", gobject.module("gdk4"));
    exe_mod.addImport("gio", gobject.module("gio2"));
    exe_mod.addImport("gdk-wayland", gobject.module("gdkwayland4"));

    b.installArtifact(exe);
    // CMD
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const generate_cmd = b.step("generate", "Generate bindings and events");
    generate_cmd.dependOn(generate_js_binding_step);
    generate_cmd.dependOn(generate_extra_js_binding_step);
    generate_cmd.dependOn(generate_events_step);
    // TEST
    const test_step = b.step("test", "Run unit tests");
    const test_dbus_step = b.step("test-dbus", "Run dbus unit tests");
    const test_wayland_step = b.step("test-wayland", "Run wayland unit tests");
    {
        // MAIN
        {
            const exe_unit_tests = b.addTest(.{
                .root_module = exe_mod,
            });
            const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
            test_step.dependOn(&run_exe_unit_tests.step);
        }
        // EXAMPLE
        {
            const example_unit_tests = b.addTest(.{
                .root_module = example_mod,
            });
            const run_example_unit_tests = b.addRunArtifact(example_unit_tests);
            test_step.dependOn(&run_example_unit_tests.step);
        }
        // PKGS/DBUS
        {
            const dbus_unit_tests = b.addTest(.{
                .root_module = dbus_mod,
            });
            const run_dbus_unit_tests = b.addRunArtifact(dbus_unit_tests);
            const check_dbus_service = b.addSystemCommand(&[_][]const u8{
                "bash",
                "-c",
                "[ ! -f ./dbus_service.pid ] || (kill $(cat ./dbus_service.pid) && rm ./dbus_service.pid)",
            });
            const run_dbus_service = b.addSystemCommand(&[_][]const u8{
                "bash",
                "-c",
                "./pkgs/dbus/dbus_test_service.py & echo $! > ./dbus_service.pid && sleep 0.1",
            });
            const kill_dbus_service = b.addSystemCommand(&[_][]const u8{
                "bash",
                "-c",
                "kill $(cat ./dbus_service.pid) && rm ./dbus_service.pid",
            });

            run_dbus_service.step.dependOn(&check_dbus_service.step);
            run_dbus_unit_tests.step.dependOn(&run_dbus_service.step);
            kill_dbus_service.step.dependOn(&run_dbus_unit_tests.step);
            test_dbus_step.dependOn(&kill_dbus_service.step);
            test_dbus_step.dependOn(&run_dbus_unit_tests.step);
        }
        // PKGS/WAYLAND
        {
            const wayland_unit_tests = b.addTest(.{
                .root_module = wayland_mod,
            });
            const run_wayland_unit_tests = b.addRunArtifact(wayland_unit_tests);
            test_wayland_step.dependOn(&run_wayland_unit_tests.step);
        }
    }
}
