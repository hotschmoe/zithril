// LineGauge widget for zithril TUI framework
// Compact single-line progress indicator

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Fractional block characters for sub-character resolution (1/8 increments).
/// These render left-to-right, filling from the left side of the cell.
const FRACTIONAL_BLOCKS: [9]u21 = .{
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

/// Line character sets for the gauge.
pub const LineSet = enum {
    /// Box drawing heavy horizontal (U+2501)
    normal,
    /// Full block for filled, space for unfilled
    thick,
    /// Box drawing light horizontal (U+2500)
    thin,

    /// Get the filled character for this line set.
    pub fn filledChar(self: LineSet) u21 {
        return switch (self) {
            .normal => 0x2501, // '━'
            .thick => 0x2588, // '█'
            .thin => 0x2500, // '─'
        };
    }

    /// Get the unfilled character for this line set.
    pub fn unfilledChar(self: LineSet) u21 {
        return switch (self) {
            .normal => 0x2500, // '─' (light horizontal for contrast)
            .thick => ' ', // space
            .thin => 0x2500, // '─' (same as filled, style differentiates)
        };
    }
};

/// LineGauge widget for compact single-line progress display.
///
/// Renders progress as a horizontal line, ideal for:
/// - Compact status bars
/// - Inline progress indicators
/// - Multiple gauges in limited vertical space
///
/// Features sub-character resolution using fractional block characters
/// for smooth progress rendering.
pub const LineGauge = struct {
    /// Progress ratio from 0.0 (empty) to 1.0 (full).
    /// Values outside this range are clamped.
    ratio: f32 = 0.0,

    /// Optional label displayed over the gauge.
    /// If null, displays the ratio as a percentage (e.g., "50%").
    label: ?[]const u8 = null,

    /// Style for the unfilled portion of the gauge.
    style: Style = Style.empty,

    /// Style for the filled portion of the gauge.
    gauge_style: Style = Style.init().fg(.green),

    /// Character set for drawing the line.
    line_set: LineSet = .normal,

    /// Render the line gauge into the buffer at the given area.
    /// Uses only the first row of the area.
    pub fn render(self: LineGauge, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;

        const clamped_ratio = std.math.clamp(self.ratio, 0.0, 1.0);
        const total_width_f = @as(f32, @floatFromInt(area.width));
        const filled_precise = total_width_f * clamped_ratio;
        const filled_whole: u16 = @intFromFloat(@floor(filled_precise));
        const fractional_part = filled_precise - @floor(filled_precise);
        const area_end = area.x +| area.width;

        // Render filled portion
        const filled_char = self.line_set.filledChar();
        var x = area.x;
        while (x < area.x +| filled_whole and x < area_end) : (x += 1) {
            buf.set(x, area.y, Cell.styled(filled_char, self.gauge_style));
        }

        // Render transition cell (fractional for thick style, unfilled otherwise)
        const transition_x = area.x +| filled_whole;
        if (transition_x < area_end) {
            const transition_char = self.transitionChar(fractional_part);
            const transition_style = if (transition_char != self.line_set.unfilledChar())
                self.gauge_style
            else
                self.style;
            buf.set(transition_x, area.y, Cell.styled(transition_char, transition_style));
        }

        // Render unfilled portion
        const unfilled_char = self.line_set.unfilledChar();
        x = transition_x +| 1;
        while (x < area_end) : (x += 1) {
            buf.set(x, area.y, Cell.styled(unfilled_char, self.style));
        }

        self.renderLabel(area, filled_whole, clamped_ratio, buf);
    }

    /// Get the character for the transition cell based on fractional fill.
    fn transitionChar(self: LineGauge, fractional_part: f32) u21 {
        if (self.line_set != .thick) return self.line_set.unfilledChar();
        const frac_index: usize = @intFromFloat(@round(fractional_part * 8.0));
        return FRACTIONAL_BLOCKS[@min(frac_index, 8)];
    }

    /// Render the label over the gauge.
    fn renderLabel(self: LineGauge, area: Rect, filled_whole: u16, ratio: f32, buf: *Buffer) void {
        // Prepare label text
        var label_buf: [8]u8 = undefined;
        const label_text = if (self.label) |l| l else blk: {
            const percent: u8 = @intFromFloat(@round(ratio * 100.0));
            const result = std.fmt.bufPrint(&label_buf, "{d}%", .{percent}) catch return;
            break :blk result;
        };

        if (label_text.len == 0) return;

        const text_len: u16 = @intCast(@min(label_text.len, area.width));
        if (text_len == 0) return;

        // Right-align the label (leave 1 cell padding if space allows)
        const label_start = if (area.width > text_len + 1)
            area.x +| area.width -| text_len -| 1
        else
            area.x +| area.width -| text_len;

        const fill_boundary = area.x +| filled_whole;

        // Write each character with appropriate style
        var iter = std.unicode.Utf8View.initUnchecked(label_text).iterator();
        var current_x = label_start;

        while (iter.nextCodepoint()) |codepoint| {
            if (current_x >= area.x +| area.width) break;

            // Use contrasting style based on position
            const char_style = if (current_x < fill_boundary)
                self.labelStyleOnFilled()
            else
                self.labelStyleOnUnfilled();

            buf.set(current_x, area.y, Cell.styled(codepoint, char_style));
            current_x +|= 1;
        }
    }

    /// Get the label style for text overlapping the filled portion.
    fn labelStyleOnFilled(self: LineGauge) Style {
        const fg_color = self.style.getBackground() orelse style_mod.Color.white;
        var result = Style.init().fg(fg_color);
        if (self.gauge_style.getForeground()) |gfg| result = result.bg(gfg);
        return result;
    }

    /// Get the label style for text on the unfilled portion.
    fn labelStyleOnUnfilled(self: LineGauge) Style {
        return self.style;
    }

    /// Create a line gauge showing a percentage (0-100).
    pub fn fromPercent(percent: u8) LineGauge {
        return .{
            .ratio = @as(f32, @floatFromInt(@min(percent, 100))) / 100.0,
        };
    }

    /// Create a line gauge from a count and total.
    pub fn fromCount(current: usize, total: usize) LineGauge {
        if (total == 0) return .{ .ratio = 0.0 };
        return .{
            .ratio = @as(f32, @floatFromInt(current)) / @as(f32, @floatFromInt(total)),
        };
    }
};

// ============================================================
// SANITY TESTS - Basic LineGauge functionality
// ============================================================

test "sanity: LineGauge with default values" {
    const gauge = LineGauge{};
    try std.testing.expectEqual(@as(f32, 0.0), gauge.ratio);
    try std.testing.expect(gauge.label == null);
    try std.testing.expect(gauge.style.isEmpty());
    try std.testing.expect(gauge.line_set == .normal);
}

test "sanity: LineGauge with ratio and label" {
    const gauge = LineGauge{
        .ratio = 0.5,
        .label = "Downloading...",
    };
    try std.testing.expectEqual(@as(f32, 0.5), gauge.ratio);
    try std.testing.expectEqualStrings("Downloading...", gauge.label.?);
}

test "sanity: LineGauge with custom styles" {
    const gauge = LineGauge{
        .ratio = 0.75,
        .style = Style.init().fg(.bright_black),
        .gauge_style = Style.init().fg(.cyan),
    };
    try std.testing.expect(!gauge.style.isEmpty());
    try std.testing.expect(!gauge.gauge_style.isEmpty());
}

test "sanity: LineSet characters are correct" {
    try std.testing.expectEqual(@as(u21, 0x2501), LineSet.normal.filledChar());
    try std.testing.expectEqual(@as(u21, 0x2500), LineSet.normal.unfilledChar());
    try std.testing.expectEqual(@as(u21, 0x2588), LineSet.thick.filledChar());
    try std.testing.expectEqual(@as(u21, ' '), LineSet.thick.unfilledChar());
    try std.testing.expectEqual(@as(u21, 0x2500), LineSet.thin.filledChar());
    try std.testing.expectEqual(@as(u21, 0x2500), LineSet.thin.unfilledChar());
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: LineGauge renders filled portion" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = 0.5,
        .line_set = .normal,
        .gauge_style = Style.init().fg(.green),
    };
    gauge.render(Rect.init(0, 0, 20, 1), &buf);

    // Check that filled portion uses the heavy horizontal character
    const filled_cell = buf.get(5, 0);
    try std.testing.expectEqual(@as(u21, 0x2501), filled_cell.char);
}

test "behavior: LineGauge renders unfilled portion" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = 0.25,
        .line_set = .normal,
        .style = Style.init().fg(.bright_black),
    };
    gauge.render(Rect.init(0, 0, 20, 1), &buf);

    // Check that unfilled portion uses the light horizontal character
    const unfilled_cell = buf.get(15, 0);
    try std.testing.expectEqual(@as(u21, 0x2500), unfilled_cell.char);
}

test "behavior: LineGauge renders default percentage label" {
    var buf = try Buffer.init(std.testing.allocator, 20, 3);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = 0.5,
    };
    gauge.render(Rect.init(0, 0, 20, 1), &buf);

    // Label "50%" should appear (right-aligned with padding)
    // Width 20, label "50%" (3 chars), padding 1 -> starts at position 16
    var found_5 = false;
    var found_0 = false;
    var found_percent = false;
    for (0..20) |x| {
        const cell = buf.get(@intCast(x), 0);
        if (cell.char == '5') found_5 = true;
        if (cell.char == '0') found_0 = true;
        if (cell.char == '%') found_percent = true;
    }
    try std.testing.expect(found_5);
    try std.testing.expect(found_0);
    try std.testing.expect(found_percent);
}

test "behavior: LineGauge renders custom label" {
    var buf = try Buffer.init(std.testing.allocator, 30, 3);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = 0.75,
        .label = "Loading",
    };
    gauge.render(Rect.init(0, 0, 30, 1), &buf);

    // Check for 'L' in "Loading"
    var found_L = false;
    for (0..30) |x| {
        if (buf.get(@intCast(x), 0).char == 'L') {
            found_L = true;
            break;
        }
    }
    try std.testing.expect(found_L);
}

test "behavior: LineGauge full renders entire width filled" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = 1.0,
        .line_set = .thick,
        .gauge_style = Style.init().fg(.green),
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // All cells should have the full block character (except where label is)
    // Label "100%" takes 4 chars + padding
    const cell = buf.get(0, 0);
    try std.testing.expectEqual(@as(u21, 0x2588), cell.char);
}

test "behavior: LineGauge empty renders all unfilled" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = 0.0,
        .line_set = .thick,
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // First cell should be space (unfilled for thick style)
    const cell = buf.get(0, 0);
    try std.testing.expectEqual(@as(u21, ' '), cell.char);
}

test "behavior: LineGauge thick style uses fractional blocks" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    // 0.55 ratio on width 10 = 5.5 cells filled
    // Should have 5 full blocks and 1 half block at position 5
    const gauge = LineGauge{
        .ratio = 0.55,
        .line_set = .thick,
        .gauge_style = Style.init().fg(.blue),
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // Cell at position 5 should be a fractional block
    const transition_cell = buf.get(5, 0);
    // Should be a fractional block (between 1/8 and full block)
    try std.testing.expect(transition_cell.char >= 0x258C and transition_cell.char <= 0x2590 or
        transition_cell.char == 0x2588 or transition_cell.char == ' ');
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: LineGauge handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const gauge = LineGauge{ .ratio = 0.5 };
    gauge.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: LineGauge clamps ratio below 0" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = -0.5,
        .line_set = .thick,
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // Should render as 0% (all unfilled)
    const cell = buf.get(0, 0);
    try std.testing.expectEqual(@as(u21, ' '), cell.char);
}

test "regression: LineGauge clamps ratio above 1" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = 1.5,
        .line_set = .thick,
        .gauge_style = Style.init().fg(.green),
    };
    gauge.render(Rect.init(0, 0, 10, 1), &buf);

    // Should render as 100% (all filled, except label area)
    const cell = buf.get(0, 0);
    try std.testing.expectEqual(@as(u21, 0x2588), cell.char);
}

test "regression: LineGauge.fromPercent creates correct ratio" {
    const g0 = LineGauge.fromPercent(0);
    try std.testing.expectEqual(@as(f32, 0.0), g0.ratio);

    const g50 = LineGauge.fromPercent(50);
    try std.testing.expectEqual(@as(f32, 0.5), g50.ratio);

    const g100 = LineGauge.fromPercent(100);
    try std.testing.expectEqual(@as(f32, 1.0), g100.ratio);

    const g150 = LineGauge.fromPercent(150);
    try std.testing.expectEqual(@as(f32, 1.0), g150.ratio);
}

test "regression: LineGauge.fromCount handles zero total" {
    const gauge = LineGauge.fromCount(5, 0);
    try std.testing.expectEqual(@as(f32, 0.0), gauge.ratio);
}

test "regression: LineGauge.fromCount calculates ratio" {
    const gauge = LineGauge.fromCount(3, 10);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), gauge.ratio, 0.001);
}

test "regression: LineGauge handles very narrow width" {
    var buf = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = 0.5,
        .label = "50%",
    };
    gauge.render(Rect.init(0, 0, 5, 1), &buf);

    // Should render without crashing, label may be truncated
}

test "regression: LineGauge renders at non-zero area offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const gauge = LineGauge{
        .ratio = 0.5,
        .line_set = .normal,
        .gauge_style = Style.init().fg(.green),
    };
    gauge.render(Rect.init(5, 3, 10, 1), &buf);

    // Filled portion should start at x=5
    const filled_cell = buf.get(7, 3);
    try std.testing.expectEqual(@as(u21, 0x2501), filled_cell.char);

    // Outside the area should be default
    try std.testing.expect(buf.get(0, 3).isDefault());
    try std.testing.expect(buf.get(15, 3).isDefault());
}

test "regression: LineGauge with all line sets" {
    var buf = try Buffer.init(std.testing.allocator, 30, 3);
    defer buf.deinit();

    // Test normal
    const gauge_normal = LineGauge{ .ratio = 0.5, .line_set = .normal };
    gauge_normal.render(Rect.init(0, 0, 30, 1), &buf);
    try std.testing.expectEqual(@as(u21, 0x2501), buf.get(2, 0).char);

    buf.clear();

    // Test thick
    const gauge_thick = LineGauge{ .ratio = 0.5, .line_set = .thick };
    gauge_thick.render(Rect.init(0, 0, 30, 1), &buf);
    try std.testing.expectEqual(@as(u21, 0x2588), buf.get(2, 0).char);

    buf.clear();

    // Test thin
    const gauge_thin = LineGauge{ .ratio = 0.5, .line_set = .thin };
    gauge_thin.render(Rect.init(0, 0, 30, 1), &buf);
    try std.testing.expectEqual(@as(u21, 0x2500), buf.get(2, 0).char);
}
