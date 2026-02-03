// Event types for zithril TUI framework
// Input events from keyboard, mouse, terminal resize, ticks, and command results

const std = @import("std");
const action_mod = @import("action.zig");

pub const CommandResult = action_mod.CommandResult;

/// Event union representing all possible input events.
/// The main event loop polls for these and passes them to the update function.
pub const Event = union(enum) {
    /// Keyboard input event.
    key: Key,

    /// Mouse input event.
    mouse: Mouse,

    /// Terminal resize event.
    resize: Size,

    /// Timer tick event (for animations, polling).
    tick: void,

    /// Result from a previously submitted command.
    /// Delivered when a Command completes execution.
    command_result: CommandResult,
};

/// Keyboard event with key code and modifier state.
pub const Key = struct {
    code: KeyCode,
    modifiers: Modifiers = .{},
};

/// Key codes for keyboard input.
/// Covers standard terminal key sequences.
pub const KeyCode = union(enum) {
    /// Unicode codepoint for printable characters.
    char: u21,

    /// Enter/Return key.
    enter: void,

    /// Tab key.
    tab: void,

    /// Shift+Tab (backtab).
    backtab: void,

    /// Backspace key.
    backspace: void,

    /// Escape key.
    escape: void,

    /// Arrow keys.
    up: void,
    down: void,
    left: void,
    right: void,

    /// Navigation keys.
    home: void,
    end: void,
    page_up: void,
    page_down: void,

    /// Edit keys.
    insert: void,
    delete: void,

    /// Function keys (1-12).
    f: u8,

    /// Create a char KeyCode from a Unicode codepoint.
    pub fn fromChar(c: u21) KeyCode {
        return .{ .char = c };
    }

    /// Create a function key KeyCode (F1-F12).
    /// Returns null if n is not in range 1-12.
    pub fn fromF(n: u8) ?KeyCode {
        if (n >= 1 and n <= 12) {
            return .{ .f = n };
        }
        return null;
    }

    /// Check if this is a printable character.
    pub fn isChar(self: KeyCode) bool {
        return self == .char;
    }

    /// Check if this is an arrow key.
    pub fn isArrow(self: KeyCode) bool {
        return switch (self) {
            .up, .down, .left, .right => true,
            else => false,
        };
    }

    /// Check if this is a navigation key (arrows, home, end, page up/down).
    pub fn isNavigation(self: KeyCode) bool {
        return switch (self) {
            .up, .down, .left, .right, .home, .end, .page_up, .page_down => true,
            else => false,
        };
    }
};

/// Modifier key state (ctrl, alt, shift).
pub const Modifiers = packed struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
    _padding: u5 = 0,

    /// No modifiers pressed.
    pub const none: Modifiers = .{};

    /// Create modifiers with only ctrl.
    pub fn ctrl_only() Modifiers {
        return .{ .ctrl = true };
    }

    /// Create modifiers with only alt.
    pub fn alt_only() Modifiers {
        return .{ .alt = true };
    }

    /// Create modifiers with only shift.
    pub fn shift_only() Modifiers {
        return .{ .shift = true };
    }

    /// Check if any modifier is pressed.
    pub fn any(self: Modifiers) bool {
        return self.ctrl or self.alt or self.shift;
    }

    /// Check if no modifiers are pressed.
    pub fn none_pressed(self: Modifiers) bool {
        return !self.any();
    }
};

/// Mouse event with position, kind, and modifiers.
pub const Mouse = struct {
    x: u16,
    y: u16,
    kind: MouseKind,
    modifiers: Modifiers = .{},

    pub fn init(x: u16, y: u16, kind: MouseKind) Mouse {
        return .{ .x = x, .y = y, .kind = kind };
    }
};

/// Mouse event kind.
pub const MouseKind = enum {
    down,
    up,
    drag,
    move,
    scroll_up,
    scroll_down,

    /// Check if this is a click event (down or up).
    pub fn isClick(self: MouseKind) bool {
        return self == .down or self == .up;
    }

    /// Check if this is a scroll event.
    pub fn isScroll(self: MouseKind) bool {
        return self == .scroll_up or self == .scroll_down;
    }
};

/// Terminal size (from resize events).
pub const Size = struct {
    width: u16,
    height: u16,

    pub fn init(width: u16, height: u16) Size {
        return .{ .width = width, .height = height };
    }

    pub fn area(self: Size) u32 {
        return @as(u32, self.width) * self.height;
    }
};

// ============================================================
// SANITY TESTS - Basic type construction
// ============================================================

test "sanity: Event.key construction" {
    const event = Event{ .key = .{ .code = .escape } };
    try std.testing.expect(event == .key);
    try std.testing.expect(event.key.code == .escape);
}

test "sanity: Event.mouse construction" {
    const event = Event{ .mouse = Mouse.init(10, 20, .down) };
    try std.testing.expect(event == .mouse);
    try std.testing.expectEqual(@as(u16, 10), event.mouse.x);
    try std.testing.expectEqual(@as(u16, 20), event.mouse.y);
}

test "sanity: Event.resize construction" {
    const event = Event{ .resize = Size.init(80, 24) };
    try std.testing.expect(event == .resize);
    try std.testing.expectEqual(@as(u16, 80), event.resize.width);
    try std.testing.expectEqual(@as(u16, 24), event.resize.height);
}

test "sanity: Event.tick construction" {
    const event = Event{ .tick = {} };
    try std.testing.expect(event == .tick);
}

test "sanity: Event.command_result construction" {
    const result = CommandResult.success(42, null);
    const event = Event{ .command_result = result };
    try std.testing.expect(event == .command_result);
    try std.testing.expectEqual(@as(u32, 42), event.command_result.id);
    try std.testing.expect(event.command_result.isSuccess());
}

test "sanity: KeyCode char creation" {
    const kc = KeyCode.fromChar('a');
    try std.testing.expect(kc == .char);
    try std.testing.expectEqual(@as(u21, 'a'), kc.char);
}

test "sanity: KeyCode function key creation" {
    const f1 = KeyCode.fromF(1);
    try std.testing.expect(f1 != null);
    try std.testing.expect(f1.? == .f);
    try std.testing.expectEqual(@as(u8, 1), f1.?.f);

    const f12 = KeyCode.fromF(12);
    try std.testing.expect(f12 != null);
    try std.testing.expectEqual(@as(u8, 12), f12.?.f);

    const invalid = KeyCode.fromF(0);
    try std.testing.expect(invalid == null);

    const out_of_range = KeyCode.fromF(13);
    try std.testing.expect(out_of_range == null);
}

test "sanity: Modifiers default to none" {
    const mods = Modifiers{};
    try std.testing.expect(!mods.ctrl);
    try std.testing.expect(!mods.alt);
    try std.testing.expect(!mods.shift);
    try std.testing.expect(mods.none_pressed());
}

test "sanity: Modifiers constructors" {
    const ctrl_mod = Modifiers.ctrl_only();
    try std.testing.expect(ctrl_mod.ctrl);
    try std.testing.expect(!ctrl_mod.alt);
    try std.testing.expect(!ctrl_mod.shift);

    const alt_mod = Modifiers.alt_only();
    try std.testing.expect(!alt_mod.ctrl);
    try std.testing.expect(alt_mod.alt);

    const shift_mod = Modifiers.shift_only();
    try std.testing.expect(shift_mod.shift);
}

// ============================================================
// BEHAVIOR TESTS - Key classification
// ============================================================

test "behavior: KeyCode.isChar" {
    try std.testing.expect(KeyCode.fromChar('x').isChar());
    try std.testing.expect(!(KeyCode{ .enter = {} }).isChar());
    try std.testing.expect(!(KeyCode{ .up = {} }).isChar());
}

test "behavior: KeyCode.isArrow" {
    try std.testing.expect((KeyCode{ .up = {} }).isArrow());
    try std.testing.expect((KeyCode{ .down = {} }).isArrow());
    try std.testing.expect((KeyCode{ .left = {} }).isArrow());
    try std.testing.expect((KeyCode{ .right = {} }).isArrow());

    try std.testing.expect(!(KeyCode{ .home = {} }).isArrow());
    try std.testing.expect(!(KeyCode{ .enter = {} }).isArrow());
    try std.testing.expect(!KeyCode.fromChar('a').isArrow());
}

test "behavior: KeyCode.isNavigation" {
    try std.testing.expect((KeyCode{ .up = {} }).isNavigation());
    try std.testing.expect((KeyCode{ .home = {} }).isNavigation());
    try std.testing.expect((KeyCode{ .end = {} }).isNavigation());
    try std.testing.expect((KeyCode{ .page_up = {} }).isNavigation());
    try std.testing.expect((KeyCode{ .page_down = {} }).isNavigation());

    try std.testing.expect(!(KeyCode{ .enter = {} }).isNavigation());
    try std.testing.expect(!(KeyCode{ .escape = {} }).isNavigation());
    try std.testing.expect(!KeyCode.fromChar('j').isNavigation());
}

test "behavior: Modifiers.any" {
    const empty_mods = Modifiers{};
    try std.testing.expect(!empty_mods.any());
    try std.testing.expect(Modifiers.ctrl_only().any());
    try std.testing.expect(Modifiers.alt_only().any());
    try std.testing.expect(Modifiers.shift_only().any());
    const combo_mods = Modifiers{ .ctrl = true, .alt = true };
    try std.testing.expect(combo_mods.any());
}

test "behavior: MouseKind.isClick" {
    try std.testing.expect(MouseKind.down.isClick());
    try std.testing.expect(MouseKind.up.isClick());
    try std.testing.expect(!MouseKind.drag.isClick());
    try std.testing.expect(!MouseKind.move.isClick());
    try std.testing.expect(!MouseKind.scroll_up.isClick());
}

test "behavior: MouseKind.isScroll" {
    try std.testing.expect(MouseKind.scroll_up.isScroll());
    try std.testing.expect(MouseKind.scroll_down.isScroll());
    try std.testing.expect(!MouseKind.down.isScroll());
    try std.testing.expect(!MouseKind.drag.isScroll());
}

test "behavior: Size.area" {
    const size = Size.init(80, 24);
    try std.testing.expectEqual(@as(u32, 1920), size.area());
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Modifiers packed struct is 1 byte" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(Modifiers));
}

test "regression: KeyCode handles full unicode range" {
    const max_unicode = KeyCode.fromChar(0x10FFFF);
    try std.testing.expectEqual(@as(u21, 0x10FFFF), max_unicode.char);

    const emoji = KeyCode.fromChar(0x1F600);
    try std.testing.expectEqual(@as(u21, 0x1F600), emoji.char);
}

test "regression: Size area doesn't overflow" {
    const large = Size.init(65535, 65535);
    try std.testing.expectEqual(@as(u32, 4294836225), large.area());
}
