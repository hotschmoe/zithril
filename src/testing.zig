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

const is_windows = @import("builtin").os.tag == .windows;

/// Cross-platform environment variable getter.
fn getEnv(name: []const u8) ?[]const u8 {
    if (is_windows) {
        return std.process.getEnvVarOwned(std.heap.page_allocator, name) catch null;
    } else {
        return std.posix.getenv(name);
    }
}

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

    /// Save snapshot text to a file.
    /// Writes a header line with dimensions, then the text content.
    /// Auto-creates parent directories if they don't exist.
    pub fn saveToFile(self: Self, path: []const u8) !void {
        if (std.fs.path.dirname(path)) |parent| {
            try std.fs.cwd().makePath(parent);
        }
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        var buf: [64]u8 = undefined;
        const header = std.fmt.bufPrint(&buf, "# zithril-golden {d}x{d}\n", .{ self.width, self.height }) catch unreachable;
        try file.writeAll(header);
        try file.writeAll(self.text);
    }

    /// Load a snapshot from a golden file.
    /// Parses the header line to extract dimensions.
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const raw = try file.readToEndAlloc(allocator, 1024 * 1024);
        errdefer allocator.free(raw);

        const prefix = "# zithril-golden ";
        if (!std.mem.startsWith(u8, raw, prefix)) {
            return error.InvalidGoldenFileHeader;
        }
        const after_prefix = raw[prefix.len..];
        const newline_pos = std.mem.indexOfScalar(u8, after_prefix, '\n') orelse
            return error.InvalidGoldenFileHeader;

        const dim_str = after_prefix[0..newline_pos];
        const x_pos = std.mem.indexOfScalar(u8, dim_str, 'x') orelse
            return error.InvalidGoldenFileHeader;

        const width = std.fmt.parseInt(u16, dim_str[0..x_pos], 10) catch
            return error.InvalidGoldenFileHeader;
        const height = std.fmt.parseInt(u16, dim_str[x_pos + 1 ..], 10) catch
            return error.InvalidGoldenFileHeader;

        const text_start = prefix.len + newline_pos + 1;
        const text = try allocator.dupe(u8, raw[text_start..]);
        allocator.free(raw);

        return Self{
            .text = text,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    /// Compare to a golden file and fail with diff on mismatch.
    /// If ZITHRIL_UPDATE_SNAPSHOTS=1, updates the file instead of failing.
    pub fn expectMatchesFile(self: Self, allocator: std.mem.Allocator, path: []const u8) !void {
        const update_mode = if (getEnv("ZITHRIL_UPDATE_SNAPSHOTS")) |v|
            std.mem.eql(u8, v, "1")
        else
            false;

        var loaded = loadFromFile(allocator, path) catch |err| {
            if (err == error.FileNotFound and update_mode) {
                try self.saveToFile(path);
                std.debug.print("SNAPSHOT CREATED: {s}\n", .{path});
                return;
            }
            return err;
        };
        defer loaded.deinit();
        if (!self.eql(loaded)) {
            if (update_mode) {
                try self.saveToFile(path);
                std.debug.print("SNAPSHOT UPDATED: {s}\n", .{path});
                return;
            }
            const diff_text = try self.diff(allocator, loaded);
            defer allocator.free(diff_text);
            std.debug.print("SNAPSHOT MISMATCH: {s}\n\n{s}\n", .{ path, diff_text });
            return error.TestExpectedEqual;
        }
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
// TEST HARNESS
// ============================================================

/// High-level test harness that drives the full update/view/render cycle
/// without a real terminal. Provides event injection and assertion APIs.
///
/// Usage:
///   var state = MyState{};
///   var harness = try TestHarness(MyState).init(allocator, .{
///       .state = &state,
///       .update = update,
///       .view = view,
///   });
///   defer harness.deinit();
///   harness.pressKey('j');
///   try harness.expectString(0, 0, "Selected: item_1");
pub fn TestHarness(comptime State: type) type {
    return struct {
        const Self = @This();
        pub const MaxWidgets: usize = 64;
        const FrameType = @import("frame.zig").Frame(MaxWidgets);
        const Action = @import("action.zig").Action;

        allocator: std.mem.Allocator,
        state: *State,
        update_fn: *const fn (*State, Event) Action,
        view_fn: *const fn (*State, *FrameType) void,
        current_buf: Buffer,
        previous_buf: Buffer,
        last_action: Action,
        frame_count: u64,

        pub const Config = struct {
            state: *State,
            update: *const fn (*State, Event) Action,
            view: *const fn (*State, *FrameType) void,
            width: u16 = 80,
            height: u16 = 24,
        };

        pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
            var self = Self{
                .allocator = allocator,
                .state = config.state,
                .update_fn = config.update,
                .view_fn = config.view,
                .current_buf = try Buffer.init(allocator, config.width, config.height),
                .previous_buf = try Buffer.init(allocator, config.width, config.height),
                .last_action = Action{ .none = {} },
                .frame_count = 0,
            };
            // Initial render
            self.render();
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.current_buf.deinit();
            self.previous_buf.deinit();
        }

        // -- Core loop --

        fn step(self: *Self, event: Event) void {
            self.last_action = self.update_fn(self.state, event);
            self.render();
        }

        fn render(self: *Self) void {
            self.current_buf.clear();
            var frame = FrameType.init(&self.current_buf);
            self.view_fn(self.state, &frame);
            @memcpy(self.previous_buf.cells, self.current_buf.cells);
            self.frame_count += 1;
        }

        // -- Event injection --

        pub fn pressKey(self: *Self, char: u21) void {
            self.step(keyEvent(char));
        }

        pub fn pressKeyWith(self: *Self, code: KeyCode, mods: Modifiers) void {
            self.step(Event{ .key = Key{ .code = code, .modifiers = mods } });
        }

        pub fn pressSpecial(self: *Self, code: KeyCode) void {
            self.step(Event{ .key = Key{ .code = code } });
        }

        pub fn click(self: *Self, x: u16, y: u16) void {
            self.step(mouseEvent(x, y, .down));
            self.step(mouseEvent(x, y, .up));
        }

        pub fn rightClick(self: *Self, x: u16, y: u16) void {
            self.step(Event{ .mouse = .{ .x = x, .y = y, .kind = .down, .modifiers = .{ .ctrl = true } } });
            self.step(Event{ .mouse = .{ .x = x, .y = y, .kind = .up, .modifiers = .{ .ctrl = true } } });
        }

        pub fn mouseDown(self: *Self, x: u16, y: u16) void {
            self.step(mouseEvent(x, y, .down));
        }

        pub fn mouseUp(self: *Self, x: u16, y: u16) void {
            self.step(mouseEvent(x, y, .up));
        }

        pub fn drag(self: *Self, from_x: u16, from_y: u16, to_x: u16, to_y: u16) void {
            self.step(mouseEvent(from_x, from_y, .down));
            self.step(Event{ .mouse = .{ .x = to_x, .y = to_y, .kind = .drag } });
            self.step(mouseEvent(to_x, to_y, .up));
        }

        pub fn hover(self: *Self, x: u16, y: u16) void {
            self.step(Event{ .mouse = .{ .x = x, .y = y, .kind = .move } });
        }

        pub fn scroll(self: *Self, x: u16, y: u16, direction: MouseKind) void {
            self.step(Event{ .mouse = .{ .x = x, .y = y, .kind = direction } });
        }

        pub fn resize(self: *Self, width: u16, height: u16) !void {
            self.current_buf.deinit();
            self.previous_buf.deinit();
            self.current_buf = try Buffer.init(self.allocator, width, height);
            self.previous_buf = try Buffer.init(self.allocator, width, height);
            self.step(resizeEvent(width, height));
        }

        pub fn tick(self: *Self) void {
            self.step(tickEvent());
        }

        pub fn tickN(self: *Self, n: u32) void {
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                self.tick();
            }
        }

        pub fn inject(self: *Self, event: Event) void {
            self.step(event);
        }

        // -- Assertions --

        pub fn expectCell(self: Self, x: u16, y: u16, expected_char: u21) !void {
            const cell = self.current_buf.get(x, y);
            if (cell.char != expected_char) {
                std.debug.print(
                    \\CELL MISMATCH at ({d}, {d}):
                    \\  Expected: '{u}' (U+{X:0>4})
                    \\  Actual:   '{u}' (U+{X:0>4})
                    \\
                , .{ x, y, expected_char, expected_char, cell.char, cell.char });
                return error.TestExpectedEqual;
            }
        }

        pub fn expectString(self: Self, x: u16, y: u16, expected: []const u8) !void {
            var current_x = x;
            var iter = std.unicode.Utf8View.initUnchecked(expected).iterator();
            var idx: usize = 0;
            while (iter.nextCodepoint()) |expected_char| {
                const cell = self.current_buf.get(current_x, y);
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

        pub fn expectStyle(self: Self, x: u16, y: u16, comptime attr: style_mod.StyleAttribute) !void {
            const cell = self.current_buf.get(x, y);
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

        pub fn expectEmpty(self: Self, x: u16, y: u16) !void {
            const cell = self.current_buf.get(x, y);
            if (cell.char != ' ' or !cell.style.isEmpty()) {
                std.debug.print(
                    \\EXPECTED EMPTY at ({d}, {d}):
                    \\  Actual char: '{u}' (U+{X:0>4})
                    \\  Has style: {}
                    \\
                , .{ x, y, cell.char, cell.char, !cell.style.isEmpty() });
                return error.TestExpectedEqual;
            }
        }

        pub fn expectAction(self: Self, expected: Action) !void {
            const match = switch (expected) {
                .none => self.last_action == .none,
                .quit => self.last_action == .quit,
                .command => self.last_action == .command,
            };
            if (!match) {
                std.debug.print(
                    \\ACTION MISMATCH:
                    \\  Expected: {s}
                    \\  Actual:   {s}
                    \\
                , .{ @tagName(expected), @tagName(self.last_action) });
                return error.TestExpectedEqual;
            }
        }

        pub fn expectQuit(self: Self) !void {
            try self.expectAction(Action{ .quit = {} });
        }

        // -- Buffer access --

        pub fn getCell(self: Self, x: u16, y: u16) Cell {
            return self.current_buf.get(x, y);
        }

        pub fn getBuffer(self: *const Self) *const Buffer {
            return &self.current_buf;
        }

        pub fn getText(self: Self, allocator: std.mem.Allocator) ![]const u8 {
            return bufferToText(allocator, self.current_buf);
        }

        pub fn getRow(self: Self, allocator: std.mem.Allocator, y: u16) ![]const u8 {
            if (y >= self.current_buf.height) {
                return try allocator.dupe(u8, "");
            }
            var result: std.ArrayListUnmanaged(u8) = .{};
            errdefer result.deinit(allocator);
            var x: u16 = 0;
            while (x < self.current_buf.width) : (x += 1) {
                const cell = self.current_buf.get(x, y);
                if (cell.width == 0) continue;
                var char_buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cell.char, &char_buf) catch 1;
                try result.appendSlice(allocator, char_buf[0..len]);
            }
            return result.toOwnedSlice(allocator);
        }

        pub fn getRegion(self: Self, allocator: std.mem.Allocator, region: Rect) ![]const u8 {
            var result: std.ArrayListUnmanaged(u8) = .{};
            errdefer result.deinit(allocator);

            const max_y = @min(region.y + region.height, self.current_buf.height);
            const max_x = @min(region.x + region.width, self.current_buf.width);

            var y = region.y;
            while (y < max_y) : (y += 1) {
                if (y > region.y) {
                    try result.append(allocator, '\n');
                }
                var x = region.x;
                while (x < max_x) : (x += 1) {
                    const cell = self.current_buf.get(x, y);
                    if (cell.width == 0) continue;
                    var char_buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(cell.char, &char_buf) catch 1;
                    try result.appendSlice(allocator, char_buf[0..len]);
                }
            }

            return result.toOwnedSlice(allocator);
        }

        // -- Snapshot --

        pub fn snapshot(self: Self, allocator: std.mem.Allocator) !Snapshot {
            return Snapshot.fromBuffer(allocator, self.current_buf);
        }

        pub fn expectSnapshot(self: Self, expected: []const u8) !void {
            var snap = try Snapshot.fromBuffer(self.allocator, self.current_buf);
            defer snap.deinit();
            if (!snap.matches(expected)) {
                var expected_snap = try Snapshot.fromText(self.allocator, expected, self.current_buf.width, self.current_buf.height);
                defer expected_snap.deinit();
                const diff_text = try expected_snap.diff(self.allocator, snap);
                defer self.allocator.free(diff_text);
                std.debug.print("SNAPSHOT MISMATCH:\n{s}\n", .{diff_text});
                return error.TestExpectedEqual;
            }
        }

        // -- Golden file operations --

        pub fn saveSnapshot(self: Self, path: []const u8) !void {
            var snap = try Snapshot.fromBuffer(self.allocator, self.current_buf);
            defer snap.deinit();
            try snap.saveToFile(path);
        }

        pub fn expectSnapshotFile(self: Self, path: []const u8) !void {
            var snap = try Snapshot.fromBuffer(self.allocator, self.current_buf);
            defer snap.deinit();
            try snap.expectMatchesFile(self.allocator, path);
        }
    };
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

// ============================================================
// TEST HARNESS TESTS
// ============================================================

const HarnessTestHelpers = struct {
    const CounterState = struct {
        count: i32 = 0,
        last_key: ?u21 = null,
        last_mouse_x: ?u16 = null,
        last_mouse_y: ?u16 = null,
        ticks: u32 = 0,
        width: u16 = 0,
        height: u16 = 0,
        quit_requested: bool = false,
    };

    const Action = @import("action.zig").Action;
    const FrameType = @import("frame.zig").Frame(64);

    fn counterUpdate(state: *CounterState, ev: Event) Action {
        switch (ev) {
            .key => |key| {
                switch (key.code) {
                    .char => |c| {
                        state.last_key = c;
                        if (c == 'q') {
                            state.quit_requested = true;
                            return Action{ .quit = {} };
                        }
                        if (c == '+') state.count += 1;
                        if (c == '-') state.count -= 1;
                    },
                    else => {},
                }
            },
            .mouse => |mouse| {
                state.last_mouse_x = mouse.x;
                state.last_mouse_y = mouse.y;
            },
            .tick => {
                state.ticks += 1;
            },
            .resize => |size| {
                state.width = size.width;
                state.height = size.height;
            },
            else => {},
        }
        return Action{ .none = {} };
    }

    fn counterView(state: *CounterState, frame: *FrameType) void {
        var count_buf: [32]u8 = undefined;
        const count_str = std.fmt.bufPrint(&count_buf, "Count: {d}", .{state.count}) catch "?";
        frame.buffer.setString(0, 0, count_str, Style.empty);

        if (state.last_key) |k| {
            var key_buf: [16]u8 = undefined;
            const key_str = std.fmt.bufPrint(&key_buf, "Key: {c}", .{@as(u8, @intCast(k & 0x7f))}) catch "?";
            frame.buffer.setString(0, 1, key_str, Style.empty);
        }
    }

    fn styledView(state: *CounterState, frame: *FrameType) void {
        _ = state;
        frame.buffer.setString(0, 0, "Bold", Style.init().bold());
        frame.buffer.setString(0, 1, "Normal", Style.empty);
    }
};

test "sanity: TestHarness init and deinit" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    try std.testing.expectEqual(@as(u64, 1), harness.frame_count);
    try std.testing.expectEqual(@as(u16, 40), harness.current_buf.width);
    try std.testing.expectEqual(@as(u16, 10), harness.current_buf.height);
}

test "sanity: TestHarness default dimensions" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
    });
    defer harness.deinit();

    try std.testing.expectEqual(@as(u16, 80), harness.current_buf.width);
    try std.testing.expectEqual(@as(u16, 24), harness.current_buf.height);
}

test "behavior: TestHarness pressKey updates state" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.pressKey('+');
    try std.testing.expectEqual(@as(i32, 1), state.count);
    try std.testing.expectEqual(@as(?u21, '+'), state.last_key);

    harness.pressKey('+');
    harness.pressKey('+');
    try std.testing.expectEqual(@as(i32, 3), state.count);
}

test "behavior: TestHarness expectString checks buffer content" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    try harness.expectString(0, 0, "Count: 0");

    harness.pressKey('+');
    try harness.expectString(0, 0, "Count: 1");

    harness.pressKey('-');
    try harness.expectString(0, 0, "Count: 0");
}

test "behavior: TestHarness expectCell checks individual cells" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    try harness.expectCell(0, 0, 'C');
    try harness.expectCell(1, 0, 'o');
    try harness.expectCell(2, 0, 'u');
    try harness.expectCell(3, 0, 'n');
    try harness.expectCell(4, 0, 't');
}

test "behavior: TestHarness expectAction checks last action" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.pressKey('+');
    try harness.expectAction(.{ .none = {} });
}

test "behavior: TestHarness expectQuit checks quit action" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.pressKey('q');
    try harness.expectQuit();
    try std.testing.expect(state.quit_requested);
}

test "behavior: TestHarness click generates down+up events" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.click(15, 7);
    try std.testing.expectEqual(@as(?u16, 15), state.last_mouse_x);
    try std.testing.expectEqual(@as(?u16, 7), state.last_mouse_y);
}

test "behavior: TestHarness tick advances tick count" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    const initial_frame = harness.frame_count;
    harness.tick();
    try std.testing.expectEqual(@as(u32, 1), state.ticks);
    try std.testing.expectEqual(initial_frame + 1, harness.frame_count);
}

test "behavior: TestHarness tickN advances multiple frames" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    const initial_frame = harness.frame_count;
    harness.tickN(5);
    try std.testing.expectEqual(@as(u32, 5), state.ticks);
    try std.testing.expectEqual(initial_frame + 5, harness.frame_count);
}

test "behavior: TestHarness resize reallocates buffers" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    try harness.resize(120, 40);
    try std.testing.expectEqual(@as(u16, 120), harness.current_buf.width);
    try std.testing.expectEqual(@as(u16, 40), harness.current_buf.height);
    try std.testing.expectEqual(@as(u16, 120), state.width);
    try std.testing.expectEqual(@as(u16, 40), state.height);
}

test "behavior: TestHarness inject allows raw events" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.inject(tickEvent());
    try std.testing.expectEqual(@as(u32, 1), state.ticks);
}

test "behavior: TestHarness drag generates down/move/up sequence" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.drag(5, 5, 20, 15);
    try std.testing.expectEqual(@as(?u16, 20), state.last_mouse_x);
    try std.testing.expectEqual(@as(?u16, 15), state.last_mouse_y);
}

test "behavior: TestHarness hover generates move event" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.hover(12, 8);
    try std.testing.expectEqual(@as(?u16, 12), state.last_mouse_x);
    try std.testing.expectEqual(@as(?u16, 8), state.last_mouse_y);
}

test "behavior: TestHarness scroll generates scroll events" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.scroll(10, 5, .scroll_up);
    try std.testing.expectEqual(@as(?u16, 10), state.last_mouse_x);
    try std.testing.expectEqual(@as(?u16, 5), state.last_mouse_y);
}

test "behavior: TestHarness expectStyle checks style attributes" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.styledView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    try harness.expectStyle(0, 0, .bold);
}

test "behavior: TestHarness expectEmpty on default cell" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    try harness.expectEmpty(39, 9);
}

test "behavior: TestHarness getCell returns cell" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    const cell = harness.getCell(0, 0);
    try std.testing.expectEqual(@as(u21, 'C'), cell.char);
}

test "behavior: TestHarness getText returns full buffer text" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    const text = try harness.getText(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Count: 0") != null);
}

test "behavior: TestHarness getRow returns single row" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    const row = try harness.getRow(std.testing.allocator, 0);
    defer std.testing.allocator.free(row);
    try std.testing.expect(std.mem.startsWith(u8, row, "Count: 0"));
}

test "behavior: TestHarness getRow out of bounds returns empty" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    const row = try harness.getRow(std.testing.allocator, 100);
    defer std.testing.allocator.free(row);
    try std.testing.expectEqualStrings("", row);
}

test "behavior: TestHarness snapshot creates Snapshot" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    var snap = try harness.snapshot(std.testing.allocator);
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 40), snap.width);
    try std.testing.expectEqual(@as(u16, 10), snap.height);
    try std.testing.expect(std.mem.indexOf(u8, snap.text, "Count: 0") != null);
}

test "behavior: TestHarness expectSnapshot inline comparison" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 10,
        .height = 1,
    });
    defer harness.deinit();

    try harness.expectSnapshot("Count: 0  ");
}

test "behavior: TestHarness pressSpecial sends special key" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.pressSpecial(.{ .enter = {} });
    try harness.expectAction(.{ .none = {} });
}

test "behavior: TestHarness pressKeyWith sends key with modifiers" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    harness.pressKeyWith(.{ .char = 'c' }, .{ .ctrl = true });
    try harness.expectAction(.{ .none = {} });
}

test "behavior: TestHarness getBuffer returns buffer reference" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    const buf = harness.getBuffer();
    try std.testing.expectEqual(@as(u16, 40), buf.width);
    try std.testing.expectEqual(@as(u16, 10), buf.height);
}

test "regression: TestHarness re-renders after each event" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    try harness.expectString(0, 0, "Count: 0");
    harness.pressKey('+');
    try harness.expectString(0, 0, "Count: 1");
    harness.pressKey('+');
    try harness.expectString(0, 0, "Count: 2");

    const expected_frames = 1 + 2; // initial + 2 key presses
    try std.testing.expectEqual(@as(u64, expected_frames), harness.frame_count);
}

test "regression: TestHarness initial render populates buffer" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    try harness.expectString(0, 0, "Count: 0");
    try std.testing.expectEqual(@as(u64, 1), harness.frame_count);
}

test "behavior: TestHarness getRegion extracts rectangular region" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    const region = try harness.getRegion(std.testing.allocator, Rect{ .x = 0, .y = 0, .width = 8, .height = 1 });
    defer std.testing.allocator.free(region);
    try std.testing.expectEqualStrings("Count: 0", region);
}

test "behavior: TestHarness getRegion clamps to buffer bounds" {
    var state = HarnessTestHelpers.CounterState{};
    var harness = try TestHarness(HarnessTestHelpers.CounterState).init(std.testing.allocator, .{
        .state = &state,
        .update = HarnessTestHelpers.counterUpdate,
        .view = HarnessTestHelpers.counterView,
        .width = 10,
        .height = 2,
    });
    defer harness.deinit();

    const region = try harness.getRegion(std.testing.allocator, Rect{ .x = 5, .y = 0, .width = 100, .height = 100 });
    defer std.testing.allocator.free(region);
    try std.testing.expect(region.len > 0);
}

// ============================================================
// SNAPSHOT FILE I/O TESTS
// ============================================================

test "behavior: Snapshot saveToFile and loadFromFile roundtrip" {
    var buf = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf.deinit();
    buf.setString(0, 0, "Hello", Style.empty);
    buf.setString(0, 1, "World", Style.empty);

    var snap1 = try Snapshot.fromBuffer(std.testing.allocator, buf);
    defer snap1.deinit();

    const path = "/tmp/zithril_test_roundtrip.golden";
    try snap1.saveToFile(path);

    var snap2 = try Snapshot.loadFromFile(std.testing.allocator, path);
    defer snap2.deinit();

    try std.testing.expect(snap1.eql(snap2));
    try std.testing.expectEqual(@as(u16, 10), snap2.width);
    try std.testing.expectEqual(@as(u16, 2), snap2.height);

    // Clean up
    std.fs.cwd().deleteFile(path) catch {};
}

test "behavior: Snapshot diff output format" {
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
    try std.testing.expect(std.mem.indexOf(u8, diff_text, "Expected:") != null);
    try std.testing.expect(std.mem.indexOf(u8, diff_text, "Actual:") != null);
}
