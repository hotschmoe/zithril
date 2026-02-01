// zithril - Zig TUI framework
// Built on rich_zig for terminal rendering primitives

const std = @import("std");
pub const rich_zig = @import("rich_zig");

// Geometry types
pub const geometry = @import("geometry.zig");
pub const Rect = geometry.Rect;
pub const Position = geometry.Position;

// Style types (wrapper around rich_zig)
pub const style_mod = @import("style.zig");
pub const Style = style_mod.Style;
pub const Color = style_mod.Color;
pub const StyleAttribute = style_mod.StyleAttribute;

// Layout types
pub const layout_mod = @import("layout.zig");
pub const Constraint = layout_mod.Constraint;
pub const Direction = layout_mod.Direction;
pub const layout = layout_mod.layout;
pub const BoundedRects = layout_mod.BoundedRects;

// Event types
pub const event = @import("event.zig");
pub const Event = event.Event;
pub const Key = event.Key;
pub const KeyCode = event.KeyCode;
pub const Modifiers = event.Modifiers;
pub const Mouse = event.Mouse;
pub const MouseKind = event.MouseKind;
pub const Size = event.Size;

// Action types
pub const action = @import("action.zig");
pub const Action = action.Action;
pub const Command = action.Command;

test "style wrapper" {
    const style = Style.init().bold().fg(.red);
    try std.testing.expect(style.hasAttribute(.bold));

    const base = Style.init().fg(.green);
    const merged = base.patch(style);
    try std.testing.expect(merged.hasAttribute(.bold));
}

test "geometry re-export" {
    const rect = Rect.init(0, 0, 80, 24);
    try std.testing.expectEqual(@as(u32, 1920), rect.area());

    const pos = Position.init(10, 20);
    try std.testing.expectEqual(@as(u16, 10), pos.x);
}

test "layout re-export" {
    const c1 = Constraint.len(10);
    const c2 = Constraint.minSize(20);
    const c3 = Constraint.maxSize(30);
    const c4 = Constraint.fractional(1, 3);
    const c5 = Constraint.flexible(2);

    try std.testing.expectEqual(@as(u16, 10), c1.apply(100));
    try std.testing.expectEqual(@as(u16, 20), c2.apply(100));
    try std.testing.expectEqual(@as(u16, 30), c3.apply(100));
    try std.testing.expectEqual(@as(u16, 33), c4.apply(100));
    try std.testing.expectEqual(@as(u16, 100), c5.apply(100));

    try std.testing.expect(Direction.horizontal != Direction.vertical);
}

test "event re-export" {
    const key_event = Event{ .key = .{ .code = .escape, .modifiers = Modifiers.ctrl_only() } };
    try std.testing.expect(key_event == .key);
    try std.testing.expect(key_event.key.code == .escape);
    try std.testing.expect(key_event.key.modifiers.ctrl);

    const mouse_event = Event{ .mouse = Mouse.init(5, 10, .down) };
    try std.testing.expect(mouse_event == .mouse);
    try std.testing.expect(mouse_event.mouse.kind == .down);

    const resize_event = Event{ .resize = Size.init(120, 40) };
    try std.testing.expect(resize_event == .resize);
    try std.testing.expectEqual(@as(u16, 120), resize_event.resize.width);

    const tick_event = Event{ .tick = {} };
    try std.testing.expect(tick_event == .tick);

    const char_key = KeyCode.fromChar('q');
    try std.testing.expect(char_key.isChar());

    const f5_key = KeyCode.fromF(5);
    try std.testing.expect(f5_key != null);
}

test "action re-export" {
    const none_action = Action{ .none = {} };
    try std.testing.expect(none_action.isNone());

    const quit_action = Action{ .quit = {} };
    try std.testing.expect(quit_action.isQuit());

    const cmd_action = Action{ .command = Command.empty() };
    try std.testing.expect(cmd_action.isCommand());

    try std.testing.expect(Action.none_action.isNone());
    try std.testing.expect(Action.quit_action.isQuit());
}
