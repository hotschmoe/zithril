// Terminal backend for zithril TUI framework
// Handles raw mode, alternate screen, cursor control, mouse, and bracketed paste
// Provides buffered output with rich_zig integration for ANSI rendering
// Includes panic handler to ensure terminal cleanup on abnormal exit

const std = @import("std");
const posix = std.posix;
const rich_zig = @import("rich_zig");
const style_mod = @import("style.zig");
pub const Style = style_mod.Style;
pub const Color = style_mod.Color;
pub const ColorSystem = style_mod.ColorSystem;
pub const Segment = style_mod.Segment;
pub const ControlCode = style_mod.ControlCode;

/// Global pointer to the active backend for panic/signal cleanup.
/// Only one backend can be active at a time (standard for TUI apps).
var global_backend: ?*Backend = null;

/// Global storage for original termios when using emergency cleanup.
var emergency_original_termios: ?posix.termios = null;
var emergency_config: ?BackendConfig = null;

/// Perform emergency terminal cleanup.
/// Called from panic handler and signal handlers.
/// Writes cleanup sequences directly to fd without checking state,
/// as the Backend state may be corrupted during panic.
fn emergencyCleanup() void {
    const fd = posix.STDOUT_FILENO;
    const file = std.fs.File{ .handle = fd };

    // Restore terminal based on saved config
    if (emergency_config) |config| {
        if (config.bracketed_paste) {
            file.writeAll("\x1b[?2004l") catch {};
        }
        if (config.mouse_capture) {
            file.writeAll("\x1b[?1006l") catch {};
            file.writeAll("\x1b[?1003l\x1b[?1002l\x1b[?1000l") catch {};
        }
        if (config.hide_cursor) {
            file.writeAll("\x1b[?25h") catch {};
        }
        if (config.alternate_screen) {
            file.writeAll("\x1b[?1049l") catch {};
        }
    }

    // Restore termios
    if (emergency_original_termios) |original| {
        posix.tcsetattr(fd, .FLUSH, original) catch {};
    }

    // Clear global state
    global_backend = null;
    emergency_original_termios = null;
    emergency_config = null;
}

/// Panic handler namespace for terminal cleanup.
/// Applications can use this by adding to their root source file:
///   pub const panic = @import("zithril").backend_mod.panic;
/// This ensures terminal state is restored before panic output is displayed.
pub const panic = struct {
    /// Core panic function called by @panic and runtime safety checks.
    pub fn call(msg: []const u8, ret_addr: ?usize) noreturn {
        @branchHint(.cold);
        // Perform cleanup first so panic message is visible
        emergencyCleanup();

        // Use standard panic behavior
        _ = ret_addr;
        std.debug.lockStdErr();
        const stderr = std.io.getStdErr();
        stderr.writeAll(msg) catch {};
        stderr.writeAll("\n") catch {};
        @trap();
    }

    pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
        _ = found;
        call("sentinel mismatch", null);
    }

    pub fn unwrapError(err: anyerror) noreturn {
        _ = &err;
        call("attempt to unwrap error", null);
    }

    pub fn outOfBounds(index: usize, len: usize) noreturn {
        _ = index;
        _ = len;
        call("index out of bounds", null);
    }

    pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
        _ = start;
        _ = end;
        call("start index is larger than end index", null);
    }

    pub fn inactiveUnionField(active: anytype, accessed: @TypeOf(active)) noreturn {
        _ = accessed;
        call("access of inactive union field", null);
    }

    pub fn sliceCastLenRemainder(src_len: usize) noreturn {
        _ = src_len;
        call("slice cast has len remainder", null);
    }

    pub fn castToNull(value: anytype) noreturn {
        _ = value;
        call("cast to null", null);
    }

    pub fn reachedUnreachable() noreturn {
        call("reached unreachable code", null);
    }

    pub fn unwrapNull() noreturn {
        call("unwrap of null optional", null);
    }

    pub fn signedOverflow(a: anytype, b: anytype) noreturn {
        _ = a;
        _ = b;
        call("signed integer overflow", null);
    }

    pub fn unsignedOverflow(a: anytype, b: anytype) noreturn {
        _ = a;
        _ = b;
        call("unsigned integer overflow", null);
    }

    pub fn exactDivisionRemainder(numerator: anytype, denominator: anytype) noreturn {
        _ = numerator;
        _ = denominator;
        call("exact division has remainder", null);
    }

    pub fn divisionByZero(numerator: anytype) noreturn {
        _ = numerator;
        call("division by zero", null);
    }

    pub fn negativeShiftCount(count: anytype) noreturn {
        _ = count;
        call("negative shift count", null);
    }

    pub fn shiftOverflow(a: anytype, b: anytype) noreturn {
        _ = a;
        _ = b;
        call("shift overflow", null);
    }

    pub fn memcpyDestOverlap() noreturn {
        call("memcpy dest overlaps src", null);
    }

    pub fn intToEnumOverflow() noreturn {
        call("int to enum overflow", null);
    }

    pub fn intToFloatOverflow(value: anytype) noreturn {
        _ = value;
        call("int to float overflow", null);
    }

    pub fn floatToIntOverflow(value: anytype) noreturn {
        _ = value;
        call("float to int overflow", null);
    }

    pub fn invalidEnumCast(value: anytype) noreturn {
        _ = value;
        call("invalid enum cast", null);
    }

    pub fn noReturn() noreturn {
        call("noreturn function returned", null);
    }
};

/// Color support levels detected from terminal capabilities.
pub const ColorSupport = enum {
    /// Basic 8/16 colors (standard ANSI).
    basic,
    /// 256 color palette (xterm-256color).
    extended,
    /// 24-bit true color (RGB).
    true_color,

    /// Returns the number of colors supported.
    pub fn colorCount(self: ColorSupport) u32 {
        return switch (self) {
            .basic => 16,
            .extended => 256,
            .true_color => 16_777_216,
        };
    }

    /// Returns true if this support level includes the given level.
    pub fn supports(self: ColorSupport, level: ColorSupport) bool {
        return @intFromEnum(self) >= @intFromEnum(level);
    }
};

/// Terminal size in cells.
pub const TerminalSize = struct {
    width: u16,
    height: u16,
};

/// Configuration options for terminal initialization.
pub const BackendConfig = struct {
    /// Enter alternate screen buffer (preserves original terminal content).
    alternate_screen: bool = true,
    /// Hide cursor during TUI operation.
    hide_cursor: bool = true,
    /// Enable mouse event reporting.
    mouse_capture: bool = false,
    /// Enable bracketed paste mode (distinguish pasted text from typed).
    bracketed_paste: bool = false,
};

/// Terminal backend state.
/// Manages raw mode, alternate screen, and other terminal features.
/// RAII pattern: deinit() restores terminal to original state.
pub const Backend = struct {
    /// File descriptor for terminal output (typically stdout).
    fd: posix.fd_t,
    /// Original terminal settings, saved for restoration.
    original_termios: ?posix.termios,
    /// Configuration used during initialization.
    config: BackendConfig,
    /// Whether the backend is currently active.
    active: bool,

    /// Error type for backend operations.
    pub const Error = error{
        NotATty,
        TerminalQueryFailed,
        TerminalSetFailed,
        IoError,
    };

    /// Initialize the terminal backend.
    /// Enables raw mode and optional features based on config.
    /// Registers panic handler to ensure cleanup on abnormal exit.
    /// Returns error if stdout is not a TTY or terminal ops fail.
    pub fn init(config: BackendConfig) Error!Backend {
        const fd = posix.STDOUT_FILENO;

        if (!posix.isatty(fd)) {
            return Error.NotATty;
        }

        var self = Backend{
            .fd = fd,
            .original_termios = null,
            .config = config,
            .active = false,
        };

        try self.enterRawMode();
        self.active = true;

        // Store state for emergency cleanup
        emergency_original_termios = self.original_termios;
        emergency_config = config;
        global_backend = &self;

        if (config.alternate_screen) {
            self.writeEscape(ENTER_ALTERNATE_SCREEN);
        }

        if (config.hide_cursor) {
            self.writeEscape(HIDE_CURSOR);
        }

        if (config.mouse_capture) {
            self.enableMouse();
        }

        if (config.bracketed_paste) {
            self.writeEscape(ENABLE_BRACKETED_PASTE);
        }

        return self;
    }

    /// Restore terminal to original state.
    /// Disables bracketed paste, mouse capture, shows cursor, leaves alternate screen,
    /// and restores raw mode settings.
    /// Safe to call multiple times.
    pub fn deinit(self: *Backend) void {
        if (!self.active) return;

        // Disable bracketed paste
        if (self.config.bracketed_paste) {
            self.writeEscape(DISABLE_BRACKETED_PASTE);
        }

        // Disable mouse capture
        if (self.config.mouse_capture) {
            self.disableMouse();
        }

        // Show cursor
        if (self.config.hide_cursor) {
            self.writeEscape(SHOW_CURSOR);
        }

        // Leave alternate screen
        if (self.config.alternate_screen) {
            self.writeEscape(LEAVE_ALTERNATE_SCREEN);
        }

        // Restore raw mode (disable raw mode)
        self.exitRawMode();
        self.active = false;

        // Clear global state for panic handler
        if (global_backend == self) {
            global_backend = null;
            emergency_original_termios = null;
            emergency_config = null;
        }
    }

    /// Enter raw mode: disable line buffering, echo, and canonical mode.
    fn enterRawMode(self: *Backend) Error!void {
        const original = posix.tcgetattr(self.fd) catch {
            return Error.TerminalQueryFailed;
        };
        self.original_termios = original;

        var raw = original;

        // Input flags: disable break handling, CR-to-NL, parity, strip, flow control
        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;

        // Output flags: disable post-processing
        raw.oflag.OPOST = false;

        // Control flags: set character size to 8 bits
        raw.cflag.CSIZE = .CS8;

        // Local flags: disable echo, canonical mode, signals, extended input
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        // Set minimum chars for non-canonical read
        raw.cc[@intFromEnum(posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(posix.V.TIME)] = 1;

        posix.tcsetattr(self.fd, .FLUSH, raw) catch {
            return Error.TerminalSetFailed;
        };
    }

    /// Exit raw mode: restore original terminal settings.
    fn exitRawMode(self: *Backend) void {
        if (self.original_termios) |original| {
            posix.tcsetattr(self.fd, .FLUSH, original) catch {};
        }
    }

    /// Enable mouse reporting (SGR mode for better coordinate handling).
    fn enableMouse(self: *Backend) void {
        self.writeEscape(ENABLE_MOUSE_CAPTURE);
        self.writeEscape(ENABLE_MOUSE_SGR);
    }

    /// Disable mouse reporting.
    fn disableMouse(self: *Backend) void {
        self.writeEscape(DISABLE_MOUSE_SGR);
        self.writeEscape(DISABLE_MOUSE_CAPTURE);
    }

    /// Write an escape sequence to the terminal.
    fn writeEscape(self: *Backend, seq: []const u8) void {
        const file = std.fs.File{ .handle = self.fd };
        file.writeAll(seq) catch {};
    }

    /// Flush output to terminal.
    pub fn flush(self: *Backend) void {
        const file = std.fs.File{ .handle = self.fd };
        file.sync() catch {};
    }

    /// Write bytes to the terminal.
    pub fn write(self: *Backend, data: []const u8) Error!void {
        const file = std.fs.File{ .handle = self.fd };
        file.writeAll(data) catch {
            return Error.IoError;
        };
    }

    /// Move cursor to home position (0, 0).
    pub fn cursorHome(self: *Backend) void {
        self.writeEscape(CURSOR_HOME);
    }

    /// Move cursor to specific position (0-indexed).
    pub fn cursorTo(self: *Backend, x: u16, y: u16) void {
        var buf: [32]u8 = undefined;
        const seq = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y + 1, x + 1 }) catch return;
        self.writeEscape(seq);
    }

    /// Clear the entire screen.
    pub fn clearScreen(self: *Backend) void {
        self.writeEscape(CLEAR_SCREEN);
    }

    /// Get terminal size (width, height).
    pub fn getSize(self: *Backend) TerminalSize {
        return getSizeForFd(self.fd);
    }

    /// Detect terminal color support level.
    /// Checks environment variables COLORTERM and TERM to determine capability.
    /// Returns the highest detected color support level.
    pub fn getColorSupport(_: *Backend) ColorSupport {
        return detectColorSupport();
    }

    // ANSI escape sequences
    const ENTER_ALTERNATE_SCREEN = "\x1b[?1049h";
    const LEAVE_ALTERNATE_SCREEN = "\x1b[?1049l";
    const HIDE_CURSOR = "\x1b[?25l";
    const SHOW_CURSOR = "\x1b[?25h";
    const CLEAR_SCREEN = "\x1b[2J";
    const CURSOR_HOME = "\x1b[H";

    const ENABLE_MOUSE_CAPTURE = "\x1b[?1000h\x1b[?1002h\x1b[?1003h";
    const DISABLE_MOUSE_CAPTURE = "\x1b[?1003l\x1b[?1002l\x1b[?1000l";
    const ENABLE_MOUSE_SGR = "\x1b[?1006h";
    const DISABLE_MOUSE_SGR = "\x1b[?1006l";

    const ENABLE_BRACKETED_PASTE = "\x1b[?2004h";
    const DISABLE_BRACKETED_PASTE = "\x1b[?2004l";
};

/// Detect terminal color support from environment variables.
/// This is a standalone function that doesn't require a Backend instance.
/// Checks COLORTERM and TERM environment variables to determine capability.
pub fn detectColorSupport() ColorSupport {
    // Check COLORTERM first - most reliable indicator of true color
    if (std.posix.getenv("COLORTERM")) |colorterm| {
        if (std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit")) {
            return .true_color;
        }
    }

    // Check TERM for terminal type hints
    if (std.posix.getenv("TERM")) |term| {
        // True color indicators in TERM
        if (std.mem.indexOf(u8, term, "truecolor") != null or
            std.mem.indexOf(u8, term, "24bit") != null or
            std.mem.indexOf(u8, term, "direct") != null)
        {
            return .true_color;
        }

        // 256 color indicators
        if (std.mem.indexOf(u8, term, "256color") != null or
            std.mem.indexOf(u8, term, "256") != null)
        {
            return .extended;
        }

        // Known modern terminals that support true color
        if (std.mem.startsWith(u8, term, "xterm") or
            std.mem.startsWith(u8, term, "screen") or
            std.mem.startsWith(u8, term, "tmux") or
            std.mem.startsWith(u8, term, "vte") or
            std.mem.startsWith(u8, term, "gnome") or
            std.mem.startsWith(u8, term, "konsole") or
            std.mem.startsWith(u8, term, "alacritty") or
            std.mem.startsWith(u8, term, "kitty") or
            std.mem.startsWith(u8, term, "iterm"))
        {
            // These terminals typically support at least 256 colors
            // Many support true color but we're conservative
            return .extended;
        }
    }

    // Default to basic 16-color support
    return .basic;
}

/// Internal: get terminal size for a specific file descriptor.
fn getSizeForFd(fd: posix.fd_t) TerminalSize {
    var ws: posix.winsize = undefined;
    const result = posix.system.ioctl(fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (result == 0) {
        return .{ .width = ws.col, .height = ws.row };
    }
    return .{ .width = 80, .height = 24 };
}

/// Get terminal size without requiring a Backend instance.
/// Useful for initial configuration before Backend initialization.
/// Returns default 80x24 if size cannot be determined.
pub fn getTerminalSize() TerminalSize {
    return getSizeForFd(posix.STDOUT_FILENO);
}

/// Buffered terminal output with rich_zig integration.
/// Accumulates output in a buffer and flushes to the terminal efficiently.
/// Provides cursor positioning, clearing, and styled text output.
pub fn Output(comptime buffer_size: usize) type {
    return struct {
        const Self = @This();

        /// Internal buffer for accumulating output.
        buffer: [buffer_size]u8 = undefined,
        /// Current position in the buffer.
        pos: usize = 0,
        /// File descriptor for output.
        fd: posix.fd_t,
        /// Detected color system for ANSI rendering.
        color_system: ColorSystem,
        /// Last style written (for optimization).
        last_style: ?Style = null,

        /// Initialize output with detected color support.
        pub fn init(fd: posix.fd_t) Self {
            return .{
                .fd = fd,
                .color_system = colorSupportToSystem(detectColorSupport()),
            };
        }

        /// Initialize output with explicit color system.
        pub fn initWithColorSystem(fd: posix.fd_t, color_system: ColorSystem) Self {
            return .{
                .fd = fd,
                .color_system = color_system,
            };
        }

        /// Write raw bytes to the buffer.
        pub fn writeRaw(self: *Self, data: []const u8) void {
            for (data) |byte| {
                if (self.pos < buffer_size) {
                    self.buffer[self.pos] = byte;
                    self.pos += 1;
                } else {
                    self.flushInternal();
                    if (self.pos < buffer_size) {
                        self.buffer[self.pos] = byte;
                        self.pos += 1;
                    }
                }
            }
        }

        /// Write a single byte to the buffer.
        pub fn writeByte(self: *Self, byte: u8) void {
            if (self.pos < buffer_size) {
                self.buffer[self.pos] = byte;
                self.pos += 1;
            } else {
                self.flushInternal();
                if (self.pos < buffer_size) {
                    self.buffer[self.pos] = byte;
                    self.pos += 1;
                }
            }
        }

        /// Get a writer interface for use with std.fmt.
        pub fn writer(self: *Self) std.io.GenericWriter(*Self, error{}, writeFn) {
            return .{ .context = self };
        }

        fn writeFn(self: *Self, data: []const u8) error{}!usize {
            self.writeRaw(data);
            return data.len;
        }

        /// Move cursor to home position (0, 0).
        pub fn cursorHome(self: *Self) void {
            self.writeRaw("\x1b[H");
        }

        /// Move cursor to specific position (0-indexed).
        pub fn cursorTo(self: *Self, x: u16, y: u16) void {
            var buf: [32]u8 = undefined;
            const seq = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y + 1, x + 1 }) catch return;
            self.writeRaw(seq);
        }

        /// Move cursor up by n rows.
        pub fn cursorUp(self: *Self, n: u16) void {
            if (n == 0) return;
            var buf: [16]u8 = undefined;
            const seq = std.fmt.bufPrint(&buf, "\x1b[{d}A", .{n}) catch return;
            self.writeRaw(seq);
        }

        /// Move cursor down by n rows.
        pub fn cursorDown(self: *Self, n: u16) void {
            if (n == 0) return;
            var buf: [16]u8 = undefined;
            const seq = std.fmt.bufPrint(&buf, "\x1b[{d}B", .{n}) catch return;
            self.writeRaw(seq);
        }

        /// Move cursor forward by n columns.
        pub fn cursorForward(self: *Self, n: u16) void {
            if (n == 0) return;
            var buf: [16]u8 = undefined;
            const seq = std.fmt.bufPrint(&buf, "\x1b[{d}C", .{n}) catch return;
            self.writeRaw(seq);
        }

        /// Move cursor backward by n columns.
        pub fn cursorBackward(self: *Self, n: u16) void {
            if (n == 0) return;
            var buf: [16]u8 = undefined;
            const seq = std.fmt.bufPrint(&buf, "\x1b[{d}D", .{n}) catch return;
            self.writeRaw(seq);
        }

        /// Clear the entire screen.
        pub fn clearScreen(self: *Self) void {
            self.writeRaw("\x1b[2J");
        }

        /// Clear from cursor to end of screen.
        pub fn clearToEndOfScreen(self: *Self) void {
            self.writeRaw("\x1b[0J");
        }

        /// Clear from cursor to start of screen.
        pub fn clearToStartOfScreen(self: *Self) void {
            self.writeRaw("\x1b[1J");
        }

        /// Clear the current line.
        pub fn clearLine(self: *Self) void {
            self.writeRaw("\x1b[2K");
        }

        /// Clear from cursor to end of line.
        pub fn clearToEndOfLine(self: *Self) void {
            self.writeRaw("\x1b[0K");
        }

        /// Clear from cursor to start of line.
        pub fn clearToStartOfLine(self: *Self) void {
            self.writeRaw("\x1b[1K");
        }

        /// Show the cursor.
        pub fn showCursor(self: *Self) void {
            self.writeRaw("\x1b[?25h");
        }

        /// Hide the cursor.
        pub fn hideCursor(self: *Self) void {
            self.writeRaw("\x1b[?25l");
        }

        /// Set the text style using rich_zig ANSI rendering.
        pub fn setStyle(self: *Self, style: Style) void {
            // Skip if same as last style
            if (self.last_style) |last| {
                if (last.eql(style)) return;
            }

            style.renderAnsi(self.color_system, self.writer()) catch {};
            self.last_style = style;
        }

        /// Reset to default style.
        pub fn resetStyle(self: *Self) void {
            self.writeRaw("\x1b[0m");
            self.last_style = null;
        }

        /// Write styled text (sets style, writes text, does not reset).
        pub fn writeStyled(self: *Self, text: []const u8, style: Style) void {
            if (!style.isEmpty()) {
                self.setStyle(style);
            }
            self.writeRaw(text);
        }

        /// Write a character with the given style.
        pub fn writeChar(self: *Self, char: u21, style: Style) void {
            if (!style.isEmpty()) {
                self.setStyle(style);
            }
            var utf8_buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(char, &utf8_buf) catch 1;
            self.writeRaw(utf8_buf[0..len]);
        }

        /// Write a segment (styled text span from rich_zig).
        pub fn writeSegment(self: *Self, segment: Segment) void {
            segment.render(self.writer(), self.color_system) catch {};
        }

        /// Execute a control code.
        pub fn writeControl(self: *Self, control: ControlCode) void {
            control.toEscapeSequence(self.writer()) catch {};
        }

        /// Flush buffered output to the terminal.
        pub fn flush(self: *Self) void {
            self.flushInternal();
        }

        fn flushInternal(self: *Self) void {
            if (self.pos == 0) return;
            const file = std.fs.File{ .handle = self.fd };
            file.writeAll(self.buffer[0..self.pos]) catch {};
            self.pos = 0;
        }

        /// Get remaining buffer capacity.
        pub fn remaining(self: Self) usize {
            return buffer_size - self.pos;
        }

        /// Check if buffer is empty.
        pub fn isEmpty(self: Self) bool {
            return self.pos == 0;
        }
    };
}

/// Default output type with 8KB buffer.
pub const DefaultOutput = Output(8192);

/// Convert ColorSupport enum to rich_zig's ColorSystem.
pub fn colorSupportToSystem(support: ColorSupport) ColorSystem {
    return switch (support) {
        .basic => .standard,
        .extended => .eight_bit,
        .true_color => .truecolor,
    };
}

// ============================================================
// SANITY TESTS - Backend configuration
// ============================================================

test "sanity: BackendConfig defaults" {
    const config = BackendConfig{};
    try std.testing.expect(config.alternate_screen);
    try std.testing.expect(config.hide_cursor);
    try std.testing.expect(!config.mouse_capture);
    try std.testing.expect(!config.bracketed_paste);
}

test "sanity: BackendConfig custom" {
    const config = BackendConfig{
        .alternate_screen = false,
        .hide_cursor = false,
        .mouse_capture = true,
        .bracketed_paste = true,
    };
    try std.testing.expect(!config.alternate_screen);
    try std.testing.expect(!config.hide_cursor);
    try std.testing.expect(config.mouse_capture);
    try std.testing.expect(config.bracketed_paste);
}

// ============================================================
// BEHAVIOR TESTS - Escape sequences
// ============================================================

test "behavior: escape sequences are correct format" {
    try std.testing.expectEqualStrings("\x1b[?1049h", Backend.ENTER_ALTERNATE_SCREEN);
    try std.testing.expectEqualStrings("\x1b[?1049l", Backend.LEAVE_ALTERNATE_SCREEN);
    try std.testing.expectEqualStrings("\x1b[?25l", Backend.HIDE_CURSOR);
    try std.testing.expectEqualStrings("\x1b[?25h", Backend.SHOW_CURSOR);
    try std.testing.expectEqualStrings("\x1b[2J", Backend.CLEAR_SCREEN);
    try std.testing.expectEqualStrings("\x1b[H", Backend.CURSOR_HOME);
}

test "behavior: bracketed paste sequences are correct" {
    try std.testing.expectEqualStrings("\x1b[?2004h", Backend.ENABLE_BRACKETED_PASTE);
    try std.testing.expectEqualStrings("\x1b[?2004l", Backend.DISABLE_BRACKETED_PASTE);
}

test "behavior: mouse SGR sequences are correct" {
    try std.testing.expectEqualStrings("\x1b[?1006h", Backend.ENABLE_MOUSE_SGR);
    try std.testing.expectEqualStrings("\x1b[?1006l", Backend.DISABLE_MOUSE_SGR);
}

// ============================================================
// BEHAVIOR TESTS - Cleanup sequences
// ============================================================

test "behavior: cleanup sequences in deinit order" {
    // deinit should disable features in reverse order of init:
    // 1. Disable bracketed paste
    // 2. Disable mouse
    // 3. Show cursor
    // 4. Leave alternate screen
    // 5. Restore termios (raw mode)

    // Verify the escape sequences exist and are correct
    try std.testing.expectEqualStrings("\x1b[?2004l", Backend.DISABLE_BRACKETED_PASTE);
    try std.testing.expectEqualStrings("\x1b[?1006l", Backend.DISABLE_MOUSE_SGR);
    try std.testing.expectEqualStrings("\x1b[?1003l\x1b[?1002l\x1b[?1000l", Backend.DISABLE_MOUSE_CAPTURE);
    try std.testing.expectEqualStrings("\x1b[?25h", Backend.SHOW_CURSOR);
    try std.testing.expectEqualStrings("\x1b[?1049l", Backend.LEAVE_ALTERNATE_SCREEN);
}

// ============================================================
// SANITY TESTS - Global state for panic handler
// ============================================================

test "sanity: global_backend starts null" {
    try std.testing.expect(global_backend == null);
    try std.testing.expect(emergency_original_termios == null);
    try std.testing.expect(emergency_config == null);
}

test "sanity: emergencyCleanup handles null state" {
    // Should not crash when called with no backend registered
    emergencyCleanup();
    try std.testing.expect(global_backend == null);
}

test "sanity: panic namespace exists with call function" {
    // Verify the panic namespace has the correct structure
    try std.testing.expect(@hasDecl(panic, "call"));
    try std.testing.expect(@hasDecl(panic, "outOfBounds"));
    try std.testing.expect(@hasDecl(panic, "unwrapError"));
}

// ============================================================
// SANITY TESTS - Color support detection
// ============================================================

test "sanity: ColorSupport enum values" {
    try std.testing.expect(@intFromEnum(ColorSupport.basic) < @intFromEnum(ColorSupport.extended));
    try std.testing.expect(@intFromEnum(ColorSupport.extended) < @intFromEnum(ColorSupport.true_color));
}

test "sanity: ColorSupport.colorCount returns correct values" {
    try std.testing.expectEqual(@as(u32, 16), ColorSupport.basic.colorCount());
    try std.testing.expectEqual(@as(u32, 256), ColorSupport.extended.colorCount());
    try std.testing.expectEqual(@as(u32, 16_777_216), ColorSupport.true_color.colorCount());
}

test "sanity: ColorSupport.supports comparison" {
    // basic supports only basic
    try std.testing.expect(ColorSupport.basic.supports(.basic));
    try std.testing.expect(!ColorSupport.basic.supports(.extended));
    try std.testing.expect(!ColorSupport.basic.supports(.true_color));

    // extended supports basic and extended
    try std.testing.expect(ColorSupport.extended.supports(.basic));
    try std.testing.expect(ColorSupport.extended.supports(.extended));
    try std.testing.expect(!ColorSupport.extended.supports(.true_color));

    // true_color supports all
    try std.testing.expect(ColorSupport.true_color.supports(.basic));
    try std.testing.expect(ColorSupport.true_color.supports(.extended));
    try std.testing.expect(ColorSupport.true_color.supports(.true_color));
}

test "behavior: detectColorSupport returns valid enum" {
    // Just verify it returns one of the valid enum values without crashing
    const support = detectColorSupport();
    try std.testing.expect(support == .basic or support == .extended or support == .true_color);
}

test "behavior: getTerminalSize returns reasonable values" {
    // Just verify it returns values without crashing
    // In a non-TTY test environment, it returns default 80x24
    const size = getTerminalSize();
    try std.testing.expect(size.width > 0);
    try std.testing.expect(size.height > 0);
}

// ============================================================
// SANITY TESTS - Output buffering
// ============================================================

test "sanity: Output buffer initialization" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);
    try std.testing.expect(out.isEmpty());
    try std.testing.expectEqual(@as(usize, 256), out.remaining());
}

test "sanity: Output.writeRaw buffers data" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.writeRaw("Hello");
    try std.testing.expect(!out.isEmpty());
    try std.testing.expectEqual(@as(usize, 251), out.remaining());
}

test "sanity: Output.writeByte buffers single byte" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.writeByte('X');
    try std.testing.expectEqual(@as(usize, 255), out.remaining());
}

// ============================================================
// BEHAVIOR TESTS - Output cursor control
// ============================================================

test "behavior: Output.cursorHome writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.cursorHome();
    try std.testing.expectEqualStrings("\x1b[H", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorTo writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.cursorTo(5, 10);
    try std.testing.expectEqualStrings("\x1b[11;6H", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorUp writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.cursorUp(3);
    try std.testing.expectEqualStrings("\x1b[3A", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorDown writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.cursorDown(5);
    try std.testing.expectEqualStrings("\x1b[5B", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorForward writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.cursorForward(2);
    try std.testing.expectEqualStrings("\x1b[2C", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorBackward writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.cursorBackward(4);
    try std.testing.expectEqualStrings("\x1b[4D", out.buffer[0..out.pos]);
}

// ============================================================
// BEHAVIOR TESTS - Output screen clearing
// ============================================================

test "behavior: Output.clearScreen writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.clearScreen();
    try std.testing.expectEqualStrings("\x1b[2J", out.buffer[0..out.pos]);
}

test "behavior: Output.clearToEndOfScreen writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.clearToEndOfScreen();
    try std.testing.expectEqualStrings("\x1b[0J", out.buffer[0..out.pos]);
}

test "behavior: Output.clearLine writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.clearLine();
    try std.testing.expectEqualStrings("\x1b[2K", out.buffer[0..out.pos]);
}

test "behavior: Output.clearToEndOfLine writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.clearToEndOfLine();
    try std.testing.expectEqualStrings("\x1b[0K", out.buffer[0..out.pos]);
}

// ============================================================
// BEHAVIOR TESTS - Output cursor visibility
// ============================================================

test "behavior: Output.showCursor writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.showCursor();
    try std.testing.expectEqualStrings("\x1b[?25h", out.buffer[0..out.pos]);
}

test "behavior: Output.hideCursor writes correct sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.hideCursor();
    try std.testing.expectEqualStrings("\x1b[?25l", out.buffer[0..out.pos]);
}

// ============================================================
// BEHAVIOR TESTS - Output style rendering
// ============================================================

test "behavior: Output.setStyle uses rich_zig rendering" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    const style = Style.init().bold().fg(.red);
    out.setStyle(style);

    const written = out.buffer[0..out.pos];
    // Should contain ANSI escape sequence
    try std.testing.expect(written[0] == 0x1b);
    try std.testing.expect(written[1] == '[');
    try std.testing.expect(written[written.len - 1] == 'm');
}

test "behavior: Output.resetStyle writes reset sequence" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.resetStyle();
    try std.testing.expectEqualStrings("\x1b[0m", out.buffer[0..out.pos]);
}

test "behavior: Output.setStyle skips duplicate styles" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    const style = Style.init().bold();
    out.setStyle(style);
    const first_len = out.pos;

    out.setStyle(style);
    // Should not write anything new
    try std.testing.expectEqual(first_len, out.pos);
}

test "behavior: Output.writeStyled combines style and text" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    const style = Style.init().bold();
    out.writeStyled("Hello", style);

    const written = out.buffer[0..out.pos];
    // Should contain the text "Hello"
    try std.testing.expect(std.mem.indexOf(u8, written, "Hello") != null);
}

test "behavior: Output.writeChar writes styled character" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.writeChar('X', Style.empty);
    try std.testing.expectEqualStrings("X", out.buffer[0..out.pos]);
}

test "behavior: Output.writeChar handles UTF-8" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.writeChar(0x4E2D, Style.empty); // CJK character
    try std.testing.expectEqual(@as(usize, 3), out.pos); // 3-byte UTF-8
}

// ============================================================
// BEHAVIOR TESTS - ColorSupport to ColorSystem conversion
// ============================================================

test "behavior: colorSupportToSystem conversion" {
    try std.testing.expectEqual(ColorSystem.standard, colorSupportToSystem(.basic));
    try std.testing.expectEqual(ColorSystem.eight_bit, colorSupportToSystem(.extended));
    try std.testing.expectEqual(ColorSystem.truecolor, colorSupportToSystem(.true_color));
}

// ============================================================
// REGRESSION TESTS - Output edge cases
// ============================================================

test "regression: Output.cursorUp with zero does nothing" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.cursorUp(0);
    try std.testing.expect(out.isEmpty());
}

test "regression: Output.cursorDown with zero does nothing" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    out.cursorDown(0);
    try std.testing.expect(out.isEmpty());
}

test "regression: Output writer interface works with fmt" {
    const TestOutput = Output(256);
    var out = TestOutput.initWithColorSystem(posix.STDOUT_FILENO, .truecolor);

    const w = out.writer();
    try std.fmt.format(w, "Value: {d}", .{42});
    try std.testing.expectEqualStrings("Value: 42", out.buffer[0..out.pos]);
}
