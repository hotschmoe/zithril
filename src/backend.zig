// Terminal backend for zithril TUI framework
// Handles raw mode, alternate screen, cursor control, mouse, and bracketed paste
// Includes panic handler to ensure terminal cleanup on abnormal exit

const std = @import("std");
const posix = std.posix;

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
    pub fn getSize(self: *Backend) struct { width: u16, height: u16 } {
        var ws: posix.winsize = undefined;
        const result = posix.system.ioctl(self.fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
        if (result == 0) {
            return .{ .width = ws.col, .height = ws.row };
        }
        return .{ .width = 80, .height = 24 };
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

/// Get terminal size without requiring a Backend instance.
/// Useful for initial configuration before Backend initialization.
/// Returns default 80x24 if size cannot be determined.
pub fn getTerminalSize() struct { width: u16, height: u16 } {
    const fd = posix.STDOUT_FILENO;
    var ws: posix.winsize = undefined;
    const result = posix.system.ioctl(fd, posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (result == 0) {
        return .{ .width = ws.col, .height = ws.row };
    }
    return .{ .width = 80, .height = 24 };
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
