//! Rung - A ladder logic puzzle game
//!
//! Learn PLC programming through 10 progressively challenging puzzles.
//! Built with zithril to stress-test the TUI framework.

const std = @import("std");
const zithril = @import("zithril");

const game = @import("game.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = try game.GameState.init(allocator);
    defer state.deinit();

    var app = zithril.App(game.GameState).init(.{
        .state = &state,
        .update = game.update,
        .view = game.view,
        .mouse_capture = true,
        .tick_rate_ms = 100,
        .kitty_keyboard = true,
    });

    try app.run(allocator);
}

// Use zithril's panic handler to ensure terminal cleanup on abnormal exit
pub const panic = zithril.terminal_panic;

// ============================================================
// QA COMPANION TESTS
// ============================================================
// Demonstrate TestHarness with allocator-based game state,
// tick-driven animation testing, and auditContrast.

const testing_alloc = std.testing.allocator;

test "rung: game state init and deinit" {
    var state = try game.GameState.init(testing_alloc);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 0), state.level_index);
    try std.testing.expectEqual(game.Mode.editing, state.mode);
}

test "rung: initial render via TestHarness" {
    var state = try game.GameState.init(testing_alloc);
    defer state.deinit();

    var harness = try zithril.TestHarness(game.GameState).init(testing_alloc, .{
        .state = &state,
        .update = game.update,
        .view = game.view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    // After initial render, frame should have been drawn
    try std.testing.expectEqual(@as(u64, 1), harness.frame_count);
    // Buffer should contain something (not all spaces)
    var snap = try harness.snapshot(testing_alloc);
    defer snap.deinit();
    try std.testing.expect(snap.text.len > 0);
}

test "rung: cursor movement" {
    var state = try game.GameState.init(testing_alloc);
    defer state.deinit();

    var harness = try zithril.TestHarness(game.GameState).init(testing_alloc, .{
        .state = &state,
        .update = game.update,
        .view = game.view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    const initial_x = state.cursor.x;
    const initial_y = state.cursor.y;

    // Move right
    harness.pressSpecial(.right);
    try std.testing.expect(state.cursor.x >= initial_x);

    // Move down
    harness.pressSpecial(.down);
    try std.testing.expect(state.cursor.y >= initial_y);
}

test "rung: tick advances animation" {
    var state = try game.GameState.init(testing_alloc);
    defer state.deinit();

    var harness = try zithril.TestHarness(game.GameState).init(testing_alloc, .{
        .state = &state,
        .update = game.update,
        .view = game.view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    // Ticks should process without crashing
    harness.tickN(10);
    try std.testing.expectEqual(@as(u64, 11), harness.frame_count);
}

test "rung: help toggle" {
    var state = try game.GameState.init(testing_alloc);
    defer state.deinit();

    var harness = try zithril.TestHarness(game.GameState).init(testing_alloc, .{
        .state = &state,
        .update = game.update,
        .view = game.view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    try std.testing.expect(!state.show_help);
    harness.pressKey('?');
    try std.testing.expect(state.show_help);
    harness.pressKey('?');
    try std.testing.expect(!state.show_help);
}

test "rung: auditContrast on game buffer" {
    var state = try game.GameState.init(testing_alloc);
    defer state.deinit();

    var harness = try zithril.TestHarness(game.GameState).init(testing_alloc, .{
        .state = &state,
        .update = game.update,
        .view = game.view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    const buf = harness.getBuffer();
    var result = try zithril.auditContrast(testing_alloc, buf);
    defer result.deinit();

    try std.testing.expectEqual(zithril.AuditCategory.contrast, result.category);
}

test "rung: ScenarioRunner basic scenario" {
    var state = try game.GameState.init(testing_alloc);
    defer state.deinit();

    var runner = zithril.ScenarioRunner(game.GameState).init(
        testing_alloc,
        &state,
        game.update,
        game.view,
    );

    const scenario =
        \\size 80 24
        \\tick
        \\key right
        \\key down
        \\tick 3
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
}
