// Terminal backend for zithril TUI framework
// Handles raw mode, alternate screen, cursor control, mouse, and bracketed paste

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

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
    /// Safe to call multiple times.
    pub fn deinit(self: *Backend) void {
        if (!self.active) return;

        if (self.config.bracketed_paste) {
            self.writeEscape(DISABLE_BRACKETED_PASTE);
        }

        if (self.config.mouse_capture) {
            self.disableMouse();
        }

        if (self.config.hide_cursor) {
            self.writeEscape(SHOW_CURSOR);
        }

        if (self.config.alternate_screen) {
            self.writeEscape(LEAVE_ALTERNATE_SCREEN);
        }

        self.exitRawMode();
        self.active = false;
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
    pub fn getSize(self: *Backend) struct { width: u16, height: u16 } {
        var ws: posix.winsize = undefined;
        const result = posix.system.ioctl(self.fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (result == 0) {
            return .{ .width = ws.col, .height = ws.row };
        }
        return .{ .width = 80, .height = 24 };
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
