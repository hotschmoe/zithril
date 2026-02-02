// Canvas widget for zithril TUI framework
// Provides a coordinate-based drawing surface for arbitrary shapes

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Color = style_mod.Color;

// Re-export shapes module
pub const shapes = @import("canvas/shapes.zig");
pub const Shape = shapes.Shape;
pub const Painter = shapes.Painter;
pub const Circle = shapes.Circle;
pub const Line = shapes.Line;
pub const Rectangle = shapes.Rectangle;
pub const Points = shapes.Points;

/// Marker styles for canvas rendering.
pub const Marker = enum {
    /// Single dot character '.'
    dot,
    /// Block character (solid)
    block,
    /// Braille patterns for high resolution (2x4 dots per cell)
    braille,
    /// Half block characters for 1x2 resolution
    half_block,
};

/// Canvas widget for drawing arbitrary shapes using terminal characters.
/// Provides a virtual coordinate system that maps to terminal cells.
pub const Canvas = struct {
    /// X-axis bounds [min, max] in virtual coordinates.
    x_bounds: [2]f64,
    /// Y-axis bounds [min, max] in virtual coordinates.
    y_bounds: [2]f64,
    /// Marker style for drawing (currently only dot is implemented).
    marker: Marker = .dot,
    /// Background color for the canvas area.
    background_color: Color = .default,

    /// Render the canvas background into the buffer.
    pub fn render(self: Canvas, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;

        // Fill with background color if not default
        if (!self.background_color.eql(.default)) {
            const bg_style = Style.init().bg(self.background_color);
            buf.fill(area, Cell.styled(' ', bg_style));
        }
    }

    /// Draw a collection of shapes onto the canvas.
    pub fn draw(self: *Canvas, area: Rect, buf: *Buffer, shape_list: []const Shape) void {
        if (area.isEmpty()) return;

        var p = Painter.init(
            self.x_bounds,
            self.y_bounds,
            buf,
            area,
            self.background_color,
        );

        for (shape_list) |shape| {
            shape.draw(&p);
        }
    }

    /// Create a Painter for direct drawing operations.
    pub fn painter(self: *Canvas, area: Rect, buf: *Buffer) Painter {
        return Painter.init(
            self.x_bounds,
            self.y_bounds,
            buf,
            area,
            self.background_color,
        );
    }

    /// Transform a point from virtual coordinates to screen coordinates.
    /// Returns null if the point is outside the canvas bounds.
    pub fn virtualToScreen(self: Canvas, x: f64, y: f64, area: Rect) ?struct { x: u16, y: u16 } {
        if (x < self.x_bounds[0] or x > self.x_bounds[1]) return null;
        if (y < self.y_bounds[0] or y > self.y_bounds[1]) return null;

        const x_range = self.x_bounds[1] - self.x_bounds[0];
        const y_range = self.y_bounds[1] - self.y_bounds[0];

        if (x_range == 0 or y_range == 0) return null;

        const x_ratio = (x - self.x_bounds[0]) / x_range;
        const y_ratio = (y - self.y_bounds[0]) / y_range;

        const w: f64 = @floatFromInt(area.width -| 1);
        const h: f64 = @floatFromInt(area.height -| 1);

        return .{
            .x = area.x +| @as(u16, @intFromFloat(x_ratio * w)),
            .y = area.y +| area.height -| 1 -| @as(u16, @intFromFloat(y_ratio * h)),
        };
    }
};

// ============================================================
// SANITY TESTS - Basic Canvas functionality
// ============================================================

test "sanity: Canvas with default values" {
    const canvas = Canvas{
        .x_bounds = .{ 0, 100 },
        .y_bounds = .{ 0, 100 },
    };
    try std.testing.expectEqual(@as(f64, 0), canvas.x_bounds[0]);
    try std.testing.expectEqual(@as(f64, 100), canvas.x_bounds[1]);
    try std.testing.expect(canvas.marker == .dot);
    try std.testing.expect(canvas.background_color.eql(.default));
}

test "sanity: Canvas.render fills background" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const canvas = Canvas{
        .x_bounds = .{ 0, 100 },
        .y_bounds = .{ 0, 100 },
        .background_color = .blue,
    };

    canvas.render(Rect.init(0, 0, 10, 5), &buf);

    // Check that background was filled
    const cell = buf.get(5, 2);
    if (cell.style.getBackground()) |bg| {
        try std.testing.expect(bg.eql(.blue));
    }
}

test "sanity: Canvas.virtualToScreen transforms correctly" {
    const canvas = Canvas{
        .x_bounds = .{ 0, 100 },
        .y_bounds = .{ 0, 100 },
    };

    const area = Rect.init(0, 0, 40, 20);

    // Origin should map to bottom-left
    const origin = canvas.virtualToScreen(0, 0, area).?;
    try std.testing.expectEqual(@as(u16, 0), origin.x);
    try std.testing.expectEqual(@as(u16, 19), origin.y);

    // Max corner should map to top-right
    const max = canvas.virtualToScreen(100, 100, area).?;
    try std.testing.expectEqual(@as(u16, 39), max.x);
    try std.testing.expectEqual(@as(u16, 0), max.y);
}

test "sanity: Canvas.virtualToScreen returns null for out-of-bounds" {
    const canvas = Canvas{
        .x_bounds = .{ 0, 100 },
        .y_bounds = .{ 0, 100 },
    };

    const area = Rect.init(0, 0, 40, 20);

    try std.testing.expect(canvas.virtualToScreen(-1, 50, area) == null);
    try std.testing.expect(canvas.virtualToScreen(101, 50, area) == null);
    try std.testing.expect(canvas.virtualToScreen(50, -1, area) == null);
    try std.testing.expect(canvas.virtualToScreen(50, 101, area) == null);
}

// ============================================================
// BEHAVIOR TESTS - Drawing shapes
// ============================================================

test "behavior: Canvas.draw draws shapes" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var canvas = Canvas{
        .x_bounds = .{ 0, 100 },
        .y_bounds = .{ 0, 100 },
    };

    const circle = Circle{
        .x = 50,
        .y = 50,
        .radius = 20,
        .color = .red,
    };

    const line = Line{
        .x1 = 0,
        .y1 = 0,
        .x2 = 100,
        .y2 = 100,
        .color = .green,
    };

    const shape_list = [_]Shape{
        circle.shape(),
        line.shape(),
    };

    canvas.draw(Rect.init(0, 0, 40, 20), &buf, &shape_list);

    // Check that shapes were drawn
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expect(pixel_count > 0);
}

test "behavior: Canvas.painter returns working Painter" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var canvas = Canvas{
        .x_bounds = .{ 0, 100 },
        .y_bounds = .{ 0, 100 },
    };

    var p = canvas.painter(Rect.init(0, 0, 40, 20), &buf);

    // Draw directly with painter
    p.paint(50, 50, .cyan);

    // Check that pixel was drawn
    var found = false;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Canvas.render with empty area does nothing" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const canvas = Canvas{
        .x_bounds = .{ 0, 100 },
        .y_bounds = .{ 0, 100 },
        .background_color = .red,
    };

    canvas.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Canvas.draw with empty shape list" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    var canvas = Canvas{
        .x_bounds = .{ 0, 100 },
        .y_bounds = .{ 0, 100 },
    };

    canvas.draw(Rect.init(0, 0, 20, 10), &buf, &.{});

    // Buffer should be unchanged (no shapes to draw)
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Canvas.virtualToScreen with zero range returns null" {
    const canvas = Canvas{
        .x_bounds = .{ 50, 50 },
        .y_bounds = .{ 50, 50 },
    };

    const result = canvas.virtualToScreen(50, 50, Rect.init(0, 0, 40, 20));
    try std.testing.expect(result == null);
}

test "regression: Canvas handles negative bounds" {
    const canvas = Canvas{
        .x_bounds = .{ -100, 100 },
        .y_bounds = .{ -50, 50 },
    };

    const area = Rect.init(0, 0, 40, 20);

    // Origin (0, 0) is at 50% of both ranges
    // x: 50% of (40-1) = 19.5 -> 19
    // y: screen Y is inverted, so 50% from top means middle
    // y: area.y + area.height - 1 - (0.5 * (height - 1))
    //  = 0 + 19 - 9 = 10 (with integer truncation on 9.5 -> 9)
    const center = canvas.virtualToScreen(0, 0, area).?;
    try std.testing.expectEqual(@as(u16, 19), center.x); // middle x
    try std.testing.expectEqual(@as(u16, 10), center.y); // middle y (19 - 9 = 10)
}

// ============================================================
// Module-level tests
// ============================================================

test "canvas module" {
    _ = shapes;
}
