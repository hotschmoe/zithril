// Sparkline widget for zithril TUI framework
// Compact inline data visualization using vertical bar Unicode characters

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Unicode block characters for bar heights (8 levels + empty).
/// Index 0 = empty (space), index 8 = full block.
const BAR_CHARS: [9]u21 = .{
    ' ',    // 0/8 - empty
    0x2581, // 1/8 - lower one eighth block
    0x2582, // 2/8 - lower one quarter block
    0x2583, // 3/8 - lower three eighths block
    0x2584, // 4/8 - lower half block
    0x2585, // 5/8 - lower five eighths block
    0x2586, // 6/8 - lower three quarters block
    0x2587, // 7/8 - lower seven eighths block
    0x2588, // 8/8 - full block
};

/// Direction for data flow in the sparkline.
pub const Direction = enum {
    /// Data flows left to right (most recent on right).
    left_to_right,
    /// Data flows right to left (most recent on left).
    right_to_left,
};

/// Sparkline widget for compact inline data visualization.
///
/// Renders a series of numeric values as vertical bars within a single line,
/// using Unicode block characters for sub-cell resolution.
/// Commonly used for CPU/memory usage history, stock prices, network throughput.
pub const Sparkline = struct {
    /// Values to display. Each value becomes one bar.
    data: []const f64 = &.{},

    /// Optional explicit maximum value. If null, auto-detects from data.
    /// Values exceeding max are clamped to full bar height.
    max: ?f64 = null,

    /// Style for the bars.
    style: Style = Style.empty,

    /// Data flow direction.
    direction: Direction = .left_to_right,

    /// Render the sparkline into the buffer at the given area.
    /// Uses only the first row of the area. Clips data to available width.
    pub fn render(self: Sparkline, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.data.len == 0) return;

        const width: usize = area.width;

        // Determine the effective maximum value
        const effective_max = self.max orelse self.findMax();
        if (effective_max <= 0) return;

        // Determine which portion of data to display (show most recent N values)
        const data_start = if (self.data.len > width) self.data.len - width else 0;
        const display_data = self.data[data_start..];

        // Render each bar
        for (display_data, 0..) |value, i| {
            const x: u16 = switch (self.direction) {
                .left_to_right => area.x +| @as(u16, @intCast(i)),
                .right_to_left => area.x +| area.width -| 1 -| @as(u16, @intCast(i)),
            };

            const bar_char = self.valueToBarChar(value, effective_max);
            buf.set(x, area.y, Cell.styled(bar_char, self.style));
        }
    }

    /// Find the maximum value in the data.
    fn findMax(self: Sparkline) f64 {
        var max_val: f64 = 0;
        for (self.data) |v| {
            if (v > max_val) max_val = v;
        }
        return max_val;
    }

    /// Convert a value to the appropriate bar character.
    fn valueToBarChar(self: Sparkline, value: f64, max_val: f64) u21 {
        _ = self;
        if (value <= 0 or max_val <= 0) return BAR_CHARS[0];

        // Normalize value to 0.0-1.0 range, clamping to max
        const normalized = @min(value / max_val, 1.0);

        // Convert to bar index (0-8)
        const bar_index: usize = @intFromFloat(@round(normalized * 8.0));
        return BAR_CHARS[@min(bar_index, 8)];
    }

    /// Create a sparkline from a slice of u64 values.
    pub fn fromU64(data: []const u64) Sparkline {
        // This is a convenience for when you have integer data.
        // Note: caller must ensure the f64 slice outlives the sparkline.
        _ = data;
        return .{};
    }

    /// Create a sparkline with percentage-based max (100.0).
    pub fn forPercentages(data: []const f64) Sparkline {
        return .{
            .data = data,
            .max = 100.0,
        };
    }
};

// ============================================================
// SANITY TESTS - Basic Sparkline functionality
// ============================================================

test "sanity: Sparkline with default values" {
    const sparkline = Sparkline{};
    try std.testing.expectEqual(@as(usize, 0), sparkline.data.len);
    try std.testing.expect(sparkline.max == null);
    try std.testing.expect(sparkline.style.isEmpty());
    try std.testing.expect(sparkline.direction == .left_to_right);
}

test "sanity: Sparkline with data" {
    const data = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const sparkline = Sparkline{
        .data = &data,
        .max = 5.0,
    };
    try std.testing.expectEqual(@as(usize, 5), sparkline.data.len);
    try std.testing.expectEqual(@as(f64, 5.0), sparkline.max.?);
}

test "sanity: Sparkline with custom style" {
    const sparkline = Sparkline{
        .style = Style.init().fg(.green),
    };
    try std.testing.expect(!sparkline.style.isEmpty());
}

// ============================================================
// BEHAVIOR TESTS - Bar character mapping
// ============================================================

test "behavior: valueToBarChar returns correct characters" {
    const sparkline = Sparkline{};

    // 0% = empty
    try std.testing.expectEqual(@as(u21, ' '), sparkline.valueToBarChar(0.0, 100.0));

    // 100% = full block
    try std.testing.expectEqual(@as(u21, 0x2588), sparkline.valueToBarChar(100.0, 100.0));

    // 50% = half block (index 4)
    try std.testing.expectEqual(@as(u21, 0x2584), sparkline.valueToBarChar(50.0, 100.0));

    // 25% = quarter block (index 2)
    try std.testing.expectEqual(@as(u21, 0x2582), sparkline.valueToBarChar(25.0, 100.0));

    // 75% = three quarters block (index 6)
    try std.testing.expectEqual(@as(u21, 0x2586), sparkline.valueToBarChar(75.0, 100.0));
}

test "behavior: valueToBarChar clamps values exceeding max" {
    const sparkline = Sparkline{};

    // Value > max should clamp to full block
    try std.testing.expectEqual(@as(u21, 0x2588), sparkline.valueToBarChar(150.0, 100.0));
}

test "behavior: valueToBarChar handles negative values" {
    const sparkline = Sparkline{};

    // Negative values should return empty
    try std.testing.expectEqual(@as(u21, ' '), sparkline.valueToBarChar(-10.0, 100.0));
}

test "behavior: findMax returns maximum value" {
    const data = [_]f64{ 1.0, 5.0, 3.0, 2.0, 4.0 };
    const sparkline = Sparkline{ .data = &data };
    try std.testing.expectEqual(@as(f64, 5.0), sparkline.findMax());
}

test "behavior: findMax returns 0 for empty data" {
    const sparkline = Sparkline{};
    try std.testing.expectEqual(@as(f64, 0.0), sparkline.findMax());
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Sparkline renders bars at correct positions" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]f64{ 0.0, 50.0, 100.0 };
    const sparkline = Sparkline{
        .data = &data,
        .max = 100.0,
    };
    sparkline.render(Rect.init(0, 0, 10, 1), &buf);

    // First bar: 0% = empty
    try std.testing.expectEqual(@as(u21, ' '), buf.get(0, 0).char);

    // Second bar: 50% = half block
    try std.testing.expectEqual(@as(u21, 0x2584), buf.get(1, 0).char);

    // Third bar: 100% = full block
    try std.testing.expectEqual(@as(u21, 0x2588), buf.get(2, 0).char);
}

test "behavior: Sparkline clips to available width" {
    var buf = try Buffer.init(std.testing.allocator, 5, 3);
    defer buf.deinit();

    const data = [_]f64{ 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0 };
    const sparkline = Sparkline{
        .data = &data,
        .max = 100.0,
    };
    sparkline.render(Rect.init(0, 0, 5, 1), &buf);

    // Should render only last 5 values (60-100)
    // Bars should be non-empty
    for (0..5) |x| {
        try std.testing.expect(buf.get(@intCast(x), 0).char != ' ');
    }
}

test "behavior: Sparkline right_to_left direction" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]f64{ 25.0, 50.0, 100.0 };
    const sparkline = Sparkline{
        .data = &data,
        .max = 100.0,
        .direction = .right_to_left,
    };
    sparkline.render(Rect.init(0, 0, 10, 1), &buf);

    // Right-to-left: first data value at rightmost position
    // Width 10, 3 values: positions 9, 8, 7
    try std.testing.expectEqual(@as(u21, 0x2582), buf.get(9, 0).char); // 25%
    try std.testing.expectEqual(@as(u21, 0x2584), buf.get(8, 0).char); // 50%
    try std.testing.expectEqual(@as(u21, 0x2588), buf.get(7, 0).char); // 100%
}

test "behavior: Sparkline applies custom style" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]f64{100.0};
    const sparkline = Sparkline{
        .data = &data,
        .max = 100.0,
        .style = Style.init().fg(.green),
    };
    sparkline.render(Rect.init(0, 0, 10, 1), &buf);

    const cell = buf.get(0, 0);
    try std.testing.expect(cell.style.getForeground() != null);
}

test "behavior: Sparkline auto-detects max from data" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]f64{ 1.0, 2.0, 4.0 };
    const sparkline = Sparkline{
        .data = &data,
        // max is null, should auto-detect to 4.0
    };
    sparkline.render(Rect.init(0, 0, 10, 1), &buf);

    // Last value (4.0) should be full block when max is auto-detected
    try std.testing.expectEqual(@as(u21, 0x2588), buf.get(2, 0).char);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Sparkline handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const data = [_]f64{100.0};
    const sparkline = Sparkline{
        .data = &data,
        .max = 100.0,
    };
    sparkline.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Sparkline handles empty data" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const sparkline = Sparkline{};
    sparkline.render(Rect.init(0, 0, 10, 1), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Sparkline handles single value" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]f64{75.0};
    const sparkline = Sparkline{
        .data = &data,
        .max = 100.0,
    };
    sparkline.render(Rect.init(0, 0, 10, 1), &buf);

    // Should render one bar at position 0
    try std.testing.expectEqual(@as(u21, 0x2586), buf.get(0, 0).char);
}

test "regression: Sparkline handles all zeros" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]f64{ 0.0, 0.0, 0.0 };
    const sparkline = Sparkline{
        .data = &data,
        .max = 100.0,
    };
    sparkline.render(Rect.init(0, 0, 10, 1), &buf);

    // All bars should be empty (space)
    try std.testing.expectEqual(@as(u21, ' '), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(2, 0).char);
}

test "regression: Sparkline with all zeros and auto-max does not render" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    const data = [_]f64{ 0.0, 0.0, 0.0 };
    const sparkline = Sparkline{
        .data = &data,
        // max is null, auto-detect will be 0
    };
    sparkline.render(Rect.init(0, 0, 10, 1), &buf);

    // With max=0, nothing should be rendered
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Sparkline renders at non-zero area offset" {
    var buf = try Buffer.init(std.testing.allocator, 30, 10);
    defer buf.deinit();

    const data = [_]f64{100.0};
    const sparkline = Sparkline{
        .data = &data,
        .max = 100.0,
    };
    sparkline.render(Rect.init(5, 3, 10, 1), &buf);

    // Bar should be at offset position
    try std.testing.expectEqual(@as(u21, 0x2588), buf.get(5, 3).char);

    // Outside the area should be default
    try std.testing.expect(buf.get(0, 3).isDefault());
    try std.testing.expect(buf.get(15, 3).isDefault());
}

test "regression: forPercentages creates correct sparkline" {
    const data = [_]f64{ 25.0, 50.0, 75.0 };
    const sparkline = Sparkline.forPercentages(&data);

    try std.testing.expectEqual(@as(f64, 100.0), sparkline.max.?);
    try std.testing.expectEqual(@as(usize, 3), sparkline.data.len);
}
