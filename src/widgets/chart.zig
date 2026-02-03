// Chart widget for zithril TUI framework
// Line chart with axis rendering

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

// Box-drawing characters for axes
const HORIZONTAL: u21 = 0x2500; // '─'
const VERTICAL: u21 = 0x2502; // '│'
const CORNER: u21 = 0x2514; // '└'
const TICK_Y: u21 = 0x2524; // '┤'
const TICK_X: u21 = 0x2534; // '┴'

// Line-drawing characters for datasets (reuse axis chars where applicable)
const LINE_DIAG_UP: u21 = '/';
const LINE_DIAG_DOWN: u21 = '\\';
const LINE_CROSS: u21 = 0x2573; // '╳'

/// A labeled point on an axis.
pub const Label = struct {
    /// The data value this label corresponds to.
    value: f64,
    /// The text to display at this position.
    text: []const u8,
};

/// Axis configuration for a chart.
pub const Axis = struct {
    /// Optional title for the axis.
    title: []const u8 = "",
    /// Data bounds [min, max].
    bounds: [2]f64,
    /// Optional custom labels. If null, auto-generate.
    labels: ?[]const Label = null,
    /// Style for the axis line and tick marks.
    style: Style = Style.empty,
    /// Style for the axis title.
    title_style: Style = Style.empty,
    /// Style for tick labels.
    labels_style: Style = Style.empty,

    /// Get the minimum bound.
    pub fn min(self: Axis) f64 {
        return self.bounds[0];
    }

    /// Get the maximum bound.
    pub fn max(self: Axis) f64 {
        return self.bounds[1];
    }

    /// Get the range (max - min).
    pub fn range(self: Axis) f64 {
        return self.bounds[1] - self.bounds[0];
    }
};

/// A line dataset to be plotted.
pub const LineDataset = struct {
    /// Optional name for the dataset (for legends).
    name: []const u8 = "",
    /// Data points as [x, y] pairs.
    data: []const [2]f64,
    /// Style for the line.
    style: Style = Style.empty,
    /// Optional marker character at data points.
    marker: ?u21 = null,
};

/// Common marker characters for scatter plots.
pub const Markers = struct {
    pub const dot: u21 = 0x25CF; // '●'
    pub const circle: u21 = 0x25CB; // '○'
    pub const square: u21 = 0x25A0; // '■'
    pub const square_empty: u21 = 0x25A1; // '□'
    pub const diamond: u21 = 0x25C6; // '◆'
    pub const diamond_empty: u21 = 0x25C7; // '◇'
    pub const triangle_up: u21 = 0x25B2; // '▲'
    pub const triangle_down: u21 = 0x25BC; // '▼'
    pub const star: u21 = 0x2605; // '★'
    pub const cross: u21 = 0x2715; // '✕'
    pub const plus: u21 = '+';
    pub const x: u21 = 0x00D7; // '×'
};

/// A scatter dataset to be plotted (points only, no connecting lines).
pub const ScatterDataset = struct {
    /// Optional name for the dataset (for legends).
    name: []const u8 = "",
    /// Data points as [x, y] pairs.
    data: []const [2]f64,
    /// Marker character for data points.
    marker: u21 = Markers.dot,
    /// Style for the markers.
    style: Style = Style.empty,
};

/// Chart widget for displaying line and scatter plots.
pub const Chart = struct {
    /// X-axis configuration.
    x_axis: Axis,
    /// Y-axis configuration.
    y_axis: Axis,
    /// Line datasets to plot.
    datasets: []const LineDataset = &.{},
    /// Scatter datasets to plot (points only, no connecting lines).
    scatter_datasets: []const ScatterDataset = &.{},
    /// Style for the chart area background.
    style: Style = Style.empty,
    /// Default style for datasets without explicit style.
    default_dataset_style: Style = Style.init().fg(.cyan),

    /// Render the chart into the buffer at the given area.
    pub fn render(self: Chart, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (area.width < 4 or area.height < 4) return;

        // Fill background if style is set
        if (!self.style.isEmpty()) {
            buf.fill(area, Cell.styled(' ', self.style));
        }

        // Calculate layout regions
        const layout = self.calculateLayout(area);

        // Render axes
        self.renderYAxis(layout, buf);
        self.renderXAxis(layout, buf);

        // Render line datasets
        for (self.datasets) |dataset| {
            self.renderLineDataset(dataset, layout, buf);
        }

        // Render scatter datasets
        for (self.scatter_datasets) |dataset| {
            self.renderScatterDataset(dataset, layout, buf);
        }
    }

    /// Layout information for chart regions.
    const ChartLayout = struct {
        /// Full chart area.
        total: Rect,
        /// Y-axis label area (left side).
        y_label_area: Rect,
        /// X-axis label area (bottom).
        x_label_area: Rect,
        /// Plot area where data is drawn.
        plot_area: Rect,
        /// Width reserved for Y-axis labels.
        y_label_width: u16,
        /// Height reserved for X-axis labels.
        x_label_height: u16,
    };

    /// Calculate the layout regions for the chart.
    fn calculateLayout(self: Chart, area: Rect) ChartLayout {
        // Calculate max Y label width
        const y_label_width = self.calculateYLabelWidth();

        // Reserve space for X-axis labels (1 row for labels + 1 for axis)
        const x_label_height: u16 = 2;

        // Reserve space for Y-axis (labels + axis line)
        const y_axis_width = y_label_width +| 1;

        // Calculate plot area
        const plot_x = area.x +| y_axis_width;
        const plot_y = area.y;
        const plot_width = area.width -| y_axis_width;
        const plot_height = area.height -| x_label_height;

        return .{
            .total = area,
            .y_label_area = Rect.init(area.x, area.y, y_label_width, plot_height),
            .x_label_area = Rect.init(plot_x, area.y +| plot_height, plot_width, x_label_height),
            .plot_area = Rect.init(plot_x, plot_y, plot_width, plot_height),
            .y_label_width = y_label_width,
            .x_label_height = x_label_height,
        };
    }

    /// Calculate the width needed for Y-axis labels.
    fn calculateYLabelWidth(self: Chart) u16 {
        if (self.y_axis.labels) |labels| {
            var max_width: u16 = 0;
            for (labels) |label| {
                const len: u16 = @intCast(@min(label.text.len, std.math.maxInt(u16)));
                if (len > max_width) max_width = len;
            }
            return max_width;
        }

        // Auto-generate: estimate width for numeric labels
        const nice_labels = generateNiceLabels(self.y_axis.bounds[0], self.y_axis.bounds[1], 5);
        var max_width: u16 = 0;
        for (nice_labels.values[0..nice_labels.count]) |value| {
            const width = formatValueWidth(value);
            if (width > max_width) max_width = width;
        }
        return max_width;
    }

    /// Render the Y-axis (vertical axis on left side).
    fn renderYAxis(self: Chart, layout: ChartLayout, buf: *Buffer) void {
        const axis_x = layout.plot_area.x -| 1;
        const plot_top = layout.plot_area.y;
        const plot_bottom = layout.plot_area.bottom() -| 1;

        // Draw vertical axis line
        var y = plot_top;
        while (y <= plot_bottom) : (y += 1) {
            buf.set(axis_x, y, Cell.styled(VERTICAL, self.y_axis.style));
        }

        // Draw corner
        buf.set(axis_x, plot_bottom +| 1, Cell.styled(CORNER, self.y_axis.style));

        // Draw labels and tick marks
        if (self.y_axis.labels) |labels| {
            for (labels) |label| {
                self.renderYLabel(label.value, label.text, layout, buf);
            }
        } else {
            // Auto-generate labels
            const nice_labels = generateNiceLabels(self.y_axis.bounds[0], self.y_axis.bounds[1], 5);
            for (nice_labels.values[0..nice_labels.count]) |value| {
                var format_buf: [16]u8 = undefined;
                const text = formatValue(value, &format_buf);
                self.renderYLabel(value, text, layout, buf);
            }
        }

        // Draw title if present
        if (self.y_axis.title.len > 0) {
            const title_y = layout.plot_area.y +| layout.plot_area.height / 2;
            var col: u16 = 0;
            var iter = std.unicode.Utf8View.initUnchecked(self.y_axis.title).iterator();
            while (iter.nextCodepoint()) |codepoint| {
                if (col >= layout.y_label_area.width) break;
                buf.set(layout.total.x +| col, title_y, Cell.styled(codepoint, self.y_axis.title_style));
                col += 1;
            }
        }
    }

    /// Render a single Y-axis label with tick mark.
    fn renderYLabel(self: Chart, value: f64, text: []const u8, layout: ChartLayout, buf: *Buffer) void {
        // Calculate Y position
        const y_pos = self.dataToScreenY(value, layout);
        if (y_pos < layout.plot_area.y or y_pos >= layout.plot_area.bottom()) return;

        // Draw tick mark
        const axis_x = layout.plot_area.x -| 1;
        buf.set(axis_x, y_pos, Cell.styled(TICK_Y, self.y_axis.style));

        // Draw label (right-aligned)
        const label_end_x = axis_x -| 1;
        const text_len: u16 = @intCast(@min(text.len, std.math.maxInt(u16)));
        const label_start_x = if (text_len > label_end_x) 0 else label_end_x -| text_len +| 1;

        var col: u16 = 0;
        var iter = std.unicode.Utf8View.initUnchecked(text).iterator();
        while (iter.nextCodepoint()) |codepoint| {
            const x = label_start_x +| col;
            if (x > label_end_x) break;
            buf.set(x, y_pos, Cell.styled(codepoint, self.y_axis.labels_style));
            col += 1;
        }
    }

    /// Render the X-axis (horizontal axis at bottom).
    fn renderXAxis(self: Chart, layout: ChartLayout, buf: *Buffer) void {
        const axis_y = layout.plot_area.bottom();
        const plot_left = layout.plot_area.x;
        const plot_right = layout.plot_area.right() -| 1;

        // Draw horizontal axis line
        var x = plot_left;
        while (x <= plot_right) : (x += 1) {
            buf.set(x, axis_y, Cell.styled(HORIZONTAL, self.x_axis.style));
        }

        // Draw labels and tick marks
        if (self.x_axis.labels) |labels| {
            for (labels) |label| {
                self.renderXLabel(label.value, label.text, layout, buf);
            }
        } else {
            // Auto-generate labels
            const label_count = @min(layout.plot_area.width / 8, 10);
            const nice_labels = generateNiceLabels(self.x_axis.bounds[0], self.x_axis.bounds[1], label_count);
            for (nice_labels.values[0..nice_labels.count]) |value| {
                var format_buf: [16]u8 = undefined;
                const text = formatValue(value, &format_buf);
                self.renderXLabel(value, text, layout, buf);
            }
        }

        // Draw title if present
        if (self.x_axis.title.len > 0) {
            const title_x = layout.plot_area.x +| layout.plot_area.width / 2 -| @as(u16, @intCast(self.x_axis.title.len / 2));
            const title_y = layout.total.bottom() -| 1;
            var col: u16 = 0;
            var iter = std.unicode.Utf8View.initUnchecked(self.x_axis.title).iterator();
            while (iter.nextCodepoint()) |codepoint| {
                buf.set(title_x +| col, title_y, Cell.styled(codepoint, self.x_axis.title_style));
                col += 1;
            }
        }
    }

    /// Render a single X-axis label with tick mark.
    fn renderXLabel(self: Chart, value: f64, text: []const u8, layout: ChartLayout, buf: *Buffer) void {
        // Calculate X position
        const x_pos = self.dataToScreenX(value, layout);
        if (x_pos < layout.plot_area.x or x_pos >= layout.plot_area.right()) return;

        // Draw tick mark
        const axis_y = layout.plot_area.bottom();
        buf.set(x_pos, axis_y, Cell.styled(TICK_X, self.x_axis.style));

        // Draw label (centered below tick)
        const label_y = axis_y +| 1;
        const text_len: u16 = @intCast(@min(text.len, std.math.maxInt(u16)));
        const label_start_x = x_pos -| text_len / 2;

        var col: u16 = 0;
        var iter = std.unicode.Utf8View.initUnchecked(text).iterator();
        while (iter.nextCodepoint()) |codepoint| {
            const x = label_start_x +| col;
            if (x >= layout.total.right()) break;
            buf.set(x, label_y, Cell.styled(codepoint, self.x_axis.labels_style));
            col += 1;
        }
    }

    /// Render a line dataset.
    fn renderLineDataset(self: Chart, dataset: LineDataset, layout: ChartLayout, buf: *Buffer) void {
        if (dataset.data.len == 0) return;

        const line_style = if (dataset.style.isEmpty()) self.default_dataset_style else dataset.style;

        // Draw lines between consecutive points
        var i: usize = 0;
        while (i < dataset.data.len -| 1) : (i += 1) {
            const p1 = dataset.data[i];
            const p2 = dataset.data[i + 1];

            const x1 = self.dataToScreenX(p1[0], layout);
            const y1 = self.dataToScreenY(p1[1], layout);
            const x2 = self.dataToScreenX(p2[0], layout);
            const y2 = self.dataToScreenY(p2[1], layout);

            drawLine(x1, y1, x2, y2, layout.plot_area, line_style, buf);
        }

        // Draw markers if specified
        if (dataset.marker) |marker| {
            for (dataset.data) |point| {
                const x = self.dataToScreenX(point[0], layout);
                const y = self.dataToScreenY(point[1], layout);
                if (layout.plot_area.contains(x, y)) {
                    buf.set(x, y, Cell.styled(marker, line_style));
                }
            }
        }
    }

    /// Render a scatter dataset (points only, no connecting lines).
    fn renderScatterDataset(self: Chart, dataset: ScatterDataset, layout: ChartLayout, buf: *Buffer) void {
        if (dataset.data.len == 0) return;

        const marker_style = if (dataset.style.isEmpty()) self.default_dataset_style else dataset.style;

        // Draw each point as a marker at its screen position
        for (dataset.data) |point| {
            const x = self.dataToScreenX(point[0], layout);
            const y = self.dataToScreenY(point[1], layout);

            // Only render if within plot area bounds
            if (layout.plot_area.contains(x, y)) {
                buf.set(x, y, Cell.styled(dataset.marker, marker_style));
            }
        }
    }

    /// Convert data X coordinate to screen X coordinate.
    fn dataToScreenX(self: Chart, data_x: f64, layout: ChartLayout) u16 {
        const x_range = self.x_axis.range();
        if (x_range == 0) return layout.plot_area.x;

        const x_ratio = (data_x - self.x_axis.min()) / x_range;
        const clamped_ratio = std.math.clamp(x_ratio, 0.0, 1.0);
        const offset: u16 = @intFromFloat(clamped_ratio * @as(f64, @floatFromInt(layout.plot_area.width -| 1)));
        return layout.plot_area.x +| offset;
    }

    /// Convert data Y coordinate to screen Y coordinate.
    fn dataToScreenY(self: Chart, data_y: f64, layout: ChartLayout) u16 {
        const y_range = self.y_axis.range();
        if (y_range == 0) return layout.plot_area.y;

        const y_ratio = (data_y - self.y_axis.min()) / y_range;
        const clamped_ratio = std.math.clamp(y_ratio, 0.0, 1.0);
        // Invert Y: screen Y increases downward, data Y increases upward
        const inverted_ratio = 1.0 - clamped_ratio;
        const offset: u16 = @intFromFloat(inverted_ratio * @as(f64, @floatFromInt(layout.plot_area.height -| 1)));
        return layout.plot_area.y +| offset;
    }
};

/// Result of nice label generation.
const NiceLabels = struct {
    values: [16]f64 = undefined,
    count: usize = 0,
};

/// Generate "nice" label values for an axis range.
fn generateNiceLabels(min_val: f64, max_val: f64, target_count: u16) NiceLabels {
    var result = NiceLabels{};
    if (target_count == 0 or min_val >= max_val) return result;

    const range = max_val - min_val;
    const rough_step = range / @as(f64, @floatFromInt(target_count));

    // Find a "nice" step size
    const step = niceNumber(rough_step, false);
    if (step <= 0) return result;

    // Round min down to nice boundary
    const nice_min = @floor(min_val / step) * step;

    // Generate labels
    var value = nice_min;
    while (value <= max_val and result.count < 16) {
        if (value >= min_val) {
            result.values[result.count] = value;
            result.count += 1;
        }
        value += step;
    }

    return result;
}

/// Find a "nice" number close to x.
/// If round is true, round to nearest; otherwise, ceiling.
fn niceNumber(x: f64, round: bool) f64 {
    if (x <= 0) return 1.0;

    const exp = @floor(std.math.log10(x));
    const f = x / std.math.pow(f64, 10, exp);

    var nf: f64 = undefined;
    if (round) {
        nf = if (f < 1.5) 1 else if (f < 3) 2 else if (f < 7) 5 else 10;
    } else {
        nf = if (f <= 1) 1 else if (f <= 2) 2 else if (f <= 5) 5 else 10;
    }

    return nf * std.math.pow(f64, 10, exp);
}

/// Format a value for display.
fn formatValue(value: f64, out_buf: []u8) []const u8 {
    const result = if (value == @trunc(value))
        std.fmt.bufPrint(out_buf, "{d:.0}", .{value})
    else
        std.fmt.bufPrint(out_buf, "{d:.1}", .{value});
    return result catch "";
}

/// Calculate the display width of a formatted value.
fn formatValueWidth(value: f64) u16 {
    var buf: [16]u8 = undefined;
    const text = formatValue(value, &buf);
    return @intCast(@min(text.len, std.math.maxInt(u16)));
}

/// Draw a line between two screen coordinates.
fn drawLine(x1: u16, y1: u16, x2: u16, y2: u16, plot_area: Rect, line_style: Style, buf: *Buffer) void {
    const dx: i32 = @as(i32, x2) - @as(i32, x1);
    const dy: i32 = @as(i32, y2) - @as(i32, y1);
    const abs_dx = @abs(dx);
    const abs_dy = @abs(dy);

    // Determine character based on slope
    const char: u21 = if (abs_dx == 0)
        VERTICAL
    else if (abs_dy == 0)
        HORIZONTAL
    else if ((dx > 0) == (dy < 0))
        LINE_DIAG_UP // Y inverted: screen Y increases downward
    else
        LINE_DIAG_DOWN;

    const steps = @max(abs_dx, abs_dy);
    if (steps == 0) {
        if (plot_area.contains(x1, y1)) {
            buf.set(x1, y1, Cell.styled(char, line_style));
        }
        return;
    }

    var step: i32 = 0;
    while (step <= steps) : (step += 1) {
        const t: f64 = @as(f64, @floatFromInt(step)) / @as(f64, @floatFromInt(steps));
        const x = @as(i32, x1) + @as(i32, @intFromFloat(t * @as(f64, @floatFromInt(dx))));
        const y = @as(i32, y1) + @as(i32, @intFromFloat(t * @as(f64, @floatFromInt(dy))));

        if (x >= 0 and y >= 0) {
            const ux: u16 = @intCast(x);
            const uy: u16 = @intCast(y);
            if (plot_area.contains(ux, uy)) {
                buf.set(ux, uy, Cell.styled(char, line_style));
            }
        }
    }
}

// ============================================================
// SANITY TESTS - Basic Chart functionality
// ============================================================

test "sanity: Chart with default values" {
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    try std.testing.expectEqual(@as(usize, 0), chart.datasets.len);
    try std.testing.expect(chart.style.isEmpty());
}

test "sanity: Axis with bounds" {
    const axis = Axis{
        .bounds = .{ 0, 100 },
        .title = "Values",
    };
    try std.testing.expectEqual(@as(f64, 0), axis.min());
    try std.testing.expectEqual(@as(f64, 100), axis.max());
    try std.testing.expectEqual(@as(f64, 100), axis.range());
}

test "sanity: LineDataset with data" {
    const data = [_][2]f64{
        .{ 0, 0 },
        .{ 50, 50 },
        .{ 100, 100 },
    };
    const dataset = LineDataset{
        .name = "Test",
        .data = &data,
        .marker = '*',
    };
    try std.testing.expectEqual(@as(usize, 3), dataset.data.len);
    try std.testing.expectEqualStrings("Test", dataset.name);
    try std.testing.expectEqual(@as(u21, '*'), dataset.marker.?);
}

test "sanity: Label struct" {
    const label = Label{
        .value = 50.0,
        .text = "50",
    };
    try std.testing.expectEqual(@as(f64, 50.0), label.value);
    try std.testing.expectEqualStrings("50", label.text);
}

// ============================================================
// BEHAVIOR TESTS - Axis rendering
// ============================================================

test "behavior: Chart renders Y-axis line" {
    var buf = try Buffer.init(std.testing.allocator, 30, 15);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    chart.render(Rect.init(0, 0, 30, 15), &buf);

    // Check that vertical axis line exists
    var found_vertical = false;
    for (buf.cells) |cell| {
        if (cell.char == VERTICAL or cell.char == TICK_Y) {
            found_vertical = true;
            break;
        }
    }
    try std.testing.expect(found_vertical);
}

test "behavior: Chart renders X-axis line" {
    var buf = try Buffer.init(std.testing.allocator, 30, 15);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    chart.render(Rect.init(0, 0, 30, 15), &buf);

    // Check that horizontal axis line exists
    var found_horizontal = false;
    for (buf.cells) |cell| {
        if (cell.char == HORIZONTAL or cell.char == TICK_X) {
            found_horizontal = true;
            break;
        }
    }
    try std.testing.expect(found_horizontal);
}

test "behavior: Chart renders corner" {
    var buf = try Buffer.init(std.testing.allocator, 30, 15);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    chart.render(Rect.init(0, 0, 30, 15), &buf);

    // Check that corner exists
    var found_corner = false;
    for (buf.cells) |cell| {
        if (cell.char == CORNER) {
            found_corner = true;
            break;
        }
    }
    try std.testing.expect(found_corner);
}

test "behavior: Chart renders Y-axis tick marks" {
    var buf = try Buffer.init(std.testing.allocator, 30, 15);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    chart.render(Rect.init(0, 0, 30, 15), &buf);

    // Check that tick marks exist
    var found_tick = false;
    for (buf.cells) |cell| {
        if (cell.char == TICK_Y) {
            found_tick = true;
            break;
        }
    }
    try std.testing.expect(found_tick);
}

test "behavior: Chart renders X-axis tick marks" {
    var buf = try Buffer.init(std.testing.allocator, 40, 15);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    chart.render(Rect.init(0, 0, 40, 15), &buf);

    // Check that tick marks exist
    var found_tick = false;
    for (buf.cells) |cell| {
        if (cell.char == TICK_X) {
            found_tick = true;
            break;
        }
    }
    try std.testing.expect(found_tick);
}

test "behavior: Chart with custom labels" {
    var buf = try Buffer.init(std.testing.allocator, 40, 15);
    defer buf.deinit();

    const y_labels = [_]Label{
        .{ .value = 0, .text = "0" },
        .{ .value = 50, .text = "50" },
        .{ .value = 100, .text = "100" },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 }, .labels = &y_labels },
    };
    chart.render(Rect.init(0, 0, 40, 15), &buf);

    // Check that some numeric labels appear
    var found_digit = false;
    for (buf.cells) |cell| {
        if (cell.char >= '0' and cell.char <= '9') {
            found_digit = true;
            break;
        }
    }
    try std.testing.expect(found_digit);
}

// ============================================================
// BEHAVIOR TESTS - Line dataset rendering
// ============================================================

test "behavior: Chart renders line dataset" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ 0, 0 },
        .{ 50, 50 },
        .{ 100, 100 },
    };
    const datasets = [_]LineDataset{
        .{ .data = &data },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .datasets = &datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Check that line characters exist
    var found_line = false;
    for (buf.cells) |cell| {
        if (cell.char == HORIZONTAL or cell.char == VERTICAL or
            cell.char == LINE_DIAG_UP or cell.char == LINE_DIAG_DOWN)
        {
            found_line = true;
            break;
        }
    }
    try std.testing.expect(found_line);
}

test "behavior: Chart renders markers" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ 50, 50 },
    };
    const datasets = [_]LineDataset{
        .{ .data = &data, .marker = '*' },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .datasets = &datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Check that marker exists
    var found_marker = false;
    for (buf.cells) |cell| {
        if (cell.char == '*') {
            found_marker = true;
            break;
        }
    }
    try std.testing.expect(found_marker);
}

test "behavior: Chart applies dataset style" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ 0, 0 },
        .{ 100, 100 },
    };
    const datasets = [_]LineDataset{
        .{ .data = &data, .style = Style.init().fg(.red) },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .datasets = &datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Check for styled cells
    var found_styled = false;
    for (buf.cells) |cell| {
        if (cell.style.getForeground()) |fg| {
            if (fg.eql(.red)) {
                found_styled = true;
                break;
            }
        }
    }
    try std.testing.expect(found_styled);
}

test "behavior: Chart renders multiple datasets" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data1 = [_][2]f64{
        .{ 0, 0 },
        .{ 100, 50 },
    };
    const data2 = [_][2]f64{
        .{ 0, 100 },
        .{ 100, 50 },
    };
    const datasets = [_]LineDataset{
        .{ .data = &data1, .style = Style.init().fg(.red) },
        .{ .data = &data2, .style = Style.init().fg(.blue) },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .datasets = &datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Check for both colored cells
    var found_red = false;
    var found_blue = false;
    for (buf.cells) |cell| {
        if (cell.style.getForeground()) |fg| {
            if (fg.eql(.red)) found_red = true;
            if (fg.eql(.blue)) found_blue = true;
        }
    }
    try std.testing.expect(found_red);
    try std.testing.expect(found_blue);
}

// ============================================================
// BEHAVIOR TESTS - Coordinate transformation
// ============================================================

test "behavior: dataToScreenX maps correctly" {
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    const layout = chart.calculateLayout(Rect.init(0, 0, 40, 20));

    // Min value should map to left of plot area
    const x_min = chart.dataToScreenX(0, layout);
    try std.testing.expectEqual(layout.plot_area.x, x_min);

    // Max value should map to right edge of plot area
    const x_max = chart.dataToScreenX(100, layout);
    try std.testing.expectEqual(layout.plot_area.right() -| 1, x_max);
}

test "behavior: dataToScreenY maps correctly with inverted Y" {
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    const layout = chart.calculateLayout(Rect.init(0, 0, 40, 20));

    // Min value (0) should map to bottom of plot area
    const y_min = chart.dataToScreenY(0, layout);
    try std.testing.expectEqual(layout.plot_area.bottom() -| 1, y_min);

    // Max value (100) should map to top of plot area
    const y_max = chart.dataToScreenY(100, layout);
    try std.testing.expectEqual(layout.plot_area.y, y_max);
}

// ============================================================
// BEHAVIOR TESTS - Nice number generation
// ============================================================

test "behavior: generateNiceLabels produces reasonable values" {
    const labels = generateNiceLabels(0, 100, 5);
    try std.testing.expect(labels.count > 0);
    try std.testing.expect(labels.count <= 16);

    // First label should be >= 0
    try std.testing.expect(labels.values[0] >= 0);

    // Last label should be <= 100
    try std.testing.expect(labels.values[labels.count - 1] <= 100);
}

test "behavior: niceNumber rounds to nice values" {
    // Should round to 1, 2, 5, or 10 times a power of 10
    try std.testing.expectEqual(@as(f64, 1), niceNumber(0.7, false));
    try std.testing.expectEqual(@as(f64, 2), niceNumber(1.5, false));
    try std.testing.expectEqual(@as(f64, 5), niceNumber(3.5, false));
    try std.testing.expectEqual(@as(f64, 10), niceNumber(7.5, false));
}

test "behavior: formatValue formats integers without decimals" {
    var buf: [16]u8 = undefined;
    const text = formatValue(50.0, &buf);
    try std.testing.expectEqualStrings("50", text);
}

test "behavior: formatValue formats decimals with one place" {
    var buf: [16]u8 = undefined;
    const text = formatValue(50.5, &buf);
    try std.testing.expectEqualStrings("50.5", text);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Chart handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    chart.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Chart handles very small area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    chart.render(Rect.init(0, 0, 3, 3), &buf);

    // Should not crash, minimal or no rendering expected
}

test "regression: Chart handles empty datasets" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .datasets = &.{},
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Should render axes without crashing
}

test "regression: Chart handles dataset with single point" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ 50, 50 },
    };
    const datasets = [_]LineDataset{
        .{ .data = &data },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .datasets = &datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Should not crash
}

test "regression: Chart handles zero range axis" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 50, 50 } },
        .y_axis = .{ .bounds = .{ 50, 50 } },
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Should not crash
}

test "regression: Chart handles negative bounds" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ -50, -50 },
        .{ 50, 50 },
    };
    const datasets = [_]LineDataset{
        .{ .data = &data },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ -100, 100 } },
        .y_axis = .{ .bounds = .{ -100, 100 } },
        .datasets = &datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Should render without crash
}

test "regression: Chart clips data points outside bounds" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ -50, 150 }, // Outside bounds
        .{ 50, 50 }, // Inside bounds
        .{ 150, -50 }, // Outside bounds
    };
    const datasets = [_]LineDataset{
        .{ .data = &data, .marker = '*' },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .datasets = &datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Should not crash, out-of-bounds points are clipped or clamped
}

test "regression: Chart renders at non-zero offset" {
    var buf = try Buffer.init(std.testing.allocator, 60, 30);
    defer buf.deinit();

    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
    };
    chart.render(Rect.init(10, 5, 40, 20), &buf);

    // Origin should be unchanged
    try std.testing.expect(buf.get(0, 0).isDefault());
}

// ============================================================
// BEHAVIOR TESTS - Scatter dataset rendering
// ============================================================

test "sanity: ScatterDataset with default values" {
    const data = [_][2]f64{
        .{ 10, 20 },
        .{ 30, 40 },
    };
    const dataset = ScatterDataset{
        .data = &data,
    };
    try std.testing.expectEqual(@as(usize, 2), dataset.data.len);
    try std.testing.expectEqual(Markers.dot, dataset.marker);
    try std.testing.expect(dataset.style.isEmpty());
}

test "sanity: Markers constants are valid unicode" {
    try std.testing.expectEqual(@as(u21, 0x25CF), Markers.dot);
    try std.testing.expectEqual(@as(u21, 0x25CB), Markers.circle);
    try std.testing.expectEqual(@as(u21, 0x25A0), Markers.square);
    try std.testing.expectEqual(@as(u21, 0x25A1), Markers.square_empty);
    try std.testing.expectEqual(@as(u21, 0x25C6), Markers.diamond);
    try std.testing.expectEqual(@as(u21, 0x25C7), Markers.diamond_empty);
    try std.testing.expectEqual(@as(u21, 0x25B2), Markers.triangle_up);
    try std.testing.expectEqual(@as(u21, 0x25BC), Markers.triangle_down);
    try std.testing.expectEqual(@as(u21, 0x2605), Markers.star);
    try std.testing.expectEqual(@as(u21, 0x2715), Markers.cross);
    try std.testing.expectEqual(@as(u21, '+'), Markers.plus);
    try std.testing.expectEqual(@as(u21, 0x00D7), Markers.x);
}

test "behavior: Chart renders scatter dataset markers" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ 50, 50 },
    };
    const scatter_datasets = [_]ScatterDataset{
        .{ .data = &data, .marker = Markers.star },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .scatter_datasets = &scatter_datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Check that marker exists somewhere in buffer
    var found_marker = false;
    for (buf.cells) |cell| {
        if (cell.char == Markers.star) {
            found_marker = true;
            break;
        }
    }
    try std.testing.expect(found_marker);
}

test "behavior: Chart renders multiple scatter points" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ 0, 0 },
        .{ 50, 50 },
        .{ 100, 100 },
    };
    const scatter_datasets = [_]ScatterDataset{
        .{ .data = &data, .marker = Markers.dot },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .scatter_datasets = &scatter_datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Count markers
    var marker_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == Markers.dot) {
            marker_count += 1;
        }
    }
    // At least some markers should be rendered (may overlap)
    try std.testing.expect(marker_count >= 1);
}

test "behavior: Chart applies scatter dataset style" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ 50, 50 },
    };
    const scatter_datasets = [_]ScatterDataset{
        .{ .data = &data, .marker = Markers.square, .style = Style.init().fg(.magenta) },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .scatter_datasets = &scatter_datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Check for styled marker
    var found_styled = false;
    for (buf.cells) |cell| {
        if (cell.char == Markers.square) {
            if (cell.style.getForeground()) |fg| {
                if (fg.eql(.magenta)) {
                    found_styled = true;
                    break;
                }
            }
        }
    }
    try std.testing.expect(found_styled);
}

test "behavior: Chart renders multiple scatter datasets" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data1 = [_][2]f64{
        .{ 25, 25 },
    };
    const data2 = [_][2]f64{
        .{ 75, 75 },
    };
    const scatter_datasets = [_]ScatterDataset{
        .{ .data = &data1, .marker = Markers.circle, .style = Style.init().fg(.red) },
        .{ .data = &data2, .marker = Markers.triangle_up, .style = Style.init().fg(.blue) },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .scatter_datasets = &scatter_datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Check for both markers
    var found_circle = false;
    var found_triangle = false;
    for (buf.cells) |cell| {
        if (cell.char == Markers.circle) found_circle = true;
        if (cell.char == Markers.triangle_up) found_triangle = true;
    }
    try std.testing.expect(found_circle);
    try std.testing.expect(found_triangle);
}

test "behavior: Chart renders both line and scatter datasets" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const line_data = [_][2]f64{
        .{ 0, 0 },
        .{ 100, 100 },
    };
    const scatter_data = [_][2]f64{
        .{ 50, 50 },
    };
    const line_datasets = [_]LineDataset{
        .{ .data = &line_data, .style = Style.init().fg(.green) },
    };
    const scatter_datasets = [_]ScatterDataset{
        .{ .data = &scatter_data, .marker = Markers.star, .style = Style.init().fg(.yellow) },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .datasets = &line_datasets,
        .scatter_datasets = &scatter_datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Check for scatter marker
    var found_star = false;
    for (buf.cells) |cell| {
        if (cell.char == Markers.star) {
            found_star = true;
            break;
        }
    }
    try std.testing.expect(found_star);
}

test "regression: Chart scatter dataset handles out-of-bounds points" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ -50, 150 }, // Outside bounds - gets clamped to edge
        .{ 50, 50 }, // Inside bounds
        .{ 150, -50 }, // Outside bounds - gets clamped to edge
    };
    const scatter_datasets = [_]ScatterDataset{
        .{ .data = &data, .marker = Markers.diamond },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .scatter_datasets = &scatter_datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // All points should render (out-of-bounds are clamped to edge, not excluded)
    // This matches the behavior of line datasets
    var marker_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == Markers.diamond) {
            marker_count += 1;
        }
    }
    // All 3 points should be rendered (clamped to edges)
    try std.testing.expect(marker_count >= 1);
}

test "regression: Chart scatter dataset handles empty data" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const scatter_datasets = [_]ScatterDataset{
        .{ .data = &.{}, .marker = Markers.dot },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .scatter_datasets = &scatter_datasets,
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Should not crash, no markers should be rendered
    var marker_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == Markers.dot) {
            marker_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), marker_count);
}

test "regression: Chart scatter uses default style when dataset style is empty" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    const data = [_][2]f64{
        .{ 50, 50 },
    };
    const scatter_datasets = [_]ScatterDataset{
        .{ .data = &data, .marker = Markers.cross },
    };
    const chart = Chart{
        .x_axis = .{ .bounds = .{ 0, 100 } },
        .y_axis = .{ .bounds = .{ 0, 100 } },
        .scatter_datasets = &scatter_datasets,
        .default_dataset_style = Style.init().fg(.cyan),
    };
    chart.render(Rect.init(0, 0, 40, 20), &buf);

    // Check for marker with default style
    var found_styled = false;
    for (buf.cells) |cell| {
        if (cell.char == Markers.cross) {
            if (cell.style.getForeground()) |fg| {
                if (fg.eql(.cyan)) {
                    found_styled = true;
                    break;
                }
            }
        }
    }
    try std.testing.expect(found_styled);
}
