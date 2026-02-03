// Menu widget for zithril TUI framework
// Nested menu navigation with keyboard support

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const block_mod = @import("block.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Block = block_mod.Block;
pub const BorderType = block_mod.BorderType;

/// Symbols used for menu rendering.
pub const MenuSymbols = struct {
    /// Indicator for items with submenus.
    submenu_indicator: []const u8 = "\xe2\x96\xb6", // ">"
    /// Character used for separator lines.
    separator: u21 = 0x2500, // "─"
    /// Checkbox checked state.
    checkbox_checked: []const u8 = "[\xe2\x9c\x93]", // "[x]"
    /// Checkbox unchecked state.
    checkbox_unchecked: []const u8 = "[ ]",
    /// Radio button selected state.
    radio_selected: []const u8 = "(\xe2\x80\xa2)", // "(o)"
    /// Radio button unselected state.
    radio_unselected: []const u8 = "( )",
};

/// Default menu symbols.
pub const default_symbols = MenuSymbols{};

/// A single menu item.
pub const MenuItem = struct {
    /// Display text for the item.
    label: []const u8 = "",
    /// Optional keyboard shortcut (e.g., "Ctrl+S").
    shortcut: ?[]const u8 = null,
    /// Child menu items for nested menus.
    children: []const MenuItem = &.{},
    /// Whether the item is enabled/selectable.
    enabled: bool = true,
    /// Whether this is a separator line instead of an item.
    separator: bool = false,

    /// Check if this item is a separator.
    pub fn isSeparator(self: MenuItem) bool {
        return self.separator;
    }

    /// Check if this item has children (submenu).
    pub fn hasChildren(self: MenuItem) bool {
        return self.children.len > 0;
    }

    /// Create a separator item.
    pub fn sep() MenuItem {
        return .{ .separator = true };
    }
};

/// State for tracking menu navigation.
pub const MenuState = struct {
    /// Stack of selected indices (for nested menus).
    /// path[0] is the root selection, path[depth] is the current level.
    path: [8]usize = [_]usize{0} ** 8,
    /// Current depth in the menu hierarchy.
    depth: usize = 0,
    /// Whether a submenu is open.
    submenu_open: bool = false,

    /// Get the selected index at the current depth.
    pub fn current(self: MenuState) usize {
        return self.path[self.depth];
    }

    /// Get the selected index at a specific depth.
    pub fn at(self: MenuState, d: usize) usize {
        return self.path[d];
    }

    /// Enter a submenu.
    pub fn enter(self: *MenuState) void {
        if (self.depth < self.path.len - 1) {
            self.depth += 1;
            self.path[self.depth] = 0;
            self.submenu_open = true;
        }
    }

    /// Leave the current submenu (go to parent).
    pub fn leave(self: *MenuState) void {
        if (self.depth > 0) {
            self.depth -= 1;
        }
        if (self.depth == 0) {
            self.submenu_open = false;
        }
    }

    /// Move selection up within the current menu.
    pub fn up(self: *MenuState, items: []const MenuItem) void {
        if (items.len == 0) return;
        var current_index = self.path[self.depth];

        // Skip separators when moving up
        var attempts: usize = 0;
        while (attempts < items.len) : (attempts += 1) {
            if (current_index == 0) {
                current_index = items.len - 1;
            } else {
                current_index -= 1;
            }
            if (!items[current_index].isSeparator()) {
                self.path[self.depth] = current_index;
                return;
            }
        }
    }

    /// Move selection down within the current menu.
    pub fn down(self: *MenuState, items: []const MenuItem) void {
        if (items.len == 0) return;
        var current_index = self.path[self.depth];

        // Skip separators when moving down
        var attempts: usize = 0;
        while (attempts < items.len) : (attempts += 1) {
            current_index = (current_index + 1) % items.len;
            if (!items[current_index].isSeparator()) {
                self.path[self.depth] = current_index;
                return;
            }
        }
    }

    /// Select a specific index at the current depth.
    pub fn select(self: *MenuState, index: usize) void {
        self.path[self.depth] = index;
    }

    /// Reset to initial state.
    pub fn reset(self: *MenuState) void {
        self.* = MenuState{};
    }
};

/// Menu widget for displaying and navigating menus.
pub const Menu = struct {
    /// Menu items to display.
    items: []const MenuItem,
    /// Style for normal items.
    style: Style = Style.empty,
    /// Style for the highlighted/selected item.
    highlight_style: Style = Style.init().bg(.blue),
    /// Style for disabled items.
    disabled_style: Style = Style.init().fg(.bright_black),
    /// Style for the menu border.
    border_style: Style = Style.empty,
    /// Border type for the menu.
    border: BorderType = .rounded,
    /// Minimum width (auto-calculated if null).
    width: ?u16 = null,
    /// Symbols for menu rendering.
    symbols: MenuSymbols = default_symbols,
    /// Left padding inside the menu.
    padding_left: u16 = 1,
    /// Right padding inside the menu.
    padding_right: u16 = 1,
    /// Horizontal gap between label and shortcut.
    shortcut_gap: u16 = 2,

    /// Calculate the required width for this menu.
    pub fn calculateWidth(self: Menu) u16 {
        if (self.width) |w| return w;

        var max_label_len: u16 = 0;
        var max_shortcut_len: u16 = 0;
        var has_submenu = false;

        for (self.items) |item| {
            if (item.isSeparator()) continue;

            const label_len: u16 = @intCast(item.label.len);
            max_label_len = @max(max_label_len, label_len);

            if (item.shortcut) |shortcut| {
                max_shortcut_len = @max(max_shortcut_len, @as(u16, @intCast(shortcut.len)));
            }

            if (item.hasChildren()) {
                has_submenu = true;
            }
        }

        var total_width = self.padding_left + max_label_len + self.padding_right;

        if (max_shortcut_len > 0) {
            total_width += self.shortcut_gap + max_shortcut_len;
        }

        if (has_submenu) {
            total_width += 1 + @as(u16, @intCast(self.symbols.submenu_indicator.len));
        }

        // Add border width (2)
        return total_width + 2;
    }

    /// Calculate the required height for this menu.
    pub fn calculateHeight(self: Menu) u16 {
        // Items + border (2)
        return @as(u16, @intCast(self.items.len)) + 2;
    }

    /// Render the menu into the buffer at the given area.
    pub fn render(self: Menu, area: Rect, buf: *Buffer, state: MenuState) void {
        if (area.isEmpty()) return;
        if (self.items.len == 0) return;

        // Draw the border/background
        const block = Block{
            .border = self.border,
            .border_style = self.border_style,
            .style = self.style,
        };
        block.render(area, buf);

        const inner_area = block.inner(area);
        if (inner_area.isEmpty()) return;

        const current_selection = state.current();

        // Calculate widths for layout
        const content_width = inner_area.width -| self.padding_left -| self.padding_right;
        var shortcut_col: u16 = 0;
        var has_submenu = false;

        // Find maximum label width and check for submenus
        var max_label: u16 = 0;
        for (self.items) |item| {
            if (!item.isSeparator()) {
                max_label = @max(max_label, @as(u16, @intCast(item.label.len)));
                if (item.hasChildren()) has_submenu = true;
            }
        }

        // Calculate shortcut column position
        if (has_submenu) {
            shortcut_col = content_width -| @as(u16, @intCast(self.symbols.submenu_indicator.len)) -| 1;
        } else {
            shortcut_col = content_width;
        }

        // Render each item
        var y = inner_area.y;
        for (self.items, 0..) |item, i| {
            if (y >= inner_area.bottom()) break;

            const is_selected = i == current_selection and state.depth == 0;
            self.renderItem(inner_area, buf, item, y, is_selected, shortcut_col, has_submenu);
            y += 1;
        }
    }

    /// Render a single menu item.
    fn renderItem(
        self: Menu,
        area: Rect,
        buf: *Buffer,
        item: MenuItem,
        y: u16,
        is_selected: bool,
        shortcut_col: u16,
        has_submenu_indicator: bool,
    ) void {
        if (item.isSeparator()) {
            // Draw separator line
            const sep_style = self.style;
            var x = area.x;
            while (x < area.right()) : (x += 1) {
                buf.set(x, y, Cell.styled(self.symbols.separator, sep_style));
            }
            return;
        }

        // Determine style based on state
        const row_style = if (!item.enabled)
            self.disabled_style
        else if (is_selected)
            self.highlight_style
        else
            self.style;

        // Fill the entire row with the appropriate style if selected
        if (is_selected) {
            const row_rect = Rect.init(area.x, y, area.width, 1);
            buf.fill(row_rect, Cell.styled(' ', row_style));
        }

        // Draw label with left padding
        const label_x = area.x +| self.padding_left;
        buf.setString(label_x, y, item.label, row_style);

        // Draw shortcut if present (right-aligned before submenu indicator)
        if (item.shortcut) |shortcut| {
            const shortcut_len: u16 = @intCast(shortcut.len);
            const shortcut_x = if (has_submenu_indicator)
                area.x +| shortcut_col -| shortcut_len -| self.shortcut_gap
            else
                area.right() -| self.padding_right -| shortcut_len;
            if (shortcut_x >= area.x and shortcut_x < area.right()) {
                buf.setString(shortcut_x, y, shortcut, row_style);
            }
        }

        // Draw submenu indicator if this item has children
        if (item.hasChildren()) {
            const indicator_x = area.right() -| self.padding_right -| @as(u16, @intCast(self.symbols.submenu_indicator.len));
            if (indicator_x >= area.x) {
                buf.setString(indicator_x, y, self.symbols.submenu_indicator, row_style);
            }
        }
    }

    /// Render a submenu at the specified position.
    /// Returns the area occupied by the submenu (for recursive rendering).
    pub fn renderSubmenu(
        self: Menu,
        parent_area: Rect,
        buf: *Buffer,
        state: MenuState,
        items: []const MenuItem,
        depth: usize,
    ) Rect {
        if (items.len == 0) return Rect.init(0, 0, 0, 0);

        // Create a temporary menu for the submenu
        const submenu = Menu{
            .items = items,
            .style = self.style,
            .highlight_style = self.highlight_style,
            .disabled_style = self.disabled_style,
            .border_style = self.border_style,
            .border = self.border,
            .symbols = self.symbols,
            .padding_left = self.padding_left,
            .padding_right = self.padding_right,
            .shortcut_gap = self.shortcut_gap,
        };

        const submenu_width = submenu.calculateWidth();
        const submenu_height = submenu.calculateHeight();

        // Position submenu to the right of parent
        const submenu_x = parent_area.right();
        const parent_selection = state.at(depth -| 1);
        const submenu_y = parent_area.y +| @as(u16, @intCast(parent_selection)) +| 1; // +1 for border

        const submenu_area = Rect.init(submenu_x, submenu_y, submenu_width, submenu_height);

        // Create a modified state at the correct depth
        var submenu_state = state;
        submenu_state.depth = 0; // Render as if it's the root
        submenu_state.path[0] = state.at(depth);

        submenu.render(submenu_area, buf, submenu_state);

        return submenu_area;
    }

    /// Get the currently selected item based on state.
    pub fn getSelectedItem(self: Menu, state: MenuState) ?*const MenuItem {
        return self.getItemAtPath(state);
    }

    /// Get item at a specific path depth.
    fn getItemAtPath(self: Menu, state: MenuState) ?*const MenuItem {
        var items = self.items;
        var d: usize = 0;

        while (d <= state.depth) {
            const idx = state.at(d);
            if (idx >= items.len) return null;

            if (d == state.depth) {
                return &items[idx];
            }

            // Navigate into submenu
            if (items[idx].hasChildren()) {
                items = items[idx].children;
                d += 1;
            } else {
                return null;
            }
        }

        return null;
    }

    /// Check if the currently selected item has children.
    pub fn selectedHasChildren(self: Menu, state: MenuState) bool {
        if (self.getSelectedItem(state)) |item| {
            return item.hasChildren();
        }
        return false;
    }

    /// Check if the currently selected item is enabled.
    pub fn selectedIsEnabled(self: Menu, state: MenuState) bool {
        if (self.getSelectedItem(state)) |item| {
            return item.enabled;
        }
        return false;
    }

    /// Get the items at the current depth.
    pub fn getItemsAtDepth(self: Menu, state: MenuState) []const MenuItem {
        var items = self.items;
        var d: usize = 0;

        while (d < state.depth) {
            const idx = state.at(d);
            if (idx >= items.len) return &.{};

            if (items[idx].hasChildren()) {
                items = items[idx].children;
                d += 1;
            } else {
                return &.{};
            }
        }

        return items;
    }
};

// ============================================================
// SANITY TESTS - Basic Menu functionality
// ============================================================

test "sanity: MenuItem with default values" {
    const item = MenuItem{ .label = "Test" };
    try std.testing.expectEqualStrings("Test", item.label);
    try std.testing.expect(item.shortcut == null);
    try std.testing.expect(item.children.len == 0);
    try std.testing.expect(item.enabled);
    try std.testing.expect(!item.separator);
    try std.testing.expect(!item.isSeparator());
    try std.testing.expect(!item.hasChildren());
}

test "sanity: MenuItem.sep creates separator" {
    const sep = MenuItem.sep();
    try std.testing.expect(sep.isSeparator());
}

test "sanity: MenuItem with children" {
    const children = [_]MenuItem{
        .{ .label = "Child 1" },
        .{ .label = "Child 2" },
    };

    const item = MenuItem{
        .label = "Parent",
        .children = &children,
    };

    try std.testing.expect(item.hasChildren());
    try std.testing.expectEqual(@as(usize, 2), item.children.len);
}

test "sanity: MenuItem with shortcut" {
    const item = MenuItem{
        .label = "Save",
        .shortcut = "Ctrl+S",
    };
    try std.testing.expectEqualStrings("Save", item.label);
    try std.testing.expectEqualStrings("Ctrl+S", item.shortcut.?);
}

test "sanity: MenuState with default values" {
    const state = MenuState{};
    try std.testing.expectEqual(@as(usize, 0), state.depth);
    try std.testing.expectEqual(@as(usize, 0), state.current());
    try std.testing.expect(!state.submenu_open);
}

test "sanity: MenuState navigation" {
    var state = MenuState{};

    state.select(2);
    try std.testing.expectEqual(@as(usize, 2), state.current());

    state.enter();
    try std.testing.expectEqual(@as(usize, 1), state.depth);
    try std.testing.expectEqual(@as(usize, 0), state.current());
    try std.testing.expect(state.submenu_open);

    state.select(1);
    try std.testing.expectEqual(@as(usize, 1), state.current());

    state.leave();
    try std.testing.expectEqual(@as(usize, 0), state.depth);
    try std.testing.expectEqual(@as(usize, 2), state.current());
}

test "sanity: Menu with default values" {
    const items = [_]MenuItem{
        .{ .label = "Item 1" },
        .{ .label = "Item 2" },
    };

    const menu = Menu{ .items = &items };
    try std.testing.expectEqual(@as(usize, 2), menu.items.len);
    try std.testing.expect(menu.width == null);
    try std.testing.expect(menu.border == .rounded);
}

test "sanity: Menu.calculateWidth" {
    const items = [_]MenuItem{
        .{ .label = "Short" },
        .{ .label = "Longer Label" },
    };

    const menu = Menu{ .items = &items };
    const width = menu.calculateWidth();

    // "Longer Label" = 12 chars + padding (1+1) + border (2) = 16
    try std.testing.expect(width >= 16);
}

test "sanity: Menu.calculateWidth with shortcuts" {
    const items = [_]MenuItem{
        .{ .label = "Save", .shortcut = "Ctrl+S" },
        .{ .label = "Open", .shortcut = "Ctrl+O" },
    };

    const menu = Menu{ .items = &items };
    const width = menu.calculateWidth();

    // "Save" = 4 chars + padding (1+1) + shortcut_gap (2) + "Ctrl+S" (6) + border (2) = 16
    try std.testing.expect(width >= 16);
}

test "sanity: Menu.calculateHeight" {
    const items = [_]MenuItem{
        .{ .label = "A" },
        .{ .label = "B" },
        .{ .label = "C" },
    };

    const menu = Menu{ .items = &items };
    const height = menu.calculateHeight();

    // 3 items + 2 border = 5
    try std.testing.expectEqual(@as(u16, 5), height);
}

// ============================================================
// BEHAVIOR TESTS - MenuState navigation
// ============================================================

test "behavior: MenuState.up wraps around" {
    const items = [_]MenuItem{
        .{ .label = "A" },
        .{ .label = "B" },
        .{ .label = "C" },
    };

    var state = MenuState{};
    state.up(&items);
    try std.testing.expectEqual(@as(usize, 2), state.current());

    state.up(&items);
    try std.testing.expectEqual(@as(usize, 1), state.current());
}

test "behavior: MenuState.down wraps around" {
    const items = [_]MenuItem{
        .{ .label = "A" },
        .{ .label = "B" },
        .{ .label = "C" },
    };

    var state = MenuState{};
    state.select(2);

    state.down(&items);
    try std.testing.expectEqual(@as(usize, 0), state.current());
}

test "behavior: MenuState.up skips separators" {
    const items = [_]MenuItem{
        .{ .label = "A" },
        MenuItem.sep(),
        .{ .label = "B" },
    };

    var state = MenuState{};
    state.select(2);

    state.up(&items);
    try std.testing.expectEqual(@as(usize, 0), state.current());
}

test "behavior: MenuState.down skips separators" {
    const items = [_]MenuItem{
        .{ .label = "A" },
        MenuItem.sep(),
        .{ .label = "B" },
    };

    var state = MenuState{};

    state.down(&items);
    try std.testing.expectEqual(@as(usize, 2), state.current());
}

test "behavior: MenuState.enter and leave" {
    var state = MenuState{};

    state.enter();
    try std.testing.expectEqual(@as(usize, 1), state.depth);
    try std.testing.expect(state.submenu_open);

    state.enter();
    try std.testing.expectEqual(@as(usize, 2), state.depth);

    state.leave();
    try std.testing.expectEqual(@as(usize, 1), state.depth);
    try std.testing.expect(state.submenu_open);

    state.leave();
    try std.testing.expectEqual(@as(usize, 0), state.depth);
    try std.testing.expect(!state.submenu_open);
}

test "behavior: MenuState.reset clears state" {
    var state = MenuState{};
    state.select(5);
    state.enter();
    state.select(3);

    state.reset();
    try std.testing.expectEqual(@as(usize, 0), state.depth);
    try std.testing.expectEqual(@as(usize, 0), state.current());
    try std.testing.expect(!state.submenu_open);
}

// ============================================================
// BEHAVIOR TESTS - Menu rendering
// ============================================================

test "behavior: Menu renders items" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const items = [_]MenuItem{
        .{ .label = "Alpha" },
        .{ .label = "Beta" },
        .{ .label = "Gamma" },
    };

    const menu = Menu{ .items = &items };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 20, 6), &buf, state);

    // Items should be rendered (after border and padding)
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(2, 1).char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(2, 2).char);
    try std.testing.expectEqual(@as(u21, 'G'), buf.get(2, 3).char);
}

test "behavior: Menu renders selected item with highlight" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const items = [_]MenuItem{
        .{ .label = "One" },
        .{ .label = "Two" },
        .{ .label = "Three" },
    };

    const menu = Menu{
        .items = &items,
        .highlight_style = Style.init().bold(),
    };

    var state = MenuState{};
    state.select(1);

    menu.render(Rect.init(0, 0, 20, 6), &buf, state);

    // Row with "Two" should have highlight style
    try std.testing.expect(buf.get(2, 2).style.hasAttribute(.bold));

    // Other rows should not have bold
    try std.testing.expect(!buf.get(2, 1).style.hasAttribute(.bold));
    try std.testing.expect(!buf.get(2, 3).style.hasAttribute(.bold));
}

test "behavior: Menu renders separator" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const items = [_]MenuItem{
        .{ .label = "Above" },
        MenuItem.sep(),
        .{ .label = "Below" },
    };

    const menu = Menu{ .items = &items };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 20, 6), &buf, state);

    // Separator should be a horizontal line character
    const sep_cell = buf.get(2, 2);
    try std.testing.expectEqual(@as(u21, 0x2500), sep_cell.char);
}

test "behavior: Menu renders shortcuts" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const items = [_]MenuItem{
        .{ .label = "Save", .shortcut = "Ctrl+S" },
    };

    const menu = Menu{ .items = &items, .width = 25 };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 25, 4), &buf, state);

    // Find "Ctrl+S" somewhere in the row
    var found_ctrl = false;
    var x: u16 = 0;
    while (x < 25) : (x += 1) {
        if (buf.get(x, 1).char == 'C') {
            found_ctrl = true;
            break;
        }
    }
    try std.testing.expect(found_ctrl);
}

test "behavior: Menu renders submenu indicator" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const submenu = [_]MenuItem{
        .{ .label = "Child" },
    };

    const items = [_]MenuItem{
        .{ .label = "Parent", .children = &submenu },
    };

    const menu = Menu{ .items = &items, .width = 20 };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 20, 4), &buf, state);

    // Verify item rendered correctly
    try std.testing.expectEqual(@as(u21, 'P'), buf.get(2, 1).char);

    // Find submenu indicator (U+25B6) somewhere in the row
    var found_indicator = false;
    for (2..19) |x| {
        if (buf.get(@intCast(x), 1).char == 0x25B6) {
            found_indicator = true;
            break;
        }
    }
    try std.testing.expect(found_indicator);
}

test "behavior: Menu renders disabled item" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const items = [_]MenuItem{
        .{ .label = "Enabled" },
        .{ .label = "Disabled", .enabled = false },
    };

    const menu = Menu{
        .items = &items,
        .disabled_style = Style.init().italic(),
    };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 20, 5), &buf, state);

    // Disabled item should have italic style
    try std.testing.expect(buf.get(2, 2).style.hasAttribute(.italic));

    // Enabled item should not have italic
    try std.testing.expect(!buf.get(2, 1).style.hasAttribute(.italic));
}

test "behavior: Menu renders border" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const items = [_]MenuItem{
        .{ .label = "Item" },
    };

    const menu = Menu{ .items = &items, .border = .rounded };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 15, 4), &buf, state);

    // Check rounded corners
    try std.testing.expectEqual(@as(u21, 0x256D), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 0x256E), buf.get(14, 0).char);
}

// ============================================================
// BEHAVIOR TESTS - Menu item access
// ============================================================

test "behavior: Menu.getSelectedItem returns correct item" {
    const items = [_]MenuItem{
        .{ .label = "First" },
        .{ .label = "Second" },
        .{ .label = "Third" },
    };

    const menu = Menu{ .items = &items };
    var state = MenuState{};

    state.select(1);
    const selected = menu.getSelectedItem(state);
    try std.testing.expect(selected != null);
    try std.testing.expectEqualStrings("Second", selected.?.label);
}

test "behavior: Menu.selectedHasChildren" {
    const children = [_]MenuItem{
        .{ .label = "Child" },
    };

    const items = [_]MenuItem{
        .{ .label = "No children" },
        .{ .label = "Has children", .children = &children },
    };

    const menu = Menu{ .items = &items };
    var state = MenuState{};

    try std.testing.expect(!menu.selectedHasChildren(state));

    state.select(1);
    try std.testing.expect(menu.selectedHasChildren(state));
}

test "behavior: Menu.selectedIsEnabled" {
    const items = [_]MenuItem{
        .{ .label = "Enabled" },
        .{ .label = "Disabled", .enabled = false },
    };

    const menu = Menu{ .items = &items };
    var state = MenuState{};

    try std.testing.expect(menu.selectedIsEnabled(state));

    state.select(1);
    try std.testing.expect(!menu.selectedIsEnabled(state));
}

test "behavior: Menu.getItemsAtDepth" {
    const grandchildren = [_]MenuItem{
        .{ .label = "Grandchild" },
    };

    const children = [_]MenuItem{
        .{ .label = "Child", .children = &grandchildren },
    };

    const items = [_]MenuItem{
        .{ .label = "Root", .children = &children },
    };

    const menu = Menu{ .items = &items };
    var state = MenuState{};

    const depth0_items = menu.getItemsAtDepth(state);
    try std.testing.expectEqual(@as(usize, 1), depth0_items.len);
    try std.testing.expectEqualStrings("Root", depth0_items[0].label);

    state.enter();
    const depth1_items = menu.getItemsAtDepth(state);
    try std.testing.expectEqual(@as(usize, 1), depth1_items.len);
    try std.testing.expectEqualStrings("Child", depth1_items[0].label);

    state.enter();
    const depth2_items = menu.getItemsAtDepth(state);
    try std.testing.expectEqual(@as(usize, 1), depth2_items.len);
    try std.testing.expectEqualStrings("Grandchild", depth2_items[0].label);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Menu handles empty items" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const items = [_]MenuItem{};
    const menu = Menu{ .items = &items };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 20, 5), &buf, state);

    // Should not crash; buffer mostly unchanged except any default fill
}

test "regression: Menu handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 30, 30);
    defer buf.deinit();

    const items = [_]MenuItem{
        .{ .label = "Item" },
    };

    const menu = Menu{ .items = &items };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 0, 0), &buf, state);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Menu handles very narrow width" {
    var buf = try Buffer.init(std.testing.allocator, 5, 10);
    defer buf.deinit();

    const items = [_]MenuItem{
        .{ .label = "Very long label" },
    };

    const menu = Menu{ .items = &items, .width = 5 };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 5, 4), &buf, state);

    // Should render what fits without crash
}

test "regression: MenuState at max depth" {
    var state = MenuState{};

    // Fill to max depth
    var i: usize = 0;
    while (i < 7) : (i += 1) {
        state.enter();
    }

    try std.testing.expectEqual(@as(usize, 7), state.depth);

    // Should not go beyond max
    state.enter();
    try std.testing.expectEqual(@as(usize, 7), state.depth);
}

test "regression: Menu.getSelectedItem with out of bounds index" {
    const items = [_]MenuItem{
        .{ .label = "Item" },
    };

    const menu = Menu{ .items = &items };
    var state = MenuState{};
    state.select(100);

    const selected = menu.getSelectedItem(state);
    try std.testing.expect(selected == null);
}

test "regression: MenuState.up with all separators" {
    const items = [_]MenuItem{
        MenuItem.sep(),
        MenuItem.sep(),
    };

    var state = MenuState{};

    // Should not infinite loop - just stays at current
    state.up(&items);
}

test "regression: MenuState.down with all separators" {
    const items = [_]MenuItem{
        MenuItem.sep(),
        MenuItem.sep(),
    };

    var state = MenuState{};

    // Should not infinite loop
    state.down(&items);
}

test "regression: Menu with only separators" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const items = [_]MenuItem{
        MenuItem.sep(),
        MenuItem.sep(),
    };

    const menu = Menu{ .items = &items };
    const state = MenuState{};

    menu.render(Rect.init(0, 0, 20, 5), &buf, state);

    // Should render separators without crash
}

test "regression: Menu calculateWidth with only separators" {
    const items = [_]MenuItem{
        MenuItem.sep(),
        MenuItem.sep(),
    };

    const menu = Menu{ .items = &items };
    const width = menu.calculateWidth();

    // Should return minimum width (border + padding)
    try std.testing.expect(width >= 4);
}
