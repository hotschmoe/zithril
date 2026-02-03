// Testing utilities for zithril TUI framework
// Provides recording/playback, headless terminal mock, and snapshot testing
//
// Usage:
//   const testing = @import("testing.zig");
//   var recorder = testing.TestRecorder(256).init();
//   var mock = testing.MockBackend.init(80, 24);
//   const snapshot = testing.Snapshot.fromBuffer(buffer);

const std = @import("std");
const event_mod = @import("event.zig");
const buffer_mod = @import("buffer.zig");
const cell_mod = @import("cell.zig");
const geometry_mod = @import("geometry.zig");
const style_mod = @import("style.zig");

pub const Event = event_mod.Event;
pub const Key = event_mod.Key;
pub const KeyCode = event_mod.KeyCode;
pub const Mouse = event_mod.Mouse;
pub const MouseKind = event_mod.MouseKind;
pub const Modifiers = event_mod.Modifiers;
pub const Size = event_mod.Size;
pub const Buffer = buffer_mod.Buffer;
pub const Cell = cell_mod.Cell;
pub const Rect = geometry_mod.Rect;
pub const Style = style_mod.Style;

// ============================================================
// EVENT RECORDING/PLAYBACK
// ============================================================

/// Records events for later playback in tests.
/// Stores events with optional timestamps for timing-sensitive tests.
pub fn TestRecorder(comptime max_events: usize) type {
    return struct {
        const Self = @This();

        /// A recorded event with optional timing information.
        pub const RecordedEvent = struct {
            event: Event,
            timestamp_ms: u64 = 0,
        };

        events: [max_events]RecordedEvent = undefined,
        count: usize = 0,
        start_time_ms: u64 = 0,

        pub fn init() Self {
            return .{
                .events = undefined,
                .count = 0,
                .start_time_ms = 0,
            };
        }

        /// Start recording with timestamp tracking.
        pub fn start(self: *Self, current_time_ms: u64) void {
            self.start_time_ms = current_time_ms;
            self.count = 0;
        }

        /// Record an event with its timestamp.
        pub fn record(self: *Self, ev: Event, current_time_ms: u64) bool {
            if (self.count >= max_events) return false;

            self.events[self.count] = .{
                .event = ev,
                .timestamp_ms = current_time_ms - self.start_time_ms,
            };
            self.count += 1;
            return true;
        }

        /// Record an event without timestamp tracking.
        pub fn recordSimple(self: *Self, ev: Event) bool {
            if (self.count >= max_events) return false;

            self.events[self.count] = .{
                .event = ev,
                .timestamp_ms = 0,
            };
            self.count += 1;
            return true;
        }

        /// Get the number of recorded events.
        pub fn len(self: Self) usize {
            return self.count;
        }

        /// Get recorded events as a slice.
        pub fn getEvents(self: *Self) []RecordedEvent {
            return self.events[0..self.count];
        }

        /// Clear all recorded events.
        pub fn clear(self: *Self) void {
            self.count = 0;
            self.start_time_ms = 0;
        }

        /// Serialize recorded events to a JSON-like format for storage.
        /// Returns the number of bytes written.
        pub fn serialize(self: Self, output: []u8) !usize {
            var stream = std.io.fixedBufferStream(output);
            var writer = stream.writer();

            try writer.writeAll("[\n");
            for (self.events[0..self.count], 0..) |recorded, i| {
                if (i > 0) try writer.writeAll(",\n");
                try serializeEvent(recorded, writer);
            }
            try writer.writeAll("\n]");

            return stream.pos;
        }

        fn serializeEvent(recorded: RecordedEvent, writer: anytype) !void {
            try writer.print("  {{\"timestamp_ms\": {d}, \"event\": ", .{recorded.timestamp_ms});

            switch (recorded.event) {
                .key => |key| {
                    try writer.writeAll("{\"type\": \"key\", ");
                    try serializeKeyCode(key.code, writer);
                    try writer.print(", \"ctrl\": {}, \"alt\": {}, \"shift\": {}}}", .{
                        key.modifiers.ctrl,
                        key.modifiers.alt,
                        key.modifiers.shift,
                    });
                },
                .mouse => |mouse| {
                    try writer.print("{{\"type\": \"mouse\", \"x\": {d}, \"y\": {d}, \"kind\": \"{s}\", \"ctrl\": {}, \"alt\": {}, \"shift\": {}}}", .{
                        mouse.x,
                        mouse.y,
                        @tagName(mouse.kind),
                        mouse.modifiers.ctrl,
                        mouse.modifiers.alt,
                        mouse.modifiers.shift,
                    });
                },
                .resize => |size| {
                    try writer.print("{{\"type\": \"resize\", \"width\": {d}, \"height\": {d}}}", .{
                        size.width,
                        size.height,
                    });
                },
                .tick => {
                    try writer.writeAll("{\"type\": \"tick\"}");
                },
                .command_result => |result| {
                    try writer.print("{{\"type\": \"command_result\", \"id\": {d}, \"success\": {}}}", .{
                        result.id,
                        result.isSuccess(),
                    });
                },
            }

            try writer.writeAll("}");
        }

        fn serializeKeyCode(code: KeyCode, writer: anytype) !void {
            switch (code) {
                .char => |c| try writer.print("\"code\": {{\"char\": {d}}}", .{c}),
                .enter => try writer.writeAll("\"code\": \"enter\""),
                .tab => try writer.writeAll("\"code\": \"tab\""),
                .backtab => try writer.writeAll("\"code\": \"backtab\""),
                .backspace => try writer.writeAll("\"code\": \"backspace\""),
                .escape => try writer.writeAll("\"code\": \"escape\""),
                .up => try writer.writeAll("\"code\": \"up\""),
                .down => try writer.writeAll("\"code\": \"down\""),
                .left => try writer.writeAll("\"code\": \"left\""),
                .right => try writer.writeAll("\"code\": \"right\""),
                .home => try writer.writeAll("\"code\": \"home\""),
                .end => try writer.writeAll("\"code\": \"end\""),
                .page_up => try writer.writeAll("\"code\": \"page_up\""),
                .page_down => try writer.writeAll("\"code\": \"page_down\""),
                .insert => try writer.writeAll("\"code\": \"insert\""),
                .delete => try writer.writeAll("\"code\": \"delete\""),
                .f => |n| try writer.print("\"code\": {{\"f\": {d}}}", .{n}),
            }
        }
    };
}

/// Plays back recorded events for testing.
/// Can be used to inject events into an app's update function.
pub fn TestPlayer(comptime max_events: usize) type {
    return struct {
        const Self = @This();
        const Recorder = TestRecorder(max_events);

        events: []Recorder.RecordedEvent,
        index: usize = 0,
        current_time_ms: u64 = 0,

        pub fn init(events: []Recorder.RecordedEvent) Self {
            return .{
                .events = events,
                .index = 0,
                .current_time_ms = 0,
            };
        }

        /// Get the next event, or null if playback is complete.
        pub fn next(self: *Self) ?Event {
            if (self.index >= self.events.len) return null;

            const recorded = self.events[self.index];
            self.index += 1;
            return recorded.event;
        }

        /// Get the next event if its timestamp has been reached.
        /// Useful for timing-accurate playback.
        pub fn nextTimed(self: *Self, current_time_ms: u64) ?Event {
            if (self.index >= self.events.len) return null;

            const recorded = self.events[self.index];
            if (current_time_ms >= recorded.timestamp_ms) {
                self.index += 1;
                return recorded.event;
            }
            return null;
        }

        /// Check if playback is complete.
        pub fn isDone(self: Self) bool {
            return self.index >= self.events.len;
        }

        /// Reset playback to the beginning.
        pub fn reset(self: *Self) void {
            self.index = 0;
            self.current_time_ms = 0;
        }

        /// Get remaining event count.
        pub fn remaining(self: Self) usize {
            return self.events.len - self.index;
        }
    };
}

// ============================================================
// MOCK BACKEND
// ============================================================

/// A mock terminal backend for headless testing.
/// Captures all output instead of writing to a real terminal.
/// Provides deterministic size and capabilities.
pub const MockBackend = struct {
    const Self = @This();

    /// Maximum output capture size (256KB default).
    pub const DefaultCaptureSize = 256 * 1024;

    /// Captured output data.
    output_buffer: []u8,
    output_len: usize = 0,

    /// Fixed terminal dimensions.
    width: u16,
    height: u16,

    /// Mock state.
    cursor_visible: bool = true,
    cursor_x: u16 = 0,
    cursor_y: u16 = 0,
    raw_mode: bool = false,
    alternate_screen: bool = false,
    mouse_capture: bool = false,
    bracketed_paste: bool = false,

    /// Allocator for output buffer.
    allocator: std.mem.Allocator,

    /// Operation counters for verification.
    write_count: usize = 0,
    flush_count: usize = 0,
    clear_count: usize = 0,

    /// Initialize a mock backend with given dimensions.
    pub fn init(allocator: std.mem.Allocator, width: u16, height: u16) !Self {
        return Self{
            .output_buffer = try allocator.alloc(u8, DefaultCaptureSize),
            .output_len = 0,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    /// Initialize with custom capture buffer size.
    pub fn initWithCapacity(allocator: std.mem.Allocator, width: u16, height: u16, capacity: usize) !Self {
        return Self{
            .output_buffer = try allocator.alloc(u8, capacity),
            .output_len = 0,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.output_buffer);
        self.* = undefined;
    }

    /// Write data to the mock output.
    pub fn write(self: *Self, data: []const u8) !void {
        const available = self.output_buffer.len - self.output_len;
        const to_write = @min(data.len, available);
        @memcpy(self.output_buffer[self.output_len..][0..to_write], data[0..to_write]);
        self.output_len += to_write;
        self.write_count += 1;
    }

    /// Get the captured output.
    pub fn getOutput(self: Self) []const u8 {
        return self.output_buffer[0..self.output_len];
    }

    /// Clear the captured output.
    pub fn clearOutput(self: *Self) void {
        self.output_len = 0;
    }

    /// Simulate terminal clear.
    pub fn clearScreen(self: *Self) void {
        self.clear_count += 1;
    }

    /// Simulate flush.
    pub fn flush(self: *Self) void {
        self.flush_count += 1;
    }

    /// Get terminal size.
    pub fn getSize(self: Self) Size {
        return Size.init(self.width, self.height);
    }

    /// Resize the mock terminal.
    pub fn resize(self: *Self, width: u16, height: u16) void {
        self.width = width;
        self.height = height;
    }

    /// Set cursor position.
    pub fn setCursor(self: *Self, x: u16, y: u16) void {
        self.cursor_x = x;
        self.cursor_y = y;
    }

    /// Show/hide cursor.
    pub fn setCursorVisible(self: *Self, visible: bool) void {
        self.cursor_visible = visible;
    }

    /// Enter raw mode.
    pub fn enterRawMode(self: *Self) void {
        self.raw_mode = true;
    }

    /// Exit raw mode.
    pub fn exitRawMode(self: *Self) void {
        self.raw_mode = false;
    }

    /// Enter alternate screen.
    pub fn enterAlternateScreen(self: *Self) void {
        self.alternate_screen = true;
    }

    /// Exit alternate screen.
    pub fn exitAlternateScreen(self: *Self) void {
        self.alternate_screen = false;
    }

    /// Enable mouse capture.
    pub fn enableMouseCapture(self: *Self) void {
        self.mouse_capture = true;
    }

    /// Disable mouse capture.
    pub fn disableMouseCapture(self: *Self) void {
        self.mouse_capture = false;
    }

    /// Enable bracketed paste.
    pub fn enableBracketedPaste(self: *Self) void {
        self.bracketed_paste = true;
    }

    /// Disable bracketed paste.
    pub fn disableBracketedPaste(self: *Self) void {
        self.bracketed_paste = false;
    }

    /// Reset all state to defaults.
    pub fn reset(self: *Self) void {
        self.output_len = 0;
        self.cursor_visible = true;
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.raw_mode = false;
        self.alternate_screen = false;
        self.mouse_capture = false;
        self.bracketed_paste = false;
        self.write_count = 0;
        self.flush_count = 0;
        self.clear_count = 0;
    }

    /// Check if output contains a specific string.
    pub fn outputContains(self: Self, needle: []const u8) bool {
        return std.mem.indexOf(u8, self.getOutput(), needle) != null;
    }

    /// Count occurrences of a pattern in output.
    pub fn countOccurrences(self: Self, needle: []const u8) usize {
        var count: usize = 0;
        var offset: usize = 0;
        const output = self.getOutput();

        while (std.mem.indexOfPos(u8, output, offset, needle)) |pos| {
            count += 1;
            offset = pos + 1;
        }
        return count;
    }
};

// ============================================================
// SNAPSHOT TESTING
// ============================================================

/// Buffer snapshot for comparison testing.
/// Converts a Buffer to a text representation for golden file comparison.
pub const Snapshot = struct {
    const Self = @This();

    /// Text representation of the buffer.
    text: []const u8,
    /// Width of the snapshot.
    width: u16,
    /// Height of the snapshot.
    height: u16,
    /// Allocator used for text storage.
    allocator: std.mem.Allocator,

    /// Create a snapshot from a buffer.
    /// Converts the buffer contents to a text representation.
    pub fn fromBuffer(allocator: std.mem.Allocator, buf: Buffer) !Self {
        const text = try bufferToText(allocator, buf);
        return Self{
            .text = text,
            .width = buf.width,
            .height = buf.height,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.text);
        self.* = undefined;
    }

    /// Compare this snapshot to another.
    /// Returns true if they are identical.
    pub fn eql(self: Self, other: Self) bool {
        return std.mem.eql(u8, self.text, other.text);
    }

    /// Compare to a string literal (for golden file testing).
    pub fn matches(self: Self, expected: []const u8) bool {
        return std.mem.eql(u8, self.text, expected);
    }

    /// Get a diff between this snapshot and another.
    /// Returns a formatted string showing differences.
    pub fn diff(self: Self, allocator: std.mem.Allocator, other: Self) ![]const u8 {
        var result: std.ArrayListUnmanaged(u8) = .{};
        errdefer result.deinit(allocator);

        var buf_writer = result.writer(allocator);

        if (self.width != other.width or self.height != other.height) {
            try buf_writer.print("Dimension mismatch: {d}x{d} vs {d}x{d}\n", .{
                self.width,
                self.height,
                other.width,
                other.height,
            });
        }

        var self_lines = std.mem.splitScalar(u8, self.text, '\n');
        var other_lines = std.mem.splitScalar(u8, other.text, '\n');

        var line_num: usize = 0;
        while (true) {
            const self_line = self_lines.next();
            const other_line = other_lines.next();

            if (self_line == null and other_line == null) break;

            const a = self_line orelse "";
            const b = other_line orelse "";

            if (!std.mem.eql(u8, a, b)) {
                try buf_writer.print("Line {d}:\n  Expected: \"{s}\"\n  Actual:   \"{s}\"\n", .{
                    line_num,
                    a,
                    b,
                });
            }
            line_num += 1;
        }

        return result.toOwnedSlice(allocator);
    }

    /// Create a snapshot directly from text (for expected values).
    pub fn fromText(allocator: std.mem.Allocator, text: []const u8, width: u16, height: u16) !Self {
        const copy = try allocator.dupe(u8, text);
        return Self{
            .text = copy,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }
};

/// Convert a buffer to a plain text representation.
/// Each row becomes a line, trailing spaces are preserved.
fn bufferToText(allocator: std.mem.Allocator, buf: Buffer) ![]const u8 {
    if (buf.width == 0 or buf.height == 0) {
        return try allocator.dupe(u8, "");
    }

    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    var y: u16 = 0;
    while (y < buf.height) : (y += 1) {
        if (y > 0) {
            try result.append(allocator, '\n');
        }

        var x: u16 = 0;
        while (x < buf.width) : (x += 1) {
            const cell = buf.get(x, y);
            if (cell.width == 0) {
                continue;
            }

            var char_buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cell.char, &char_buf) catch 1;
            try result.appendSlice(allocator, char_buf[0..len]);
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Convert a buffer to an annotated text representation.
/// Includes cell coordinates and style information.
pub fn bufferToAnnotatedText(allocator: std.mem.Allocator, buf: Buffer) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    var buf_writer = result.writer(allocator);

    try buf_writer.print("Buffer {d}x{d}:\n", .{ buf.width, buf.height });
    try buf_writer.writeAll("+" ++ "-" ** 40 ++ "+\n");

    var y: u16 = 0;
    while (y < buf.height) : (y += 1) {
        try buf_writer.print("{d:>3}| ", .{y});

        var x: u16 = 0;
        while (x < buf.width) : (x += 1) {
            const cell = buf.get(x, y);
            if (cell.width == 0) continue;

            var char_buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cell.char, &char_buf) catch 1;
            try result.appendSlice(allocator, char_buf[0..len]);
        }
        try buf_writer.writeAll("\n");
    }

    try buf_writer.writeAll("+" ++ "-" ** 40 ++ "+\n");

    return result.toOwnedSlice(allocator);
}

// ============================================================
// TEST HELPER FUNCTIONS
// ============================================================

/// Create a key event helper.
pub fn keyEvent(char: u21) Event {
    return Event{
        .key = Key{
            .code = KeyCode.fromChar(char),
            .modifiers = .{},
        },
    };
}

/// Create a key event with modifiers.
pub fn keyEventWithMods(char: u21, ctrl: bool, alt: bool, shift: bool) Event {
    return Event{
        .key = Key{
            .code = KeyCode.fromChar(char),
            .modifiers = .{ .ctrl = ctrl, .alt = alt, .shift = shift },
        },
    };
}

/// Create a special key event (enter, escape, arrows, etc.).
pub fn specialKeyEvent(code: KeyCode) Event {
    return Event{
        .key = Key{
            .code = code,
            .modifiers = .{},
        },
    };
}

/// Create a mouse event helper.
pub fn mouseEvent(x: u16, y: u16, kind: MouseKind) Event {
    return Event{
        .mouse = Mouse.init(x, y, kind),
    };
}

/// Create a resize event helper.
pub fn resizeEvent(width: u16, height: u16) Event {
    return Event{
        .resize = Size.init(width, height),
    };
}

/// Create a tick event.
pub fn tickEvent() Event {
    return Event{ .tick = {} };
}

/// Assert that a buffer cell matches expected values.
pub fn expectCell(buf: Buffer, x: u16, y: u16, expected_char: u21) !void {
    const cell = buf.get(x, y);
    if (cell.char != expected_char) {
        std.debug.print(
            \\CELL MISMATCH at ({d}, {d}):
            \\  Expected: '{u}' (U+{X:0>4})
            \\  Actual:   '{u}' (U+{X:0>4})
            \\
        , .{
            x,
            y,
            expected_char,
            expected_char,
            cell.char,
            cell.char,
        });
        return error.TestExpectedEqual;
    }
}

/// Assert that a buffer cell has a specific style attribute.
pub fn expectCellStyle(buf: Buffer, x: u16, y: u16, comptime attr: style_mod.StyleAttribute) !void {
    const cell = buf.get(x, y);
    if (!cell.style.hasAttribute(attr)) {
        std.debug.print(
            \\STYLE MISMATCH at ({d}, {d}):
            \\  Expected attribute: {s}
            \\  Cell char: '{u}'
            \\
        , .{ x, y, @tagName(attr), cell.char });
        return error.TestExpectedEqual;
    }
}

/// Assert that a buffer region contains a specific string.
pub fn expectString(buf: Buffer, x: u16, y: u16, expected: []const u8) !void {
    var current_x = x;
    var iter = std.unicode.Utf8View.initUnchecked(expected).iterator();

    var idx: usize = 0;
    while (iter.nextCodepoint()) |expected_char| {
        const cell = buf.get(current_x, y);
        if (cell.char != expected_char) {
            std.debug.print(
                \\STRING MISMATCH at ({d}, {d}) index {d}:
                \\  Expected string: "{s}"
                \\  Mismatch at char: expected '{u}', got '{u}'
                \\
            , .{ x, y, idx, expected, expected_char, cell.char });
            return error.TestExpectedEqual;
        }
        current_x += if (cell.isWide()) 2 else 1;
        idx += 1;
    }
}

// ============================================================
// SANITY TESTS
// ============================================================

test "sanity: TestRecorder init" {
    var recorder = TestRecorder(256).init();
    try std.testing.expectEqual(@as(usize, 0), recorder.len());
}

test "sanity: TestRecorder recordSimple" {
    var recorder = TestRecorder(256).init();

    const ev = keyEvent('a');
    try std.testing.expect(recorder.recordSimple(ev));
    try std.testing.expectEqual(@as(usize, 1), recorder.len());

    const events = recorder.getEvents();
    try std.testing.expect(events[0].event == .key);
}

test "sanity: TestRecorder capacity limit" {
    var recorder = TestRecorder(2).init();

    try std.testing.expect(recorder.recordSimple(keyEvent('a')));
    try std.testing.expect(recorder.recordSimple(keyEvent('b')));
    try std.testing.expect(!recorder.recordSimple(keyEvent('c')));

    try std.testing.expectEqual(@as(usize, 2), recorder.len());
}

test "sanity: TestPlayer playback" {
    var recorder = TestRecorder(256).init();
    _ = recorder.recordSimple(keyEvent('a'));
    _ = recorder.recordSimple(keyEvent('b'));
    _ = recorder.recordSimple(keyEvent('c'));

    var player = TestPlayer(256).init(recorder.getEvents());

    try std.testing.expectEqual(@as(usize, 3), player.remaining());
    try std.testing.expect(!player.isDone());

    const ev1 = player.next();
    try std.testing.expect(ev1 != null);
    try std.testing.expect(ev1.? == .key);

    const ev2 = player.next();
    try std.testing.expect(ev2 != null);

    const ev3 = player.next();
    try std.testing.expect(ev3 != null);

    try std.testing.expect(player.isDone());
    try std.testing.expect(player.next() == null);
}

test "sanity: MockBackend init and write" {
    var mock = try MockBackend.init(std.testing.allocator, 80, 24);
    defer mock.deinit();

    try std.testing.expectEqual(@as(u16, 80), mock.width);
    try std.testing.expectEqual(@as(u16, 24), mock.height);

    try mock.write("Hello");
    try std.testing.expectEqualStrings("Hello", mock.getOutput());
}

test "sanity: MockBackend state tracking" {
    var mock = try MockBackend.init(std.testing.allocator, 80, 24);
    defer mock.deinit();

    try std.testing.expect(!mock.raw_mode);
    try std.testing.expect(!mock.alternate_screen);

    mock.enterRawMode();
    mock.enterAlternateScreen();

    try std.testing.expect(mock.raw_mode);
    try std.testing.expect(mock.alternate_screen);

    mock.reset();
    try std.testing.expect(!mock.raw_mode);
    try std.testing.expect(!mock.alternate_screen);
}

test "sanity: Snapshot from buffer" {
    var buf = try Buffer.init(std.testing.allocator, 10, 3);
    defer buf.deinit();

    buf.setString(0, 0, "Hello", Style.empty);
    buf.setString(0, 1, "World", Style.empty);

    var snapshot = try Snapshot.fromBuffer(std.testing.allocator, buf);
    defer snapshot.deinit();

    try std.testing.expectEqual(@as(u16, 10), snapshot.width);
    try std.testing.expectEqual(@as(u16, 3), snapshot.height);
}

// ============================================================
// BEHAVIOR TESTS
// ============================================================

test "behavior: TestRecorder timed recording" {
    var recorder = TestRecorder(256).init();
    recorder.start(1000);

    try std.testing.expect(recorder.record(keyEvent('a'), 1050));
    try std.testing.expect(recorder.record(keyEvent('b'), 1100));

    const events = recorder.getEvents();
    try std.testing.expectEqual(@as(u64, 50), events[0].timestamp_ms);
    try std.testing.expectEqual(@as(u64, 100), events[1].timestamp_ms);
}

test "behavior: TestPlayer timed playback" {
    var recorder = TestRecorder(256).init();
    recorder.start(0);
    _ = recorder.record(keyEvent('a'), 0);
    _ = recorder.record(keyEvent('b'), 100);
    _ = recorder.record(keyEvent('c'), 200);

    var player = TestPlayer(256).init(recorder.getEvents());

    try std.testing.expect(player.nextTimed(0) != null);
    try std.testing.expect(player.nextTimed(50) == null);
    try std.testing.expect(player.nextTimed(100) != null);
    try std.testing.expect(player.nextTimed(150) == null);
    try std.testing.expect(player.nextTimed(200) != null);
    try std.testing.expect(player.isDone());
}

test "behavior: MockBackend output helpers" {
    var mock = try MockBackend.init(std.testing.allocator, 80, 24);
    defer mock.deinit();

    try mock.write("\x1b[H");
    try mock.write("Hello World");
    try mock.write("\x1b[H");

    try std.testing.expect(mock.outputContains("Hello"));
    try std.testing.expect(mock.outputContains("\x1b[H"));
    try std.testing.expect(!mock.outputContains("Goodbye"));

    try std.testing.expectEqual(@as(usize, 2), mock.countOccurrences("\x1b[H"));
}

test "behavior: Snapshot comparison" {
    var buf1 = try Buffer.init(std.testing.allocator, 5, 2);
    defer buf1.deinit();
    buf1.setString(0, 0, "Hello", Style.empty);

    var buf2 = try Buffer.init(std.testing.allocator, 5, 2);
    defer buf2.deinit();
    buf2.setString(0, 0, "Hello", Style.empty);

    var buf3 = try Buffer.init(std.testing.allocator, 5, 2);
    defer buf3.deinit();
    buf3.setString(0, 0, "World", Style.empty);

    var snap1 = try Snapshot.fromBuffer(std.testing.allocator, buf1);
    defer snap1.deinit();

    var snap2 = try Snapshot.fromBuffer(std.testing.allocator, buf2);
    defer snap2.deinit();

    var snap3 = try Snapshot.fromBuffer(std.testing.allocator, buf3);
    defer snap3.deinit();

    try std.testing.expect(snap1.eql(snap2));
    try std.testing.expect(!snap1.eql(snap3));
}

test "behavior: Snapshot diff" {
    var buf1 = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf1.deinit();
    buf1.setString(0, 0, "Hello", Style.empty);
    buf1.setString(0, 1, "World", Style.empty);

    var buf2 = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf2.deinit();
    buf2.setString(0, 0, "Hello", Style.empty);
    buf2.setString(0, 1, "Zig!!", Style.empty);

    var snap1 = try Snapshot.fromBuffer(std.testing.allocator, buf1);
    defer snap1.deinit();

    var snap2 = try Snapshot.fromBuffer(std.testing.allocator, buf2);
    defer snap2.deinit();

    const diff_text = try snap1.diff(std.testing.allocator, snap2);
    defer std.testing.allocator.free(diff_text);

    try std.testing.expect(std.mem.indexOf(u8, diff_text, "Line 1:") != null);
}

test "behavior: event helper functions" {
    const key_ev = keyEvent('x');
    try std.testing.expect(key_ev == .key);
    try std.testing.expectEqual(@as(u21, 'x'), key_ev.key.code.char);

    const ctrl_c = keyEventWithMods('c', true, false, false);
    try std.testing.expect(ctrl_c.key.modifiers.ctrl);

    const mouse_ev = mouseEvent(10, 20, .down);
    try std.testing.expect(mouse_ev == .mouse);
    try std.testing.expectEqual(@as(u16, 10), mouse_ev.mouse.x);

    const resize_ev = resizeEvent(120, 40);
    try std.testing.expect(resize_ev == .resize);

    const tick_ev = tickEvent();
    try std.testing.expect(tick_ev == .tick);
}

test "behavior: expectCell and expectString" {
    var buf = try Buffer.init(std.testing.allocator, 20, 5);
    defer buf.deinit();

    buf.setString(0, 0, "Hello", Style.init().bold());

    try expectCell(buf, 0, 0, 'H');
    try expectCell(buf, 4, 0, 'o');
    try expectString(buf, 0, 0, "Hello");
    try expectCellStyle(buf, 0, 0, .bold);
}

// ============================================================
// REGRESSION TESTS
// ============================================================

test "regression: TestRecorder serialization" {
    var recorder = TestRecorder(256).init();
    _ = recorder.recordSimple(keyEvent('a'));
    _ = recorder.recordSimple(mouseEvent(10, 20, .down));
    _ = recorder.recordSimple(resizeEvent(100, 50));
    _ = recorder.recordSimple(tickEvent());

    var output: [4096]u8 = undefined;
    const len = try recorder.serialize(&output);

    const json = output[0..len];
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\": \"key\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\": \"mouse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\": \"resize\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\": \"tick\"") != null);
}

test "regression: Snapshot handles empty buffer" {
    var buf = try Buffer.init(std.testing.allocator, 0, 0);
    defer buf.deinit();

    var snapshot = try Snapshot.fromBuffer(std.testing.allocator, buf);
    defer snapshot.deinit();

    try std.testing.expectEqualStrings("", snapshot.text);
}

test "regression: Snapshot handles wide characters" {
    var buf = try Buffer.init(std.testing.allocator, 10, 1);
    defer buf.deinit();

    buf.setString(0, 0, "\u{4E2D}\u{6587}", Style.empty);

    var snapshot = try Snapshot.fromBuffer(std.testing.allocator, buf);
    defer snapshot.deinit();

    try std.testing.expect(std.mem.indexOf(u8, snapshot.text, "\u{4E2D}") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot.text, "\u{6587}") != null);
}

test "regression: MockBackend resize" {
    var mock = try MockBackend.init(std.testing.allocator, 80, 24);
    defer mock.deinit();

    mock.resize(120, 40);

    try std.testing.expectEqual(@as(u16, 120), mock.getSize().width);
    try std.testing.expectEqual(@as(u16, 40), mock.getSize().height);
}

test "regression: TestPlayer reset" {
    var recorder = TestRecorder(256).init();
    _ = recorder.recordSimple(keyEvent('a'));
    _ = recorder.recordSimple(keyEvent('b'));

    var player = TestPlayer(256).init(recorder.getEvents());

    _ = player.next();
    _ = player.next();
    try std.testing.expect(player.isDone());

    player.reset();
    try std.testing.expect(!player.isDone());
    try std.testing.expectEqual(@as(usize, 2), player.remaining());
}
