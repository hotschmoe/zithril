// Tree widget for zithril TUI framework
// Displays hierarchical data with expandable/collapsible nodes

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Symbols used for tree rendering.
pub const TreeSymbols = struct {
    /// Symbol for expanded nodes.
    expanded: []const u8 = "\xe2\x96\xbc ", // "▼ "
    /// Symbol for collapsed nodes.
    collapsed: []const u8 = "\xe2\x96\xb6 ", // "▶ "
    /// Symbol for leaf nodes (no children).
    leaf: []const u8 = "  ",
};

/// Default symbols instance.
pub const default_symbols = TreeSymbols{};

/// A node in the tree structure.
/// Generic over the data type T.
pub fn TreeItem(comptime T: type) type {
    return struct {
        /// User data stored in this node.
        data: T,
        /// Child nodes.
        children: []const TreeItem(T) = &.{},
        /// Whether this node is expanded (showing children).
        expanded: bool = true,

        const Self = @This();

        /// Returns true if this node has children.
        pub fn hasChildren(self: Self) bool {
            return self.children.len > 0;
        }

        /// Returns true if this node is a leaf (no children).
        pub fn isLeaf(self: Self) bool {
            return self.children.len == 0;
        }
    };
}

/// Tree widget for displaying hierarchical data.
/// Generic over the data type T.
pub fn Tree(comptime T: type) type {
    return struct {
        /// Root items of the tree.
        items: []const TreeItem(T),
        /// Currently selected visible row (null for no selection).
        selected: ?usize = null,
        /// Scroll offset for virtual scrolling.
        offset: usize = 0,
        /// Default style for non-selected items.
        style: Style = Style.empty,
        /// Style for the selected item.
        highlight_style: Style = Style.init().bg(.blue),
        /// Indentation width per level.
        indent: u16 = 2,
        /// Function to render item data as text.
        render_fn: *const fn (data: T) []const u8,
        /// Symbols for tree structure.
        symbols: TreeSymbols = default_symbols,

        const Self = @This();

        /// Render the tree into the buffer at the given area.
        pub fn render(self: Self, area: Rect, buf: *Buffer) void {
            if (area.isEmpty()) return;
            if (self.items.len == 0) return;

            const visible_height = area.height;
            var y: u16 = 0;
            var visible_index: usize = 0;

            var iter = self.iterator();
            while (iter.next()) |node| {
                if (visible_index < self.offset) {
                    visible_index += 1;
                    continue;
                }

                if (y >= visible_height) break;

                const is_selected = self.selected != null and visible_index == self.selected.?;
                self.renderNode(area, buf, node, area.y +| y, is_selected);

                y += 1;
                visible_index += 1;
            }
        }

        /// Render a single node at the given y position.
        fn renderNode(
            self: Self,
            area: Rect,
            buf: *Buffer,
            node: IterNode,
            y: u16,
            is_selected: bool,
        ) void {
            const row_style = if (is_selected) self.highlight_style else self.style;

            // Fill the entire row with the appropriate style
            if (is_selected) {
                const row_rect = Rect.init(area.x, y, area.width, 1);
                buf.fill(row_rect, Cell.styled(' ', row_style));
            }

            // Calculate indentation
            const indent_width = node.depth *| self.indent;
            var x = area.x +| indent_width;

            // Draw expand/collapse symbol
            const symbol = if (node.has_children)
                if (node.is_expanded) self.symbols.expanded else self.symbols.collapsed
            else
                self.symbols.leaf;

            if (x < area.right()) {
                const symbol_width: u16 = @intCast(@min(symbol.len, area.right() -| x));
                buf.setString(x, y, symbol[0..symbol_width], row_style);
                x +|= @intCast(symbol.len);
            }

            // Draw node content
            if (x < area.right()) {
                const text = self.render_fn(node.data);
                buf.setString(x, y, text, row_style);
            }
        }

        /// Internal iterator node representation.
        const IterNode = struct {
            depth: u16,
            is_expanded: bool,
            has_children: bool,
            data: T,
        };

        /// Iterator for traversing visible tree nodes.
        const TreeIterator = struct {
            tree: *const Self,
            stack: [64]StackEntry,
            stack_len: usize,

            const StackEntry = struct {
                items: []const TreeItem(T),
                index: usize,
                depth: u16,
            };

            fn init(tree: *const Self) TreeIterator {
                var iter = TreeIterator{
                    .tree = tree,
                    .stack = undefined,
                    .stack_len = 0,
                };
                if (tree.items.len > 0) {
                    iter.stack[0] = .{
                        .items = tree.items,
                        .index = 0,
                        .depth = 0,
                    };
                    iter.stack_len = 1;
                }
                return iter;
            }

            fn next(self: *TreeIterator) ?IterNode {
                while (self.stack_len > 0) {
                    const top = &self.stack[self.stack_len - 1];

                    if (top.index >= top.items.len) {
                        self.stack_len -= 1;
                        continue;
                    }

                    const item = &top.items[top.index];
                    const depth = top.depth;
                    top.index += 1;

                    // Push children if expanded and has children
                    if (item.expanded and item.children.len > 0) {
                        if (self.stack_len < self.stack.len) {
                            self.stack[self.stack_len] = .{
                                .items = item.children,
                                .index = 0,
                                .depth = depth + 1,
                            };
                            self.stack_len += 1;
                        }
                    }

                    return IterNode{
                        .depth = depth,
                        .is_expanded = item.expanded,
                        .has_children = item.children.len > 0,
                        .data = item.data,
                    };
                }
                return null;
            }
        };

        /// Create an iterator over visible tree nodes.
        pub fn iterator(self: *const Self) TreeIterator {
            return TreeIterator.init(self);
        }

        /// Count the total number of visible nodes.
        pub fn visibleCount(self: Self) usize {
            var count: usize = 0;
            var iter = self.iterator();
            while (iter.next()) |_| {
                count += 1;
            }
            return count;
        }

        /// Check if the tree is empty.
        pub fn isEmpty(self: Self) bool {
            return self.items.len == 0;
        }
    };
}

/// State management for Tree widget interaction.
/// Separates mutable navigation state from tree data.
pub fn TreeState(comptime T: type) type {
    return struct {
        /// Currently selected visible row index.
        selected: usize = 0,
        /// Scroll offset for large trees.
        offset: usize = 0,

        const Self = @This();

        /// Move selection to the previous item.
        pub fn selectPrev(self: *Self) void {
            if (self.selected > 0) {
                self.selected -= 1;
                if (self.selected < self.offset) {
                    self.offset = self.selected;
                }
            }
        }

        /// Move selection to the next item.
        pub fn selectNext(self: *Self, tree: Tree(T)) void {
            const count = tree.visibleCount();
            if (count > 0 and self.selected < count - 1) {
                self.selected += 1;
            }
        }

        /// Ensure selection is visible within the viewport.
        pub fn scrollIntoView(self: *Self, viewport_height: u16) void {
            if (self.selected < self.offset) {
                self.offset = self.selected;
            } else if (self.selected >= self.offset + viewport_height) {
                self.offset = self.selected - viewport_height + 1;
            }
        }

        /// Apply state to a tree for rendering.
        pub fn applyTo(self: Self, tree: *Tree(T)) void {
            tree.selected = self.selected;
            tree.offset = self.offset;
        }
    };
}

/// Mutable version of TreeItem for dynamic tree manipulation.
/// Allows toggling expand/collapse state.
pub fn MutableTreeItem(comptime T: type) type {
    return struct {
        data: T,
        children: []MutableTreeItem(T),
        expanded: bool,

        const Self = @This();

        /// Toggle the expanded state of this node.
        pub fn toggle(self: *Self) void {
            if (self.children.len > 0) {
                self.expanded = !self.expanded;
            }
        }

        /// Expand this node.
        pub fn expand(self: *Self) void {
            self.expanded = true;
        }

        /// Collapse this node.
        pub fn collapse(self: *Self) void {
            self.expanded = false;
        }

        /// Convert from immutable TreeItem (shallow copy, children still immutable).
        pub fn fromTreeItem(item: TreeItem(T), allocator: std.mem.Allocator) !Self {
            const children = try allocator.alloc(Self, item.children.len);
            for (item.children, 0..) |child, i| {
                children[i] = try fromTreeItem(child, allocator);
            }
            return Self{
                .data = item.data,
                .children = children,
                .expanded = item.expanded,
            };
        }

        /// Free allocated children recursively.
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (self.children) |*child| {
                child.deinit(allocator);
            }
            allocator.free(self.children);
        }
    };
}

// ============================================================
// SANITY TESTS - Basic Tree functionality
// ============================================================

fn testRenderString(data: []const u8) []const u8 {
    return data;
}

test "sanity: TreeItem with default values" {
    const item = TreeItem([]const u8){
        .data = "Root",
    };

    try std.testing.expectEqualStrings("Root", item.data);
    try std.testing.expect(item.children.len == 0);
    try std.testing.expect(item.expanded);
    try std.testing.expect(item.isLeaf());
    try std.testing.expect(!item.hasChildren());
}

test "sanity: TreeItem with children" {
    const children = [_]TreeItem([]const u8){
        .{ .data = "Child 1" },
        .{ .data = "Child 2" },
    };

    const item = TreeItem([]const u8){
        .data = "Root",
        .children = &children,
    };

    try std.testing.expect(item.hasChildren());
    try std.testing.expect(!item.isLeaf());
    try std.testing.expectEqual(@as(usize, 2), item.children.len);
}

test "sanity: Tree with default values" {
    const items = [_]TreeItem([]const u8){
        .{ .data = "Item 1" },
        .{ .data = "Item 2" },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
    };

    try std.testing.expect(!tree.isEmpty());
    try std.testing.expect(tree.selected == null);
    try std.testing.expectEqual(@as(usize, 0), tree.offset);
    try std.testing.expectEqual(@as(u16, 2), tree.indent);
}

test "sanity: Tree.visibleCount counts visible nodes" {
    const grandchildren = [_]TreeItem([]const u8){
        .{ .data = "Grandchild" },
    };

    const children = [_]TreeItem([]const u8){
        .{ .data = "Child 1", .children = &grandchildren },
        .{ .data = "Child 2" },
    };

    const items = [_]TreeItem([]const u8){
        .{ .data = "Root", .children = &children },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
    };

    // Root + Child 1 + Grandchild + Child 2 = 4
    try std.testing.expectEqual(@as(usize, 4), tree.visibleCount());
}

test "sanity: Tree.visibleCount respects collapsed nodes" {
    const children = [_]TreeItem([]const u8){
        .{ .data = "Child 1" },
        .{ .data = "Child 2" },
    };

    const items = [_]TreeItem([]const u8){
        .{ .data = "Root", .children = &children, .expanded = false },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
    };

    // Only root is visible when collapsed
    try std.testing.expectEqual(@as(usize, 1), tree.visibleCount());
}

test "sanity: TreeSymbols defaults" {
    const symbols = TreeSymbols{};
    try std.testing.expectEqualStrings("\xe2\x96\xbc ", symbols.expanded);
    try std.testing.expectEqualStrings("\xe2\x96\xb6 ", symbols.collapsed);
    try std.testing.expectEqualStrings("  ", symbols.leaf);
}

// ============================================================
// BEHAVIOR TESTS - Tree rendering
// ============================================================

test "behavior: Tree renders items" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const items = [_]TreeItem([]const u8){
        .{ .data = "Alpha" },
        .{ .data = "Beta" },
        .{ .data = "Gamma" },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
        .symbols = .{ .leaf = "  ", .expanded = "> ", .collapsed = "> " },
    };

    tree.render(Rect.init(0, 0, 40, 10), &buf);

    // Items should be rendered with leaf symbol offset
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(2, 1).char);
    try std.testing.expectEqual(@as(u21, 'G'), buf.get(2, 2).char);
}

test "behavior: Tree renders hierarchical structure with indentation" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const children = [_]TreeItem([]const u8){
        .{ .data = "Child" },
    };

    const items = [_]TreeItem([]const u8){
        .{ .data = "Root", .children = &children },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
        .indent = 2,
        .symbols = .{ .leaf = "  ", .expanded = "> ", .collapsed = "X " },
    };

    tree.render(Rect.init(0, 0, 40, 10), &buf);

    // Root at depth 0, no indentation
    try std.testing.expectEqual(@as(u21, '>'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'R'), buf.get(2, 0).char);

    // Child at depth 1, indented by 2
    try std.testing.expectEqual(@as(u21, 'C'), buf.get(4, 1).char);
}

test "behavior: Tree renders selected item with highlight" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const items = [_]TreeItem([]const u8){
        .{ .data = "One" },
        .{ .data = "Two" },
        .{ .data = "Three" },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
        .selected = 1,
        .highlight_style = Style.init().bold(),
        .symbols = .{ .leaf = "  ", .expanded = "> ", .collapsed = "> " },
    };

    tree.render(Rect.init(0, 0, 40, 10), &buf);

    // Row 1 should have highlight style
    try std.testing.expect(buf.get(0, 1).style.hasAttribute(.bold));
    try std.testing.expect(buf.get(2, 1).style.hasAttribute(.bold));

    // Row 0 and 2 should not have bold
    try std.testing.expect(!buf.get(2, 0).style.hasAttribute(.bold));
    try std.testing.expect(!buf.get(2, 2).style.hasAttribute(.bold));
}

test "behavior: Tree respects scroll offset" {
    var buf = try Buffer.init(std.testing.allocator, 40, 2);
    defer buf.deinit();

    const items = [_]TreeItem([]const u8){
        .{ .data = "First" },
        .{ .data = "Second" },
        .{ .data = "Third" },
        .{ .data = "Fourth" },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
        .offset = 2,
        .symbols = .{ .leaf = "", .expanded = "", .collapsed = "" },
    };

    tree.render(Rect.init(0, 0, 40, 2), &buf);

    // With offset 2, should render Third and Fourth
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'F'), buf.get(0, 1).char);
}

test "behavior: Tree shows expanded/collapsed symbols" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const children = [_]TreeItem([]const u8){
        .{ .data = "Child" },
    };

    const items = [_]TreeItem([]const u8){
        .{ .data = "Expanded", .children = &children, .expanded = true },
        .{ .data = "Collapsed", .children = &children, .expanded = false },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
        .symbols = .{ .expanded = "v ", .collapsed = "> ", .leaf = "  " },
    };

    tree.render(Rect.init(0, 0, 40, 10), &buf);

    // First item expanded, shows 'v'
    try std.testing.expectEqual(@as(u21, 'v'), buf.get(0, 0).char);

    // Collapsed node shows '>' (row 2 because expanded node's child is at row 1)
    try std.testing.expectEqual(@as(u21, '>'), buf.get(0, 2).char);
}

// ============================================================
// BEHAVIOR TESTS - TreeState navigation
// ============================================================

test "behavior: TreeState.selectPrev moves selection up" {
    var state = TreeState([]const u8){ .selected = 2 };
    state.selectPrev();
    try std.testing.expectEqual(@as(usize, 1), state.selected);

    state.selectPrev();
    try std.testing.expectEqual(@as(usize, 0), state.selected);

    // Can't go below 0
    state.selectPrev();
    try std.testing.expectEqual(@as(usize, 0), state.selected);
}

test "behavior: TreeState.selectNext moves selection down" {
    const items = [_]TreeItem([]const u8){
        .{ .data = "A" },
        .{ .data = "B" },
        .{ .data = "C" },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
    };

    var state = TreeState([]const u8){ .selected = 0 };

    state.selectNext(tree);
    try std.testing.expectEqual(@as(usize, 1), state.selected);

    state.selectNext(tree);
    try std.testing.expectEqual(@as(usize, 2), state.selected);

    // Can't go beyond last item
    state.selectNext(tree);
    try std.testing.expectEqual(@as(usize, 2), state.selected);
}

test "behavior: TreeState.scrollIntoView adjusts offset" {
    var state = TreeState([]const u8){ .selected = 10, .offset = 0 };

    state.scrollIntoView(5);
    // Selected item 10 should be visible in viewport of height 5
    // offset should be 10 - 5 + 1 = 6
    try std.testing.expectEqual(@as(usize, 6), state.offset);

    state.selected = 3;
    state.scrollIntoView(5);
    // Selected item 3 is below offset 6, need to scroll up
    try std.testing.expectEqual(@as(usize, 3), state.offset);
}

test "behavior: TreeState.applyTo transfers state to tree" {
    const items = [_]TreeItem([]const u8){
        .{ .data = "A" },
    };

    var tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
    };

    const state = TreeState([]const u8){ .selected = 5, .offset = 2 };
    state.applyTo(&tree);

    try std.testing.expectEqual(@as(?usize, 5), tree.selected);
    try std.testing.expectEqual(@as(usize, 2), tree.offset);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Tree handles empty items" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const items = [_]TreeItem([]const u8){};
    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
    };

    tree.render(Rect.init(0, 0, 40, 10), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Tree handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 40, 40);
    defer buf.deinit();

    const items = [_]TreeItem([]const u8){
        .{ .data = "Test" },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
    };

    tree.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Tree renders at area offset" {
    var buf = try Buffer.init(std.testing.allocator, 50, 20);
    defer buf.deinit();

    const items = [_]TreeItem([]const u8){
        .{ .data = "Test" },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
        .symbols = .{ .leaf = "", .expanded = "", .collapsed = "" },
    };

    tree.render(Rect.init(10, 5, 30, 10), &buf);

    // Item should be at offset position
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(10, 5).char);
}

test "regression: Tree handles deeply nested structure" {
    const depth4 = [_]TreeItem([]const u8){
        .{ .data = "D4" },
    };
    const depth3 = [_]TreeItem([]const u8){
        .{ .data = "D3", .children = &depth4 },
    };
    const depth2 = [_]TreeItem([]const u8){
        .{ .data = "D2", .children = &depth3 },
    };
    const depth1 = [_]TreeItem([]const u8){
        .{ .data = "D1", .children = &depth2 },
    };
    const items = [_]TreeItem([]const u8){
        .{ .data = "D0", .children = &depth1 },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
    };

    // All 5 nodes should be visible
    try std.testing.expectEqual(@as(usize, 5), tree.visibleCount());
}

test "regression: Tree handles selection out of bounds" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const items = [_]TreeItem([]const u8){
        .{ .data = "A" },
        .{ .data = "B" },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
        .selected = 100,
    };

    // Should render without crash
    tree.render(Rect.init(0, 0, 40, 10), &buf);
}

test "regression: Tree handles narrow width" {
    var buf = try Buffer.init(std.testing.allocator, 5, 10);
    defer buf.deinit();

    const items = [_]TreeItem([]const u8){
        .{ .data = "Very long text" },
    };

    const tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
        .symbols = .{ .leaf = "> ", .expanded = "> ", .collapsed = "> " },
    };

    // Should render what fits without crash
    tree.render(Rect.init(0, 0, 5, 10), &buf);
}

test "regression: Tree isEmpty check" {
    const empty_items = [_]TreeItem([]const u8){};
    const empty_tree = Tree([]const u8){
        .items = &empty_items,
        .render_fn = testRenderString,
    };
    try std.testing.expect(empty_tree.isEmpty());

    const items = [_]TreeItem([]const u8){
        .{ .data = "A" },
    };
    const non_empty_tree = Tree([]const u8){
        .items = &items,
        .render_fn = testRenderString,
    };
    try std.testing.expect(!non_empty_tree.isEmpty());
}
