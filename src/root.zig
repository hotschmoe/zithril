// zithril - Zig TUI framework
// Built on rich_zig for terminal rendering primitives

const std = @import("std");
pub const rich_zig = @import("rich_zig");

// Re-export rich_zig types that are part of zithril's public API
pub const Style = rich_zig.Style;
pub const Color = rich_zig.Color;

test "style re-export" {
    const style = Style.empty.bold().fg(.red);
    try std.testing.expect(style.hasAttribute(.bold));
}
