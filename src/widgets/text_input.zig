// TextInput widget for zithril TUI framework
// Single-line text input with cursor movement, selection, and clipboard support

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const event_mod = @import("../event.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Key = event_mod.Key;
pub const KeyCode = event_mod.KeyCode;
pub const Modifiers = event_mod.Modifiers;

/// Text input state managing content, cursor, and selection.
pub const TextInputState = struct {
    /// The text content (user provides backing storage).
    buffer: []u8,

    /// Current length of text content.
    len: usize = 0,

    /// Cursor position (byte index).
    cursor: usize = 0,

    /// Selection anchor (byte index). If different from cursor, text is selected.
    /// Selection range is [min(anchor, cursor), max(anchor, cursor)).
    anchor: usize = 0,

    /// Horizontal scroll offset (for text wider than viewport).
    scroll_offset: usize = 0,

    /// Maximum allowed content length (0 = use buffer size).
    max_len: usize = 0,

    /// Create a new text input state with the given buffer.
    pub fn init(backing_buffer: []u8) TextInputState {
        return .{
            .buffer = backing_buffer,
        };
    }

    /// Create a text input state with initial content.
    pub fn initWithContent(backing_buffer: []u8, initial: []const u8) TextInputState {
        var state = init(backing_buffer);
        state.setText(initial);
        return state;
    }

    /// Get the current text content.
    pub fn text(self: TextInputState) []const u8 {
        return self.buffer[0..self.len];
    }

    /// Set the text content, replacing all existing content.
    pub fn setText(self: *TextInputState, content: []const u8) void {
        const max = self.maxLength();
        const copy_len = @min(content.len, max);
        @memcpy(self.buffer[0..copy_len], content[0..copy_len]);
        self.len = copy_len;
        self.cursor = copy_len;
        self.anchor = copy_len;
        self.scroll_offset = 0;
    }

    /// Clear all content.
    pub fn clear(self: *TextInputState) void {
        self.len = 0;
        self.cursor = 0;
        self.anchor = 0;
        self.scroll_offset = 0;
    }

    /// Get maximum allowed length.
    fn maxLength(self: TextInputState) usize {
        if (self.max_len > 0) {
            return @min(self.max_len, self.buffer.len);
        }
        return self.buffer.len;
    }

    // ========================================
    // Cursor Movement
    // ========================================

    /// Move cursor left by one character.
    pub fn cursorLeft(self: *TextInputState) void {
        if (self.cursor > 0) {
            self.cursor = self.prevCharBoundary(self.cursor);
        }
        self.anchor = self.cursor;
    }

    /// Move cursor right by one character.
    pub fn cursorRight(self: *TextInputState) void {
        if (self.cursor < self.len) {
            self.cursor = self.nextCharBoundary(self.cursor);
        }
        self.anchor = self.cursor;
    }

    /// Move cursor to start of line.
    pub fn cursorHome(self: *TextInputState) void {
        self.cursor = 0;
        self.anchor = 0;
    }

    /// Move cursor to end of line.
    pub fn cursorEnd(self: *TextInputState) void {
        self.cursor = self.len;
        self.anchor = self.len;
    }

    /// Move cursor left by one word.
    pub fn cursorWordLeft(self: *TextInputState) void {
        self.cursor = self.findWordBoundaryLeft(self.cursor);
        self.anchor = self.cursor;
    }

    /// Move cursor right by one word.
    pub fn cursorWordRight(self: *TextInputState) void {
        self.cursor = self.findWordBoundaryRight(self.cursor);
        self.anchor = self.cursor;
    }

    // ========================================
    // Selection
    // ========================================

    /// Check if there is an active selection.
    pub fn hasSelection(self: TextInputState) bool {
        return self.cursor != self.anchor;
    }

    /// Get the selection range [start, end).
    pub fn selectionRange(self: TextInputState) struct { start: usize, end: usize } {
        return .{
            .start = @min(self.cursor, self.anchor),
            .end = @max(self.cursor, self.anchor),
        };
    }

    /// Get the selected text.
    pub fn selectedText(self: TextInputState) []const u8 {
        const range = self.selectionRange();
        return self.buffer[range.start..range.end];
    }

    /// Clear selection (keep cursor position).
    pub fn clearSelection(self: *TextInputState) void {
        self.anchor = self.cursor;
    }

    /// Select all text.
    pub fn selectAll(self: *TextInputState) void {
        self.anchor = 0;
        self.cursor = self.len;
    }

    /// Extend selection left by one character.
    pub fn selectLeft(self: *TextInputState) void {
        if (self.cursor > 0) {
            self.cursor = self.prevCharBoundary(self.cursor);
        }
    }

    /// Extend selection right by one character.
    pub fn selectRight(self: *TextInputState) void {
        if (self.cursor < self.len) {
            self.cursor = self.nextCharBoundary(self.cursor);
        }
    }

    /// Extend selection to start of line.
    pub fn selectToStart(self: *TextInputState) void {
        self.cursor = 0;
    }

    /// Extend selection to end of line.
    pub fn selectToEnd(self: *TextInputState) void {
        self.cursor = self.len;
    }

    /// Extend selection left by one word.
    pub fn selectWordLeft(self: *TextInputState) void {
        self.cursor = self.findWordBoundaryLeft(self.cursor);
    }

    /// Extend selection right by one word.
    pub fn selectWordRight(self: *TextInputState) void {
        self.cursor = self.findWordBoundaryRight(self.cursor);
    }

    // ========================================
    // Editing
    // ========================================

    /// Insert a character at cursor position.
    /// Replaces selection if active.
    pub fn insertChar(self: *TextInputState, char: u21) void {
        var utf8_buf: [4]u8 = undefined;
        const utf8_len = std.unicode.utf8Encode(char, &utf8_buf) catch return;
        self.insertBytes(utf8_buf[0..utf8_len]);
    }

    /// Insert text at cursor position.
    /// Replaces selection if active.
    pub fn insertBytes(self: *TextInputState, bytes: []const u8) void {
        // Delete selection first if present
        if (self.hasSelection()) {
            self.deleteSelection();
        }

        const max = self.maxLength();
        const available = max -| self.len;
        const insert_len = @min(bytes.len, available);
        if (insert_len == 0) return;

        // Make room by shifting content after cursor
        const after_cursor = self.len - self.cursor;
        if (after_cursor > 0) {
            std.mem.copyBackwards(
                u8,
                self.buffer[self.cursor + insert_len .. self.len + insert_len],
                self.buffer[self.cursor..self.len],
            );
        }

        // Insert new content
        @memcpy(self.buffer[self.cursor .. self.cursor + insert_len], bytes[0..insert_len]);
        self.len += insert_len;
        self.cursor += insert_len;
        self.anchor = self.cursor;
    }

    /// Delete character before cursor (backspace).
    pub fn deleteBackward(self: *TextInputState) void {
        if (self.hasSelection()) {
            self.deleteSelection();
            return;
        }

        if (self.cursor == 0) return;

        const prev = self.prevCharBoundary(self.cursor);
        const delete_len = self.cursor - prev;

        // Shift content after cursor
        const after = self.len - self.cursor;
        if (after > 0) {
            std.mem.copyForwards(
                u8,
                self.buffer[prev .. prev + after],
                self.buffer[self.cursor..self.len],
            );
        }

        self.len -= delete_len;
        self.cursor = prev;
        self.anchor = prev;
    }

    /// Delete character at cursor (delete key).
    pub fn deleteForward(self: *TextInputState) void {
        if (self.hasSelection()) {
            self.deleteSelection();
            return;
        }

        if (self.cursor >= self.len) return;

        const next = self.nextCharBoundary(self.cursor);
        const delete_len = next - self.cursor;

        // Shift content after deleted character
        const after = self.len - next;
        if (after > 0) {
            std.mem.copyForwards(
                u8,
                self.buffer[self.cursor .. self.cursor + after],
                self.buffer[next..self.len],
            );
        }

        self.len -= delete_len;
    }

    /// Delete word before cursor.
    pub fn deleteWordBackward(self: *TextInputState) void {
        if (self.hasSelection()) {
            self.deleteSelection();
            return;
        }

        const target = self.findWordBoundaryLeft(self.cursor);
        if (target == self.cursor) return;

        const delete_len = self.cursor - target;
        const after = self.len - self.cursor;
        if (after > 0) {
            std.mem.copyForwards(
                u8,
                self.buffer[target .. target + after],
                self.buffer[self.cursor..self.len],
            );
        }

        self.len -= delete_len;
        self.cursor = target;
        self.anchor = target;
    }

    /// Delete word after cursor.
    pub fn deleteWordForward(self: *TextInputState) void {
        if (self.hasSelection()) {
            self.deleteSelection();
            return;
        }

        const target = self.findWordBoundaryRight(self.cursor);
        if (target == self.cursor) return;

        const delete_len = target - self.cursor;
        const after = self.len - target;
        if (after > 0) {
            std.mem.copyForwards(
                u8,
                self.buffer[self.cursor .. self.cursor + after],
                self.buffer[target..self.len],
            );
        }

        self.len -= delete_len;
    }

    /// Delete the current selection.
    fn deleteSelection(self: *TextInputState) void {
        if (!self.hasSelection()) return;

        const range = self.selectionRange();
        const delete_len = range.end - range.start;
        const after = self.len - range.end;

        if (after > 0) {
            std.mem.copyForwards(
                u8,
                self.buffer[range.start .. range.start + after],
                self.buffer[range.end..self.len],
            );
        }

        self.len -= delete_len;
        self.cursor = range.start;
        self.anchor = range.start;
    }

    // ========================================
    // Clipboard Operations
    // ========================================

    /// Copy selected text to provided buffer.
    /// Returns the copied text slice, or empty if no selection.
    pub fn copyTo(self: TextInputState, dest: []u8) []const u8 {
        if (!self.hasSelection()) return dest[0..0];

        const selected = self.selectedText();
        const copy_len = @min(selected.len, dest.len);
        @memcpy(dest[0..copy_len], selected[0..copy_len]);
        return dest[0..copy_len];
    }

    /// Cut selected text to provided buffer.
    /// Returns the cut text slice, or empty if no selection.
    pub fn cutTo(self: *TextInputState, dest: []u8) []const u8 {
        const copied = self.copyTo(dest);
        if (copied.len > 0) {
            self.deleteSelection();
        }
        return copied;
    }

    /// Paste text from provided slice.
    pub fn paste(self: *TextInputState, content: []const u8) void {
        self.insertBytes(content);
    }

    // ========================================
    // Input Handling
    // ========================================

    /// Handle keyboard input.
    /// Returns true if the event was handled.
    pub fn handleKey(self: *TextInputState, key: Key) bool {
        const ctrl = key.modifiers.ctrl;
        const shift = key.modifiers.shift;

        switch (key.code) {
            .char => |c| {
                if (ctrl) {
                    // Ctrl+key shortcuts
                    switch (c) {
                        'a' => {
                            self.selectAll();
                            return true;
                        },
                        'w' => {
                            self.deleteWordBackward();
                            return true;
                        },
                        'u' => {
                            self.clear();
                            return true;
                        },
                        else => {},
                    }
                    return false;
                }
                // Regular character input
                self.insertChar(c);
                return true;
            },
            .left => {
                if (ctrl and shift) {
                    self.selectWordLeft();
                } else if (ctrl) {
                    self.cursorWordLeft();
                } else if (shift) {
                    self.selectLeft();
                } else {
                    self.cursorLeft();
                }
                return true;
            },
            .right => {
                if (ctrl and shift) {
                    self.selectWordRight();
                } else if (ctrl) {
                    self.cursorWordRight();
                } else if (shift) {
                    self.selectRight();
                } else {
                    self.cursorRight();
                }
                return true;
            },
            .home => {
                if (shift) {
                    self.selectToStart();
                } else {
                    self.cursorHome();
                }
                return true;
            },
            .end => {
                if (shift) {
                    self.selectToEnd();
                } else {
                    self.cursorEnd();
                }
                return true;
            },
            .backspace => {
                if (ctrl) {
                    self.deleteWordBackward();
                } else {
                    self.deleteBackward();
                }
                return true;
            },
            .delete => {
                if (ctrl) {
                    self.deleteWordForward();
                } else {
                    self.deleteForward();
                }
                return true;
            },
            else => {},
        }
        return false;
    }

    // ========================================
    // UTF-8 Helpers
    // ========================================

    /// Find the previous character boundary.
    fn prevCharBoundary(self: TextInputState, pos: usize) usize {
        if (pos == 0) return 0;
        var i = pos - 1;
        while (i > 0 and !isCharStart(self.buffer[i])) {
            i -= 1;
        }
        return i;
    }

    /// Find the next character boundary.
    fn nextCharBoundary(self: TextInputState, pos: usize) usize {
        if (pos >= self.len) return self.len;
        var i = pos + 1;
        while (i < self.len and !isCharStart(self.buffer[i])) {
            i += 1;
        }
        return i;
    }

    /// Check if byte is a UTF-8 character start.
    fn isCharStart(byte: u8) bool {
        return (byte & 0xC0) != 0x80;
    }

    /// Check if character is a word character.
    fn isWordChar(char: u8) bool {
        return std.ascii.isAlphanumeric(char) or char == '_';
    }

    /// Find word boundary to the left.
    fn findWordBoundaryLeft(self: TextInputState, pos: usize) usize {
        if (pos == 0) return 0;

        var i = pos;

        // Skip any non-word characters immediately before cursor
        while (i > 0 and !isWordChar(self.buffer[i - 1])) {
            i -= 1;
        }

        // Skip word characters
        while (i > 0 and isWordChar(self.buffer[i - 1])) {
            i -= 1;
        }

        return i;
    }

    /// Find word boundary to the right.
    fn findWordBoundaryRight(self: TextInputState, pos: usize) usize {
        if (pos >= self.len) return self.len;

        var i = pos;

        // Skip word characters at cursor
        while (i < self.len and isWordChar(self.buffer[i])) {
            i += 1;
        }

        // Skip any non-word characters
        while (i < self.len and !isWordChar(self.buffer[i])) {
            i += 1;
        }

        return i;
    }

    // ========================================
    // Display Helpers
    // ========================================

    /// Calculate the display width of text up to a byte position.
    pub fn displayWidthTo(self: TextInputState, byte_pos: usize) usize {
        var width: usize = 0;
        var i: usize = 0;
        const content = self.buffer[0..@min(byte_pos, self.len)];

        while (i < content.len) {
            const byte = content[i];
            if (byte < 0x80) {
                width += 1;
                i += 1;
            } else {
                const char_len = std.unicode.utf8ByteSequenceLength(byte) catch {
                    i += 1;
                    continue;
                };
                if (i + char_len <= content.len) {
                    const codepoint = std.unicode.utf8Decode(content[i..][0..char_len]) catch {
                        i += 1;
                        continue;
                    };
                    // Rough approximation: CJK and emoji are double-width
                    if (codepoint >= 0x1100) {
                        width += 2;
                    } else {
                        width += 1;
                    }
                }
                i += char_len;
            }
        }
        return width;
    }

    /// Update scroll offset to keep cursor visible.
    pub fn updateScrollOffset(self: *TextInputState, viewport_width: u16) void {
        if (viewport_width == 0) return;

        const cursor_display_pos = self.displayWidthTo(self.cursor);
        const vw: usize = viewport_width;

        if (cursor_display_pos < self.scroll_offset) {
            self.scroll_offset = cursor_display_pos;
        } else if (cursor_display_pos >= self.scroll_offset + vw) {
            self.scroll_offset = cursor_display_pos -| (vw -| 1);
        }
    }
};

/// TextInput widget for rendering text input fields.
pub const TextInput = struct {
    /// Text input state.
    state: *TextInputState,

    /// Default text style.
    style: Style = Style.empty,

    /// Cursor style (when focused).
    cursor_style: Style = Style.init().reverse(),

    /// Selection highlight style.
    selection_style: Style = Style.init().bg(.blue),

    /// Placeholder text when empty.
    placeholder: []const u8 = "",

    /// Placeholder style.
    placeholder_style: Style = Style.init().dim(),

    /// Whether the input is focused (shows cursor).
    focused: bool = true,

    /// Render the text input into the buffer.
    pub fn render(self: TextInput, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;

        // Update scroll offset based on viewport
        self.state.updateScrollOffset(area.width);

        // Fill background
        buf.fill(area, Cell.styled(' ', self.style));

        const content = self.state.text();

        // Show placeholder if empty and not focused
        if (content.len == 0 and self.placeholder.len > 0 and !self.focused) {
            buf.setString(area.x, area.y, self.placeholder, self.placeholder_style);
            return;
        }

        // Render visible text
        const selection = self.state.selectionRange();
        const scroll = self.state.scroll_offset;

        var x: u16 = area.x;
        var byte_idx: usize = 0;
        var display_idx: usize = 0;

        while (byte_idx < content.len and x < area.right()) {
            const byte = content[byte_idx];
            const char_len = if (byte < 0x80)
                @as(usize, 1)
            else
                std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (byte_idx + char_len > content.len) break;

            const codepoint = if (byte < 0x80)
                @as(u21, byte)
            else
                std.unicode.utf8Decode(content[byte_idx..][0..char_len]) catch byte;

            // Rough display width
            const char_width: usize = if (codepoint >= 0x1100) 2 else 1;

            // Check if this character is visible
            if (display_idx + char_width > scroll) {
                // Determine style
                var char_style = self.style;
                const in_selection = self.state.hasSelection() and
                    byte_idx >= selection.start and byte_idx < selection.end;

                if (in_selection) {
                    char_style = self.selection_style;
                }

                // Draw cursor
                if (self.focused and byte_idx == self.state.cursor) {
                    char_style = self.cursor_style;
                }

                buf.set(x, area.y, Cell.styled(codepoint, char_style));
                x += @intCast(@min(char_width, area.right() - x));
            }

            display_idx += char_width;
            byte_idx += char_len;
        }

        // Draw cursor at end if needed
        if (self.focused and self.state.cursor >= self.state.len) {
            if (x < area.right()) {
                buf.set(x, area.y, Cell.styled(' ', self.cursor_style));
            }
        }
    }
};

// ============================================================
// SANITY TESTS - TextInputState basic functionality
// ============================================================

test "sanity: TextInputState default values" {
    var backing: [256]u8 = undefined;
    const state = TextInputState.init(&backing);

    try std.testing.expectEqual(@as(usize, 0), state.len);
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
    try std.testing.expectEqual(@as(usize, 0), state.anchor);
    try std.testing.expectEqualStrings("", state.text());
}

test "sanity: TextInputState.initWithContent" {
    var backing: [256]u8 = undefined;
    const state = TextInputState.initWithContent(&backing, "hello");

    try std.testing.expectEqual(@as(usize, 5), state.len);
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
    try std.testing.expectEqualStrings("hello", state.text());
}

test "sanity: TextInputState.setText" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.init(&backing);

    state.setText("world");
    try std.testing.expectEqualStrings("world", state.text());
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
}

test "sanity: TextInputState.clear" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "test");

    state.clear();
    try std.testing.expectEqualStrings("", state.text());
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
}

// ============================================================
// BEHAVIOR TESTS - Cursor Movement
// ============================================================

test "behavior: TextInputState cursor left/right" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");

    state.cursorLeft();
    try std.testing.expectEqual(@as(usize, 4), state.cursor);

    state.cursorRight();
    try std.testing.expectEqual(@as(usize, 5), state.cursor);

    state.cursorHome();
    try std.testing.expectEqual(@as(usize, 0), state.cursor);

    state.cursorEnd();
    try std.testing.expectEqual(@as(usize, 5), state.cursor);
}

test "behavior: TextInputState cursor word navigation" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello world foo");

    state.cursorHome();
    state.cursorWordRight();
    try std.testing.expectEqual(@as(usize, 6), state.cursor);

    state.cursorWordRight();
    try std.testing.expectEqual(@as(usize, 12), state.cursor);

    state.cursorWordLeft();
    try std.testing.expectEqual(@as(usize, 6), state.cursor);
}

// ============================================================
// BEHAVIOR TESTS - Selection
// ============================================================

test "behavior: TextInputState selection" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello world");
    state.cursorHome();

    try std.testing.expect(!state.hasSelection());

    state.selectRight();
    state.selectRight();
    state.selectRight();

    try std.testing.expect(state.hasSelection());
    try std.testing.expectEqualStrings("hel", state.selectedText());

    const range = state.selectionRange();
    try std.testing.expectEqual(@as(usize, 0), range.start);
    try std.testing.expectEqual(@as(usize, 3), range.end);
}

test "behavior: TextInputState selectAll" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");

    state.selectAll();
    try std.testing.expectEqualStrings("hello", state.selectedText());
}

// ============================================================
// BEHAVIOR TESTS - Editing
// ============================================================

test "behavior: TextInputState insertChar" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.init(&backing);

    state.insertChar('a');
    state.insertChar('b');
    state.insertChar('c');

    try std.testing.expectEqualStrings("abc", state.text());
    try std.testing.expectEqual(@as(usize, 3), state.cursor);
}

test "behavior: TextInputState insertBytes" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");
    state.cursor = 5;

    state.insertBytes(" world");
    try std.testing.expectEqualStrings("hello world", state.text());
}

test "behavior: TextInputState insert replaces selection" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello world");
    state.cursorHome();

    // Select "hello"
    state.anchor = 0;
    state.cursor = 5;

    state.insertBytes("hi");
    try std.testing.expectEqualStrings("hi world", state.text());
}

test "behavior: TextInputState deleteBackward" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");

    state.deleteBackward();
    try std.testing.expectEqualStrings("hell", state.text());
    try std.testing.expectEqual(@as(usize, 4), state.cursor);
}

test "behavior: TextInputState deleteForward" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");
    state.cursorHome();

    state.deleteForward();
    try std.testing.expectEqualStrings("ello", state.text());
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
}

test "behavior: TextInputState deleteWordBackward" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello world");

    state.deleteWordBackward();
    try std.testing.expectEqualStrings("hello ", state.text());
}

// ============================================================
// BEHAVIOR TESTS - Clipboard
// ============================================================

test "behavior: TextInputState copyTo" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello world");
    state.anchor = 0;
    state.cursor = 5;

    var clip_buf: [256]u8 = undefined;
    const copied = state.copyTo(&clip_buf);
    try std.testing.expectEqualStrings("hello", copied);
}

test "behavior: TextInputState cutTo" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello world");
    state.anchor = 0;
    state.cursor = 6;

    var clip_buf: [256]u8 = undefined;
    const cut = state.cutTo(&clip_buf);
    try std.testing.expectEqualStrings("hello ", cut);
    try std.testing.expectEqualStrings("world", state.text());
}

test "behavior: TextInputState paste" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");

    state.paste(" world");
    try std.testing.expectEqualStrings("hello world", state.text());
}

// ============================================================
// BEHAVIOR TESTS - Input Handling
// ============================================================

test "behavior: TextInputState handleKey character input" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.init(&backing);

    const handled = state.handleKey(.{ .code = .{ .char = 'x' } });
    try std.testing.expect(handled);
    try std.testing.expectEqualStrings("x", state.text());
}

test "behavior: TextInputState handleKey navigation" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "test");

    _ = state.handleKey(.{ .code = .left });
    try std.testing.expectEqual(@as(usize, 3), state.cursor);

    _ = state.handleKey(.{ .code = .home });
    try std.testing.expectEqual(@as(usize, 0), state.cursor);

    _ = state.handleKey(.{ .code = .end });
    try std.testing.expectEqual(@as(usize, 4), state.cursor);
}

test "behavior: TextInputState handleKey with shift selects" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "test");
    state.cursorHome();

    _ = state.handleKey(.{ .code = .right, .modifiers = .{ .shift = true } });
    _ = state.handleKey(.{ .code = .right, .modifiers = .{ .shift = true } });

    try std.testing.expect(state.hasSelection());
    try std.testing.expectEqualStrings("te", state.selectedText());
}

test "behavior: TextInputState handleKey Ctrl+A selects all" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");

    _ = state.handleKey(.{ .code = .{ .char = 'a' }, .modifiers = .{ .ctrl = true } });

    try std.testing.expect(state.hasSelection());
    try std.testing.expectEqualStrings("hello", state.selectedText());
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: TextInput renders text" {
    var buf = try Buffer.init(std.testing.allocator, 20, 1);
    defer buf.deinit();

    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");

    const input = TextInput{
        .state = &state,
        .focused = false,
    };
    input.render(Rect.init(0, 0, 20, 1), &buf);

    try std.testing.expectEqual(@as(u21, 'h'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).char);
}

test "behavior: TextInput renders cursor when focused" {
    var buf = try Buffer.init(std.testing.allocator, 20, 1);
    defer buf.deinit();

    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hi");
    state.cursor = 2;

    const input = TextInput{
        .state = &state,
        .focused = true,
        .cursor_style = Style.init().reverse(),
    };
    input.render(Rect.init(0, 0, 20, 1), &buf);

    // Cursor at position 2 should have cursor style
    try std.testing.expect(buf.get(2, 0).style.hasAttribute(.reverse));
}

test "behavior: TextInput renders placeholder when empty" {
    var buf = try Buffer.init(std.testing.allocator, 20, 1);
    defer buf.deinit();

    var backing: [256]u8 = undefined;
    var state = TextInputState.init(&backing);

    const input = TextInput{
        .state = &state,
        .focused = false,
        .placeholder = "Type here",
        .placeholder_style = Style.init().dim(),
    };
    input.render(Rect.init(0, 0, 20, 1), &buf);

    try std.testing.expectEqual(@as(u21, 'T'), buf.get(0, 0).char);
    try std.testing.expect(buf.get(0, 0).style.hasAttribute(.dim));
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: TextInputState handles empty buffer" {
    var backing: [0]u8 = undefined;
    var state = TextInputState.init(&backing);

    state.insertChar('a');
    try std.testing.expectEqual(@as(usize, 0), state.len);
}

test "regression: TextInputState respects max_len" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.init(&backing);
    state.max_len = 5;

    state.setText("hello world");
    try std.testing.expectEqualStrings("hello", state.text());
}

test "regression: TextInputState cursor bounds" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hi");

    // Try to go past end
    state.cursorRight();
    state.cursorRight();
    state.cursorRight();
    try std.testing.expectEqual(@as(usize, 2), state.cursor);

    // Try to go before start
    state.cursorHome();
    state.cursorLeft();
    try std.testing.expectEqual(@as(usize, 0), state.cursor);
}

test "regression: TextInputState handles UTF-8" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.init(&backing);

    state.insertBytes("cafe");
    try std.testing.expectEqualStrings("cafe", state.text());
    try std.testing.expectEqual(@as(usize, 4), state.len);

    state.cursorLeft();
    try std.testing.expectEqual(@as(usize, 3), state.cursor);
}

test "regression: TextInput handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 20, 20);
    defer buf.deinit();

    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "test");

    const input = TextInput{ .state = &state };
    input.render(Rect.init(0, 0, 0, 0), &buf);

    // Should not crash
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: TextInputState deleteBackward at start" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");
    state.cursorHome();

    state.deleteBackward();
    try std.testing.expectEqualStrings("hello", state.text());
}

test "regression: TextInputState deleteForward at end" {
    var backing: [256]u8 = undefined;
    var state = TextInputState.initWithContent(&backing, "hello");

    state.deleteForward();
    try std.testing.expectEqualStrings("hello", state.text());
}
