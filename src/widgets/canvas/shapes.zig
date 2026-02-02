// Canvas shapes module for zithril TUI framework
// Provides Shape trait interface and built-in shapes (Circle, Line)

const std = @import("std");
const buffer_mod = @import("../../buffer.zig");
const geometry = @import("../../geometry.zig");
const style_mod = @import("../../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Color = style_mod.Color;

// ============================================================
// Painter - Drawing context for shapes
// ============================================================

/// Screen coordinate pair returned by coordinate transformation.
pub const ScreenPoint = struct { x: i32, y: i32 };

/// Painter provides drawing operations for shapes on a Canvas.
/// Transforms virtual coordinates to screen coordinates and handles pixel operations.
pub const Painter = struct {
    /// X-axis bounds [min, max] in virtual coordinates.
    x_bounds: [2]f64,
    /// Y-axis bounds [min, max] in virtual coordinates.
    y_bounds: [2]f64,
    /// Buffer to draw into.
    buffer: *Buffer,
    /// Screen area to draw within.
    area: Rect,
    /// Background color for the canvas.
    background_color: Color,

    /// Initialize a Painter for the given bounds, buffer, and area.
    pub fn init(
        x_bounds: [2]f64,
        y_bounds: [2]f64,
        buffer: *Buffer,
        area: Rect,
        background_color: Color,
    ) Painter {
        return .{
            .x_bounds = x_bounds,
            .y_bounds = y_bounds,
            .buffer = buffer,
            .area = area,
            .background_color = background_color,
        };
    }

    /// Paint a single point in virtual coordinates.
    pub fn paint(self: *Painter, x: f64, y: f64, color: Color) void {
        if (self.virtualToScreen(x, y)) |screen| {
            self.setPixel(screen.x, screen.y, color);
        }
    }

    /// Set a pixel at screen coordinates with the given color.
    pub fn setPixel(self: *Painter, x: i32, y: i32, color: Color) void {
        if (x < 0 or y < 0) return;

        const ux: u16 = @intCast(x);
        const uy: u16 = @intCast(y);

        if (!self.area.contains(ux, uy)) return;

        const style = Style.init().fg(color);
        self.buffer.set(ux, uy, Cell.styled(0x2022, style)); // bullet point
    }

    /// Transform virtual coordinates to screen coordinates.
    /// Returns null if bounds have zero range.
    pub fn virtualToScreen(self: Painter, x: f64, y: f64) ?ScreenPoint {
        const x_range = self.x_bounds[1] - self.x_bounds[0];
        const y_range = self.y_bounds[1] - self.y_bounds[0];

        if (x_range == 0 or y_range == 0) return null;

        const w: f64 = @floatFromInt(self.area.width -| 1);
        const h: f64 = @floatFromInt(self.area.height -| 1);
        const x_ratio = (x - self.x_bounds[0]) / x_range;
        const y_ratio = (y - self.y_bounds[0]) / y_range;

        return .{
            .x = @as(i32, self.area.x) + @as(i32, @intFromFloat(x_ratio * w)),
            .y = @as(i32, self.area.y) + @as(i32, self.area.height -| 1) - @as(i32, @intFromFloat(y_ratio * h)),
        };
    }

    /// Get the screen-space width of the drawing area.
    pub fn screenWidth(self: Painter) u16 {
        return self.area.width;
    }

    /// Get the screen-space height of the drawing area.
    pub fn screenHeight(self: Painter) u16 {
        return self.area.height;
    }
};

// ============================================================
// Shape Interface - Type-erased trait for custom shapes
// ============================================================

/// Shape is a type-erased interface for drawable objects.
/// Allows heterogeneous collections of shapes to be drawn on a Canvas.
pub const Shape = struct {
    ptr: *const anyopaque,
    drawFn: *const fn (ptr: *const anyopaque, painter: *Painter) void,

    /// Create a Shape from a concrete shape type.
    /// The concrete type must have a `draw(*Painter)` method or be passed a draw function.
    pub fn init(pointer: anytype, comptime drawFn: fn (ptr: @TypeOf(pointer), painter: *Painter) void) Shape {
        const Ptr = @TypeOf(pointer);

        const wrapper = struct {
            fn draw(ptr: *const anyopaque, painter: *Painter) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                drawFn(self, painter);
            }
        };

        return .{
            .ptr = pointer,
            .drawFn = wrapper.draw,
        };
    }

    /// Draw this shape using the provided painter.
    pub fn draw(self: Shape, painter: *Painter) void {
        self.drawFn(self.ptr, painter);
    }
};

// ============================================================
// Circle Shape - Bresenham's circle algorithm
// ============================================================

/// Circle shape for drawing circle outlines on a Canvas.
pub const Circle = struct {
    /// Center X coordinate in virtual space.
    x: f64,
    /// Center Y coordinate in virtual space.
    y: f64,
    /// Radius in virtual coordinate units.
    radius: f64,
    /// Color of the circle outline.
    color: Color = .white,

    /// Create a Shape interface for this Circle.
    pub fn shape(self: *const Circle) Shape {
        return Shape.init(self, draw);
    }

    /// Draw the circle using Bresenham's algorithm.
    fn draw(self: *const Circle, painter: *Painter) void {
        // Transform center to screen coordinates
        const center = painter.virtualToScreen(self.x, self.y) orelse return;

        // Calculate screen-space radius
        // Use average of x and y scale to get approximate radius in screen space
        const x_range = painter.x_bounds[1] - painter.x_bounds[0];
        const y_range = painter.y_bounds[1] - painter.y_bounds[0];

        if (x_range == 0 or y_range == 0) return;

        // Scale radius based on screen dimensions vs virtual dimensions
        const x_scale = @as(f64, @floatFromInt(painter.area.width)) / x_range;
        const y_scale = @as(f64, @floatFromInt(painter.area.height)) / y_range;
        const avg_scale = (x_scale + y_scale) / 2.0;

        const screen_radius = self.radius * avg_scale;
        if (screen_radius < 0.5) {
            // Very small circle - just draw center point
            painter.setPixel(center.x, center.y, self.color);
            return;
        }

        const r: i32 = @intFromFloat(@round(screen_radius));
        if (r == 0) {
            painter.setPixel(center.x, center.y, self.color);
            return;
        }

        bresenhamCircle(painter, center.x, center.y, r, self.color);
    }
};

/// Draw a circle using Bresenham's circle algorithm.
/// Efficiently draws all 8 symmetric octants simultaneously.
fn bresenhamCircle(painter: *Painter, cx: i32, cy: i32, r: i32, color: Color) void {
    var x: i32 = 0;
    var y: i32 = r;
    var d: i32 = 3 - 2 * r;

    while (x <= y) {
        // Draw 8 symmetric points
        painter.setPixel(cx + x, cy + y, color);
        painter.setPixel(cx - x, cy + y, color);
        painter.setPixel(cx + x, cy - y, color);
        painter.setPixel(cx - x, cy - y, color);
        painter.setPixel(cx + y, cy + x, color);
        painter.setPixel(cx - y, cy + x, color);
        painter.setPixel(cx + y, cy - x, color);
        painter.setPixel(cx - y, cy - x, color);

        if (d < 0) {
            d = d + 4 * x + 6;
        } else {
            d = d + 4 * (x - y) + 10;
            y -= 1;
        }
        x += 1;
    }
}

// ============================================================
// Line Shape - Bresenham's line algorithm
// ============================================================

/// Line shape for drawing lines between two points on a Canvas.
pub const Line = struct {
    /// Start X coordinate in virtual space.
    x1: f64,
    /// Start Y coordinate in virtual space.
    y1: f64,
    /// End X coordinate in virtual space.
    x2: f64,
    /// End Y coordinate in virtual space.
    y2: f64,
    /// Color of the line.
    color: Color = .white,

    /// Create a Shape interface for this Line.
    pub fn shape(self: *const Line) Shape {
        return Shape.init(self, draw);
    }

    /// Draw the line using Bresenham's algorithm with Cohen-Sutherland clipping.
    fn draw(self: *const Line, painter: *Painter) void {
        // Transform endpoints to screen coordinates (allows out-of-bounds for clipping)
        const p1 = painter.virtualToScreen(self.x1, self.y1) orelse return;
        const p2 = painter.virtualToScreen(self.x2, self.y2) orelse return;

        // Get screen bounds for clipping
        const x_min: i32 = @intCast(painter.area.x);
        const y_min: i32 = @intCast(painter.area.y);
        const x_max: i32 = @as(i32, @intCast(painter.area.x)) + @as(i32, @intCast(painter.area.width)) - 1;
        const y_max: i32 = @as(i32, @intCast(painter.area.y)) + @as(i32, @intCast(painter.area.height)) - 1;

        var x0: i32 = p1.x;
        var y0: i32 = p1.y;
        var x1: i32 = p2.x;
        var y1: i32 = p2.y;

        // Cohen-Sutherland line clipping
        if (clipLine(&x0, &y0, &x1, &y1, x_min, y_min, x_max, y_max)) {
            bresenhamLine(painter, x0, y0, x1, y1, self.color);
        }
    }
};

// Cohen-Sutherland outcode constants
const INSIDE: u4 = 0;
const LEFT: u4 = 1;
const RIGHT: u4 = 2;
const BOTTOM: u4 = 4;
const TOP: u4 = 8;

/// Compute the Cohen-Sutherland outcode for a point.
fn computeOutCode(x: i32, y: i32, x_min: i32, y_min: i32, x_max: i32, y_max: i32) u4 {
    var code: u4 = INSIDE;

    if (x < x_min) {
        code |= LEFT;
    } else if (x > x_max) {
        code |= RIGHT;
    }

    if (y < y_min) {
        code |= TOP;
    } else if (y > y_max) {
        code |= BOTTOM;
    }

    return code;
}

/// Cohen-Sutherland line clipping algorithm.
/// Modifies the endpoints to be within bounds if possible.
/// Returns true if any part of the line is visible.
fn clipLine(x0: *i32, y0: *i32, x1: *i32, y1: *i32, x_min: i32, y_min: i32, x_max: i32, y_max: i32) bool {
    var outcode0 = computeOutCode(x0.*, y0.*, x_min, y_min, x_max, y_max);
    var outcode1 = computeOutCode(x1.*, y1.*, x_min, y_min, x_max, y_max);

    while (true) {
        if ((outcode0 | outcode1) == 0) {
            // Both endpoints inside window - trivial accept
            return true;
        } else if ((outcode0 & outcode1) != 0) {
            // Both endpoints share an outside region - trivial reject
            return false;
        } else {
            // Failed both tests, so calculate the line segment to clip
            const outcode_out = if (outcode1 > outcode0) outcode1 else outcode0;

            var x: i32 = undefined;
            var y: i32 = undefined;

            // Calculate intersection point
            const dx = x1.* - x0.*;
            const dy = y1.* - y0.*;

            if ((outcode_out & TOP) != 0) {
                x = x0.* + @divTrunc(dx * (y_min - y0.*), dy);
                y = y_min;
            } else if ((outcode_out & BOTTOM) != 0) {
                x = x0.* + @divTrunc(dx * (y_max - y0.*), dy);
                y = y_max;
            } else if ((outcode_out & RIGHT) != 0) {
                y = y0.* + @divTrunc(dy * (x_max - x0.*), dx);
                x = x_max;
            } else if ((outcode_out & LEFT) != 0) {
                y = y0.* + @divTrunc(dy * (x_min - x0.*), dx);
                x = x_min;
            }

            // Replace point outside window with intersection point
            if (outcode_out == outcode0) {
                x0.* = x;
                y0.* = y;
                outcode0 = computeOutCode(x0.*, y0.*, x_min, y_min, x_max, y_max);
            } else {
                x1.* = x;
                y1.* = y;
                outcode1 = computeOutCode(x1.*, y1.*, x_min, y_min, x_max, y_max);
            }
        }
    }
}

/// Draw a line using Bresenham's line algorithm.
fn bresenhamLine(painter: *Painter, x0: i32, y0: i32, x1: i32, y1: i32, color: Color) void {
    var x = x0;
    var y = y0;
    const dx = @abs(x1 - x0);
    const dy = @abs(y1 - y0);
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err: i32 = @as(i32, @intCast(dx)) - @as(i32, @intCast(dy));

    while (true) {
        painter.setPixel(x, y, color);
        if (x == x1 and y == y1) break;

        const e2 = 2 * err;
        if (e2 > -@as(i32, @intCast(dy))) {
            err -= @as(i32, @intCast(dy));
            x += sx;
        }
        if (e2 < @as(i32, @intCast(dx))) {
            err += @as(i32, @intCast(dx));
            y += sy;
        }
    }
}

// ============================================================
// SANITY TESTS - Basic shape functionality
// ============================================================

test "sanity: Circle with default color" {
    const circle = Circle{
        .x = 50,
        .y = 50,
        .radius = 10,
    };
    try std.testing.expectEqual(@as(f64, 50), circle.x);
    try std.testing.expectEqual(@as(f64, 50), circle.y);
    try std.testing.expectEqual(@as(f64, 10), circle.radius);
    try std.testing.expect(circle.color.eql(.white));
}

test "sanity: Line with default color" {
    const line = Line{
        .x1 = 0,
        .y1 = 0,
        .x2 = 100,
        .y2 = 100,
    };
    try std.testing.expectEqual(@as(f64, 0), line.x1);
    try std.testing.expectEqual(@as(f64, 0), line.y1);
    try std.testing.expectEqual(@as(f64, 100), line.x2);
    try std.testing.expectEqual(@as(f64, 100), line.y2);
    try std.testing.expect(line.color.eql(.white));
}

test "sanity: Circle.shape returns Shape interface" {
    const circle = Circle{
        .x = 25,
        .y = 25,
        .radius = 5,
        .color = .red,
    };
    const s = circle.shape();
    // Shape should have valid function pointer and point to the circle
    try std.testing.expect(s.ptr == @as(*const anyopaque, &circle));
}

test "sanity: Line.shape returns Shape interface" {
    const line = Line{
        .x1 = 10,
        .y1 = 20,
        .x2 = 30,
        .y2 = 40,
        .color = .blue,
    };
    const s = line.shape();
    // Shape should have valid function pointer and point to the line
    try std.testing.expect(s.ptr == @as(*const anyopaque, &line));
}

// ============================================================
// BEHAVIOR TESTS - Painter coordinate transformation
// ============================================================

test "behavior: Painter.virtualToScreen transforms origin" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    // Origin (0, 0) should map to bottom-left of screen area
    const screen = painter.virtualToScreen(0, 0).?;
    try std.testing.expectEqual(@as(i32, 0), screen.x);
    try std.testing.expectEqual(@as(i32, 19), screen.y);
}

test "behavior: Painter.virtualToScreen transforms max corner" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    // Max corner (100, 100) should map to top-right of screen area
    const screen = painter.virtualToScreen(100, 100).?;
    try std.testing.expectEqual(@as(i32, 39), screen.x);
    try std.testing.expectEqual(@as(i32, 0), screen.y);
}

test "behavior: Painter.virtualToScreen with offset area" {
    var buf = try Buffer.init(std.testing.allocator, 60, 30);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(10, 5, 40, 20),
        .default,
    );

    // Origin should map to area's bottom-left
    const screen = painter.virtualToScreen(0, 0).?;
    try std.testing.expectEqual(@as(i32, 10), screen.x);
    try std.testing.expectEqual(@as(i32, 24), screen.y);
}

test "behavior: Painter.setPixel clips to bounds" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(5, 3, 10, 5),
        .default,
    );

    // Outside bounds - should not crash or set anything
    painter.setPixel(-1, -1, .red);
    painter.setPixel(100, 100, .red);
    painter.setPixel(4, 4, .red); // Just outside area left
    painter.setPixel(15, 4, .red); // Just outside area right

    // Inside bounds - should set
    painter.setPixel(5, 3, .green);
    painter.setPixel(14, 7, .blue);

    // Check that in-bounds pixels were set
    const cell1 = buf.get(5, 3);
    try std.testing.expect(cell1.char == 0x2022);

    const cell2 = buf.get(14, 7);
    try std.testing.expect(cell2.char == 0x2022);

    // Check that out-of-bounds pixels were not set
    try std.testing.expect(buf.get(4, 4).isDefault());
}

// ============================================================
// BEHAVIOR TESTS - Circle rendering
// ============================================================

test "behavior: Circle renders at center" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    const circle = Circle{
        .x = 50,
        .y = 50,
        .radius = 10,
        .color = .red,
    };

    circle.draw(&painter);

    // Check that some pixels were drawn (circle should have points)
    var found_pixel = false;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            found_pixel = true;
            break;
        }
    }
    try std.testing.expect(found_pixel);
}

test "behavior: Circle with very small radius draws single point" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    const circle = Circle{
        .x = 50,
        .y = 50,
        .radius = 0.1,
        .color = .yellow,
    };

    circle.draw(&painter);

    // Should draw at least the center point
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expect(pixel_count >= 1);
}

test "behavior: Circle partially outside bounds clips correctly" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 20, 10),
        .default,
    );

    // Circle centered at corner with large radius
    const circle = Circle{
        .x = 0,
        .y = 0,
        .radius = 50,
        .color = .cyan,
    };

    circle.draw(&painter);

    // Should draw some pixels (arc portion in visible area)
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expect(pixel_count > 0);
}

// ============================================================
// BEHAVIOR TESTS - Line rendering
// ============================================================

test "behavior: Line renders horizontal" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    const line = Line{
        .x1 = 10,
        .y1 = 50,
        .x2 = 90,
        .y2 = 50,
        .color = .green,
    };

    line.draw(&painter);

    // Check that pixels were drawn
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expect(pixel_count > 1);
}

test "behavior: Line renders vertical" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    const line = Line{
        .x1 = 50,
        .y1 = 10,
        .x2 = 50,
        .y2 = 90,
        .color = .magenta,
    };

    line.draw(&painter);

    // Check that pixels were drawn
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expect(pixel_count > 1);
}

test "behavior: Line renders diagonal" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    const line = Line{
        .x1 = 0,
        .y1 = 0,
        .x2 = 100,
        .y2 = 100,
        .color = .white,
    };

    line.draw(&painter);

    // Check that pixels were drawn
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expect(pixel_count > 1);
}

test "behavior: Line clips at bounds" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(5, 2, 10, 6),
        .default,
    );

    // Line extending beyond visible area
    const line = Line{
        .x1 = -50,
        .y1 = 50,
        .x2 = 150,
        .y2 = 50,
        .color = .red,
    };

    line.draw(&painter);

    // Should draw pixels only within the clip area
    var pixel_count: usize = 0;
    var all_in_bounds = true;
    for (0..buf.height) |y| {
        for (0..buf.width) |x| {
            const cell = buf.get(@intCast(x), @intCast(y));
            if (cell.char == 0x2022) {
                pixel_count += 1;
                // Check that pixel is within clip area
                if (x < 5 or x >= 15 or y < 2 or y >= 8) {
                    all_in_bounds = false;
                }
            }
        }
    }
    try std.testing.expect(pixel_count > 0);
    try std.testing.expect(all_in_bounds);
}

test "behavior: Line completely outside bounds draws nothing" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 20, 10),
        .default,
    );

    // Line completely outside visible area (above the canvas)
    const line = Line{
        .x1 = 0,
        .y1 = 150,
        .x2 = 100,
        .y2 = 200,
        .color = .blue,
    };

    line.draw(&painter);

    // No pixels should be drawn
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), pixel_count);
}

// ============================================================
// BEHAVIOR TESTS - Shape interface with heterogeneous shapes
// ============================================================

test "behavior: Shape interface allows heterogeneous drawing" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    const circle = Circle{
        .x = 25,
        .y = 50,
        .radius = 10,
        .color = .red,
    };

    const line = Line{
        .x1 = 50,
        .y1 = 0,
        .x2 = 50,
        .y2 = 100,
        .color = .blue,
    };

    // Create shape interfaces
    const shapes = [_]Shape{
        circle.shape(),
        line.shape(),
    };

    // Draw all shapes through interface
    for (&shapes) |s| {
        s.draw(&painter);
    }

    // Both shapes should have drawn pixels
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expect(pixel_count > 2);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Circle with zero radius draws single point" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    const circle = Circle{
        .x = 50,
        .y = 50,
        .radius = 0,
        .color = .white,
    };

    circle.draw(&painter);

    // Should draw center point at minimum
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expect(pixel_count >= 1);
}

test "regression: Line with same start and end draws single point" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    const line = Line{
        .x1 = 50,
        .y1 = 50,
        .x2 = 50,
        .y2 = 50,
        .color = .white,
    };

    line.draw(&painter);

    // Should draw exactly one point
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), pixel_count);
}

test "regression: Painter handles zero-range bounds" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 50, 50 }, // Zero range
        .{ 50, 50 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    // Should return null for any coordinate
    const result = painter.virtualToScreen(50, 50);
    try std.testing.expect(result == null);
}

test "regression: Circle outside canvas bounds" {
    var buf = try Buffer.init(std.testing.allocator, 40, 20);
    defer buf.deinit();

    var painter = Painter.init(
        .{ 0, 100 },
        .{ 0, 100 },
        &buf,
        Rect.init(0, 0, 40, 20),
        .default,
    );

    const circle = Circle{
        .x = 200,
        .y = 200,
        .radius = 10,
        .color = .red,
    };

    // Should not crash
    circle.draw(&painter);

    // No pixels in visible area
    var pixel_count: usize = 0;
    for (buf.cells) |cell| {
        if (cell.char == 0x2022) {
            pixel_count += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), pixel_count);
}
