const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the rich_zig dependency
    const rich_zig = b.dependency("rich_zig", .{
        .target = target,
        .optimize = optimize,
    });

    // Create the zithril module with rich_zig as a dependency
    const mod = b.addModule("zithril", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "rich_zig", .module = rich_zig.module("rich_zig") },
        },
    });

    // Demo executable
    const exe = b.addExecutable(.{
        .name = "zithril",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zithril", .module = mod },
                .{ .name = "rich_zig", .module = rich_zig.module("rich_zig") },
            },
        }),
    });

    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the demo");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Tests
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Examples - each example gets its own build target
    const examples = [_][]const u8{
        "counter",
        "list",
        "tabs",
        "ralph",
    };

    var prev_step: *std.Build.Step = b.getInstallStep();

    for (examples) |name| {
        const example_exe = b.addExecutable(.{
            .name = b.fmt("example-{s}", .{name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zithril", .module = mod },
                    .{ .name = "rich_zig", .module = rich_zig.module("rich_zig") },
                },
            }),
        });

        b.installArtifact(example_exe);

        // Chained run for "run-examples" step
        const chained_run = b.addRunArtifact(example_exe);
        chained_run.step.dependOn(b.getInstallStep());
        chained_run.step.dependOn(prev_step);
        prev_step = &chained_run.step;

        // Standalone run for individual example
        const standalone_run = b.addRunArtifact(example_exe);
        standalone_run.step.dependOn(b.getInstallStep());

        const example_step = b.step(
            b.fmt("run-example-{s}", .{name}),
            b.fmt("Run the {s} example", .{name}),
        );
        example_step.dependOn(&standalone_run.step);
    }

    const run_examples_step = b.step("run-examples", "Run all examples");
    run_examples_step.dependOn(prev_step);

    // Fuzz testing step (for CI/CD Option C)
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

    // Demos - larger applications in their own directories
    const demos = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "rung", .desc = "Ladder logic puzzle game" },
        .{ .name = "dashboard", .desc = "System monitoring dashboard" },
        .{ .name = "explorer", .desc = "File explorer with tree navigation" },
        .{ .name = "dataviz", .desc = "Data visualization gallery" },
    };

    for (demos) |demo| {
        const demo_exe = b.addExecutable(.{
            .name = demo.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("demos/{s}/main.zig", .{demo.name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zithril", .module = mod },
                    .{ .name = "rich_zig", .module = rich_zig.module("rich_zig") },
                },
            }),
        });

        b.installArtifact(demo_exe);

        const demo_run = b.addRunArtifact(demo_exe);
        demo_run.step.dependOn(b.getInstallStep());

        const demo_step = b.step(
            b.fmt("run-{s}", .{demo.name}),
            b.fmt("Run {s}", .{demo.desc}),
        );
        demo_step.dependOn(&demo_run.step);
    }
}
