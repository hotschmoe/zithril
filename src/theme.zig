// Theme system for zithril TUI framework
// Maps named styles for consistent theming across an application

const std = @import("std");
const style_mod = @import("style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;

/// A named style registry for consistent theming.
///
/// Stores a mapping of string names to zithril Styles, allowing
/// applications to define a theme once and reference styles by name
/// throughout the UI.
pub const Theme = struct {
    map: std.StringHashMap(Style),

    /// Create a new empty theme.
    pub fn init(allocator: std.mem.Allocator) Theme {
        return .{ .map = std.StringHashMap(Style).init(allocator) };
    }

    /// Release all resources.
    pub fn deinit(self: *Theme) void {
        self.map.deinit();
    }

    /// Define a named style. Overwrites any existing style with the same name.
    pub fn define(self: *Theme, name: []const u8, style: Style) !void {
        try self.map.put(name, style);
    }

    /// Look up a style by name.
    pub fn get(self: *const Theme, name: []const u8) ?Style {
        return self.map.get(name);
    }

    /// Check whether a named style is defined.
    pub fn contains(self: *const Theme, name: []const u8) bool {
        return self.map.contains(name);
    }

    /// Return the number of defined styles.
    pub fn count(self: *const Theme) usize {
        return self.map.count();
    }

    /// Merge another theme into this one. Styles from `other` overwrite
    /// existing styles with the same name.
    pub fn merge(self: *Theme, other: *const Theme) !void {
        var it = other.map.iterator();
        while (it.next()) |entry| {
            try self.map.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    /// Create a default theme with common semantic styles.
    pub fn defaultTheme(allocator: std.mem.Allocator) !Theme {
        var theme = Theme.init(allocator);
        errdefer theme.deinit();

        try theme.define("info", Style.init().fg(.cyan));
        try theme.define("warning", Style.init().fg(.yellow).bold());
        try theme.define("error", Style.init().fg(.red).bold());
        try theme.define("success", Style.init().fg(.green));
        try theme.define("muted", Style.init().dim());
        try theme.define("accent", Style.init().fg(.blue).bold());
        try theme.define("title", Style.init().bold());

        return theme;
    }
};

// ============================================================
// SANITY TESTS - Basic functionality
// ============================================================

test "sanity: Theme init and deinit" {
    var theme = Theme.init(std.testing.allocator);
    defer theme.deinit();
    try std.testing.expectEqual(@as(usize, 0), theme.count());
}

test "sanity: Theme define and get" {
    var theme = Theme.init(std.testing.allocator);
    defer theme.deinit();

    const bold_red = Style.init().bold().fg(.red);
    try theme.define("alert", bold_red);

    const got = theme.get("alert");
    try std.testing.expect(got != null);
    try std.testing.expect(got.?.eql(bold_red));
}

test "sanity: Theme get returns null for missing" {
    var theme = Theme.init(std.testing.allocator);
    defer theme.deinit();
    try std.testing.expect(theme.get("nonexistent") == null);
}

// ============================================================
// BEHAVIOR TESTS - Contains, count, merge, overwrite
// ============================================================

test "behavior: Theme contains" {
    var theme = Theme.init(std.testing.allocator);
    defer theme.deinit();

    try theme.define("primary", Style.init().fg(.blue));
    try std.testing.expect(theme.contains("primary"));
    try std.testing.expect(!theme.contains("secondary"));
}

test "behavior: Theme count" {
    var theme = Theme.init(std.testing.allocator);
    defer theme.deinit();

    try theme.define("a", Style.init().bold());
    try theme.define("b", Style.init().italic());
    try theme.define("c", Style.init().dim());
    try std.testing.expectEqual(@as(usize, 3), theme.count());
}

test "behavior: Theme define overwrites existing" {
    var theme = Theme.init(std.testing.allocator);
    defer theme.deinit();

    try theme.define("x", Style.init().bold());
    try theme.define("x", Style.init().italic());

    const got = theme.get("x").?;
    try std.testing.expect(!got.hasAttribute(.bold));
    try std.testing.expect(got.hasAttribute(.italic));
    try std.testing.expectEqual(@as(usize, 1), theme.count());
}

test "behavior: Theme merge combines themes" {
    var base = Theme.init(std.testing.allocator);
    defer base.deinit();
    try base.define("primary", Style.init().fg(.blue));
    try base.define("secondary", Style.init().fg(.green));

    var extra = Theme.init(std.testing.allocator);
    defer extra.deinit();
    try extra.define("accent", Style.init().fg(.magenta));

    try base.merge(&extra);
    try std.testing.expectEqual(@as(usize, 3), base.count());
    try std.testing.expect(base.contains("accent"));
}

test "behavior: Theme merge overwrites on conflict" {
    var base = Theme.init(std.testing.allocator);
    defer base.deinit();
    try base.define("x", Style.init().bold());

    var overlay = Theme.init(std.testing.allocator);
    defer overlay.deinit();
    try overlay.define("x", Style.init().italic());

    try base.merge(&overlay);
    const got = base.get("x").?;
    try std.testing.expect(got.hasAttribute(.italic));
    try std.testing.expect(!got.hasAttribute(.bold));
}

test "behavior: defaultTheme has info, warning, error" {
    var theme = try Theme.defaultTheme(std.testing.allocator);
    defer theme.deinit();

    try std.testing.expect(theme.contains("info"));
    try std.testing.expect(theme.contains("warning"));
    try std.testing.expect(theme.contains("error"));

    const info = theme.get("info").?;
    try std.testing.expect(!info.isEmpty());

    const warning = theme.get("warning").?;
    try std.testing.expect(warning.hasAttribute(.bold));

    const err = theme.get("error").?;
    try std.testing.expect(err.hasAttribute(.bold));
}

test "behavior: defaultTheme has additional semantic styles" {
    var theme = try Theme.defaultTheme(std.testing.allocator);
    defer theme.deinit();

    try std.testing.expect(theme.contains("success"));
    try std.testing.expect(theme.contains("muted"));
    try std.testing.expect(theme.contains("accent"));
    try std.testing.expect(theme.contains("title"));
    try std.testing.expectEqual(@as(usize, 7), theme.count());
}
