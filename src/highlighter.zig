const std = @import("std");
pub const rich_zig = @import("rich_zig");

pub const Highlighter = rich_zig.Highlighter;
pub const HighlightRule = Highlighter.HighlightRule;
pub const Match = Highlighter.Match;
pub const Text = rich_zig.Text;
pub const Span = rich_zig.Span;

/// Create the built-in repr highlighter that recognizes common patterns:
/// integers, floats, booleans/null, strings, URLs, file paths, UUIDs.
pub fn repr() Highlighter {
    return Highlighter.repr();
}

/// Convenience: create a Text from plain string, apply repr() highlighting,
/// and return the highlighted Text. Caller owns the returned Text and must
/// call deinit() when done.
pub fn highlightText(plain: []const u8, allocator: std.mem.Allocator) !Text {
    var text = try Text.fromPlainOwned(allocator, plain);
    errdefer text.deinit();
    const h = Highlighter.repr();
    try h.highlight(&text);
    return text;
}

// ============================================================
// SANITY TESTS
// ============================================================

test "sanity: repr creates valid highlighter with rules" {
    const h = repr();
    try std.testing.expect(h.rules.len > 0);
}

test "sanity: Highlighter.init with empty rules" {
    const h = Highlighter.init(&[_]HighlightRule{});
    try std.testing.expectEqual(@as(usize, 0), h.rules.len);
}

// ============================================================
// BEHAVIOR TESTS
// ============================================================

test "behavior: highlighting text with numbers creates spans" {
    const allocator = std.testing.allocator;
    var text = try highlightText("count is 42 and pi is 3.14", allocator);
    defer text.deinit();

    // repr() should have matched at least integer 42 and float 3.14
    try std.testing.expect(text.spans.len >= 2);
}

test "behavior: highlighting plain text without patterns creates no spans" {
    const allocator = std.testing.allocator;
    var text = try highlightText("hello world", allocator);
    defer text.deinit();

    try std.testing.expectEqual(@as(usize, 0), text.spans.len);
}

test "behavior: highlighting preserves original plain text" {
    const allocator = std.testing.allocator;
    const input = "value is 100";
    var text = try highlightText(input, allocator);
    defer text.deinit();

    try std.testing.expectEqualStrings(input, text.plain);
}

test "behavior: repr highlights booleans" {
    const allocator = std.testing.allocator;
    var text = try highlightText("result is true", allocator);
    defer text.deinit();

    try std.testing.expect(text.spans.len >= 1);
    // The span should cover "true" at position 10..14
    try std.testing.expectEqual(@as(usize, 10), text.spans[text.spans.len - 1].start);
    try std.testing.expectEqual(@as(usize, 14), text.spans[text.spans.len - 1].end);
}

test "behavior: repr highlights strings" {
    const allocator = std.testing.allocator;
    var text = try highlightText("name is \"Alice\"", allocator);
    defer text.deinit();

    try std.testing.expect(text.spans.len >= 1);
}

test "behavior: custom highlighter applies rules" {
    const allocator = std.testing.allocator;
    var text = try Text.fromPlainOwned(allocator, "hello world");
    defer text.deinit();

    const h = Highlighter.init(&[_]HighlightRule{});
    try h.highlight(&text);

    // No rules means no spans added
    try std.testing.expectEqual(@as(usize, 0), text.spans.len);
}
