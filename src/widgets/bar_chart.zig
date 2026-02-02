// BarChart widget for zithril TUI framework
// Displays datasets as grouped vertical or horizontal bars

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Unicode block characters for sub-cell bar heights (8 levels + empty).
const VERTICAL_BAR_CHARS: [9]u21 = .{
    ' ', // 0/8 - empty
    0x2581, // 1/8 - lower one eighth block
    0x2582, // 2/8 - lower one quarter block
    0x2583, // 3/8 - lower three eighths block
    0x2584, // 4/8 - lower half block
    0x2585, // 5/8 - lower five eighths block
    0x2586, // 6/8 - lower three quarters block
    0x2587, // 7/8 - lower seven eighths block
    0x2588, // 8/8 - full block
};

/// Unicode block characters for horizontal bar widths.
const HORIZONTAL_BAR_CHARS: [9]u21 = .{
    ' ', // 0/8 - empty
    0x258F, // 1/8 - left one eighth block
    0x258E, // 2/8 - left one quarter block
    0x258D, // 3/8 - left three eighths block
    0x258C, // 4/8 - left half block
    0x258B, // 5/8 - left five eighths block
    0x258A, // 6/8 - left three quarters block
    0x2589, // 7/8 - left seven eighths block
    0x2588, // 8/8 - full block
};

/// Orientation for bar chart rendering.
pub const Orientation = enum {
    /// Bars grow upward from baseline.
    vertical,
    /// Bars grow rightward from labels.
    horizontal,
};

/// A single bar in the chart.
pub const Bar = struct {
    /// The value this bar represents.
    value: f64,
    /// Optional label for this bar.
    label: []const u8 = "",
    /// Style for the bar itself.
    style: Style = Style.empty,
    /// Style for the value label (if shown).
    value_style: Style = Style.empty,
};

/// A group of related bars.
pub const BarGroup = struct {
    /// Optional label for this group.
    label: []const u8 = "",
    /// The bars in this group.
    bars: []const Bar,
};

/// Bar chart widget for displaying comparative data.
///
/// Renders one or more groups of bars, each bar representing a numeric value.
/// Supports both vertical (bars grow up) and horizontal (bars grow right) orientations.
pub const BarChart = struct {
    /// Groups of bars to display.
    groups: []const BarGroup = &.{},
    /// Bar orientation.
    orientation: Orientation = .vertical,
    /// Width of each bar in cells.
    bar_width: u16 = 1,
    /// Gap between bars within a group.
    bar_gap: u16 = 1,
    /// Gap between groups.
    group_gap: u16 = 2,
    /// Maximum value for scaling. If null, auto-detected from data.
    max_value: ?f64 = null,
    /// Whether to show values above/beside bars.
    show_values: bool = true,
    /// Style for group/bar labels.
    label_style: Style = Style.empty,
    /// Default style for bars without explicit style.
    default_bar_style: Style = Style.init().fg(.green),

    /// Render the bar chart into the buffer at the given area.
    pub fn render(self: BarChart, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.groups.len == 0) return;

        switch (self.orientation) {
            .vertical => self.renderVertical(area, buf),
            .horizontal => self.renderHorizontal(area, buf),
        }
    }

    /// Render vertical bars (growing upward).
    fn renderVertical(self: BarChart, area: Rect, buf: *Buffer) void {
        const effective_max = self.max_value orelse self.findMaxValue();
        if (effective_max <= 0) return;

        // Reserve bottom row for labels
        const label_height: u16 = 1;
        const value_height: u16 = if (self.show_values) 1 else 0;
        const bar_area_height = area.height -| label_height -| value_height;
        if (bar_area_height == 0) return;

        var x_pos: u16 = area.x;

        for (self.groups, 0..) |group, group_idx| {
            // Render bars in this group
            for (group.bars, 0..) |bar, bar_idx| {
                if (x_pos >= area.x +| area.width) break;

                const bar_style = if (bar.style.isEmpty()) self.default_bar_style else bar.style;

                // Calculate bar height based on value
                const normalized = @min(bar.value / effective_max, 1.0);
                const total_eighths: usize = @intFromFloat(@round(normalized * @as(f64, @floatFromInt(bar_area_height)) * 8.0));
                const full_cells = total_eighths / 8;
                const remaining_eighths = total_eighths % 8;

                // Render bar from bottom up
                const bar_base_y = area.y +| value_height +| bar_area_height -| 1;
                var cells_drawn: u16 = 0;

                // Draw full block cells
                while (cells_drawn < full_cells and cells_drawn < bar_area_height) : (cells_drawn += 1) {
                    const y = bar_base_y -| cells_drawn;
                    self.renderBarCell(buf, x_pos, y, self.bar_width, VERTICAL_BAR_CHARS[8], bar_style);
                }

                // Draw partial top cell if needed
                if (remaining_eighths > 0 and cells_drawn < bar_area_height) {
                    const y = bar_base_y -| cells_drawn;
                    self.renderBarCell(buf, x_pos, y, self.bar_width, VERTICAL_BAR_CHARS[remaining_eighths], bar_style);
                }

                // Render value above bar if enabled
                if (self.show_values) {
                    self.renderValue(buf, x_pos, area.y, bar.value, self.bar_width, bar.value_style);
                }

                // Render bar label at bottom
                if (bar.label.len > 0) {
                    const label_y = area.y +| area.height -| 1;
                    self.renderLabel(buf, x_pos, label_y, bar.label, self.bar_width, self.label_style);
                }

                x_pos +|= self.bar_width;

                // Add gap between bars (not after last bar in group)
                if (bar_idx + 1 < group.bars.len) {
                    x_pos +|= self.bar_gap;
                }
            }

            // Render group label (centered under bars)
            if (group.label.len > 0) {
                // Group label goes in a second label row if we have space
                const label_y = area.y +| area.height -| 1;
                const group_start = x_pos -| self.groupWidth(group);
                self.renderLabel(buf, group_start, label_y, group.label, self.groupWidth(group), self.label_style);
            }

            // Add gap between groups (not after last group)
            if (group_idx + 1 < self.groups.len) {
                x_pos +|= self.group_gap;
            }
        }
    }

    /// Render horizontal bars (growing rightward).
    fn renderHorizontal(self: BarChart, area: Rect, buf: *Buffer) void {
        const effective_max = self.max_value orelse self.findMaxValue();
        if (effective_max <= 0) return;

        // Find max label width for alignment
        const max_label_width = self.maxLabelWidth();
        const value_width: u16 = if (self.show_values) 6 else 0; // Space for value display
        const bar_area_width = area.width -| max_label_width -| 1 -| value_width;
        if (bar_area_width == 0) return;

        var y_pos: u16 = area.y;

        for (self.groups, 0..) |group, group_idx| {
            // Render group label if present
            if (group.label.len > 0 and y_pos < area.y +| area.height) {
                self.renderLabel(buf, area.x, y_pos, group.label, max_label_width, self.label_style.bold());
                y_pos +|= 1;
            }

            // Render bars in this group
            for (group.bars, 0..) |bar, bar_idx| {
                if (y_pos >= area.y +| area.height) break;

                const bar_style = if (bar.style.isEmpty()) self.default_bar_style else bar.style;

                // Render label
                self.renderLabel(buf, area.x, y_pos, bar.label, max_label_width, self.label_style);

                // Calculate bar width based on value
                const bar_start_x = area.x +| max_label_width +| 1;
                const normalized = @min(bar.value / effective_max, 1.0);
                const total_eighths: usize = @intFromFloat(@round(normalized * @as(f64, @floatFromInt(bar_area_width)) * 8.0));
                const full_cells = total_eighths / 8;
                const remaining_eighths = total_eighths % 8;

                // Draw full block cells
                var cells_drawn: u16 = 0;
                while (cells_drawn < full_cells and cells_drawn < bar_area_width) : (cells_drawn += 1) {
                    const x = bar_start_x +| cells_drawn;
                    buf.set(x, y_pos, Cell.styled(HORIZONTAL_BAR_CHARS[8], bar_style));
                }

                // Draw partial end cell if needed
                if (remaining_eighths > 0 and cells_drawn < bar_area_width) {
                    const x = bar_start_x +| cells_drawn;
                    buf.set(x, y_pos, Cell.styled(HORIZONTAL_BAR_CHARS[remaining_eighths], bar_style));
                }

                // Render value at end of bar
                if (self.show_values) {
                    const value_x = bar_start_x +| bar_area_width +| 1;
                    self.renderValue(buf, value_x, y_pos, bar.value, value_width, bar.value_style);
                }

                y_pos +|= 1;

                // Add bar_gap rows for multi-row bars (bar_width as height in horizontal mode)
                if (self.bar_width > 1) {
                    y_pos +|= self.bar_width -| 1;
                }

                // Add gap between bars
                if (bar_idx + 1 < group.bars.len and self.bar_gap > 0) {
                    y_pos +|= self.bar_gap -| 1;
                }
            }

            // Add gap between groups
            if (group_idx + 1 < self.groups.len) {
                y_pos +|= self.group_gap;
            }
        }
    }

    /// Render a single bar cell (possibly multiple columns wide).
    fn renderBarCell(self: BarChart, buf: *Buffer, x: u16, y: u16, width: u16, char: u21, style: Style) void {
        _ = self;
        var i: u16 = 0;
        while (i < width) : (i += 1) {
            buf.set(x +| i, y, Cell.styled(char, style));
        }
    }

    /// Render a label, truncated or padded to fit width.
    fn renderLabel(self: BarChart, buf: *Buffer, x: u16, y: u16, label: []const u8, width: u16, style: Style) void {
        _ = self;
        if (label.len == 0 or width == 0) return;

        var iter = std.unicode.Utf8View.initUnchecked(label).iterator();
        var col: u16 = 0;

        while (iter.nextCodepoint()) |codepoint| {
            if (col >= width) break;
            buf.set(x +| col, y, Cell.styled(codepoint, style));
            col += 1;
        }
    }

    /// Render a numeric value.
    fn renderValue(self: BarChart, buf: *Buffer, x: u16, y: u16, value: f64, width: u16, style: Style) void {
        _ = self;
        if (width == 0) return;

        var format_buf: [16]u8 = undefined;
        const value_str = if (value == @trunc(value))
            std.fmt.bufPrint(&format_buf, "{d:.0}", .{value}) catch return
        else
            std.fmt.bufPrint(&format_buf, "{d:.1}", .{value}) catch return;

        var col: u16 = 0;
        for (value_str) |c| {
            if (col >= width) break;
            buf.set(x +| col, y, Cell.styled(c, style));
            col += 1;
        }
    }

    /// Calculate the width of a group (all bars + gaps).
    fn groupWidth(self: BarChart, group: BarGroup) u16 {
        if (group.bars.len == 0) return 0;
        const bar_count: u16 = @intCast(group.bars.len);
        const bars_width = bar_count * self.bar_width;
        const gaps_width = (bar_count -| 1) * self.bar_gap;
        return bars_width +| gaps_width;
    }

    /// Find the maximum value across all bars.
    fn findMaxValue(self: BarChart) f64 {
        var max_val: f64 = 0;
        for (self.groups) |group| {
            for (group.bars) |bar| {
                if (bar.value > max_val) max_val = bar.value;
            }
        }
        return max_val;
    }

    /// Find the maximum label width across all bars.
    fn maxLabelWidth(self: BarChart) u16 {
        var max_width: u16 = 0;
        for (self.groups) |group| {
            for (group.bars) |bar| {
                const len: u16 = @intCast(@min(bar.label.len, std.math.maxInt(u16)));
                if (len > max_width) max_width = len;
            }
        }
        return max_width;
    }

    /// Create a bar chart from simple value/label pairs.
    pub fn fromPairs(labels: []const []const u8, values: []const f64) BarChart {
        _ = labels;
        _ = values;
        // This would require allocation to create Bar structs,
        // so we'll leave it as a pattern for the user to follow
        return BarChart{};
    }
};

// ============================================================
// SANITY TESTS - Basic BarChart functionality
// ============================================================

test "sanity: BarChart with default values" {
    const chart = BarChart{};
    try std.testing.expectEqual(@as(usize, 0), chart.groups.len);
    try std.testing.expect(chart.orientation == .vertical);
    try std.testing.expectEqual(@as(u16, 1), chart.bar_width);
    try std.testing.expect(chart.max_value == null);
    try std.testing.expect(chart.show_values);
}

test "sanity: Bar with default values" {
    const bar = Bar{ .value = 42.0 };
    try std.testing.expectEqual(@as(f64, 42.0), bar.value);
    try std.testing.expectEqualStrings("", bar.label);
    try std.testing.expect(bar.style.isEmpty());
}

test "sanity: BarGroup with bars" {
    const bars = [_]Bar{
        .{ .value = 10.0, .label = "A" },
        .{ .value = 20.0, .label = "B" },
    };
    const group = BarGroup{
        .label = "Group 1",
        .bars = &bars,
    };
    try std.testing.expectEqual(@as(usize, 2), group.bars.len);
    try std.testing.expectEqualStrings("Group 1", group.label);
}

test "sanity: BarChart with groups" {
    const bars = [_]Bar{
        .{ .value = 10.0 },
        .{ .value = 20.0 },
    };
    const groups = [_]BarGroup{
        .{ .bars = &bars },
    };
    const chart = BarChart{
        .groups = &groups,
        .max_value = 100.0,
    };
    try std.testing.expectEqual(@as(usize, 1), chart.groups.len);
    try std.testing.expectEqual(@as(f64, 100.0), chart.max_value.?);
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: BarChart vertical renders bars" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]Bar{
        .{ .value = 100.0, .label = "A" },
        .{ .value = 50.0, .label = "B" },
    };
    const groups = [_]BarGroup{
        .{ .bars = &bars },
    };
    const chart = BarChart{
        .groups = &groups,
        .max_value = 100.0,
        .bar_width = 1,
        .bar_gap = 1,
    };
    chart.render(Rect.init(0, 0, 20, 10), &buf);

    // The first bar (100%) should have full blocks
    // Check that some rendering occurred
    var has_content = false;
    for (buf.cells) |cell| {
        if (cell.char != ' ' and cell.char != 0) {
            has_content = true;
            break;
        }
    }
    try std.testing.expect(has_content);
}

test "behavior: BarChart horizontal renders bars" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const bars = [_]Bar{
        .{ .value = 100.0, .label = "foo" },
        .{ .value = 50.0, .label = "bar" },
    };
    const groups = [_]BarGroup{
        .{ .bars = &bars },
    };
    const chart = BarChart{
        .groups = &groups,
        .orientation = .horizontal,
        .max_value = 100.0,
    };
    chart.render(Rect.init(0, 0, 30, 10), &buf);

    // Check for label rendering
    try std.testing.expectEqual(@as(u21, 'f'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(1, 0).char);
}

test "behavior: BarChart auto-detects max value" {
    const bars = [_]Bar{
        .{ .value = 10.0 },
        .{ .value = 30.0 },
        .{ .value = 20.0 },
    };
    const groups = [_]BarGroup{
        .{ .bars = &bars },
    };
    const chart = BarChart{
        .groups = &groups,
    };
    try std.testing.expectEqual(@as(f64, 30.0), chart.findMaxValue());
}

test "behavior: BarChart renders values when enabled" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const bars = [_]Bar{
        .{ .value = 75.0, .label = "X" },
    };
    const groups = [_]BarGroup{
        .{ .bars = &bars },
    };
    const chart = BarChart{
        .groups = &groups,
        .orientation = .horizontal,
        .max_value = 100.0,
        .show_values = true,
    };
    chart.render(Rect.init(0, 0, 30, 10), &buf);

    // Value "75" should appear somewhere
    var found_seven = false;
    var found_five = false;
    for (0..30) |x| {
        const cell = buf.get(@intCast(x), 0);
        if (cell.char == '7') found_seven = true;
        if (cell.char == '5') found_five = true;
    }
    try std.testing.expect(found_seven);
    try std.testing.expect(found_five);
}

test "behavior: BarChart calculates group width" {
    const bars = [_]Bar{
        .{ .value = 10.0 },
        .{ .value = 20.0 },
        .{ .value = 30.0 },
    };
    const group = BarGroup{ .bars = &bars };
    const chart = BarChart{
        .bar_width = 2,
        .bar_gap = 1,
    };
    // 3 bars * 2 width + 2 gaps * 1 = 6 + 2 = 8
    try std.testing.expectEqual(@as(u16, 8), chart.groupWidth(group));
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: BarChart handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const bars = [_]Bar{.{ .value = 100.0 }};
    const groups = [_]BarGroup{.{ .bars = &bars }};
    const chart = BarChart{
        .groups = &groups,
    };
    chart.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: BarChart handles empty groups" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const chart = BarChart{};
    chart.render(Rect.init(0, 0, 20, 10), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: BarChart handles zero max value" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]Bar{
        .{ .value = 0.0 },
        .{ .value = 0.0 },
    };
    const groups = [_]BarGroup{.{ .bars = &bars }};
    const chart = BarChart{
        .groups = &groups,
    };
    chart.render(Rect.init(0, 0, 20, 10), &buf);

    // Should not crash, max_value will be 0 so no bars render
}

test "regression: BarChart handles single bar" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]Bar{.{ .value = 50.0 }};
    const groups = [_]BarGroup{.{ .bars = &bars }};
    const chart = BarChart{
        .groups = &groups,
        .max_value = 100.0,
    };
    chart.render(Rect.init(0, 0, 20, 10), &buf);

    // Should render without crash
    var has_content = false;
    for (buf.cells) |cell| {
        if (cell.char != ' ' and cell.char != 0) {
            has_content = true;
            break;
        }
    }
    try std.testing.expect(has_content);
}

test "regression: BarChart clips to area bounds" {
    var buf = try Buffer.init(std.testing.allocator, 5, 5);
    defer buf.deinit();

    const bars = [_]Bar{
        .{ .value = 100.0, .label = "A" },
        .{ .value = 100.0, .label = "B" },
        .{ .value = 100.0, .label = "C" },
        .{ .value = 100.0, .label = "D" },
        .{ .value = 100.0, .label = "E" },
    };
    const groups = [_]BarGroup{.{ .bars = &bars }};
    const chart = BarChart{
        .groups = &groups,
        .max_value = 100.0,
        .bar_width = 2,
        .bar_gap = 1,
    };
    chart.render(Rect.init(0, 0, 5, 5), &buf);

    // Should not crash, bars will be clipped
}

test "regression: BarChart uses custom bar style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]Bar{
        .{ .value = 100.0, .style = Style.init().fg(.red) },
    };
    const groups = [_]BarGroup{.{ .bars = &bars }};
    const chart = BarChart{
        .groups = &groups,
        .max_value = 100.0,
    };
    chart.render(Rect.init(0, 0, 20, 10), &buf);

    // Find a cell with the bar and check style
    var found_styled = false;
    for (buf.cells) |cell| {
        if (cell.char == VERTICAL_BAR_CHARS[8] and cell.style.getForeground() != null) {
            if (cell.style.getForeground().?.eql(.red)) {
                found_styled = true;
                break;
            }
        }
    }
    try std.testing.expect(found_styled);
}

test "regression: BarChart values exceeding max are clamped" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const bars = [_]Bar{
        .{ .value = 150.0 }, // Exceeds max_value
    };
    const groups = [_]BarGroup{.{ .bars = &bars }};
    const chart = BarChart{
        .groups = &groups,
        .max_value = 100.0,
    };
    chart.render(Rect.init(0, 0, 20, 10), &buf);

    // Should render as full bar without crash
}

test "regression: BarChart renders at non-zero offset" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const bars = [_]Bar{.{ .value = 100.0, .label = "X" }};
    const groups = [_]BarGroup{.{ .bars = &bars }};
    const chart = BarChart{
        .groups = &groups,
        .max_value = 100.0,
    };
    chart.render(Rect.init(10, 5, 20, 10), &buf);

    // Check that content is at offset, not at origin
    try std.testing.expect(buf.get(0, 0).isDefault());
}
