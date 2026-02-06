const std = @import("std");
pub const rich_zig = @import("rich_zig");

pub const Text = rich_zig.Text;
pub const Span = rich_zig.Span;
pub const fromAnsi = rich_zig.fromAnsi;
pub const stripAnsi = rich_zig.stripAnsi;
pub const Segment = rich_zig.Segment;

/// Parse ANSI-escaped text into an array of styled Segments.
/// Each segment holds a slice of the plain text and its associated style.
/// Useful for rendering ANSI content directly into a Buffer.
///
/// The returned slice and internal text data are owned by the caller.
/// Free with `freeSegments`.
pub fn parseAnsiToSegments(allocator: std.mem.Allocator, input: []const u8) ![]Segment {
    var text = try fromAnsi(allocator, input);
    // We will take ownership of the plain text; prevent text.deinit from freeing it.
    const plain = text.plain;
    const spans = text.spans;

    // Prevent deinit from freeing plain/spans since we manage them below.
    text.owns_plain = false;
    text.owns_spans = false;
    defer text.deinit();
    defer allocator.free(spans);

    var segments: std.ArrayList(Segment) = .empty;
    errdefer {
        segments.deinit(allocator);
        allocator.free(plain);
    }

    if (plain.len == 0) {
        allocator.free(plain);
        return segments.toOwnedSlice(allocator);
    }

    // Sort spans by start position and walk through the plain text,
    // emitting unstyled segments for gaps and styled segments for spans.
    var pos: usize = 0;
    for (spans) |span| {
        if (span.start > pos) {
            try segments.append(allocator, Segment.plain(plain[pos..span.start]));
        }
        const style = if (span.style.isEmpty()) null else span.style;
        try segments.append(allocator, Segment.styledOptional(plain[span.start..span.end], style));
        if (span.end > pos) pos = span.end;
    }

    // Trailing unstyled text
    if (pos < plain.len) {
        try segments.append(allocator, Segment.plain(plain[pos..plain.len]));
    }

    return segments.toOwnedSlice(allocator);
}

/// Free a segment slice returned by parseAnsiToSegments.
/// Frees the underlying plain text buffer and the segment array.
/// Segments are built left-to-right from a contiguous buffer, so the
/// first segment's pointer is the allocation start and the last
/// segment's end is the allocation end.
pub fn freeSegments(allocator: std.mem.Allocator, segments: []Segment) void {
    if (segments.len > 0) {
        const first = segments[0];
        const last = segments[segments.len - 1];
        const buf_start = first.text.ptr;
        const buf_len = (@intFromPtr(last.text.ptr) + last.text.len) - @intFromPtr(buf_start);
        if (buf_len > 0) {
            allocator.free(buf_start[0..buf_len]);
        }
    }
    allocator.free(segments);
}

// ============================================================
// SANITY TESTS - Basic functionality
// ============================================================

test "sanity: stripAnsi removes escape codes" {
    const allocator = std.testing.allocator;
    const result = try stripAnsi(allocator, "\x1b[1mBold\x1b[0m");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Bold", result);
}

test "sanity: stripAnsi passthrough for plain text" {
    const allocator = std.testing.allocator;
    const result = try stripAnsi(allocator, "Hello World");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

test "sanity: fromAnsi parses basic styling" {
    const allocator = std.testing.allocator;
    var text = try fromAnsi(allocator, "\x1b[1mBold\x1b[0m");
    defer text.deinit();

    try std.testing.expectEqualStrings("Bold", text.plain);
    try std.testing.expect(text.spans.len >= 1);
    try std.testing.expect(text.spans[0].style.hasAttribute(.bold));
}

test "sanity: fromAnsi with empty input" {
    const allocator = std.testing.allocator;
    var text = try fromAnsi(allocator, "");
    defer text.deinit();

    try std.testing.expectEqualStrings("", text.plain);
    try std.testing.expectEqual(@as(usize, 0), text.spans.len);
}

// ============================================================
// BEHAVIOR TESTS - richer ANSI sequences
// ============================================================

test "integration: fromAnsi colored text produces spans" {
    const allocator = std.testing.allocator;
    var text = try fromAnsi(allocator, "\x1b[31mRed\x1b[0m");
    defer text.deinit();

    try std.testing.expectEqualStrings("Red", text.plain);
    try std.testing.expect(text.spans.len >= 1);
    try std.testing.expect(text.spans[0].style.color != null);
}

test "integration: fromAnsi multiple styled segments" {
    const allocator = std.testing.allocator;
    var text = try fromAnsi(allocator, "\x1b[1mBold\x1b[0m \x1b[3mItalic\x1b[0m");
    defer text.deinit();

    try std.testing.expectEqualStrings("Bold Italic", text.plain);
    try std.testing.expectEqual(@as(usize, 2), text.spans.len);
    try std.testing.expect(text.spans[0].style.hasAttribute(.bold));
    try std.testing.expect(text.spans[1].style.hasAttribute(.italic));
}

test "integration: stripAnsi handles multiple escape types" {
    const allocator = std.testing.allocator;
    const result = try stripAnsi(allocator, "\x1b[1;31mHello\x1b[0m \x1b[42mWorld\x1b[0m");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

// ============================================================
// parseAnsiToSegments TESTS
// ============================================================

test "behavior: parseAnsiToSegments with styled input" {
    const allocator = std.testing.allocator;
    const segments = try parseAnsiToSegments(allocator, "\x1b[1mBold\x1b[0m");
    defer freeSegments(allocator, segments);

    try std.testing.expect(segments.len >= 1);
    try std.testing.expectEqualStrings("Bold", segments[0].text);
    try std.testing.expect(segments[0].style != null);
    try std.testing.expect(segments[0].style.?.hasAttribute(.bold));
}

test "behavior: parseAnsiToSegments with plain input" {
    const allocator = std.testing.allocator;
    const segments = try parseAnsiToSegments(allocator, "No styles");
    defer freeSegments(allocator, segments);

    try std.testing.expectEqual(@as(usize, 1), segments.len);
    try std.testing.expectEqualStrings("No styles", segments[0].text);
    try std.testing.expect(segments[0].style == null);
}

test "behavior: parseAnsiToSegments with empty input" {
    const allocator = std.testing.allocator;
    const segments = try parseAnsiToSegments(allocator, "");
    defer allocator.free(segments);

    try std.testing.expectEqual(@as(usize, 0), segments.len);
}

test "behavior: parseAnsiToSegments mixed styled and unstyled" {
    const allocator = std.testing.allocator;
    const segments = try parseAnsiToSegments(allocator, "Hello \x1b[1mBold\x1b[0m World");
    defer freeSegments(allocator, segments);

    try std.testing.expect(segments.len >= 2);
    // First segment: unstyled "Hello "
    try std.testing.expectEqualStrings("Hello ", segments[0].text);
    try std.testing.expect(segments[0].style == null);
    // Second segment: bold "Bold"
    try std.testing.expectEqualStrings("Bold", segments[1].text);
    try std.testing.expect(segments[1].style != null);
    try std.testing.expect(segments[1].style.?.hasAttribute(.bold));
    // Third segment: unstyled " World"
    if (segments.len > 2) {
        try std.testing.expectEqualStrings(" World", segments[2].text);
        try std.testing.expect(segments[2].style == null);
    }
}
