// Text utilities for zithril TUI framework
// Shared functions for text display width calculation

const std = @import("std");
const cell_mod = @import("cell.zig");

/// Calculate the display width of a string in terminal columns.
/// Uses rich_zig's character width calculation for accuracy with CJK,
/// emoji, and other wide characters.
pub fn displayWidth(str: []const u8) u16 {
    var width: u16 = 0;
    var iter = std.unicode.Utf8View.initUnchecked(str).iterator();
    while (iter.nextCodepoint()) |cp| {
        width +|= cell_mod.Cell.charWidth(cp);
    }
    return width;
}

// ============================================================
// TESTS
// ============================================================

test "displayWidth: ASCII string" {
    try std.testing.expectEqual(@as(u16, 5), displayWidth("Hello"));
}

test "displayWidth: empty string" {
    try std.testing.expectEqual(@as(u16, 0), displayWidth(""));
}

test "displayWidth: CJK character" {
    try std.testing.expectEqual(@as(u16, 2), displayWidth("\u{4E2D}"));
}

test "displayWidth: mixed ASCII and CJK" {
    // "Hi" (2) + CJK (2) = 4
    try std.testing.expectEqual(@as(u16, 4), displayWidth("Hi\u{4E2D}"));
}
