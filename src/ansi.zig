// ANSI escape sequence parsing for zithril TUI framework
// Wraps rich_zig's ANSI parsing with zithril-style conveniences

const std = @import("std");
pub const rich_zig = @import("rich_zig");

/// Styled text parsed from ANSI escape sequences.
/// Wraps rich_zig.Text -- call deinit() when done.
pub const Text = rich_zig.Text;

/// A span of styled text within a Text object.
/// Fields: .start, .end (byte offsets into plain text), .style (rich_zig.Style).
pub const Span = rich_zig.Span;

/// Parse ANSI-escaped text into a styled Text object.
/// Converts SGR escape sequences into Style spans.
/// Caller owns the returned Text and must call .deinit() to free.
pub const fromAnsi = rich_zig.fromAnsi;

/// Strip all ANSI escape sequences from text, returning plain bytes.
/// Caller owns the returned slice and must free with the same allocator.
pub const stripAnsi = rich_zig.stripAnsi;

/// Re-export rich_zig's Segment for use in parseAnsiToSegments results.
pub const Segment = rich_zig.Segment;

/// Strip ANSI escape sequences and return an owned copy of the plain text.
/// Equivalent to stripAnsi -- provided for naming consistency with
/// other zithril APIs that distinguish borrowed vs owned returns.
pub fn stripToOwned(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return stripAnsi(allocator, input);
}

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
/// This frees both the segment array and the underlying plain text buffer
/// that segment text slices point into.
pub fn freeSegments(allocator: std.mem.Allocator, segments: []Segment) void {
    // All segment .text slices point into the same plain buffer.
    // Find the earliest pointer to free the backing allocation.
    if (segments.len > 0) {
        // The first segment's text points to the start (or near start) of the buffer.
        // We need the original allocation start. Since fromAnsi returns a contiguous
        // plain buffer and we walk it left-to-right, the first segment's text pointer
        // is either the start or after a gap. We stored a reference to the full buffer
        // via the first segment -- but actually we need to recover the original pointer.
        // The safest approach: find the minimum pointer.
        var min_ptr: [*]const u8 = segments[0].text.ptr;
        for (segments) |seg| {
            if (@intFromPtr(seg.text.ptr) < @intFromPtr(min_ptr)) {
                min_ptr = seg.text.ptr;
            }
        }
        // Find max end to get full length
        var max_end: usize = 0;
        for (segments) |seg| {
            const end = @intFromPtr(seg.text.ptr) + seg.text.len;
            if (end > max_end) max_end = end;
        }
        const total_len = max_end - @intFromPtr(min_ptr);
        if (total_len > 0) {
            allocator.free(min_ptr[0..total_len]);
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
// BEHAVIOR TESTS - stripToOwned convenience
// ============================================================

test "behavior: stripToOwned removes escape codes" {
    const allocator = std.testing.allocator;
    const result = try stripToOwned(allocator, "\x1b[31;1mRed Bold\x1b[0m");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Red Bold", result);
}

test "behavior: stripToOwned with plain text" {
    const allocator = std.testing.allocator;
    const result = try stripToOwned(allocator, "No escapes here");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("No escapes here", result);
}

// ============================================================
// INTEGRATION TESTS - richer ANSI sequences
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
