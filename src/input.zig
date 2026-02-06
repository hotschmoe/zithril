// Terminal input parsing for zithril TUI framework
// Parses raw terminal bytes into Event types
// Handles ANSI escape sequences for keys, mouse, and special characters

const std = @import("std");
const event_mod = @import("event.zig");

pub const Event = event_mod.Event;
pub const Key = event_mod.Key;
pub const KeyCode = event_mod.KeyCode;
pub const Modifiers = event_mod.Modifiers;
pub const Mouse = event_mod.Mouse;
pub const MouseKind = event_mod.MouseKind;
pub const Size = event_mod.Size;

/// Input parser state machine.
/// Parses raw terminal input bytes into Event types.
pub const Input = struct {
    /// Buffer for incomplete escape sequences
    buffer: [32]u8 = undefined,
    /// Number of bytes in buffer
    buffer_len: usize = 0,
    /// Whether we're in a paste sequence
    in_paste: bool = false,

    const Self = @This();

    /// Initialize a new input parser.
    pub fn init() Self {
        return .{};
    }

    /// Parse input bytes and return an event if one is complete.
    /// May consume partial input for multi-byte sequences.
    pub fn parse(self: *Self, bytes: []const u8) ?Event {
        if (bytes.len == 0) {
            return null;
        }

        // Handle bracketed paste mode
        if (self.in_paste) {
            return self.parsePaste(bytes);
        }

        // Check for escape sequence
        if (bytes[0] == 0x1b) {
            return self.parseEscape(bytes);
        }

        // Handle control characters (0x00-0x1F and DEL 0x7F)
        if (bytes[0] < 0x20 or bytes[0] == 0x7f) {
            return self.parseControl(bytes[0]);
        }

        // Handle regular UTF-8 character
        return self.parseUtf8(bytes);
    }

    /// Parse a control character (0x00-0x1F).
    fn parseControl(self: *Self, byte: u8) ?Event {
        _ = self;
        return switch (byte) {
            0x00 => Event{ .key = .{ .code = .{ .char = ' ' }, .modifiers = .{ .ctrl = true } } }, // Ctrl+Space
            0x09 => Event{ .key = .{ .code = .tab } }, // Tab
            0x0a, 0x0d => Event{ .key = .{ .code = .enter } }, // Enter (LF or CR)
            0x7f => Event{ .key = .{ .code = .backspace } }, // Backspace (DEL)
            // Ctrl+A through Ctrl+Z (excluding tab=0x09, enter=0x0a, and 0x0d)
            0x01...0x08, 0x0b, 0x0c, 0x0e...0x1a => |b| Event{ .key = .{ .code = .{ .char = 'a' + (b - 1) }, .modifiers = .{ .ctrl = true } } },
            0x1b => Event{ .key = .{ .code = .escape } }, // Escape (handled elsewhere)
            else => null,
        };
    }

    /// Parse an escape sequence.
    fn parseEscape(self: *Self, bytes: []const u8) ?Event {
        if (bytes.len == 1) {
            // Just ESC by itself
            return Event{ .key = .{ .code = .escape } };
        }

        const second = bytes[1];

        // CSI sequence (ESC [)
        if (second == '[') {
            return self.parseCsi(bytes[2..]);
        }

        // SS3 sequence (ESC O)
        if (second == 'O') {
            return self.parseSs3(bytes[2..]);
        }

        // Alt+Escape
        if (second == 0x1b) {
            return Event{ .key = .{ .code = .escape, .modifiers = .{ .alt = true } } };
        }

        // Alt+Backspace (DEL)
        if (second == 0x7f) {
            return Event{ .key = .{ .code = .backspace, .modifiers = .{ .alt = true } } };
        }

        // Alt+key (printable ASCII)
        if (second >= 0x20 and second < 0x7f) {
            return Event{ .key = .{ .code = .{ .char = second }, .modifiers = .{ .alt = true } } };
        }

        return Event{ .key = .{ .code = .escape } };
    }

    /// Parse a CSI (Control Sequence Introducer) sequence.
    /// Format: ESC [ <params> <final>
    fn parseCsi(self: *Self, bytes: []const u8) ?Event {
        if (bytes.len == 0) {
            return Event{ .key = .{ .code = .escape } };
        }

        // Check for mouse sequences
        if (bytes[0] == 'M' or bytes[0] == '<') {
            return self.parseMouse(bytes);
        }

        // Check for bracketed paste
        if (bytes.len >= 4 and bytes[0] == '2' and bytes[1] == '0' and bytes[2] == '0' and bytes[3] == '~') {
            self.in_paste = true;
            return null;
        }

        // Parse arrow keys and simple sequences
        return switch (bytes[0]) {
            'A' => Event{ .key = .{ .code = .up } },
            'B' => Event{ .key = .{ .code = .down } },
            'C' => Event{ .key = .{ .code = .right } },
            'D' => Event{ .key = .{ .code = .left } },
            'H' => Event{ .key = .{ .code = .home } },
            'F' => Event{ .key = .{ .code = .end } },
            'Z' => Event{ .key = .{ .code = .backtab } }, // Shift+Tab
            else => self.parseCsiParams(bytes),
        };
    }

    /// Parse CSI sequences with parameters.
    fn parseCsiParams(self: *Self, bytes: []const u8) ?Event {
        _ = self;

        // Find the final character
        var i: usize = 0;
        var param1: u16 = 0;
        var param2: u16 = 0;
        var in_second_param = false;

        while (i < bytes.len) : (i += 1) {
            const c = bytes[i];
            if (c >= '0' and c <= '9') {
                if (in_second_param) {
                    param2 = param2 * 10 + (c - '0');
                } else {
                    param1 = param1 * 10 + (c - '0');
                }
            } else if (c == ';') {
                in_second_param = true;
            } else {
                // Final character
                return parseCsiFinal(c, param1, param2);
            }
        }

        return null;
    }

    /// Parse the final character of a CSI sequence.
    fn parseCsiFinal(final: u8, param1: u16, param2: u16) ?Event {
        // Extract modifiers from param2 (CSI 1;2A = Shift+Up, etc.)
        const mods = modifiersFromParam(param2);

        return switch (final) {
            'A' => Event{ .key = .{ .code = .up, .modifiers = mods } },
            'B' => Event{ .key = .{ .code = .down, .modifiers = mods } },
            'C' => Event{ .key = .{ .code = .right, .modifiers = mods } },
            'D' => Event{ .key = .{ .code = .left, .modifiers = mods } },
            'H' => Event{ .key = .{ .code = .home, .modifiers = mods } },
            'F' => Event{ .key = .{ .code = .end, .modifiers = mods } },
            '~' => switch (param1) {
                1 => Event{ .key = .{ .code = .home, .modifiers = mods } },
                2 => Event{ .key = .{ .code = .insert, .modifiers = mods } },
                3 => Event{ .key = .{ .code = .delete, .modifiers = mods } },
                4 => Event{ .key = .{ .code = .end, .modifiers = mods } },
                5 => Event{ .key = .{ .code = .page_up, .modifiers = mods } },
                6 => Event{ .key = .{ .code = .page_down, .modifiers = mods } },
                7 => Event{ .key = .{ .code = .home, .modifiers = mods } },
                8 => Event{ .key = .{ .code = .end, .modifiers = mods } },
                11...15 => |p| Event{ .key = .{ .code = .{ .f = @intCast(p - 10) }, .modifiers = mods } }, // F1-F5
                17...21 => |p| Event{ .key = .{ .code = .{ .f = @intCast(p - 11) }, .modifiers = mods } }, // F6-F10
                23, 24 => |p| Event{ .key = .{ .code = .{ .f = @intCast(p - 12) }, .modifiers = mods } }, // F11-F12
                200 => null, // Bracketed paste start (handled elsewhere)
                201 => null, // Bracketed paste end (handled elsewhere)
                else => null,
            },
            'P' => Event{ .key = .{ .code = .{ .f = 1 }, .modifiers = mods } }, // F1
            'Q' => Event{ .key = .{ .code = .{ .f = 2 }, .modifiers = mods } }, // F2
            'R' => Event{ .key = .{ .code = .{ .f = 3 }, .modifiers = mods } }, // F3
            'S' => Event{ .key = .{ .code = .{ .f = 4 }, .modifiers = mods } }, // F4
            else => null,
        };
    }

    /// Convert modifier parameter to Modifiers struct.
    /// Terminal convention: 1=none, 2=shift, 3=alt, 4=shift+alt, 5=ctrl, etc.
    fn modifiersFromParam(param: u16) Modifiers {
        if (param == 0 or param == 1) {
            return Modifiers{};
        }

        const p = param - 1;
        return Modifiers{
            .shift = (p & 1) != 0,
            .alt = (p & 2) != 0,
            .ctrl = (p & 4) != 0,
        };
    }

    /// Parse an SS3 (Single Shift 3) sequence.
    /// Used by some terminals for function keys and keypad.
    fn parseSs3(self: *Self, bytes: []const u8) ?Event {
        _ = self;
        if (bytes.len == 0) {
            return Event{ .key = .{ .code = .escape } };
        }

        return switch (bytes[0]) {
            'A' => Event{ .key = .{ .code = .up } },
            'B' => Event{ .key = .{ .code = .down } },
            'C' => Event{ .key = .{ .code = .right } },
            'D' => Event{ .key = .{ .code = .left } },
            'H' => Event{ .key = .{ .code = .home } },
            'F' => Event{ .key = .{ .code = .end } },
            'P' => Event{ .key = .{ .code = .{ .f = 1 } } },
            'Q' => Event{ .key = .{ .code = .{ .f = 2 } } },
            'R' => Event{ .key = .{ .code = .{ .f = 3 } } },
            'S' => Event{ .key = .{ .code = .{ .f = 4 } } },
            else => null,
        };
    }

    /// Parse mouse sequences (X10 or SGR mode).
    fn parseMouse(self: *Self, bytes: []const u8) ?Event {
        _ = self;

        if (bytes.len == 0) {
            return null;
        }

        // SGR mode: ESC [ < Cb ; Cx ; Cy M/m
        if (bytes[0] == '<') {
            return parseMouseSgr(bytes[1..]);
        }

        // X10 mode: ESC [ M Cb Cx Cy
        if (bytes[0] == 'M') {
            return parseMouseX10(bytes[1..]);
        }

        return null;
    }

    /// Parse SGR mouse sequence.
    /// Format: <Cb;Cx;Cy M or <Cb;Cx;Cy m
    fn parseMouseSgr(bytes: []const u8) ?Event {
        var i: usize = 0;
        var cb: u16 = 0;
        var cx: u16 = 0;
        var cy: u16 = 0;
        var param_index: u8 = 0;

        while (i < bytes.len) : (i += 1) {
            const c = bytes[i];
            if (c >= '0' and c <= '9') {
                switch (param_index) {
                    0 => cb = cb * 10 + (c - '0'),
                    1 => cx = cx * 10 + (c - '0'),
                    2 => cy = cy * 10 + (c - '0'),
                    else => {},
                }
            } else if (c == ';') {
                param_index += 1;
            } else if (c == 'M' or c == 'm') {
                // M = button press, m = button release
                const is_release = (c == 'm');

                // Decode button and modifiers from cb
                const button = @as(u8, @intCast(cb & 0x03));
                const shift = (cb & 0x04) != 0;
                const alt = (cb & 0x08) != 0;
                const ctrl = (cb & 0x10) != 0;
                const motion = (cb & 0x20) != 0;
                const wheel = (cb & 0x40) != 0;

                const kind: MouseKind = if (wheel)
                    if (button == 0) .scroll_up else .scroll_down
                else if (motion)
                    .drag
                else if (is_release)
                    .up
                else
                    .down;

                // SGR coordinates are 1-based
                const x = if (cx > 0) cx - 1 else 0;
                const y = if (cy > 0) cy - 1 else 0;

                return Event{
                    .mouse = .{
                        .x = x,
                        .y = y,
                        .kind = kind,
                        .modifiers = .{
                            .shift = shift,
                            .alt = alt,
                            .ctrl = ctrl,
                        },
                    },
                };
            }
        }

        return null;
    }

    /// Parse X10 mouse sequence.
    /// Format: M Cb Cx Cy (all encoded as Cb+32, Cx+32, Cy+32)
    fn parseMouseX10(bytes: []const u8) ?Event {
        if (bytes.len < 3) {
            return null;
        }

        const cb = bytes[0] -| 32;
        const cx = bytes[1] -| 32;
        const cy = bytes[2] -| 32;

        const button = cb & 0x03;
        const shift = (cb & 0x04) != 0;
        const alt = (cb & 0x08) != 0;
        const ctrl = (cb & 0x10) != 0;
        const motion = (cb & 0x20) != 0;
        const wheel = (cb & 0x40) != 0;

        const kind: MouseKind = if (wheel)
            if (button == 0) .scroll_up else .scroll_down
        else if (motion)
            .drag
        else if (button == 3)
            .up // X10 uses button 3 for release
        else
            .down;

        return Event{
            .mouse = .{
                .x = cx,
                .y = cy,
                .kind = kind,
                .modifiers = .{
                    .shift = shift,
                    .alt = alt,
                    .ctrl = ctrl,
                },
            },
        };
    }

    /// Parse a paste sequence.
    fn parsePaste(self: *Self, bytes: []const u8) ?Event {
        // Look for paste end sequence: ESC [ 2 0 1 ~
        const end_seq = "\x1b[201~";
        if (std.mem.indexOf(u8, bytes, end_seq)) |_| {
            self.in_paste = false;
            // For now, we don't expose paste content as events
            // Future: could return a paste event with content
        }
        return null;
    }

    /// Parse a UTF-8 character sequence.
    fn parseUtf8(self: *Self, bytes: []const u8) ?Event {
        _ = self;

        // Determine UTF-8 sequence length from first byte
        const len = utf8ByteLen(bytes[0]);

        if (len == 0) {
            return null;
        }

        if (bytes.len < len) {
            // Incomplete sequence
            return null;
        }

        // Decode the codepoint
        const codepoint = std.unicode.utf8Decode(bytes[0..len]) catch {
            return null;
        };

        return Event{ .key = .{ .code = .{ .char = codepoint } } };
    }
};

/// Get the length of a UTF-8 sequence from its first byte.
fn utf8ByteLen(byte: u8) usize {
    if (byte < 0x80) return 1;
    if (byte < 0xc0) return 0; // Continuation byte
    if (byte < 0xe0) return 2;
    if (byte < 0xf0) return 3;
    if (byte < 0xf8) return 4;
    return 0;
}

// ============================================================
// SANITY TESTS - Basic input parsing
// ============================================================

test "sanity: Input.init creates parser" {
    const input = Input.init();
    try std.testing.expectEqual(@as(usize, 0), input.buffer_len);
    try std.testing.expect(!input.in_paste);
}

test "sanity: parse single ASCII character" {
    var input = Input.init();
    const event = input.parse("a");
    try std.testing.expect(event != null);
    try std.testing.expect(event.? == .key);
    try std.testing.expect(event.?.key.code == .char);
    try std.testing.expectEqual(@as(u21, 'a'), event.?.key.code.char);
}

test "sanity: parse escape key" {
    var input = Input.init();
    const event = input.parse("\x1b");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .escape);
}

test "sanity: parse enter key" {
    var input = Input.init();
    const event = input.parse("\r");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .enter);
}

test "sanity: parse tab key" {
    var input = Input.init();
    const event = input.parse("\t");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .tab);
}

// ============================================================
// BEHAVIOR TESTS - Arrow keys
// ============================================================

test "behavior: parse arrow up" {
    var input = Input.init();
    const event = input.parse("\x1b[A");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .up);
}

test "behavior: parse arrow down" {
    var input = Input.init();
    const event = input.parse("\x1b[B");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .down);
}

test "behavior: parse arrow right" {
    var input = Input.init();
    const event = input.parse("\x1b[C");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .right);
}

test "behavior: parse arrow left" {
    var input = Input.init();
    const event = input.parse("\x1b[D");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .left);
}

// ============================================================
// BEHAVIOR TESTS - Modifier keys
// ============================================================

test "behavior: parse Ctrl+C" {
    var input = Input.init();
    const event = input.parse("\x03");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.modifiers.ctrl);
    try std.testing.expect(event.?.key.code == .char);
    try std.testing.expectEqual(@as(u21, 'c'), event.?.key.code.char);
}

test "behavior: parse Alt+a" {
    var input = Input.init();
    const event = input.parse("\x1ba");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.modifiers.alt);
    try std.testing.expect(event.?.key.code == .char);
    try std.testing.expectEqual(@as(u21, 'a'), event.?.key.code.char);
}

test "behavior: parse Shift+Up" {
    var input = Input.init();
    const event = input.parse("\x1b[1;2A");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .up);
    try std.testing.expect(event.?.key.modifiers.shift);
}

test "behavior: parse Ctrl+Alt+Up" {
    var input = Input.init();
    const event = input.parse("\x1b[1;7A");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .up);
    try std.testing.expect(event.?.key.modifiers.ctrl);
    try std.testing.expect(event.?.key.modifiers.alt);
}

// ============================================================
// BEHAVIOR TESTS - Function keys
// ============================================================

test "behavior: parse F1 (SS3)" {
    var input = Input.init();
    const event = input.parse("\x1bOP");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .f);
    try std.testing.expectEqual(@as(u8, 1), event.?.key.code.f);
}

test "behavior: parse F5 (CSI)" {
    var input = Input.init();
    const event = input.parse("\x1b[15~");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .f);
    try std.testing.expectEqual(@as(u8, 5), event.?.key.code.f);
}

test "behavior: parse F12" {
    var input = Input.init();
    const event = input.parse("\x1b[24~");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .f);
    try std.testing.expectEqual(@as(u8, 12), event.?.key.code.f);
}

// ============================================================
// BEHAVIOR TESTS - Navigation keys
// ============================================================

test "behavior: parse Home" {
    var input = Input.init();
    const event = input.parse("\x1b[H");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .home);
}

test "behavior: parse End" {
    var input = Input.init();
    const event = input.parse("\x1b[F");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .end);
}

test "behavior: parse Insert" {
    var input = Input.init();
    const event = input.parse("\x1b[2~");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .insert);
}

test "behavior: parse Delete" {
    var input = Input.init();
    const event = input.parse("\x1b[3~");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .delete);
}

test "behavior: parse PageUp" {
    var input = Input.init();
    const event = input.parse("\x1b[5~");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .page_up);
}

test "behavior: parse PageDown" {
    var input = Input.init();
    const event = input.parse("\x1b[6~");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .page_down);
}

test "behavior: parse Backtab (Shift+Tab)" {
    var input = Input.init();
    const event = input.parse("\x1b[Z");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .backtab);
}

// ============================================================
// BEHAVIOR TESTS - Mouse input
// ============================================================

test "behavior: parse mouse click SGR" {
    var input = Input.init();
    const event = input.parse("\x1b[<0;10;20M");
    try std.testing.expect(event != null);
    try std.testing.expect(event.? == .mouse);
    try std.testing.expectEqual(@as(u16, 9), event.?.mouse.x);
    try std.testing.expectEqual(@as(u16, 19), event.?.mouse.y);
    try std.testing.expect(event.?.mouse.kind == .down);
}

test "behavior: parse mouse release SGR" {
    var input = Input.init();
    const event = input.parse("\x1b[<0;10;20m");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.mouse.kind == .up);
}

test "behavior: parse mouse scroll up SGR" {
    var input = Input.init();
    const event = input.parse("\x1b[<64;10;20M");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.mouse.kind == .scroll_up);
}

test "behavior: parse mouse scroll down SGR" {
    var input = Input.init();
    const event = input.parse("\x1b[<65;10;20M");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.mouse.kind == .scroll_down);
}

test "behavior: parse mouse with modifiers SGR" {
    var input = Input.init();
    // cb = 0 + 4 (shift) + 8 (alt) = 12
    const event = input.parse("\x1b[<12;10;20M");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.mouse.modifiers.shift);
    try std.testing.expect(event.?.mouse.modifiers.alt);
}

// ============================================================
// BEHAVIOR TESTS - UTF-8 input
// ============================================================

test "behavior: parse 2-byte UTF-8" {
    var input = Input.init();
    // e with acute accent (U+00E9)
    const event = input.parse("\xc3\xa9");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .char);
    try std.testing.expectEqual(@as(u21, 0x00e9), event.?.key.code.char);
}

test "behavior: parse 3-byte UTF-8 CJK" {
    var input = Input.init();
    // Chinese character (U+4E2D)
    const event = input.parse("\xe4\xb8\xad");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .char);
    try std.testing.expectEqual(@as(u21, 0x4e2d), event.?.key.code.char);
}

test "behavior: parse 4-byte UTF-8 emoji" {
    var input = Input.init();
    // Grinning face emoji (U+1F600)
    const event = input.parse("\xf0\x9f\x98\x80");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .char);
    try std.testing.expectEqual(@as(u21, 0x1f600), event.?.key.code.char);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: parse empty input returns null" {
    var input = Input.init();
    const event = input.parse("");
    try std.testing.expect(event == null);
}

test "regression: utf8ByteLen handles all cases" {
    try std.testing.expectEqual(@as(usize, 1), utf8ByteLen(0x00));
    try std.testing.expectEqual(@as(usize, 1), utf8ByteLen(0x7f));
    try std.testing.expectEqual(@as(usize, 0), utf8ByteLen(0x80)); // Invalid continuation
    try std.testing.expectEqual(@as(usize, 2), utf8ByteLen(0xc0));
    try std.testing.expectEqual(@as(usize, 3), utf8ByteLen(0xe0));
    try std.testing.expectEqual(@as(usize, 4), utf8ByteLen(0xf0));
}

test "regression: modifiersFromParam handles edge cases" {
    const no_mods = Input.modifiersFromParam(0);
    try std.testing.expect(!no_mods.shift and !no_mods.alt and !no_mods.ctrl);

    const no_mods_1 = Input.modifiersFromParam(1);
    try std.testing.expect(!no_mods_1.shift and !no_mods_1.alt and !no_mods_1.ctrl);

    const shift_only = Input.modifiersFromParam(2);
    try std.testing.expect(shift_only.shift);
    try std.testing.expect(!shift_only.alt);
    try std.testing.expect(!shift_only.ctrl);

    const all_mods = Input.modifiersFromParam(8); // 1 + shift + alt + ctrl
    try std.testing.expect(all_mods.shift);
    try std.testing.expect(all_mods.alt);
    try std.testing.expect(all_mods.ctrl);
}

test "regression: 0x7F (DEL) parses as backspace, not char" {
    var input = Input.init();
    const event = input.parse("\x7f");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .backspace);
    try std.testing.expect(!event.?.key.modifiers.any());
}

test "regression: Alt+Backspace (ESC 0x7F) parses as alt+backspace" {
    var input = Input.init();
    const event = input.parse("\x1b\x7f");
    try std.testing.expect(event != null);
    try std.testing.expect(event.?.key.code == .backspace);
    try std.testing.expect(event.?.key.modifiers.alt);
    try std.testing.expect(!event.?.key.modifiers.ctrl);
}
