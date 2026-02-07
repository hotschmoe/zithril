const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const rich_zig = b.dependency("rich_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("zithril", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "rich_zig", .module = rich_zig.module("rich_zig") },
        },
    });

    const update_snapshots = b.option(bool, "update-snapshots", "Auto-update golden files on mismatch") orelse false;

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    if (update_snapshots) {
        run_mod_tests.setEnvironmentVariable("ZITHRIL_UPDATE_SNAPSHOTS", "1");
    }

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    const fuzz_step = b.step("fuzz", "Run fuzz tests");
    const fuzz_exe = b.addExecutable(.{
        .name = "fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/fuzz.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zithril", .module = mod },
            },
        }),
    });
    const fuzz_run = b.addRunArtifact(fuzz_exe);
    fuzz_run.step.dependOn(b.getInstallStep());
    fuzz_step.dependOn(&fuzz_run.step);

    const showcases = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "gallery", .desc = "Widget gallery - every widget in tabbed pages" },
        .{ .name = "workbench", .desc = "Interactive workbench - focus, mouse, input, panels" },
        .{ .name = "rung", .desc = "Ladder logic puzzle game" },
    };

    for (showcases) |app| {
        const app_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("showcases/{s}/main.zig", .{app.name})),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zithril", .module = mod },
                .{ .name = "rich_zig", .module = rich_zig.module("rich_zig") },
            },
        });

        const app_exe = b.addExecutable(.{
            .name = app.name,
            .root_module = app_module,
        });
        b.installArtifact(app_exe);

        const app_run = b.addRunArtifact(app_exe);
        app_run.step.dependOn(b.getInstallStep());

        const app_step = b.step(
            b.fmt("run-{s}", .{app.name}),
            b.fmt("Run {s}", .{app.desc}),
        );
        app_step.dependOn(&app_run.step);

        const app_tests = b.addTest(.{
            .root_module = app_module,
        });
        const run_app_tests = b.addRunArtifact(app_tests);
        if (update_snapshots) {
            run_app_tests.setEnvironmentVariable("ZITHRIL_UPDATE_SNAPSHOTS", "1");
        }
        test_step.dependOn(&run_app_tests.step);

        const app_test_step = b.step(
            b.fmt("test-{s}", .{app.name}),
            b.fmt("Run {s} QA tests", .{app.name}),
        );
        app_test_step.dependOn(&run_app_tests.step);
    }
}
