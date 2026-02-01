// ScrollView widget for zithril TUI framework
// Virtual scrolling container with scroll state management and scrollbar integration

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const scrollbar_mod = @import("scrollbar.zig");
const event_mod = @import("../event.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Scrollbar = scrollbar_mod.Scrollbar;
pub const Orientation = scrollbar_mod.Orientation;
pub const MouseKind = event_mod.MouseKind;
pub const Mouse = event_mod.Mouse;
pub const KeyCode = event_mod.KeyCode;
pub const Key = event_mod.Key;

/// Scroll state for a scrollable container.
/// Tracks scroll position and provides helpers for navigation.
pub const ScrollState = struct {
    /// Current vertical scroll offset (first visible row).
    offset: usize = 0,

    /// Total number of items/rows in the content.
    total: usize = 0,

    /// Viewport height (number of visible rows).
    viewport: u16 = 0,

    /// Create a new scroll state.
    pub fn init(total: usize) ScrollState {
        return .{ .total = total };
    }

    /// Update viewport size and clamp offset if needed.
    pub fn setViewport(self: *ScrollState, viewport: u16) void {
        self.viewport = viewport;
        self.clampOffset();
    }

    /// Update total content size and clamp offset if needed.
    pub fn setTotal(self: *ScrollState, total: usize) void {
        self.total = total;
        self.clampOffset();
    }

    /// Scroll to a specific offset (clamped to valid range).
    pub fn scrollTo(self: *ScrollState, offset: usize) void {
        self.offset = offset;
        self.clampOffset();
    }

    /// Scroll by a delta amount (positive = down, negative = up).
    pub fn scrollBy(self: *ScrollState, delta: i32) void {
        if (delta < 0) {
            const abs_delta: usize = @intCast(-delta);
            self.offset -|= abs_delta;
        } else {
            const pos_delta: usize = @intCast(delta);
            self.offset +|= pos_delta;
        }
        self.clampOffset();
    }

    /// Scroll up by one line.
    pub fn scrollUp(self: *ScrollState) void {
        self.scrollBy(-1);
    }

    /// Scroll down by one line.
    pub fn scrollDown(self: *ScrollState) void {
        self.scrollBy(1);
    }

    /// Scroll up by one page (viewport height).
    pub fn pageUp(self: *ScrollState) void {
        self.scrollBy(-@as(i32, @intCast(self.viewport)));
    }

    /// Scroll down by one page (viewport height).
    pub fn pageDown(self: *ScrollState) void {
        self.scrollBy(@as(i32, @intCast(self.viewport)));
    }

    /// Scroll to the beginning.
    pub fn scrollToStart(self: *ScrollState) void {
        self.offset = 0;
    }

    /// Scroll to the end.
    pub fn scrollToEnd(self: *ScrollState) void {
        self.offset = self.maxOffset();
    }

    /// Ensure a specific index is visible, scrolling if necessary.
    pub fn ensureVisible(self: *ScrollState, index: usize) void {
        if (index < self.offset) {
            self.offset = index;
        } else if (index >= self.offset + self.viewport) {
            self.offset = index -| (self.viewport -| 1);
        }
        self.clampOffset();
    }

    /// Get the maximum valid scroll offset.
    pub fn maxOffset(self: ScrollState) usize {
        if (self.total <= self.viewport) return 0;
        return self.total - self.viewport;
    }

    /// Check if currently at the top.
    pub fn atStart(self: ScrollState) bool {
        return self.offset == 0;
    }

    /// Check if currently at the bottom.
    pub fn atEnd(self: ScrollState) bool {
        return self.offset >= self.maxOffset();
    }

    /// Check if scrolling is needed (content exceeds viewport).
    pub fn canScroll(self: ScrollState) bool {
        return self.total > self.viewport;
    }

    /// Get the range of visible indices [start, end).
    pub fn visibleRange(self: ScrollState) struct { start: usize, end: usize } {
        const start = self.offset;
        const end = @min(self.offset + self.viewport, self.total);
        return .{ .start = start, .end = end };
    }

    /// Clamp offset to valid range.
    fn clampOffset(self: *ScrollState) void {
        self.offset = @min(self.offset, self.maxOffset());
    }

    /// Handle keyboard input for scrolling.
    /// Returns true if the event was handled.
    pub fn handleKey(self: *ScrollState, key: Key) bool {
        switch (key.code) {
            .up => {
                self.scrollUp();
                return true;
            },
            .down => {
                self.scrollDown();
                return true;
            },
            .page_up => {
                self.pageUp();
                return true;
            },
            .page_down => {
                self.pageDown();
                return true;
            },
            .home => if (key.modifiers.ctrl) {
                self.scrollToStart();
                return true;
            },
            .end => if (key.modifiers.ctrl) {
                self.scrollToEnd();
                return true;
            },
            else => {},
        }
        return false;
    }

    /// Handle mouse scroll events.
    /// Returns true if the event was handled.
    pub fn handleMouse(self: *ScrollState, mouse: Mouse) bool {
        switch (mouse.kind) {
            .scroll_up => {
                self.scrollBy(-3);
                return true;
            },
            .scroll_down => {
                self.scrollBy(3);
                return true;
            },
            else => {},
        }
        return false;
    }
};

/// ScrollView widget configuration.
/// Wraps content with virtual scrolling and optional scrollbar.
pub const ScrollView = struct {
    /// Scroll state (tracks position).
    state: *ScrollState,

    /// Show scrollbar when content exceeds viewport.
    show_scrollbar: bool = true,

    /// Scrollbar style.
    scrollbar_style: Style = Style.empty,

    /// Scrollbar thumb style.
    scrollbar_thumb_style: Style = Style.init().reverse(),

    /// Background style for the viewport.
    style: Style = Style.empty,

    /// Scrollbar position (right edge by default).
    scrollbar_on_left: bool = false,

    /// Get the content area (viewport minus scrollbar if shown).
    pub fn contentArea(self: ScrollView, area: Rect) Rect {
        if (!self.show_scrollbar or !self.state.canScroll()) {
            return area;
        }

        if (self.scrollbar_on_left) {
            return Rect.init(
                area.x +| 1,
                area.y,
                area.width -| 1,
                area.height,
            );
        } else {
            return Rect.init(
                area.x,
                area.y,
                area.width -| 1,
                area.height,
            );
        }
    }

    /// Get the scrollbar area.
    pub fn scrollbarArea(self: ScrollView, area: Rect) Rect {
        if (self.scrollbar_on_left) {
            return Rect.init(area.x, area.y, 1, area.height);
        } else {
            return Rect.init(area.x +| (area.width -| 1), area.y, 1, area.height);
        }
    }

    /// Render the scrollbar (if needed).
    pub fn render(self: ScrollView, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;

        // Update viewport in scroll state
        self.state.setViewport(area.height);

        // Fill background
        if (!self.style.isEmpty()) {
            buf.fill(area, Cell.styled(' ', self.style));
        }

        // Draw scrollbar if needed
        if (self.show_scrollbar and self.state.canScroll()) {
            const sb_area = self.scrollbarArea(area);
            const scrollbar = Scrollbar{
                .total = self.state.total,
                .position = self.state.offset,
                .viewport = self.state.viewport,
                .style = self.scrollbar_style,
                .thumb_style = self.scrollbar_thumb_style,
                .orientation = .vertical,
            };
            scrollbar.render(sb_area, buf);
        }
    }
};

/// ScrollableList combines List behavior with virtual scrolling.
/// Renders only visible items and integrates with ScrollState.
pub const ScrollableList = struct {
    /// Items to display.
    items: []const []const u8,

    /// Scroll state.
    scroll: *ScrollState,

    /// Currently selected item index (null for no selection).
    selected: ?usize = null,

    /// Default style for non-selected items.
    style: Style = Style.empty,

    /// Style for the selected item.
    highlight_style: Style = Style.init().bg(.blue),

    /// Prefix shown before the selected item.
    highlight_symbol: []const u8 = "> ",

    /// Show scrollbar when content exceeds viewport.
    show_scrollbar: bool = true,

    /// Scrollbar style.
    scrollbar_style: Style = Style.empty,

    /// Scrollbar thumb style.
    scrollbar_thumb_style: Style = Style.init().reverse(),

    /// Update scroll state from items.
    pub fn syncState(self: *ScrollableList) void {
        self.scroll.setTotal(self.items.len);
        if (self.selected) |sel| {
            self.scroll.ensureVisible(sel);
        }
    }

    /// Move selection up.
    pub fn selectPrevious(self: *ScrollableList) void {
        if (self.items.len == 0) return;
        if (self.selected) |sel| {
            if (sel > 0) {
                self.selected = sel - 1;
                self.scroll.ensureVisible(sel - 1);
            }
        } else {
            self.selected = 0;
            self.scroll.ensureVisible(0);
        }
    }

    /// Move selection down.
    pub fn selectNext(self: *ScrollableList) void {
        if (self.items.len == 0) return;
        if (self.selected) |sel| {
            if (sel + 1 < self.items.len) {
                self.selected = sel + 1;
                self.scroll.ensureVisible(sel + 1);
            }
        } else {
            self.selected = 0;
            self.scroll.ensureVisible(0);
        }
    }

    /// Select first item.
    pub fn selectFirst(self: *ScrollableList) void {
        if (self.items.len == 0) return;
        self.selected = 0;
        self.scroll.ensureVisible(0);
    }

    /// Select last item.
    pub fn selectLast(self: *ScrollableList) void {
        if (self.items.len == 0) return;
        self.selected = self.items.len - 1;
        self.scroll.ensureVisible(self.items.len - 1);
    }

    /// Handle keyboard input for navigation.
    /// Returns true if the event was handled.
    pub fn handleKey(self: *ScrollableList, key: Key) bool {
        switch (key.code) {
            .up => {
                self.selectPrevious();
                return true;
            },
            .down => {
                self.selectNext();
                return true;
            },
            .home => {
                self.selectFirst();
                return true;
            },
            .end => {
                self.selectLast();
                return true;
            },
            .page_up => {
                if (self.items.len == 0) return true;
                if (self.selected) |sel| {
                    const page = self.scroll.viewport;
                    self.selected = sel -| page;
                    self.scroll.ensureVisible(self.selected.?);
                }
                return true;
            },
            .page_down => {
                if (self.items.len == 0) return true;
                if (self.selected) |sel| {
                    const page = self.scroll.viewport;
                    self.selected = @min(sel + page, self.items.len -| 1);
                    self.scroll.ensureVisible(self.selected.?);
                }
                return true;
            },
            else => {},
        }
        return false;
    }

    /// Render the scrollable list.
    pub fn render(self: ScrollableList, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;

        // Calculate content area (minus scrollbar if needed)
        const needs_scrollbar = self.show_scrollbar and self.items.len > area.height;
        const content_width = if (needs_scrollbar) area.width -| 1 else area.width;
        const content_area = Rect.init(area.x, area.y, content_width, area.height);

        if (content_area.isEmpty()) return;

        const symbol_len: u16 = @intCast(@min(self.highlight_symbol.len, content_area.width));
        const content_start = content_area.x +| symbol_len;
        const text_width = content_area.width -| symbol_len;

        // Get visible range
        const range = self.scroll.visibleRange();

        // Render visible items
        var y = content_area.y;
        var item_index = range.start;
        while (item_index < range.end and y < content_area.bottom()) : ({
            y += 1;
            item_index += 1;
        }) {
            const item = self.items[item_index];
            const is_selected = self.selected != null and self.selected.? == item_index;

            if (is_selected) {
                // Fill the entire row with highlight style
                const row_rect = Rect.init(content_area.x, y, content_area.width, 1);
                buf.fill(row_rect, Cell.styled(' ', self.highlight_style));

                // Draw highlight symbol
                if (symbol_len > 0) {
                    buf.setString(content_area.x, y, self.highlight_symbol[0..symbol_len], self.highlight_style);
                }

                // Draw item text with highlight style
                if (text_width > 0) {
                    buf.setString(content_start, y, item, self.highlight_style);
                }
            } else {
                // Draw item text with normal style
                if (text_width > 0) {
                    buf.setString(content_start, y, item, self.style);
                }
            }
        }

        // Draw scrollbar if needed
        if (needs_scrollbar) {
            const sb_area = Rect.init(area.x +| content_width, area.y, 1, area.height);
            const scrollbar = Scrollbar{
                .total = self.items.len,
                .position = self.scroll.offset,
                .viewport = area.height,
                .style = self.scrollbar_style,
                .thumb_style = self.scrollbar_thumb_style,
                .orientation = .vertical,
            };
            scrollbar.render(sb_area, buf);
        }
    }

    /// Get the number of items.
    pub fn len(self: ScrollableList) usize {
        return self.items.len;
    }

    /// Check if empty.
    pub fn isEmpty(self: ScrollableList) bool {
        return self.items.len == 0;
    }
};

// ============================================================
// SANITY TESTS - ScrollState basic functionality
// ============================================================

test "sanity: ScrollState default values" {
    const state = ScrollState{};
    try std.testing.expectEqual(@as(usize, 0), state.offset);
    try std.testing.expectEqual(@as(usize, 0), state.total);
    try std.testing.expectEqual(@as(u16, 0), state.viewport);
}

test "sanity: ScrollState.init" {
    const state = ScrollState.init(100);
    try std.testing.expectEqual(@as(usize, 0), state.offset);
    try std.testing.expectEqual(@as(usize, 100), state.total);
}

test "sanity: ScrollState.setViewport" {
    var state = ScrollState.init(100);
    state.setViewport(20);
    try std.testing.expectEqual(@as(u16, 20), state.viewport);
}

test "sanity: ScrollState.maxOffset" {
    var state = ScrollState.init(100);
    state.setViewport(20);
    try std.testing.expectEqual(@as(usize, 80), state.maxOffset());
}

test "sanity: ScrollState.canScroll" {
    var small = ScrollState.init(10);
    small.setViewport(20);
    try std.testing.expect(!small.canScroll());

    var large = ScrollState.init(100);
    large.setViewport(20);
    try std.testing.expect(large.canScroll());
}

// ============================================================
// BEHAVIOR TESTS - ScrollState navigation
// ============================================================

test "behavior: ScrollState.scrollTo" {
    var state = ScrollState.init(100);
    state.setViewport(20);

    state.scrollTo(50);
    try std.testing.expectEqual(@as(usize, 50), state.offset);

    state.scrollTo(90);
    try std.testing.expectEqual(@as(usize, 80), state.offset);

    state.scrollTo(0);
    try std.testing.expectEqual(@as(usize, 0), state.offset);
}

test "behavior: ScrollState.scrollBy" {
    var state = ScrollState.init(100);
    state.setViewport(20);

    state.scrollBy(10);
    try std.testing.expectEqual(@as(usize, 10), state.offset);

    state.scrollBy(-5);
    try std.testing.expectEqual(@as(usize, 5), state.offset);

    state.scrollBy(-100);
    try std.testing.expectEqual(@as(usize, 0), state.offset);

    state.scrollBy(200);
    try std.testing.expectEqual(@as(usize, 80), state.offset);
}

test "behavior: ScrollState.pageUp and pageDown" {
    var state = ScrollState.init(100);
    state.setViewport(20);

    state.scrollTo(50);
    state.pageUp();
    try std.testing.expectEqual(@as(usize, 30), state.offset);

    state.pageDown();
    try std.testing.expectEqual(@as(usize, 50), state.offset);
}

test "behavior: ScrollState.scrollToStart and scrollToEnd" {
    var state = ScrollState.init(100);
    state.setViewport(20);

    state.scrollTo(50);
    state.scrollToStart();
    try std.testing.expectEqual(@as(usize, 0), state.offset);
    try std.testing.expect(state.atStart());

    state.scrollToEnd();
    try std.testing.expectEqual(@as(usize, 80), state.offset);
    try std.testing.expect(state.atEnd());
}

test "behavior: ScrollState.ensureVisible" {
    var state = ScrollState.init(100);
    state.setViewport(20);
    state.scrollTo(50);

    // Item already visible
    state.ensureVisible(55);
    try std.testing.expectEqual(@as(usize, 50), state.offset);

    // Item above viewport
    state.ensureVisible(40);
    try std.testing.expectEqual(@as(usize, 40), state.offset);

    // Item below viewport
    state.ensureVisible(80);
    try std.testing.expectEqual(@as(usize, 61), state.offset);
}

test "behavior: ScrollState.visibleRange" {
    var state = ScrollState.init(100);
    state.setViewport(20);
    state.scrollTo(50);

    const range = state.visibleRange();
    try std.testing.expectEqual(@as(usize, 50), range.start);
    try std.testing.expectEqual(@as(usize, 70), range.end);
}

// ============================================================
// BEHAVIOR TESTS - ScrollState input handling
// ============================================================

test "behavior: ScrollState.handleKey up/down" {
    var state = ScrollState.init(100);
    state.setViewport(20);
    state.scrollTo(50);

    const handled_up = state.handleKey(.{ .code = .up });
    try std.testing.expect(handled_up);
    try std.testing.expectEqual(@as(usize, 49), state.offset);

    const handled_down = state.handleKey(.{ .code = .down });
    try std.testing.expect(handled_down);
    try std.testing.expectEqual(@as(usize, 50), state.offset);
}

test "behavior: ScrollState.handleKey page up/down" {
    var state = ScrollState.init(100);
    state.setViewport(20);
    state.scrollTo(50);

    const handled_pgup = state.handleKey(.{ .code = .page_up });
    try std.testing.expect(handled_pgup);
    try std.testing.expectEqual(@as(usize, 30), state.offset);

    const handled_pgdn = state.handleKey(.{ .code = .page_down });
    try std.testing.expect(handled_pgdn);
    try std.testing.expectEqual(@as(usize, 50), state.offset);
}

test "behavior: ScrollState.handleMouse scroll" {
    var state = ScrollState.init(100);
    state.setViewport(20);
    state.scrollTo(50);

    const handled_up = state.handleMouse(.{ .x = 0, .y = 0, .kind = .scroll_up });
    try std.testing.expect(handled_up);
    try std.testing.expectEqual(@as(usize, 47), state.offset);

    const handled_down = state.handleMouse(.{ .x = 0, .y = 0, .kind = .scroll_down });
    try std.testing.expect(handled_down);
    try std.testing.expectEqual(@as(usize, 50), state.offset);
}

// ============================================================
// SANITY TESTS - ScrollView
// ============================================================

test "sanity: ScrollView contentArea" {
    var state = ScrollState.init(100);
    state.setViewport(20);

    const sv = ScrollView{ .state = &state };
    const area = Rect.init(0, 0, 40, 20);

    const content = sv.contentArea(area);
    try std.testing.expectEqual(@as(u16, 0), content.x);
    try std.testing.expectEqual(@as(u16, 39), content.width);
}

test "sanity: ScrollView scrollbarArea" {
    var state = ScrollState.init(100);
    state.setViewport(20);

    const sv = ScrollView{ .state = &state };
    const area = Rect.init(0, 0, 40, 20);

    const sb_area = sv.scrollbarArea(area);
    try std.testing.expectEqual(@as(u16, 39), sb_area.x);
    try std.testing.expectEqual(@as(u16, 1), sb_area.width);
}

test "sanity: ScrollView no scrollbar when not needed" {
    var state = ScrollState.init(10);
    state.setViewport(20);

    const sv = ScrollView{ .state = &state };
    const area = Rect.init(0, 0, 40, 20);

    const content = sv.contentArea(area);
    try std.testing.expectEqual(@as(u16, 40), content.width);
}

// ============================================================
// SANITY TESTS - ScrollableList
// ============================================================

test "sanity: ScrollableList default values" {
    var state = ScrollState{};
    const items = [_][]const u8{ "a", "b", "c" };
    const list = ScrollableList{
        .items = &items,
        .scroll = &state,
    };

    try std.testing.expectEqual(@as(usize, 3), list.len());
    try std.testing.expect(!list.isEmpty());
    try std.testing.expect(list.selected == null);
}

test "sanity: ScrollableList.syncState" {
    var state = ScrollState{};
    const items = [_][]const u8{ "a", "b", "c", "d", "e" };
    var list = ScrollableList{
        .items = &items,
        .scroll = &state,
    };
    state.setViewport(3);

    list.syncState();
    try std.testing.expectEqual(@as(usize, 5), state.total);
}

// ============================================================
// BEHAVIOR TESTS - ScrollableList navigation
// ============================================================

test "behavior: ScrollableList.selectPrevious and selectNext" {
    var state = ScrollState{};
    state.setViewport(3);
    const items = [_][]const u8{ "a", "b", "c", "d", "e" };
    var list = ScrollableList{
        .items = &items,
        .scroll = &state,
        .selected = 2,
    };
    list.syncState();

    list.selectNext();
    try std.testing.expectEqual(@as(?usize, 3), list.selected);

    list.selectPrevious();
    try std.testing.expectEqual(@as(?usize, 2), list.selected);
}

test "behavior: ScrollableList.selectFirst and selectLast" {
    var state = ScrollState{};
    state.setViewport(3);
    const items = [_][]const u8{ "a", "b", "c", "d", "e" };
    var list = ScrollableList{
        .items = &items,
        .scroll = &state,
        .selected = 2,
    };
    list.syncState();

    list.selectFirst();
    try std.testing.expectEqual(@as(?usize, 0), list.selected);

    list.selectLast();
    try std.testing.expectEqual(@as(?usize, 4), list.selected);
}

test "behavior: ScrollableList selection scrolls into view" {
    var state = ScrollState{};
    state.setViewport(3);
    const items = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h" };
    var list = ScrollableList{
        .items = &items,
        .scroll = &state,
        .selected = 0,
    };
    list.syncState();

    // Select last - should scroll
    list.selectLast();
    try std.testing.expectEqual(@as(?usize, 7), list.selected);
    try std.testing.expect(state.offset > 0);

    // Select first - should scroll back
    list.selectFirst();
    try std.testing.expectEqual(@as(usize, 0), state.offset);
}

// ============================================================
// BEHAVIOR TESTS - ScrollableList rendering
// ============================================================

test "behavior: ScrollableList renders visible items" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    var state = ScrollState{};
    state.setViewport(3);
    const items = [_][]const u8{ "Alpha", "Beta", "Gamma", "Delta", "Epsilon" };
    var list = ScrollableList{
        .items = &items,
        .scroll = &state,
        .show_scrollbar = false,
    };
    list.syncState();

    list.render(Rect.init(0, 0, 20, 3), &buf);

    // First 3 items should be visible (with highlight symbol offset)
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(2, 1).char);
    try std.testing.expectEqual(@as(u21, 'G'), buf.get(2, 2).char);
}

test "behavior: ScrollableList renders scrolled items" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    var state = ScrollState{};
    state.setViewport(3);
    const items = [_][]const u8{ "Alpha", "Beta", "Gamma", "Delta", "Epsilon" };
    var list = ScrollableList{
        .items = &items,
        .scroll = &state,
        .show_scrollbar = false,
    };
    list.syncState();
    state.scrollTo(2);

    list.render(Rect.init(0, 0, 20, 3), &buf);

    // Items 2-4 should be visible
    try std.testing.expectEqual(@as(u21, 'G'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'D'), buf.get(2, 1).char);
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(2, 2).char);
}

test "behavior: ScrollableList renders with scrollbar" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    var state = ScrollState{};
    state.setViewport(3);
    const items = [_][]const u8{ "Alpha", "Beta", "Gamma", "Delta", "Epsilon" };
    var list = ScrollableList{
        .items = &items,
        .scroll = &state,
        .show_scrollbar = true,
        .scrollbar_thumb_style = Style.init().reverse(),
    };
    list.syncState();

    list.render(Rect.init(0, 0, 20, 3), &buf);

    // Scrollbar should be in last column
    const sb_cell = buf.get(19, 0);
    try std.testing.expect(sb_cell.style.hasAttribute(.reverse));
}

test "behavior: ScrollableList renders selection" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    var state = ScrollState{};
    state.setViewport(3);
    const items = [_][]const u8{ "Alpha", "Beta", "Gamma" };
    var list = ScrollableList{
        .items = &items,
        .scroll = &state,
        .selected = 1,
        .highlight_style = Style.init().bold(),
        .show_scrollbar = false,
    };
    list.syncState();

    list.render(Rect.init(0, 0, 20, 3), &buf);

    // Selected row should have highlight style
    try std.testing.expect(buf.get(0, 1).style.hasAttribute(.bold));
    try std.testing.expect(!buf.get(0, 0).style.hasAttribute(.bold));
    try std.testing.expect(!buf.get(0, 2).style.hasAttribute(.bold));
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: ScrollState handles zero total" {
    var state = ScrollState.init(0);
    state.setViewport(20);

    try std.testing.expectEqual(@as(usize, 0), state.maxOffset());
    try std.testing.expect(!state.canScroll());
    try std.testing.expect(state.atStart());
    try std.testing.expect(state.atEnd());
}

test "regression: ScrollState handles zero viewport" {
    var state = ScrollState.init(100);
    state.setViewport(0);

    try std.testing.expectEqual(@as(usize, 100), state.maxOffset());
    try std.testing.expect(state.canScroll());
}

test "regression: ScrollableList handles empty items" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    var state = ScrollState{};
    const items = [_][]const u8{};
    var list = ScrollableList{
        .items = &items,
        .scroll = &state,
    };
    list.syncState();

    list.render(Rect.init(0, 0, 20, 5), &buf);

    // Should not crash, buffer unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: ScrollableList handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    var state = ScrollState{};
    const items = [_][]const u8{ "A", "B" };
    const list = ScrollableList{
        .items = &items,
        .scroll = &state,
    };

    list.render(Rect.init(0, 0, 0, 0), &buf);

    // Should not crash
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: ScrollState.setTotal clamps offset" {
    var state = ScrollState.init(100);
    state.setViewport(20);
    state.scrollTo(80);

    state.setTotal(50);
    try std.testing.expectEqual(@as(usize, 30), state.offset);
}
