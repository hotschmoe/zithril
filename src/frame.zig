// Frame type for zithril TUI framework
// Provides layout and rendering methods during view function

const std = @import("std");
const buffer_mod = @import("buffer.zig");
const geometry = @import("geometry.zig");
const layout_mod = @import("layout.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Rect = geometry.Rect;
pub const Direction = layout_mod.Direction;
pub const Constraint = layout_mod.Constraint;
pub const BoundedRects = layout_mod.BoundedRects;

/// Frame is passed to the view function and provides layout and rendering methods.
/// Generic over max_widgets to allow comptime-sized layout cache.
///
/// The Frame provides:
/// - size(): Returns the full terminal area
/// - layout(): Splits an area according to constraints
/// - render(): Renders a widget into an area
pub fn Frame(comptime max_widgets: usize) type {
    return struct {
        const Self = @This();

        /// Reference to the buffer for rendering.
        buffer: *Buffer,

        /// Full terminal area (size of the buffer).
        size_: Rect,

        /// Comptime-sized cache for layout results.
        /// Each entry stores the result of a layout() call.
        layout_cache: [max_widgets]BoundedRects = [_]BoundedRects{BoundedRects.init()} ** max_widgets,

        /// Number of cached layout results.
        layout_cache_len: usize = 0,

        /// Initialize a Frame with a buffer.
        pub fn init(buffer: *Buffer) Self {
            return .{
                .buffer = buffer,
                .size_ = Rect.init(0, 0, buffer.width, buffer.height),
            };
        }

        /// Returns the full terminal area.
        pub fn size(self: Self) Rect {
            return self.size_;
        }

        /// Split an area according to constraints.
        /// Returns a bounded array of Rects matching the constraint count.
        ///
        /// Constraints describe how space should be allocated:
        /// - length(n): Exactly n cells
        /// - min(n): At least n cells
        /// - max(n): At most n cells
        /// - ratio(a, b): Fraction a/b of available space
        /// - flex(n): Proportional share (like CSS flex-grow)
        pub fn layout(
            self: *Self,
            area: Rect,
            direction: Direction,
            constraints: []const Constraint,
        ) BoundedRects {
            const result = layout_mod.layout(area, direction, constraints);

            if (self.layout_cache_len < max_widgets) {
                self.layout_cache[self.layout_cache_len] = result;
                self.layout_cache_len += 1;
            }

            return result;
        }

        /// Render a widget into an area.
        /// Widget must have: pub fn render(self: T, area: Rect, buf: *Buffer) void
        pub fn render(self: *Self, widget: anytype, area: Rect) void {
            widget.render(area, self.buffer);
        }

        /// Clear the layout cache for reuse.
        pub fn clearCache(self: *Self) void {
            self.layout_cache_len = 0;
        }

        /// Get a cached layout result by index.
        /// Returns null if index is out of bounds.
        pub fn getCachedLayout(self: Self, index: usize) ?BoundedRects {
            if (index < self.layout_cache_len) {
                return self.layout_cache[index];
            }
            return null;
        }
    };
}

// ============================================================
// SANITY TESTS - Basic Frame functionality
// ============================================================

test "sanity: Frame init with buffer" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var frame = Frame(16).init(&buf);

    try std.testing.expectEqual(@as(u16, 80), frame.size().width);
    try std.testing.expectEqual(@as(u16, 24), frame.size().height);
}

test "sanity: Frame.size returns full terminal area" {
    var buf = try Buffer.init(std.testing.allocator, 120, 40);
    defer buf.deinit();

    var frame = Frame(16).init(&buf);
    const area = frame.size();

    try std.testing.expectEqual(@as(u16, 0), area.x);
    try std.testing.expectEqual(@as(u16, 0), area.y);
    try std.testing.expectEqual(@as(u16, 120), area.width);
    try std.testing.expectEqual(@as(u16, 40), area.height);
}

// ============================================================
// BEHAVIOR TESTS - Layout and rendering
// ============================================================

test "behavior: Frame.layout splits area horizontally" {
    var buf = try Buffer.init(std.testing.allocator, 100, 50);
    defer buf.deinit();

    var frame = Frame(16).init(&buf);
    const result = frame.layout(frame.size(), .horizontal, &.{
        Constraint.len(30),
        Constraint.flexible(1),
    });

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqual(@as(u16, 30), result.get(0).width);
    try std.testing.expectEqual(@as(u16, 70), result.get(1).width);
}

test "behavior: Frame.layout splits area vertically" {
    var buf = try Buffer.init(std.testing.allocator, 100, 50);
    defer buf.deinit();

    var frame = Frame(16).init(&buf);
    const result = frame.layout(frame.size(), .vertical, &.{
        Constraint.len(10),
        Constraint.flexible(1),
        Constraint.len(5),
    });

    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqual(@as(u16, 10), result.get(0).height);
    try std.testing.expectEqual(@as(u16, 35), result.get(1).height);
    try std.testing.expectEqual(@as(u16, 5), result.get(2).height);
}

test "behavior: Frame.render calls widget render method" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const TestWidget = struct {
        char: u21,

        pub fn render(self: @This(), area: Rect, buffer: *Buffer) void {
            buffer.set(area.x, area.y, buffer_mod.Cell.init(self.char));
        }
    };

    var frame = Frame(16).init(&buf);
    frame.render(TestWidget{ .char = 'X' }, Rect.init(5, 5, 10, 5));

    try std.testing.expectEqual(@as(u21, 'X'), buf.get(5, 5).char);
}

test "behavior: Frame layout caches results" {
    var buf = try Buffer.init(std.testing.allocator, 100, 50);
    defer buf.deinit();

    var frame = Frame(16).init(&buf);

    _ = frame.layout(frame.size(), .horizontal, &.{Constraint.flexible(1)});
    _ = frame.layout(frame.size(), .vertical, &.{Constraint.len(10)});

    try std.testing.expectEqual(@as(usize, 2), frame.layout_cache_len);

    const cached = frame.getCachedLayout(0);
    try std.testing.expect(cached != null);
    try std.testing.expectEqual(@as(usize, 1), cached.?.len);
}

test "behavior: Frame.clearCache resets cache" {
    var buf = try Buffer.init(std.testing.allocator, 100, 50);
    defer buf.deinit();

    var frame = Frame(16).init(&buf);

    _ = frame.layout(frame.size(), .horizontal, &.{Constraint.flexible(1)});
    try std.testing.expectEqual(@as(usize, 1), frame.layout_cache_len);

    frame.clearCache();
    try std.testing.expectEqual(@as(usize, 0), frame.layout_cache_len);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Frame with zero-size buffer" {
    var buf = try Buffer.init(std.testing.allocator, 0, 0);
    defer buf.deinit();

    var frame = Frame(16).init(&buf);
    const area = frame.size();

    try std.testing.expectEqual(@as(u16, 0), area.width);
    try std.testing.expectEqual(@as(u16, 0), area.height);
}

test "regression: Frame layout cache overflow is handled" {
    var buf = try Buffer.init(std.testing.allocator, 100, 50);
    defer buf.deinit();

    var frame = Frame(2).init(&buf);

    _ = frame.layout(frame.size(), .horizontal, &.{Constraint.flexible(1)});
    _ = frame.layout(frame.size(), .horizontal, &.{Constraint.flexible(1)});
    _ = frame.layout(frame.size(), .horizontal, &.{Constraint.flexible(1)});

    try std.testing.expectEqual(@as(usize, 2), frame.layout_cache_len);
}

test "regression: Frame.getCachedLayout out of bounds returns null" {
    var buf = try Buffer.init(std.testing.allocator, 100, 50);
    defer buf.deinit();

    const frame = Frame(16).init(&buf);

    try std.testing.expect(frame.getCachedLayout(0) == null);
    try std.testing.expect(frame.getCachedLayout(100) == null);
}

test "regression: Frame layout with empty constraints" {
    var buf = try Buffer.init(std.testing.allocator, 100, 50);
    defer buf.deinit();

    var frame = Frame(16).init(&buf);
    const result = frame.layout(frame.size(), .horizontal, &.{});

    try std.testing.expectEqual(@as(usize, 0), result.len);
}
