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
    var dbus_mod: *std.Build.Module = undefined;
    var glib_mod: *std.Build.Module = undefined;
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
            .link_libc = true,
        });
        dbus_mod = b.createModule(.{
            .root_source_file = b.path("pkgs/dbus/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        glib_mod = b.createModule(.{
            .root_source_file = b.path("pkgs/glib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        // Linking
        gtk_mod.linkSystemLibrary("gtk4", dynamic_link_opts);
        layershell_mod.linkSystemLibrary("gtk4-layer-shell-0", dynamic_link_opts);
        layershell_mod.linkSystemLibrary("gtk4", dynamic_link_opts);
        layershell_mod.addImport("gtk", gtk_mod);
        webkit_mod.linkSystemLibrary("webkitgtk-6.0", dynamic_link_opts);
        webkit_mod.linkSystemLibrary("gtk4", dynamic_link_opts);

        webkit_mod.addImport("gtk", gtk_mod);
        dbus_mod.linkSystemLibrary("dbus-1", dynamic_link_opts);
        dbus_mod.addCSourceFile(.{
            .file = b.path("pkgs/dbus/dbus.c"),
        });
        dbus_mod.addIncludePath(b.path("pkgs/dbus"));
        dbus_mod.addImport("glib", glib_mod);
        glib_mod.linkSystemLibrary("glib-2.0", dynamic_link_opts);
        glib_mod.linkSystemLibrary("gio-2.0", dynamic_link_opts);
    }
    // EXAMPLE
    const example_mod = b.createModule(.{
        .root_source_file = b.path("example/example.zig"),
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
    const generate_js_binding = b.addSystemCommand(&.{
        "esbuild",
        "bindings/index.ts",
        "--bundle",
        std.fmt.allocPrint(b.allocator, "--minify={}", .{optimize != .Debug}) catch @panic("OOM"),
        "--outfile=src/bindings.js",
    });
    const exe = b.addExecutable(.{
        .name = "mika-shell",
        .root_module = exe_mod,
        .optimize = optimize,
    });
    exe.step.dependOn(&generate_js_binding.step);

    exe_mod.linkSystemLibrary("libwebp", dynamic_link_opts);
    exe_mod.linkSystemLibrary("gtk4", dynamic_link_opts);
    exe_mod.linkSystemLibrary("gtk4-wayland", dynamic_link_opts);
    exe_mod.linkSystemLibrary("webkitgtk-6.0", dynamic_link_opts);
    const httpz = b.dependency("httpz", .{ .target = target, .optimize = optimize });
    const zigcli = b.dependency("zig-cli", .{ .target = target, .optimize = optimize });
    const ini = b.dependency("ini", .{ .target = target, .optimize = optimize });

    exe_mod.addImport("example", example_mod);
    exe_mod.addImport("httpz", httpz.module("httpz"));
    exe_mod.addImport("zig-cli", zigcli.module("zig-cli"));
    exe_mod.addImport("ini", ini.module("ini"));
    exe_mod.addImport("gtk", gtk_mod);
    exe_mod.addImport("layershell", layershell_mod);
    exe_mod.addImport("webkit", webkit_mod);
    exe_mod.addImport("glib", glib_mod);
    exe_mod.addImport("dbus", dbus_mod);

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
    const test_step = b.step("test", "Run unit tests");
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
        // MODULES
        {
            const modules_mod = b.createModule(.{
                .root_source_file = b.path("src/modules/modules.zig"),
                .target = target,
                .optimize = optimize,
            });
            modules_mod.addImport("webkit", webkit_mod);

            const modules_unit_tests = b.addTest(.{
                .root_module = modules_mod,
            });

            const run_modules_unit_tests = b.addRunArtifact(modules_unit_tests);

            test_step.dependOn(&run_modules_unit_tests.step);
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
            test_step.dependOn(&kill_dbus_service.step);
        }
    }
}
