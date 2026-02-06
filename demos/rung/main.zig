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
