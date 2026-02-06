const std = @import("std");
const rich_zig = @import("rich_zig");

const buffer_mod = @import("buffer.zig");
const geometry = @import("geometry.zig");
const style_mod = @import("style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Segment = style_mod.Segment;

pub const PrettyTheme = rich_zig.PrettyTheme;
pub const PrettyOptions = rich_zig.PrettyOptions;
pub const Pretty = rich_zig.Pretty;
pub const pretty = rich_zig.pretty.pretty;
pub const prettyWithOptions = rich_zig.pretty.prettyWithOptions;

/// Render a slice of Segments into a zithril Buffer at the given area.
/// Iterates segments left-to-right, wrapping to the next line when the
/// area's right edge is reached. Newline characters in segment text
/// advance to the next line.
pub fn formatToBuffer(buf: *Buffer, area: Rect, segments: []const Segment, base_style: Style) void {
    if (area.isEmpty()) return;

    var cx: u16 = area.x;
    var cy: u16 = area.y;

    for (segments) |seg| {
        if (cy >= area.bottom()) break;

        // Determine the style: segment style patched over base, or base alone
        const seg_style = if (seg.style) |rs|
            base_style.patch(Style.fromRichStyle(rs))
        else
            base_style;

        for (seg.text) |byte| {
            if (cy >= area.bottom()) break;

            if (byte == '\n') {
                cy += 1;
                cx = area.x;
                continue;
            }

            if (cx >= area.right()) {
                cy += 1;
                cx = area.x;
                if (cy >= area.bottom()) break;
            }

            buf.setString(cx, cy, &.{byte}, seg_style);
            cx += 1;
        }
    }
}

/// Free segments allocated by Pretty.format / pretty() / prettyWithOptions().
/// Frees both the segment text slices and the segment slice itself.
pub fn freeSegments(allocator: std.mem.Allocator, segments: []Segment) void {
    for (segments) |seg| {
        allocator.free(seg.text);
    }
    allocator.free(segments);
}

// ============================================================
// SANITY TESTS
// ============================================================

test "sanity: PrettyTheme.default exists and has styled fields" {
    const theme = PrettyTheme.default;
    try std.testing.expect(theme.number.hasAttribute(.bold));
    try std.testing.expect(theme.boolean.hasAttribute(.italic));
}

test "sanity: PrettyTheme.minimal exists with empty styles" {
    const theme = PrettyTheme.minimal;
    try std.testing.expect(!theme.number.hasAttribute(.bold));
    try std.testing.expect(!theme.boolean.hasAttribute(.italic));
}

test "sanity: PrettyOptions defaults" {
    const opts = PrettyOptions{};
    try std.testing.expectEqual(@as(usize, 2), opts.indent);
    try std.testing.expectEqual(@as(usize, 6), opts.max_depth);
    try std.testing.expectEqual(@as(usize, 80), opts.max_string_length);
    try std.testing.expectEqual(@as(usize, 30), opts.max_items);
    try std.testing.expectEqual(@as(usize, 60), opts.single_line_max);
}

// ============================================================
// BEHAVIOR TESTS
// ============================================================

test "behavior: Pretty.format with integer" {
    const allocator = std.testing.allocator;
    var p = Pretty.init(allocator);
    const segments = try p.format(@as(i32, 42));
    defer freeSegments(allocator, segments);

    try std.testing.expectEqual(@as(usize, 1), segments.len);
    try std.testing.expectEqualStrings("42", segments[0].text);
}

test "behavior: Pretty.format with bool" {
    const allocator = std.testing.allocator;
    var p = Pretty.init(allocator);
    const segments = try p.format(true);
    defer freeSegments(allocator, segments);

    try std.testing.expectEqual(@as(usize, 1), segments.len);
    try std.testing.expectEqualStrings("true", segments[0].text);
}

test "behavior: pretty convenience function" {
    const allocator = std.testing.allocator;
    const segments = try pretty(allocator, @as(i32, 99));
    defer freeSegments(allocator, segments);

    try std.testing.expectEqual(@as(usize, 1), segments.len);
    try std.testing.expectEqualStrings("99", segments[0].text);
}

test "behavior: prettyWithOptions with minimal theme" {
    const allocator = std.testing.allocator;
    const segments = try prettyWithOptions(allocator, @as(i32, 7), .{
        .theme = PrettyTheme.minimal,
    });
    defer freeSegments(allocator, segments);

    try std.testing.expectEqual(@as(usize, 1), segments.len);
    try std.testing.expectEqualStrings("7", segments[0].text);
    // With minimal theme, segment should have no style
    try std.testing.expect(segments[0].style == null or
        (segments[0].style != null and segments[0].style.?.isEmpty()));
}

// ============================================================
// INTEGRATION TESTS - formatToBuffer
// ============================================================

test "integration: formatToBuffer renders segments into buffer" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const segments = try pretty(allocator, @as(i32, 42));
    defer freeSegments(allocator, segments);

    const area = Rect.init(0, 0, 20, 5);
    formatToBuffer(&buf, area, segments, Style.empty);

    try std.testing.expectEqual(@as(u21, '4'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(1, 0).char);
}

test "integration: formatToBuffer respects area bounds" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const segments = try pretty(allocator, @as(i32, 42));
    defer freeSegments(allocator, segments);

    // Render at offset (5, 2)
    const area = Rect.init(5, 2, 10, 2);
    formatToBuffer(&buf, area, segments, Style.empty);

    // Should be at (5,2), not (0,0)
    try std.testing.expect(buf.get(0, 0).char == ' ');
    try std.testing.expectEqual(@as(u21, '4'), buf.get(5, 2).char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(6, 2).char);
}

test "integration: formatToBuffer with empty area does nothing" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const segments = try pretty(allocator, @as(i32, 42));
    defer freeSegments(allocator, segments);

    const area = Rect.init(0, 0, 0, 0);
    formatToBuffer(&buf, area, segments, Style.empty);

    // Buffer should be unchanged
    try std.testing.expect(buf.get(0, 0).char == ' ');
}

test "integration: formatToBuffer applies base style" {
    const allocator = std.testing.allocator;

    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    // Use minimal theme so segments have no style of their own
    const segments = try prettyWithOptions(allocator, @as(i32, 42), .{
        .theme = PrettyTheme.minimal,
    });
    defer freeSegments(allocator, segments);

    const area = Rect.init(0, 0, 20, 5);
    formatToBuffer(&buf, area, segments, Style.init().bold());

    // Cell should have the bold attribute from base_style
    try std.testing.expect(buf.get(0, 0).style.hasAttribute(.bold));
}
