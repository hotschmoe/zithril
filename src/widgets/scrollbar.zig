// Scrollbar widget for zithril TUI framework
// Scroll position indicator with configurable orientation and style

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;

/// Scrollbar orientation.
pub const Orientation = enum {
    vertical,
    horizontal,
};

/// Scroll position indicator widget.
///
/// Displays a scrollbar track with a thumb indicating the current scroll position.
/// The thumb size is proportional to the viewport size relative to total content.
/// Supports both vertical and horizontal orientations.
pub const Scrollbar = struct {
    /// Total number of items/lines in the scrollable content.
    total: usize = 0,

    /// Current scroll position (index of first visible item).
    position: usize = 0,

    /// Number of items visible in the viewport.
    viewport: u16 = 0,

    /// Style applied to the scrollbar track.
    style: Style = Style.empty,

    /// Style applied to the scrollbar thumb.
    thumb_style: Style = Style.init().reverse(),

    /// Orientation of the scrollbar.
    orientation: Orientation = .vertical,

    /// Characters used for rendering.
    /// Track character fills the scrollbar background.
    track_char: u21 = ' ',

    /// Thumb character fills the scrollbar thumb.
    thumb_char: u21 = ' ',

    /// Render the scrollbar into the buffer at the given area.
    pub fn render(self: Scrollbar, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;

        const track_length = switch (self.orientation) {
            .vertical => area.height,
            .horizontal => area.width,
        };

        if (track_length == 0) return;

        // Draw the track first
        self.drawTrack(area, buf);

        // Calculate and draw the thumb
        if (self.total > 0 and self.viewport > 0) {
            const thumb_info = self.calculateThumb(track_length);
            self.drawThumb(area, thumb_info.start, thumb_info.length, buf);
        }
    }

    /// Draw the scrollbar track.
    fn drawTrack(self: Scrollbar, area: Rect, buf: *Buffer) void {
        const track_cell = Cell.styled(self.track_char, self.style);

        switch (self.orientation) {
            .vertical => {
                var y = area.y;
                while (y < area.bottom()) : (y += 1) {
                    buf.set(area.x, y, track_cell);
                }
            },
            .horizontal => {
                var x = area.x;
                while (x < area.right()) : (x += 1) {
                    buf.set(x, area.y, track_cell);
                }
            },
        }
    }

    /// Draw the scrollbar thumb at the calculated position.
    fn drawThumb(self: Scrollbar, area: Rect, start: u16, length: u16, buf: *Buffer) void {
        if (length == 0) return;

        const thumb_cell = Cell.styled(self.thumb_char, self.thumb_style);

        switch (self.orientation) {
            .vertical => {
                const thumb_y = area.y +| start;
                var y = thumb_y;
                while (y < thumb_y +| length and y < area.bottom()) : (y += 1) {
                    buf.set(area.x, y, thumb_cell);
                }
            },
            .horizontal => {
                const thumb_x = area.x +| start;
                var x = thumb_x;
                while (x < thumb_x +| length and x < area.right()) : (x += 1) {
                    buf.set(x, area.y, thumb_cell);
                }
            },
        }
    }

    /// Calculate thumb position and size.
    fn calculateThumb(self: Scrollbar, track_length: u16) struct { start: u16, length: u16 } {
        if (self.total == 0 or self.viewport == 0 or track_length == 0) {
            return .{ .start = 0, .length = 0 };
        }

        const total_f: f64 = @floatFromInt(self.total);
        const viewport_f: f64 = @floatFromInt(self.viewport);
        const track_f: f64 = @floatFromInt(track_length);
        const position_f: f64 = @floatFromInt(self.position);

        // Thumb length proportional to viewport/total ratio
        const thumb_ratio = @min(viewport_f / total_f, 1.0);
        var thumb_length: u16 = @intFromFloat(@max(thumb_ratio * track_f, 1.0));
        thumb_length = @min(thumb_length, track_length);

        // Thumb position based on scroll position
        const scrollable_items = if (self.total > self.viewport)
            self.total - self.viewport
        else
            0;

        var thumb_start: u16 = 0;
        if (scrollable_items > 0) {
            const scrollable_f: f64 = @floatFromInt(scrollable_items);
            const scrollable_track = track_length -| thumb_length;
            const scrollable_track_f: f64 = @floatFromInt(scrollable_track);

            const position_ratio = @min(position_f / scrollable_f, 1.0);
            thumb_start = @intFromFloat(position_ratio * scrollable_track_f);
        }

        return .{ .start = thumb_start, .length = thumb_length };
    }

    /// Create a scrollbar for a list with the given state.
    pub fn forList(items_count: usize, selected: usize, visible_rows: u16) Scrollbar {
        return .{
            .total = items_count,
            .position = selected,
            .viewport = visible_rows,
        };
    }
};

// ============================================================
// SANITY TESTS - Basic Scrollbar functionality
// ============================================================

test "sanity: Scrollbar with default values" {
    const scrollbar = Scrollbar{};
    try std.testing.expectEqual(@as(usize, 0), scrollbar.total);
    try std.testing.expectEqual(@as(usize, 0), scrollbar.position);
    try std.testing.expectEqual(@as(u16, 0), scrollbar.viewport);
    try std.testing.expect(scrollbar.orientation == .vertical);
}

test "sanity: Scrollbar with values" {
    const scrollbar = Scrollbar{
        .total = 100,
        .position = 25,
        .viewport = 10,
        .orientation = .horizontal,
    };
    try std.testing.expectEqual(@as(usize, 100), scrollbar.total);
    try std.testing.expectEqual(@as(usize, 25), scrollbar.position);
    try std.testing.expectEqual(@as(u16, 10), scrollbar.viewport);
    try std.testing.expect(scrollbar.orientation == .horizontal);
}

test "sanity: Scrollbar.forList creates correctly" {
    const scrollbar = Scrollbar.forList(50, 10, 20);
    try std.testing.expectEqual(@as(usize, 50), scrollbar.total);
    try std.testing.expectEqual(@as(usize, 10), scrollbar.position);
    try std.testing.expectEqual(@as(u16, 20), scrollbar.viewport);
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Scrollbar renders vertical track" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 100,
        .position = 0,
        .viewport = 10,
        .style = Style.init().bg(.blue),
    };
    scrollbar.render(Rect.init(0, 0, 1, 10), &buf);

    // Track should be drawn along the height
    const cell = buf.get(0, 5);
    try std.testing.expect(cell.style.getBackground() != null);
}

test "behavior: Scrollbar renders horizontal track" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 100,
        .position = 0,
        .viewport = 10,
        .orientation = .horizontal,
        .style = Style.init().bg(.blue),
    };
    scrollbar.render(Rect.init(0, 0, 20, 1), &buf);

    // Track should be drawn along the width
    const cell = buf.get(10, 0);
    try std.testing.expect(cell.style.getBackground() != null);
}

test "behavior: Scrollbar thumb at start when position is 0" {
    var buf = try Buffer.init(std.testing.allocator, 10, 20);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 100,
        .position = 0,
        .viewport = 10,
        .thumb_style = Style.init().reverse(),
    };
    scrollbar.render(Rect.init(0, 0, 1, 20), &buf);

    // Thumb should start at the top
    const top_cell = buf.get(0, 0);
    try std.testing.expect(top_cell.style.hasAttribute(.reverse));
}

test "behavior: Scrollbar thumb at end when position is at max" {
    var buf = try Buffer.init(std.testing.allocator, 10, 20);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 100,
        .position = 90,
        .viewport = 10,
        .thumb_style = Style.init().reverse(),
    };
    scrollbar.render(Rect.init(0, 0, 1, 20), &buf);

    // Thumb should be at the bottom
    const bottom_cell = buf.get(0, 19);
    try std.testing.expect(bottom_cell.style.hasAttribute(.reverse));
}

test "behavior: Scrollbar thumb proportional to viewport" {
    var buf = try Buffer.init(std.testing.allocator, 10, 20);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 20,
        .position = 0,
        .viewport = 10,
        .thumb_style = Style.init().reverse(),
    };
    scrollbar.render(Rect.init(0, 0, 1, 20), &buf);

    // With viewport = 50% of total, thumb should be roughly 10 cells (50% of 20)
    var thumb_count: u16 = 0;
    for (0..20) |y| {
        if (buf.get(0, @intCast(y)).style.hasAttribute(.reverse)) {
            thumb_count += 1;
        }
    }
    try std.testing.expect(thumb_count >= 9 and thumb_count <= 11);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Scrollbar handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const scrollbar = Scrollbar{ .total = 100, .position = 0, .viewport = 10 };
    scrollbar.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Scrollbar handles zero total" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 0,
        .position = 0,
        .viewport = 10,
        .style = Style.init().bg(.blue),
    };
    scrollbar.render(Rect.init(0, 0, 1, 10), &buf);

    // Track should still be drawn but no thumb
    const cell = buf.get(0, 5);
    try std.testing.expect(cell.style.getBackground() != null);
}

test "regression: Scrollbar handles zero viewport" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 100,
        .position = 0,
        .viewport = 0,
        .style = Style.init().bg(.blue),
    };
    scrollbar.render(Rect.init(0, 0, 1, 10), &buf);

    // Track should be drawn but no thumb
    const cell = buf.get(0, 5);
    try std.testing.expect(cell.style.getBackground() != null);
}

test "regression: Scrollbar handles viewport larger than total" {
    var buf = try Buffer.init(std.testing.allocator, 10, 20);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 5,
        .position = 0,
        .viewport = 20,
        .thumb_style = Style.init().reverse(),
    };
    scrollbar.render(Rect.init(0, 0, 1, 20), &buf);

    // Thumb should fill entire track when viewport >= total
    var thumb_count: u16 = 0;
    for (0..20) |y| {
        if (buf.get(0, @intCast(y)).style.hasAttribute(.reverse)) {
            thumb_count += 1;
        }
    }
    try std.testing.expectEqual(@as(u16, 20), thumb_count);
}

test "regression: Scrollbar handles position beyond total" {
    var buf = try Buffer.init(std.testing.allocator, 10, 20);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 100,
        .position = 200,
        .viewport = 10,
        .thumb_style = Style.init().reverse(),
    };
    scrollbar.render(Rect.init(0, 0, 1, 20), &buf);

    // Should clamp and render at end
    const bottom_cell = buf.get(0, 19);
    try std.testing.expect(bottom_cell.style.hasAttribute(.reverse));
}

test "regression: Scrollbar renders at non-zero offset" {
    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    const scrollbar = Scrollbar{
        .total = 100,
        .position = 0,
        .viewport = 10,
        .style = Style.init().bg(.blue),
    };
    scrollbar.render(Rect.init(5, 3, 1, 10), &buf);

    // Track should be at x=5
    const track_cell = buf.get(5, 5);
    try std.testing.expect(track_cell.style.getBackground() != null);

    // Outside should be default
    try std.testing.expect(buf.get(4, 5).isDefault());
    try std.testing.expect(buf.get(5, 2).isDefault());
}

test "regression: Scrollbar calculateThumb minimum length is 1" {
    const scrollbar = Scrollbar{
        .total = 1000,
        .position = 0,
        .viewport = 1,
    };

    const thumb_info = scrollbar.calculateThumb(10);
    try std.testing.expect(thumb_info.length >= 1);
}
