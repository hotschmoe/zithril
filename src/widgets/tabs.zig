// Tabs widget for zithril TUI framework
// Tab bar with titles, selection, and customizable divider

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const text_mod = @import("../text.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Tabs widget displaying a horizontal tab bar.
///
/// Renders a row of tab titles with the selected tab highlighted.
/// Tabs are separated by a configurable divider string.
pub const Tabs = struct {
    /// Tab titles to display
    titles: []const []const u8,

    /// Index of the currently selected tab
    selected: usize = 0,

    /// Default style for unselected tabs
    style: Style = Style.empty,

    /// Style for the selected tab
    highlight_style: Style = Style.init().bold().fg(.yellow),

    /// Divider string between tabs
    divider: []const u8 = " | ",

    /// Render the tabs into the buffer at the given area.
    /// Tabs are rendered horizontally on the first row of the area.
    pub fn render(self: Tabs, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.titles.len == 0) return;

        var x = area.x;

        for (self.titles, 0..) |title, idx| {
            if (x >= area.right()) break;

            // Determine if this tab is selected
            const is_selected = idx == self.selected;
            const tab_style = if (is_selected) self.highlight_style else self.style;

            // Render tab title
            const available_width = area.right() -| x;
            if (available_width == 0) break;

            const title_len = text_mod.displayWidth(title);
            const render_len = @min(title_len, available_width);

            if (render_len > 0) {
                buf.setString(x, area.y, title, tab_style);
            }

            x +|= @intCast(render_len);

            // Render divider after tab (except for last tab)
            if (idx + 1 < self.titles.len and x < area.right()) {
                const divider_available = area.right() -| x;
                const divider_len = text_mod.displayWidth(self.divider);
                const divider_render_len = @min(divider_len, divider_available);

                if (divider_render_len > 0) {
                    buf.setString(x, area.y, self.divider, self.style);
                }

                x +|= @intCast(divider_render_len);
            }
        }
    }

    /// Get the number of tabs
    pub fn count(self: Tabs) usize {
        return self.titles.len;
    }

    /// Check if tabs are empty
    pub fn isEmpty(self: Tabs) bool {
        return self.titles.len == 0;
    }

    /// Get the selected tab index, clamped to valid range
    pub fn selectedClamped(self: Tabs) ?usize {
        if (self.titles.len == 0) return null;
        return @min(self.selected, self.titles.len - 1);
    }
};

// ============================================================
// SANITY TESTS - Basic Tabs functionality
// ============================================================

test "sanity: Tabs with default values" {
    const titles = [_][]const u8{ "Tab1", "Tab2", "Tab3" };
    const tabs = Tabs{ .titles = &titles };

    try std.testing.expectEqual(@as(usize, 3), tabs.count());
    try std.testing.expectEqual(@as(usize, 0), tabs.selected);
    try std.testing.expectEqualStrings(" | ", tabs.divider);
}

test "sanity: Tabs with selection" {
    const titles = [_][]const u8{ "A", "B", "C" };
    const tabs = Tabs{
        .titles = &titles,
        .selected = 1,
    };

    try std.testing.expectEqual(@as(usize, 1), tabs.selected);
}

test "sanity: Tabs with custom styles" {
    const titles = [_][]const u8{"X"};
    const tabs = Tabs{
        .titles = &titles,
        .style = Style.init().fg(.white),
        .highlight_style = Style.init().bold().bg(.red),
        .divider = " - ",
    };

    try std.testing.expect(!tabs.style.isEmpty());
    try std.testing.expect(tabs.highlight_style.hasAttribute(.bold));
    try std.testing.expectEqualStrings(" - ", tabs.divider);
}

test "sanity: Tabs.count and Tabs.isEmpty" {
    const titles = [_][]const u8{ "A", "B" };
    const tabs = Tabs{ .titles = &titles };

    try std.testing.expectEqual(@as(usize, 2), tabs.count());
    try std.testing.expect(!tabs.isEmpty());

    const empty_titles = [_][]const u8{};
    const empty_tabs = Tabs{ .titles = &empty_titles };

    try std.testing.expectEqual(@as(usize, 0), empty_tabs.count());
    try std.testing.expect(empty_tabs.isEmpty());
}

test "sanity: Tabs.selectedClamped" {
    const titles = [_][]const u8{ "A", "B" };
    const tabs = Tabs{
        .titles = &titles,
        .selected = 5,
    };

    try std.testing.expectEqual(@as(?usize, 1), tabs.selectedClamped());

    const empty_titles = [_][]const u8{};
    const empty_tabs = Tabs{ .titles = &empty_titles };

    try std.testing.expect(empty_tabs.selectedClamped() == null);
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Tabs renders titles" {
    var buf = try Buffer.init(std.testing.allocator, 30, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "One", "Two", "Three" };
    const tabs = Tabs{
        .titles = &titles,
        .divider = " | ",
    };
    tabs.render(Rect.init(0, 0, 30, 1), &buf);

    // "One | Two | Three"
    try std.testing.expectEqual(@as(u21, 'O'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(3, 0).char);
    try std.testing.expectEqual(@as(u21, '|'), buf.get(4, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(5, 0).char);
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(6, 0).char);
}

test "behavior: Tabs highlights selected tab" {
    var buf = try Buffer.init(std.testing.allocator, 30, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "AA", "BB", "CC" };
    const tabs = Tabs{
        .titles = &titles,
        .selected = 1,
        .highlight_style = Style.init().bold(),
        .divider = "|",
    };
    tabs.render(Rect.init(0, 0, 30, 1), &buf);

    // "AA|BB|CC"
    // AA at 0-1, | at 2, BB at 3-4 (selected), | at 5, CC at 6-7

    // AA should not be bold
    try std.testing.expect(!buf.get(0, 0).style.hasAttribute(.bold));
    try std.testing.expect(!buf.get(1, 0).style.hasAttribute(.bold));

    // BB should be bold (selected)
    try std.testing.expect(buf.get(3, 0).style.hasAttribute(.bold));
    try std.testing.expect(buf.get(4, 0).style.hasAttribute(.bold));

    // CC should not be bold
    try std.testing.expect(!buf.get(6, 0).style.hasAttribute(.bold));
}

test "behavior: Tabs renders at area offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const titles = [_][]const u8{"Tab"};
    const tabs = Tabs{ .titles = &titles };
    tabs.render(Rect.init(5, 3, 20, 1), &buf);

    try std.testing.expectEqual(@as(u21, 'T'), buf.get(5, 3).char);
    try std.testing.expectEqual(@as(u21, 'a'), buf.get(6, 3).char);
    try std.testing.expectEqual(@as(u21, 'b'), buf.get(7, 3).char);
}

test "behavior: Tabs applies divider style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "A", "B" };
    const tabs = Tabs{
        .titles = &titles,
        .style = Style.init().italic(),
        .divider = "-",
    };
    tabs.render(Rect.init(0, 0, 20, 1), &buf);

    // Divider at position 1 should have normal style
    try std.testing.expectEqual(@as(u21, '-'), buf.get(1, 0).char);
    try std.testing.expect(buf.get(1, 0).style.hasAttribute(.italic));
}

test "behavior: Tabs clips at area boundary" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "VeryLongTab", "Another" };
    const tabs = Tabs{
        .titles = &titles,
        .divider = " | ",
    };
    tabs.render(Rect.init(0, 0, 10, 1), &buf);

    // Should render what fits
    try std.testing.expectEqual(@as(u21, 'V'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).char);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Tabs handles empty titles" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const titles = [_][]const u8{};
    const tabs = Tabs{ .titles = &titles };
    tabs.render(Rect.init(0, 0, 20, 5), &buf);

    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Tabs handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    const titles = [_][]const u8{"Tab"};
    const tabs = Tabs{ .titles = &titles };
    tabs.render(Rect.init(0, 0, 0, 0), &buf);

    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Tabs handles single tab" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const titles = [_][]const u8{"Solo"};
    const tabs = Tabs{
        .titles = &titles,
        .selected = 0,
        .highlight_style = Style.init().bold(),
    };
    tabs.render(Rect.init(0, 0, 20, 1), &buf);

    // Single tab should be highlighted, no divider
    try std.testing.expect(buf.get(0, 0).style.hasAttribute(.bold));
    try std.testing.expectEqual(@as(u21, 'S'), buf.get(0, 0).char);
}

test "regression: Tabs selection out of bounds uses first tab" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "A", "B" };
    const tabs = Tabs{
        .titles = &titles,
        .selected = 99,
        .highlight_style = Style.init().bold(),
    };
    tabs.render(Rect.init(0, 0, 20, 1), &buf);

    // Should render without crash
    // No tab should be highlighted since selected is out of range
    try std.testing.expect(!buf.get(0, 0).style.hasAttribute(.bold));
}

test "regression: Tabs with empty divider" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "A", "B", "C" };
    const tabs = Tabs{
        .titles = &titles,
        .divider = "",
    };
    tabs.render(Rect.init(0, 0, 20, 1), &buf);

    // "ABC" with no dividers
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'C'), buf.get(2, 0).char);
}

test "regression: Tabs with narrow width" {
    var buf = try Buffer.init(std.testing.allocator, 3, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "AAAA", "BBBB" };
    const tabs = Tabs{
        .titles = &titles,
        .divider = "|",
    };
    tabs.render(Rect.init(0, 0, 3, 1), &buf);

    // Should render what fits (AAA)
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(2, 0).char);
}

test "regression: Tabs last tab selected" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const titles = [_][]const u8{ "First", "Last" };
    const tabs = Tabs{
        .titles = &titles,
        .selected = 1,
        .highlight_style = Style.init().bold(),
        .divider = "|",
    };
    tabs.render(Rect.init(0, 0, 20, 1), &buf);

    // "First|Last"
    // First at 0-4, | at 5, Last at 6-9

    // Last should be bold
    try std.testing.expect(buf.get(6, 0).style.hasAttribute(.bold));
}
