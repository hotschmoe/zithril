// List widget for zithril TUI framework
// Navigable list with items, selection, and highlight styling

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Navigable list widget with items, selection highlighting, and scroll support.
///
/// Renders a vertical list of text items. The selected item is highlighted
/// with highlight_style and prefixed with highlight_symbol.
pub const List = struct {
    /// The items to display in the list
    items: []const []const u8,

    /// Currently selected item index (null for no selection)
    selected: ?usize = null,

    /// Default style for non-selected items
    style: Style = Style.empty,

    /// Style for the selected item
    highlight_style: Style = Style.init().bg(.blue),

    /// Prefix shown before the selected item
    highlight_symbol: []const u8 = "> ",

    /// Render the list into the buffer at the given area.
    /// Each item takes one row. Items beyond the area height are not rendered.
    pub fn render(self: List, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.items.len == 0) return;

        const symbol_len: u16 = @intCast(@min(self.highlight_symbol.len, area.width));
        const content_start = area.x +| symbol_len;
        const content_width = area.width -| symbol_len;

        // Render visible items
        var y = area.y;
        var item_index: usize = 0;
        while (item_index < self.items.len and y < area.bottom()) : ({
            y += 1;
            item_index += 1;
        }) {
            const item = self.items[item_index];
            const is_selected = self.selected != null and self.selected.? == item_index;

            if (is_selected) {
                // Fill the entire row with highlight style
                const row_rect = Rect.init(area.x, y, area.width, 1);
                buf.fill(row_rect, Cell.styled(' ', self.highlight_style));

                // Draw highlight symbol
                if (symbol_len > 0) {
                    buf.setString(area.x, y, self.highlight_symbol[0..symbol_len], self.highlight_style);
                }

                // Draw item text with highlight style
                if (content_width > 0) {
                    buf.setString(content_start, y, item, self.highlight_style);
                }
            } else {
                // Draw item text with normal style (offset for alignment with highlighted items)
                if (content_width > 0) {
                    buf.setString(content_start, y, item, self.style);
                }
            }
        }
    }

    /// Get the number of items in the list
    pub fn len(self: List) usize {
        return self.items.len;
    }

    /// Check if the list is empty
    pub fn isEmpty(self: List) bool {
        return self.items.len == 0;
    }
};

// ============================================================
// SANITY TESTS - Basic List functionality
// ============================================================

test "sanity: List with default values" {
    const items = [_][]const u8{ "a", "b", "c" };
    const list = List{ .items = &items };

    try std.testing.expectEqual(@as(usize, 3), list.len());
    try std.testing.expect(list.selected == null);
    try std.testing.expect(list.style.isEmpty());
    try std.testing.expectEqualStrings("> ", list.highlight_symbol);
}

test "sanity: List with selection" {
    const items = [_][]const u8{ "a", "b", "c" };
    const list = List{
        .items = &items,
        .selected = 1,
    };

    try std.testing.expect(list.selected != null);
    try std.testing.expectEqual(@as(usize, 1), list.selected.?);
}

test "sanity: List with custom styles" {
    const items = [_][]const u8{ "a", "b" };
    const list = List{
        .items = &items,
        .style = Style.init().fg(.white),
        .highlight_style = Style.init().bg(.red).bold(),
        .highlight_symbol = "* ",
    };

    try std.testing.expect(!list.style.isEmpty());
    try std.testing.expect(list.highlight_style.hasAttribute(.bold));
    try std.testing.expectEqualStrings("* ", list.highlight_symbol);
}

test "sanity: List.len and List.isEmpty" {
    const items = [_][]const u8{ "a", "b" };
    const list = List{ .items = &items };

    try std.testing.expectEqual(@as(usize, 2), list.len());
    try std.testing.expect(!list.isEmpty());

    const empty_items = [_][]const u8{};
    const empty_list = List{ .items = &empty_items };

    try std.testing.expectEqual(@as(usize, 0), empty_list.len());
    try std.testing.expect(empty_list.isEmpty());
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: List renders items" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{ "Alpha", "Beta", "Gamma" };
    const list = List{ .items = &items };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    // Items should be offset by highlight_symbol length (2)
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(3, 0).char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(2, 1).char);
    try std.testing.expectEqual(@as(u21, 'G'), buf.get(2, 2).char);
}

test "behavior: List renders selected item with highlight" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{ "One", "Two", "Three" };
    const list = List{
        .items = &items,
        .selected = 1,
        .highlight_style = Style.init().bold(),
    };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    // Row 1 should have highlight style
    try std.testing.expect(buf.get(0, 1).style.hasAttribute(.bold));
    try std.testing.expect(buf.get(2, 1).style.hasAttribute(.bold));

    // Row 0 and 2 should not have bold
    try std.testing.expect(!buf.get(2, 0).style.hasAttribute(.bold));
    try std.testing.expect(!buf.get(2, 2).style.hasAttribute(.bold));
}

test "behavior: List renders highlight symbol" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B", "C" };
    const list = List{
        .items = &items,
        .selected = 1,
        .highlight_symbol = "> ",
    };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    // Selected row (1) should have highlight symbol
    try std.testing.expectEqual(@as(u21, '>'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(1, 1).char);

    // Non-selected rows should not have symbol (spaces)
    try std.testing.expect(buf.get(0, 0).isDefault() or buf.get(0, 0).char == ' ');
}

test "behavior: List respects area boundaries" {
    var buf = try Buffer.init(std.testing.allocator, 20, 2);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B", "C", "D", "E" };
    const list = List{ .items = &items };
    list.render(Rect.init(0, 0, 20, 2), &buf);

    // Only first 2 items should be rendered
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(2, 1).char);
}

test "behavior: List renders at area offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const items = [_][]const u8{ "X", "Y" };
    const list = List{ .items = &items };
    list.render(Rect.init(5, 3, 10, 5), &buf);

    // Items at offset position
    try std.testing.expectEqual(@as(u21, 'X'), buf.get(7, 3).char);
    try std.testing.expectEqual(@as(u21, 'Y'), buf.get(7, 4).char);
}

test "behavior: List applies item style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{ "Item" };
    const list = List{
        .items = &items,
        .style = Style.init().italic(),
    };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    try std.testing.expect(buf.get(2, 0).style.hasAttribute(.italic));
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: List handles empty items" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{};
    const list = List{ .items = &items };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: List handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B" };
    const list = List{ .items = &items };
    list.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: List handles selection out of bounds" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B" };
    const list = List{
        .items = &items,
        .selected = 10, // Out of bounds
    };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    // Should render without crash; no item highlighted
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(2, 0).char);
}

test "regression: List handles narrow width" {
    var buf = try Buffer.init(std.testing.allocator, 3, 5);
    defer buf.deinit();

    const items = [_][]const u8{ "Long text" };
    const list = List{
        .items = &items,
        .highlight_symbol = "> ",
    };
    list.render(Rect.init(0, 0, 3, 5), &buf);

    // Should render what fits
    try std.testing.expectEqual(@as(u21, 'L'), buf.get(2, 0).char);
}

test "regression: List with single item" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{"Solo"};
    const list = List{
        .items = &items,
        .selected = 0,
        .highlight_style = Style.init().bold(),
    };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    try std.testing.expect(buf.get(0, 0).style.hasAttribute(.bold));
    try std.testing.expectEqual(@as(u21, 'S'), buf.get(2, 0).char);
}

test "regression: List with empty highlight symbol" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{ "A", "B" };
    const list = List{
        .items = &items,
        .selected = 0,
        .highlight_symbol = "",
    };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    // Item should start at x=0 since no symbol
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(0, 0).char);
}

test "regression: List first item selected" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{ "First", "Second" };
    const list = List{
        .items = &items,
        .selected = 0,
    };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    // Highlight symbol on first row
    try std.testing.expectEqual(@as(u21, '>'), buf.get(0, 0).char);
}

test "regression: List last item selected" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const items = [_][]const u8{ "First", "Last" };
    const list = List{
        .items = &items,
        .selected = 1,
    };
    list.render(Rect.init(0, 0, 20, 5), &buf);

    // Highlight symbol on second row
    try std.testing.expectEqual(@as(u21, '>'), buf.get(0, 1).char);
}
