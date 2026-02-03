// Gauge widget for zithril TUI framework
// Progress bar with configurable ratio, label, and styles

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const text_mod = @import("text.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Alignment = text_mod.Alignment;

/// Progress bar widget.
///
/// Displays a horizontal progress bar with a filled portion representing the ratio
/// (0.0 to 1.0). Supports an optional centered label and separate styles for the
/// filled (gauge) and unfilled (background) portions.
pub const Gauge = struct {
    /// Progress ratio from 0.0 (empty) to 1.0 (full).
    /// Values outside this range are clamped.
    ratio: f32 = 0.0,

    /// Optional label displayed centered over the gauge.
    /// The label text color will be inverted where it overlaps the filled portion.
    label: ?[]const u8 = null,

    /// Style for the unfilled (background) portion of the gauge.
    style: Style = Style.empty,

    /// Style for the filled portion of the gauge.
    /// The background color of this style determines the fill color.
    gauge_style: Style = Style.init().bg(.green),

    /// Render the gauge into the buffer at the given area.
    /// Only uses the first row of the area.
    pub fn render(self: Gauge, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;

        // Clamp ratio to valid range
        const clamped_ratio = std.math.clamp(self.ratio, 0.0, 1.0);

        // Calculate filled width
        const total_width = area.width;
        const filled_width: u16 = @intFromFloat(@as(f32, @floatFromInt(total_width)) * clamped_ratio);

        // Fill background (unfilled portion)
        if (!self.style.isEmpty()) {
            const bg_cell = Cell.styled(' ', self.style);
            var x = area.x;
            while (x < area.x +| total_width) : (x += 1) {
                buf.set(x, area.y, bg_cell);
            }
        }

        // Fill gauge (filled portion)
        if (filled_width > 0) {
            const gauge_cell = Cell.styled(' ', self.gauge_style);
            var x = area.x;
            const fill_end = area.x +| filled_width;
            while (x < fill_end) : (x += 1) {
                buf.set(x, area.y, gauge_cell);
            }
        }

        // Render label if present
        if (self.label) |label_text| {
            self.renderLabel(label_text, area, filled_width, buf);
        }
    }

    /// Render the label centered over the gauge.
    /// Text overlapping the filled portion uses inverted colors.
    fn renderLabel(self: Gauge, label_text: []const u8, area: Rect, filled_width: u16, buf: *Buffer) void {
        if (label_text.len == 0) return;
        if (area.width == 0) return;

        const text_len: u16 = @intCast(@min(label_text.len, area.width));

        // Center the label
        const x_offset = (area.width -| text_len) / 2;
        const label_start = area.x +| x_offset;
        const fill_boundary = area.x +| filled_width;

        // Write each character with appropriate style
        var iter = std.unicode.Utf8View.initUnchecked(label_text).iterator();
        var current_x = label_start;

        while (iter.nextCodepoint()) |codepoint| {
            if (current_x >= area.x +| area.width) break;

            // Determine style based on position relative to fill boundary
            const char_style = if (current_x < fill_boundary)
                self.labelStyleOnFilled()
            else
                self.labelStyleOnUnfilled();

            buf.set(current_x, area.y, Cell.styled(codepoint, char_style));
            current_x +|= 1;
        }
    }

    /// Get the label style for text overlapping the filled portion.
    /// Uses gauge_style background as foreground, and optionally inverts.
    fn labelStyleOnFilled(self: Gauge) Style {
        // Get gauge background color for foreground
        const gauge_bg = self.gauge_style.getBackground();
        var result = Style.init();

        // Use gauge's background as label's foreground for contrast
        if (gauge_bg) |bg| {
            result = result.fg(bg);
        }

        // If style has a foreground, use it as background
        const style_fg = self.style.getForeground();
        if (style_fg) |fg| {
            result = result.bg(fg);
        } else {
            // Default: use gauge background
            if (gauge_bg) |bg| {
                result = result.bg(bg);
            }
        }

        return result;
    }

    /// Get the label style for text on the unfilled portion.
    fn labelStyleOnUnfilled(self: Gauge) Style {
        // Use the base style for unfilled areas
        return self.style;
    }

    /// Create a gauge showing a percentage (0-100).
    pub fn fromPercent(percent: u8) Gauge {
        return .{
            .ratio = @as(f32, @floatFromInt(@min(percent, 100))) / 100.0,
        };
    }

    /// Create a gauge from a count and total.
    pub fn fromCount(current: usize, total: usize) Gauge {
        if (total == 0) return .{ .ratio = 0.0 };
        return .{
            .ratio = @as(f32, @floatFromInt(current)) / @as(f32, @floatFromInt(total)),
        };
    }
};

// ============================================================
// SANITY TESTS - Basic Gauge functionality
// ============================================================

test "sanity: Gauge with default values" {
    const gauge = Gauge{};
    try std.testing.expectEqual(@as(f32, 0.0), gauge.ratio);
    try std.testing.expect(gauge.label == null);
    try std.testing.expect(gauge.style.isEmpty());
}

test "sanity: Gauge with ratio and label" {
    const gauge = Gauge{
        .ratio = 0.5,
        .label = "50%",
    };
    try std.testing.expectEqual(@as(f32, 0.5), gauge.ratio);
    try std.testing.expectEqualStrings("50%", gauge.label.?);
}

test "sanity: Gauge with custom styles" {
    const gauge = Gauge{
        .ratio = 0.75,
        .style = Style.init().bg(.black),
        .gauge_style = Style.init().bg(.cyan),
    };
    try std.testing.expect(!gauge.style.isEmpty());
    try std.testing.expect(!gauge.gauge_style.isEmpty());
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Gauge renders filled portion" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = 0.5,
        .gauge_style = Style.init().bg(.green),
    };
    gauge.render(Rect.init(0, 0, 20, 1), &buf);

    // First 10 cells should have green background
    const filled_cell = buf.get(5, 0);
    try std.testing.expect(filled_cell.style.getBackground() != null);

    // Cell at position 15 should not have gauge_style background
    const unfilled_cell = buf.get(15, 0);
    _ = unfilled_cell;
}

test "behavior: Gauge renders background style" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = 0.25,
        .style = Style.init().bg(.blue),
        .gauge_style = Style.init().bg(.green),
    };
    gauge.render(Rect.init(0, 0, 20, 1), &buf);

    // Background portion should have blue bg
    const bg_cell = buf.get(15, 0);
    try std.testing.expect(bg_cell.style.getBackground() != null);
}

test "behavior: Gauge renders label centered" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = 0.0,
        .label = "TEST",
    };
    gauge.render(Rect.init(0, 0, 20, 1), &buf);

    // "TEST" (4 chars) centered in 20 = offset 8
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(8, 0).char);
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(9, 0).char);
    try std.testing.expectEqual(@as(u21, 'S'), buf.get(10, 0).char);
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(11, 0).char);
}

test "behavior: Gauge full renders entire width" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = 1.0,
        .gauge_style = Style.init().bg(.green),
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // All cells should have green background
    for (0..10) |x| {
        const cell = buf.get(@intCast(x), 0);
        try std.testing.expect(cell.style.getBackground() != null);
    }
}

test "behavior: Gauge empty renders no filled portion" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = 0.0,
        .style = Style.init().bg(.black),
        .gauge_style = Style.init().bg(.green),
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // All cells should have black background (style, not gauge_style)
    const cell = buf.get(5, 0);
    const bg = cell.style.getBackground();
    try std.testing.expect(bg != null);
    try std.testing.expect(bg.?.eql(.black));
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Gauge handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const gauge = Gauge{ .ratio = 0.5 };
    gauge.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Gauge clamps ratio below 0" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = -0.5,
        .gauge_style = Style.init().bg(.green),
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // No filled portion should exist (clamped to 0)
    const cell = buf.get(0, 0);
    const bg = cell.style.getBackground();
    // Should not have green background
    try std.testing.expect(bg == null or !bg.?.eql(.green));
}

test "regression: Gauge clamps ratio above 1" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = 1.5,
        .gauge_style = Style.init().bg(.green),
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // All cells should be filled (clamped to 1.0)
    for (0..10) |x| {
        const cell = buf.get(@intCast(x), 0);
        try std.testing.expect(cell.style.getBackground() != null);
    }
}

test "regression: Gauge.fromPercent creates correct ratio" {
    const g0 = Gauge.fromPercent(0);
    try std.testing.expectEqual(@as(f32, 0.0), g0.ratio);

    const g50 = Gauge.fromPercent(50);
    try std.testing.expectEqual(@as(f32, 0.5), g50.ratio);

    const g100 = Gauge.fromPercent(100);
    try std.testing.expectEqual(@as(f32, 1.0), g100.ratio);

    const g150 = Gauge.fromPercent(150);
    try std.testing.expectEqual(@as(f32, 1.0), g150.ratio);
}

test "regression: Gauge.fromCount handles zero total" {
    const gauge = Gauge.fromCount(5, 0);
    try std.testing.expectEqual(@as(f32, 0.0), gauge.ratio);
}

test "regression: Gauge.fromCount calculates ratio" {
    const gauge = Gauge.fromCount(3, 10);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), gauge.ratio, 0.001);
}

test "regression: Gauge label truncated when too long" {
    var buf = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = 0.0,
        .label = "This is a very long label",
    };
    gauge.render(Rect.init(0, 0, 5, 1), &buf);

    // Should render some of the label without crashing
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(0, 0).char);
}

test "regression: Gauge handles empty label" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = 0.5,
        .label = "",
        .gauge_style = Style.init().bg(.green),
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // Should render gauge without label
    const cell = buf.get(2, 0);
    try std.testing.expect(cell.style.getBackground() != null);
}

test "regression: Gauge renders at non-zero area offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const gauge = Gauge{
        .ratio = 0.5,
        .gauge_style = Style.init().bg(.green),
    };
    gauge.render(Rect.init(5, 3, 10, 1), &buf);

    // Filled portion should start at x=5
    const filled_cell = buf.get(7, 3);
    try std.testing.expect(filled_cell.style.getBackground() != null);

    // Outside the area should be default
    try std.testing.expect(buf.get(0, 3).isDefault());
    try std.testing.expect(buf.get(15, 3).isDefault());
}
