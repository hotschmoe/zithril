// Terminal backend for zithril TUI framework
// Handles raw mode, alternate screen, cursor control, mouse, and bracketed paste
// Provides buffered output with rich_zig integration for ANSI rendering
// Includes panic handler to ensure terminal cleanup on abnormal exit
//
// Platform support:
// - Linux/macOS/BSD: POSIX backend (termios, ioctl)
// - Windows: Windows Console API / Virtual Terminal Sequences

const std = @import("std");
const builtin = @import("builtin");
const rich_zig = @import("rich_zig");
const style_mod = @import("style.zig");
pub const Style = style_mod.Style;
pub const Color = style_mod.Color;
pub const ColorSystem = style_mod.ColorSystem;
pub const Segment = style_mod.Segment;
pub const ControlCode = style_mod.ControlCode;

// Platform-specific imports
const is_windows = builtin.os.tag == .windows;
const posix = if (is_windows) void else std.posix;
const windows = if (is_windows) std.os.windows else void;

// ============================================================
// CROSS-PLATFORM TYPES
// ============================================================

/// Terminal type detected at runtime.
/// Used to determine feature support and rendering quirks.
pub const TerminalType = enum {
    // Modern terminals with full feature support
    windows_terminal, // Windows Terminal (full VT support)
    iterm2, // iTerm2 (macOS)
    kitty, // Kitty terminal
    alacritty, // Alacritty
    wezterm, // WezTerm
    gnome_terminal, // GNOME Terminal / VTE-based
    konsole, // KDE Konsole

    // Common terminal emulators
    xterm, // XTerm and compatibles
    rxvt, // rxvt-unicode
    screen, // GNU Screen
    tmux, // tmux

    // Limited terminals
    linux_console, // Linux virtual console (limited)
    cmd_exe, // Windows cmd.exe (legacy, limited)
    conemu, // ConEmu (Windows)

    // Fallback
    unknown, // Unknown terminal

    /// Returns whether this terminal supports true color (24-bit RGB).
    pub fn supportsTrueColor(self: TerminalType) bool {
        return switch (self) {
            .windows_terminal,
            .iterm2,
            .kitty,
            .alacritty,
            .wezterm,
            .gnome_terminal,
            .konsole,
            .xterm,
            .tmux,
            .conemu,
            => true,
            .screen,
            .rxvt,
            .linux_console,
            .cmd_exe,
            .unknown,
            => false,
        };
    }

    /// Returns whether this terminal supports 256 colors.
    pub fn supports256Colors(self: TerminalType) bool {
        return switch (self) {
            .linux_console => false,
            .cmd_exe => false,
            else => true,
        };
    }

    /// Returns whether this terminal supports mouse events.
    pub fn supportsMouse(self: TerminalType) bool {
        return switch (self) {
            .linux_console => false,
            .cmd_exe => false,
            else => true,
        };
    }

    /// Returns whether this terminal supports SGR mouse mode.
    pub fn supportsSgrMouse(self: TerminalType) bool {
        return switch (self) {
            .linux_console, .cmd_exe, .unknown => false,
            else => true,
        };
    }

    /// Returns whether this terminal supports bracketed paste.
    pub fn supportsBracketedPaste(self: TerminalType) bool {
        return switch (self) {
            .linux_console, .cmd_exe => false,
            else => true,
        };
    }

    /// Returns whether this terminal supports alternate screen buffer.
    pub fn supportsAlternateScreen(self: TerminalType) bool {
        return switch (self) {
            .linux_console => false,
            else => true,
        };
    }

    /// Returns whether this terminal supports Unicode.
    pub fn supportsUnicode(self: TerminalType) bool {
        return switch (self) {
            .cmd_exe => false,
            .linux_console => true, // Depends on font, but generally yes
            else => true,
        };
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

/// Terminal capabilities detected at runtime.
/// Combines terminal type with feature support information.
pub const TerminalCapabilities = struct {
    terminal_type: TerminalType,
    color_support: ColorSupport,
    unicode: bool,
    mouse: bool,
    sgr_mouse: bool,
    bracketed_paste: bool,
    alternate_screen: bool,

    /// Create capabilities from detected terminal type.
    pub fn fromTerminalType(term_type: TerminalType, color: ColorSupport) TerminalCapabilities {
        return .{
            .terminal_type = term_type,
            .color_support = color,
            .unicode = term_type.supportsUnicode(),
            .mouse = term_type.supportsMouse(),
            .sgr_mouse = term_type.supportsSgrMouse(),
            .bracketed_paste = term_type.supportsBracketedPaste(),
            .alternate_screen = term_type.supportsAlternateScreen(),
        };
    }
};

// ============================================================
// GLOBAL STATE FOR PANIC HANDLER
// ============================================================

/// Global pointer to the active backend for panic/signal cleanup.
/// Only one backend can be active at a time (standard for TUI apps).
var global_backend: ?*Backend = null;

/// Global storage for original terminal state when using emergency cleanup.
var emergency_original_state: ?EmergencyState = null;
var emergency_config: ?BackendConfig = null;

const EmergencyState = if (is_windows) struct {
    input_mode: u32,
    output_mode: u32,
} else struct {
    termios: std.posix.termios,
};

/// Perform emergency terminal cleanup.
/// Called from panic handler and signal handlers.
/// Writes cleanup sequences directly to fd without checking state,
/// as the Backend state may be corrupted during panic.
fn emergencyCleanup() void {
    if (is_windows) {
        emergencyCleanupWindows();
    } else {
        emergencyCleanupPosix();
    }
}

fn emergencyCleanupPosix() void {
    const fd = std.posix.STDOUT_FILENO;
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
    if (emergency_original_state) |state| {
        std.posix.tcsetattr(fd, .FLUSH, state.termios) catch {};
    }

    // Clear global state
    global_backend = null;
    emergency_original_state = null;
    emergency_config = null;
}

fn emergencyCleanupWindows() void {
    if (!is_windows) return;

    const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch return;
    const stdin_handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch return;

    // Restore terminal based on saved config
    if (emergency_config) |config| {
        const file = std.fs.File{ .handle = stdout_handle };
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

    // Restore console modes
    if (emergency_original_state) |state| {
        _ = windows.kernel32.SetConsoleMode(stdin_handle, state.input_mode);
        _ = windows.kernel32.SetConsoleMode(stdout_handle, state.output_mode);
    }

    // Clear global state
    global_backend = null;
    emergency_original_state = null;
    emergency_config = null;
}

/// Panic handler namespace for terminal cleanup.
/// Applications can use this by adding to their root source file:
///   pub const panic = @import("zithril").backend_mod.panic;
/// This ensures terminal state is restored before panic output is displayed.
///
/// The panic namespace matches Zig 0.15's expected interface (std.debug.no_panic).
pub const panic = struct {
    /// Core panic function called by @panic and runtime safety checks.
    pub fn call(msg: []const u8, ret_addr: ?usize) noreturn {
        @branchHint(.cold);
        _ = ret_addr;

        // Perform cleanup first so panic message is visible
        emergencyCleanup();

        // Write error message directly to stderr
        if (is_windows) {
            const stderr_handle = windows.GetStdHandle(windows.STD_ERROR_HANDLE) catch @trap();
            const stderr = std.fs.File{ .handle = stderr_handle };
            stderr.writeAll(msg) catch {};
            stderr.writeAll("\n") catch {};
        } else {
            const stderr_fd = std.posix.STDERR_FILENO;
            const stderr = std.fs.File{ .handle = stderr_fd };
            stderr.writeAll(msg) catch {};
            stderr.writeAll("\n") catch {};
        }
        @trap();
    }

    pub fn sentinelMismatch(_: anytype, _: anytype) noreturn {
        @branchHint(.cold);
        call("sentinel mismatch", null);
    }

    pub fn unwrapError(_: anyerror) noreturn {
        @branchHint(.cold);
        call("attempt to unwrap error", null);
    }

    pub fn outOfBounds(_: usize, _: usize) noreturn {
        @branchHint(.cold);
        call("index out of bounds", null);
    }

    pub fn startGreaterThanEnd(_: usize, _: usize) noreturn {
        @branchHint(.cold);
        call("start index is larger than end index", null);
    }

    pub fn inactiveUnionField(_: anytype, _: anytype) noreturn {
        @branchHint(.cold);
        call("access of inactive union field", null);
    }

    pub fn sliceCastLenRemainder(_: usize) noreturn {
        @branchHint(.cold);
        call("slice cast has len remainder", null);
    }

    pub fn reachedUnreachable() noreturn {
        @branchHint(.cold);
        call("reached unreachable code", null);
    }

    pub fn unwrapNull() noreturn {
        @branchHint(.cold);
        call("unwrap of null optional", null);
    }

    pub fn castToNull() noreturn {
        @branchHint(.cold);
        call("cast to null", null);
    }

    pub fn incorrectAlignment() noreturn {
        @branchHint(.cold);
        call("incorrect alignment", null);
    }

    pub fn invalidErrorCode() noreturn {
        @branchHint(.cold);
        call("invalid error code", null);
    }

    pub fn integerOutOfBounds() noreturn {
        @branchHint(.cold);
        call("integer out of bounds", null);
    }

    pub fn integerOverflow() noreturn {
        @branchHint(.cold);
        call("integer overflow", null);
    }

    pub fn shlOverflow() noreturn {
        @branchHint(.cold);
        call("shift left overflow", null);
    }

    pub fn shrOverflow() noreturn {
        @branchHint(.cold);
        call("shift right overflow", null);
    }

    pub fn divideByZero() noreturn {
        @branchHint(.cold);
        call("division by zero", null);
    }

    pub fn exactDivisionRemainder() noreturn {
        @branchHint(.cold);
        call("exact division has remainder", null);
    }

    pub fn integerPartOutOfBounds() noreturn {
        @branchHint(.cold);
        call("integer part out of bounds", null);
    }

    pub fn corruptSwitch() noreturn {
        @branchHint(.cold);
        call("corrupt switch", null);
    }

    pub fn shiftRhsTooBig() noreturn {
        @branchHint(.cold);
        call("shift rhs too big", null);
    }

    pub fn invalidEnumValue() noreturn {
        @branchHint(.cold);
        call("invalid enum value", null);
    }

    pub fn forLenMismatch() noreturn {
        @branchHint(.cold);
        call("for loop length mismatch", null);
    }

    pub fn copyLenMismatch() noreturn {
        @branchHint(.cold);
        call("copy length mismatch", null);
    }

    pub fn memcpyAlias() noreturn {
        @branchHint(.cold);
        call("memcpy with overlapping memory", null);
    }

    pub fn noreturnReturned() noreturn {
        @branchHint(.cold);
        call("noreturn function returned", null);
    }
};

// ============================================================
// TERMINAL BACKEND
// ============================================================

/// Terminal backend state.
/// Manages raw mode, alternate screen, and other terminal features.
/// RAII pattern: deinit() restores terminal to original state.
pub const Backend = struct {
    /// File handle for terminal output.
    handle: std.fs.File.Handle,
    /// Original terminal state for restoration.
    original_state: ?OriginalState,
    /// Configuration used during initialization.
    config: BackendConfig,
    /// Whether the backend is currently active.
    active: bool,
    /// Detected terminal capabilities.
    capabilities: TerminalCapabilities,

    const OriginalState = if (is_windows) struct {
        input_mode: u32,
        output_mode: u32,
    } else struct {
        termios: std.posix.termios,
    };

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
        if (is_windows) {
            return initWindows(config);
        } else {
            return initPosix(config);
        }
    }

    fn initPosix(config: BackendConfig) Error!Backend {
        const fd = std.posix.STDOUT_FILENO;

        if (!std.posix.isatty(fd)) {
            return Error.NotATty;
        }

        // Detect terminal type and capabilities
        const term_type = detectTerminalType();
        const color_support = detectColorSupport();
        const caps = TerminalCapabilities.fromTerminalType(term_type, color_support);

        var self = Backend{
            .handle = fd,
            .original_state = null,
            .config = config,
            .active = false,
            .capabilities = caps,
        };

        try self.enterRawMode();
        self.active = true;

        // Store state for emergency cleanup
        if (self.original_state) |state| {
            emergency_original_state = .{ .termios = state.termios };
        }
        emergency_config = config;
        global_backend = &self;

        if (config.alternate_screen and caps.alternate_screen) {
            self.writeEscape(ENTER_ALTERNATE_SCREEN);
        }

        if (config.hide_cursor) {
            self.writeEscape(HIDE_CURSOR);
        }

        if (config.mouse_capture and caps.mouse) {
            self.enableMouse();
        }

        if (config.bracketed_paste and caps.bracketed_paste) {
            self.writeEscape(ENABLE_BRACKETED_PASTE);
        }

        return self;
    }

    fn initWindows(config: BackendConfig) Error!Backend {
        if (!is_windows) unreachable;

        const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch {
            return Error.TerminalQueryFailed;
        };
        const stdin_handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch {
            return Error.TerminalQueryFailed;
        };

        // Check if we're connected to a console
        var mode: u32 = 0;
        if (windows.kernel32.GetConsoleMode(stdout_handle, &mode) == 0) {
            return Error.NotATty;
        }

        // Detect terminal type and capabilities
        const term_type = detectTerminalType();
        const color_support = detectColorSupport();
        const caps = TerminalCapabilities.fromTerminalType(term_type, color_support);

        // Save original console modes
        var input_mode: u32 = 0;
        _ = windows.kernel32.GetConsoleMode(stdin_handle, &input_mode);
        var output_mode: u32 = 0;
        _ = windows.kernel32.GetConsoleMode(stdout_handle, &output_mode);

        var self = Backend{
            .handle = stdout_handle,
            .original_state = .{
                .input_mode = input_mode,
                .output_mode = output_mode,
            },
            .config = config,
            .active = false,
            .capabilities = caps,
        };

        // Enable virtual terminal processing for ANSI sequences
        const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
        const DISABLE_NEWLINE_AUTO_RETURN: u32 = 0x0008;
        const new_output_mode = output_mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN;
        if (windows.kernel32.SetConsoleMode(stdout_handle, new_output_mode) == 0) {
            return Error.TerminalSetFailed;
        }

        // Enable virtual terminal input processing
        const ENABLE_VIRTUAL_TERMINAL_INPUT: u32 = 0x0200;
        const ENABLE_WINDOW_INPUT: u32 = 0x0008;
        var new_input_mode = input_mode | ENABLE_VIRTUAL_TERMINAL_INPUT | ENABLE_WINDOW_INPUT;
        // Disable line input and echo for raw mode
        const ENABLE_LINE_INPUT: u32 = 0x0002;
        const ENABLE_ECHO_INPUT: u32 = 0x0004;
        const ENABLE_PROCESSED_INPUT: u32 = 0x0001;
        new_input_mode &= ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT);
        if (windows.kernel32.SetConsoleMode(stdin_handle, new_input_mode) == 0) {
            // Restore output mode on failure
            _ = windows.kernel32.SetConsoleMode(stdout_handle, output_mode);
            return Error.TerminalSetFailed;
        }

        self.active = true;

        // Store state for emergency cleanup
        emergency_original_state = .{
            .input_mode = input_mode,
            .output_mode = output_mode,
        };
        emergency_config = config;
        global_backend = &self;

        // Use ANSI escape sequences (works in Windows Terminal and modern Windows 10+)
        if (config.alternate_screen and caps.alternate_screen) {
            self.writeEscape(ENTER_ALTERNATE_SCREEN);
        }

        if (config.hide_cursor) {
            self.writeEscape(HIDE_CURSOR);
        }

        if (config.mouse_capture and caps.mouse) {
            self.enableMouse();
        }

        if (config.bracketed_paste and caps.bracketed_paste) {
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
        if (self.config.bracketed_paste and self.capabilities.bracketed_paste) {
            self.writeEscape(DISABLE_BRACKETED_PASTE);
        }

        // Disable mouse capture
        if (self.config.mouse_capture and self.capabilities.mouse) {
            self.disableMouse();
        }

        // Show cursor
        if (self.config.hide_cursor) {
            self.writeEscape(SHOW_CURSOR);
        }

        // Leave alternate screen
        if (self.config.alternate_screen and self.capabilities.alternate_screen) {
            self.writeEscape(LEAVE_ALTERNATE_SCREEN);
        }

        // Restore terminal mode
        if (is_windows) {
            self.exitRawModeWindows();
        } else {
            self.exitRawMode();
        }
        self.active = false;

        // Clear global state for panic handler
        if (global_backend == self) {
            global_backend = null;
            emergency_original_state = null;
            emergency_config = null;
        }
    }

    /// Enter raw mode: disable line buffering, echo, and canonical mode.
    fn enterRawMode(self: *Backend) Error!void {
        if (is_windows) return; // Handled in initWindows

        const original = std.posix.tcgetattr(self.handle) catch {
            return Error.TerminalQueryFailed;
        };
        self.original_state = .{ .termios = original };

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
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 1;

        std.posix.tcsetattr(self.handle, .FLUSH, raw) catch {
            return Error.TerminalSetFailed;
        };
    }

    /// Exit raw mode: restore original terminal settings (POSIX).
    fn exitRawMode(self: *Backend) void {
        if (is_windows) return;
        if (self.original_state) |state| {
            std.posix.tcsetattr(self.handle, .FLUSH, state.termios) catch {};
        }
    }

    /// Exit raw mode: restore original console modes (Windows).
    fn exitRawModeWindows(self: *Backend) void {
        if (!is_windows) return;
        if (self.original_state) |state| {
            const stdin_handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch return;
            _ = windows.kernel32.SetConsoleMode(stdin_handle, state.input_mode);
            _ = windows.kernel32.SetConsoleMode(self.handle, state.output_mode);
        }
    }

    /// Enable mouse reporting (SGR mode for better coordinate handling).
    fn enableMouse(self: *Backend) void {
        if (self.capabilities.sgr_mouse) {
            self.writeEscape(ENABLE_MOUSE_CAPTURE);
            self.writeEscape(ENABLE_MOUSE_SGR);
        } else if (self.capabilities.mouse) {
            // Fall back to X10 mode for terminals without SGR support
            self.writeEscape(ENABLE_MOUSE_CAPTURE);
        }
    }

    /// Disable mouse reporting.
    fn disableMouse(self: *Backend) void {
        if (self.capabilities.sgr_mouse) {
            self.writeEscape(DISABLE_MOUSE_SGR);
        }
        self.writeEscape(DISABLE_MOUSE_CAPTURE);
    }

    /// Write an escape sequence to the terminal.
    fn writeEscape(self: *Backend, seq: []const u8) void {
        const file = std.fs.File{ .handle = self.handle };
        file.writeAll(seq) catch {};
    }

    /// Flush output to terminal.
    pub fn flush(self: *Backend) void {
        const file = std.fs.File{ .handle = self.handle };
        file.sync() catch {};
    }

    /// Write bytes to the terminal.
    pub fn write(self: *Backend, data: []const u8) Error!void {
        const file = std.fs.File{ .handle = self.handle };
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
        if (is_windows) {
            return getSizeWindows(self.handle);
        } else {
            return getSizeForFd(self.handle);
        }
    }

    /// Get detected terminal capabilities.
    pub fn getCapabilities(self: *Backend) TerminalCapabilities {
        return self.capabilities;
    }

    /// Detect terminal color support level.
    /// Checks environment variables COLORTERM and TERM to determine capability.
    /// Returns the highest detected color support level.
    pub fn getColorSupport(self: *Backend) ColorSupport {
        return self.capabilities.color_support;
    }

    // ANSI escape sequences
    pub const ENTER_ALTERNATE_SCREEN = "\x1b[?1049h";
    pub const LEAVE_ALTERNATE_SCREEN = "\x1b[?1049l";
    pub const HIDE_CURSOR = "\x1b[?25l";
    pub const SHOW_CURSOR = "\x1b[?25h";
    pub const CLEAR_SCREEN = "\x1b[2J";
    pub const CURSOR_HOME = "\x1b[H";

    pub const ENABLE_MOUSE_CAPTURE = "\x1b[?1000h\x1b[?1002h\x1b[?1003h";
    pub const DISABLE_MOUSE_CAPTURE = "\x1b[?1003l\x1b[?1002l\x1b[?1000l";
    pub const ENABLE_MOUSE_SGR = "\x1b[?1006h";
    pub const DISABLE_MOUSE_SGR = "\x1b[?1006l";

    pub const ENABLE_BRACKETED_PASTE = "\x1b[?2004h";
    pub const DISABLE_BRACKETED_PASTE = "\x1b[?2004l";
};

// ============================================================
// TERMINAL DETECTION
// ============================================================

/// Detect the terminal type from environment variables.
pub fn detectTerminalType() TerminalType {
    if (is_windows) {
        return detectTerminalTypeWindows();
    } else {
        return detectTerminalTypePosix();
    }
}

fn detectTerminalTypePosix() TerminalType {
    // Check for specific terminal indicators

    // iTerm2
    if (getEnv("ITERM_SESSION_ID") != null or getEnv("ITERM_PROFILE") != null) {
        return .iterm2;
    }

    // Kitty
    if (getEnv("KITTY_WINDOW_ID") != null) {
        return .kitty;
    }

    // WezTerm
    if (getEnv("WEZTERM_PANE") != null or getEnv("WEZTERM_UNIX_SOCKET") != null) {
        return .wezterm;
    }

    // Alacritty (check TERM first, then ALACRITTY_LOG)
    if (getEnv("ALACRITTY_LOG") != null or getEnv("ALACRITTY_SOCKET") != null) {
        return .alacritty;
    }

    // Konsole
    if (getEnv("KONSOLE_VERSION") != null) {
        return .konsole;
    }

    // GNOME Terminal / VTE
    if (getEnv("VTE_VERSION") != null or getEnv("GNOME_TERMINAL_SCREEN") != null) {
        return .gnome_terminal;
    }

    // Check TERM_PROGRAM
    if (getEnv("TERM_PROGRAM")) |term_program| {
        if (std.mem.eql(u8, term_program, "iTerm.app")) return .iterm2;
        if (std.mem.eql(u8, term_program, "Apple_Terminal")) return .xterm;
        if (std.mem.eql(u8, term_program, "WezTerm")) return .wezterm;
        if (std.mem.eql(u8, term_program, "Hyper")) return .xterm;
        if (std.mem.eql(u8, term_program, "vscode")) return .xterm;
    }

    // tmux
    if (getEnv("TMUX") != null) {
        return .tmux;
    }

    // GNU Screen
    if (getEnv("STY") != null) {
        return .screen;
    }

    // Check TERM variable
    if (getEnv("TERM")) |term| {
        if (std.mem.startsWith(u8, term, "alacritty")) return .alacritty;
        if (std.mem.startsWith(u8, term, "kitty")) return .kitty;
        if (std.mem.startsWith(u8, term, "xterm")) return .xterm;
        if (std.mem.startsWith(u8, term, "rxvt")) return .rxvt;
        if (std.mem.startsWith(u8, term, "screen")) return .screen;
        if (std.mem.startsWith(u8, term, "tmux")) return .tmux;
        if (std.mem.startsWith(u8, term, "linux")) return .linux_console;
        if (std.mem.startsWith(u8, term, "vte")) return .gnome_terminal;
        if (std.mem.startsWith(u8, term, "gnome")) return .gnome_terminal;
        if (std.mem.startsWith(u8, term, "konsole")) return .konsole;
    }

    return .unknown;
}

fn detectTerminalTypeWindows() TerminalType {
    if (!is_windows) return .unknown;

    // Check for Windows Terminal
    if (getEnv("WT_SESSION") != null or getEnv("WT_PROFILE_ID") != null) {
        return .windows_terminal;
    }

    // Check for ConEmu
    if (getEnv("ConEmuPID") != null or getEnv("ConEmuANSI") != null) {
        return .conemu;
    }

    // Check for various terminal emulators that might run on Windows
    if (getEnv("TERM_PROGRAM")) |term_program| {
        if (std.mem.eql(u8, term_program, "mintty")) return .xterm;
        if (std.mem.eql(u8, term_program, "vscode")) return .xterm;
        if (std.mem.eql(u8, term_program, "Hyper")) return .xterm;
        if (std.mem.eql(u8, term_program, "Alacritty")) return .alacritty;
        if (std.mem.eql(u8, term_program, "WezTerm")) return .wezterm;
    }

    // Check TERM for MSYS/Cygwin/Git Bash
    if (getEnv("TERM")) |term| {
        if (std.mem.startsWith(u8, term, "xterm")) return .xterm;
        if (std.mem.startsWith(u8, term, "cygwin")) return .xterm;
        if (std.mem.startsWith(u8, term, "mintty")) return .xterm;
    }

    // Check for MSYSTEM (Git Bash / MSYS2)
    if (getEnv("MSYSTEM") != null) {
        return .xterm;
    }

    // Default to cmd.exe for legacy Windows console
    return .cmd_exe;
}

/// Detect terminal color support from environment variables.
/// This is a standalone function that doesn't require a Backend instance.
/// Checks COLORTERM and TERM environment variables to determine capability.
pub fn detectColorSupport() ColorSupport {
    if (is_windows) {
        return detectColorSupportWindows();
    } else {
        return detectColorSupportPosix();
    }
}

fn detectColorSupportPosix() ColorSupport {
    // Check COLORTERM first - most reliable indicator of true color
    if (getEnv("COLORTERM")) |colorterm| {
        if (std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit")) {
            return .true_color;
        }
    }

    // Check for specific terminal environment variables that indicate true color
    // iTerm2
    if (getEnv("ITERM_SESSION_ID") != null) return .true_color;
    // Kitty
    if (getEnv("KITTY_WINDOW_ID") != null) return .true_color;
    // WezTerm
    if (getEnv("WEZTERM_PANE") != null) return .true_color;
    // Alacritty (via socket or log)
    if (getEnv("ALACRITTY_LOG") != null or getEnv("ALACRITTY_SOCKET") != null) return .true_color;
    // Konsole (version 220000+ has true color)
    if (getEnv("KONSOLE_VERSION") != null) return .true_color;
    // VTE 3600+ has true color (GNOME Terminal)
    if (getEnv("VTE_VERSION") != null) return .true_color;

    // Check TERM for terminal type hints
    if (getEnv("TERM")) |term| {
        // True color indicators in TERM
        if (std.mem.indexOf(u8, term, "truecolor") != null or
            std.mem.indexOf(u8, term, "24bit") != null or
            std.mem.indexOf(u8, term, "direct") != null)
        {
            return .true_color;
        }

        // Known terminals that support true color
        if (std.mem.startsWith(u8, term, "alacritty") or
            std.mem.startsWith(u8, term, "kitty"))
        {
            return .true_color;
        }

        // 256 color indicators
        if (std.mem.indexOf(u8, term, "256color") != null or
            std.mem.indexOf(u8, term, "256") != null)
        {
            return .extended;
        }

        // Known modern terminals that typically support at least 256 colors
        if (std.mem.startsWith(u8, term, "xterm") or
            std.mem.startsWith(u8, term, "screen") or
            std.mem.startsWith(u8, term, "tmux") or
            std.mem.startsWith(u8, term, "vte") or
            std.mem.startsWith(u8, term, "gnome") or
            std.mem.startsWith(u8, term, "konsole") or
            std.mem.startsWith(u8, term, "rxvt"))
        {
            return .extended;
        }

        // Linux console is limited
        if (std.mem.startsWith(u8, term, "linux")) {
            return .basic;
        }
    }

    // Default to basic 16-color support
    return .basic;
}

fn detectColorSupportWindows() ColorSupport {
    if (!is_windows) return .basic;

    // Windows Terminal supports true color
    if (getEnv("WT_SESSION") != null or getEnv("WT_PROFILE_ID") != null) {
        return .true_color;
    }

    // ConEmu with ANSI support
    if (getEnv("ConEmuANSI")) |ansi| {
        if (std.mem.eql(u8, ansi, "ON")) {
            return .true_color;
        }
    }

    // Check COLORTERM (might be set by some terminals)
    if (getEnv("COLORTERM")) |colorterm| {
        if (std.mem.eql(u8, colorterm, "truecolor") or std.mem.eql(u8, colorterm, "24bit")) {
            return .true_color;
        }
    }

    // Check for terminal emulators running on Windows
    if (getEnv("TERM_PROGRAM")) |term_program| {
        if (std.mem.eql(u8, term_program, "Alacritty") or
            std.mem.eql(u8, term_program, "WezTerm") or
            std.mem.eql(u8, term_program, "mintty"))
        {
            return .true_color;
        }
        if (std.mem.eql(u8, term_program, "vscode")) {
            return .extended;
        }
    }

    // MSYS2/Git Bash typically support 256 colors
    if (getEnv("MSYSTEM") != null) {
        return .extended;
    }

    // Check TERM for hints
    if (getEnv("TERM")) |term| {
        if (std.mem.indexOf(u8, term, "256color") != null) {
            return .extended;
        }
        if (std.mem.startsWith(u8, term, "xterm") or
            std.mem.startsWith(u8, term, "mintty"))
        {
            return .extended;
        }
    }

    // Modern Windows 10+ console supports 256 colors and possibly true color
    // but we're conservative here - default to extended
    return .extended;
}

/// Cross-platform environment variable getter.
fn getEnv(name: []const u8) ?[]const u8 {
    if (is_windows) {
        return std.process.getEnvVarOwned(std.heap.page_allocator, name) catch null;
    } else {
        return std.posix.getenv(name);
    }
}

/// Internal: get terminal size for a specific file descriptor (POSIX).
fn getSizeForFd(fd: std.posix.fd_t) TerminalSize {
    var ws: std.posix.winsize = undefined;
    const result = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (result == 0) {
        return .{ .width = ws.col, .height = ws.row };
    }
    return .{ .width = 80, .height = 24 };
}

/// Internal: get terminal size (Windows).
fn getSizeWindows(handle: std.fs.File.Handle) TerminalSize {
    if (!is_windows) return .{ .width = 80, .height = 24 };

    var csbi: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (windows.kernel32.GetConsoleScreenBufferInfo(handle, &csbi) != 0) {
        const width = csbi.srWindow.Right - csbi.srWindow.Left + 1;
        const height = csbi.srWindow.Bottom - csbi.srWindow.Top + 1;
        return .{
            .width = @intCast(@max(1, width)),
            .height = @intCast(@max(1, height)),
        };
    }
    return .{ .width = 80, .height = 24 };
}

/// Get terminal size without requiring a Backend instance.
/// Useful for initial configuration before Backend initialization.
/// Returns default 80x24 if size cannot be determined.
pub fn getTerminalSize() TerminalSize {
    if (is_windows) {
        const stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch {
            return .{ .width = 80, .height = 24 };
        };
        return getSizeWindows(stdout_handle);
    } else {
        return getSizeForFd(std.posix.STDOUT_FILENO);
    }
}

// ============================================================
// BUFFERED OUTPUT
// ============================================================

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
        /// File handle for output.
        handle: std.fs.File.Handle,
        /// Detected color system for ANSI rendering.
        color_system: ColorSystem,
        /// Last style written (for optimization).
        last_style: ?Style = null,

        /// Initialize output with detected color support.
        pub fn init(handle: std.fs.File.Handle) Self {
            return .{
                .handle = handle,
                .color_system = colorSupportToSystem(detectColorSupport()),
            };
        }

        /// Initialize output with explicit color system.
        pub fn initWithColorSystem(handle: std.fs.File.Handle, color_system: ColorSystem) Self {
            return .{
                .handle = handle,
                .color_system = color_system,
            };
        }

        /// Write raw bytes to the buffer.
        pub fn writeRaw(self: *Self, data: []const u8) void {
            for (data) |byte| {
                if (self.pos >= buffer_size) {
                    self.flushInternal();
                }
                self.buffer[self.pos] = byte;
                self.pos += 1;
            }
        }

        /// Write a single byte to the buffer.
        pub fn writeByte(self: *Self, byte: u8) void {
            if (self.pos >= buffer_size) {
                self.flushInternal();
            }
            self.buffer[self.pos] = byte;
            self.pos += 1;
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
            const file = std.fs.File{ .handle = self.handle };
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
    try std.testing.expect(emergency_original_state == null);
    try std.testing.expect(emergency_config == null);
}

test "sanity: emergencyCleanup handles null state" {
    emergencyCleanup();
    try std.testing.expect(global_backend == null);
}

test "sanity: panic namespace exists with call function" {
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
    try std.testing.expect(ColorSupport.basic.supports(.basic));
    try std.testing.expect(!ColorSupport.basic.supports(.extended));
    try std.testing.expect(!ColorSupport.basic.supports(.true_color));

    try std.testing.expect(ColorSupport.extended.supports(.basic));
    try std.testing.expect(ColorSupport.extended.supports(.extended));
    try std.testing.expect(!ColorSupport.extended.supports(.true_color));

    try std.testing.expect(ColorSupport.true_color.supports(.basic));
    try std.testing.expect(ColorSupport.true_color.supports(.extended));
    try std.testing.expect(ColorSupport.true_color.supports(.true_color));
}

test "behavior: detectColorSupport returns valid enum" {
    const support = detectColorSupport();
    try std.testing.expect(support == .basic or support == .extended or support == .true_color);
}

test "behavior: getTerminalSize returns reasonable values" {
    const size = getTerminalSize();
    try std.testing.expect(size.width > 0);
    try std.testing.expect(size.height > 0);
}

// ============================================================
// SANITY TESTS - Terminal type detection
// ============================================================

test "sanity: TerminalType enum exists" {
    const term_type = detectTerminalType();
    _ = term_type;
}

test "sanity: TerminalType feature queries" {
    try std.testing.expect(TerminalType.windows_terminal.supportsTrueColor());
    try std.testing.expect(TerminalType.iterm2.supportsTrueColor());
    try std.testing.expect(TerminalType.kitty.supportsTrueColor());
    try std.testing.expect(!TerminalType.cmd_exe.supportsTrueColor());

    try std.testing.expect(TerminalType.xterm.supports256Colors());
    try std.testing.expect(!TerminalType.linux_console.supports256Colors());

    try std.testing.expect(TerminalType.windows_terminal.supportsMouse());
    try std.testing.expect(!TerminalType.cmd_exe.supportsMouse());

    try std.testing.expect(TerminalType.kitty.supportsUnicode());
    try std.testing.expect(!TerminalType.cmd_exe.supportsUnicode());
}

test "sanity: TerminalCapabilities creation" {
    const caps = TerminalCapabilities.fromTerminalType(.xterm, .extended);
    try std.testing.expect(caps.terminal_type == .xterm);
    try std.testing.expect(caps.color_support == .extended);
    try std.testing.expect(caps.unicode);
    try std.testing.expect(caps.mouse);
    try std.testing.expect(caps.sgr_mouse);
    try std.testing.expect(caps.bracketed_paste);
    try std.testing.expect(caps.alternate_screen);
}

// ============================================================
// SANITY TESTS - Output buffering
// ============================================================

test "sanity: Output buffer initialization" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);
    try std.testing.expect(out.isEmpty());
    try std.testing.expectEqual(@as(usize, 256), out.remaining());
}

test "sanity: Output.writeRaw buffers data" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.writeRaw("Hello");
    try std.testing.expect(!out.isEmpty());
    try std.testing.expectEqual(@as(usize, 251), out.remaining());
}

test "sanity: Output.writeByte buffers single byte" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.writeByte('X');
    try std.testing.expectEqual(@as(usize, 255), out.remaining());
}

// ============================================================
// BEHAVIOR TESTS - Output cursor control
// ============================================================

test "behavior: Output.cursorHome writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.cursorHome();
    try std.testing.expectEqualStrings("\x1b[H", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorTo writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.cursorTo(5, 10);
    try std.testing.expectEqualStrings("\x1b[11;6H", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorUp writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.cursorUp(3);
    try std.testing.expectEqualStrings("\x1b[3A", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorDown writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.cursorDown(5);
    try std.testing.expectEqualStrings("\x1b[5B", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorForward writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.cursorForward(2);
    try std.testing.expectEqualStrings("\x1b[2C", out.buffer[0..out.pos]);
}

test "behavior: Output.cursorBackward writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.cursorBackward(4);
    try std.testing.expectEqualStrings("\x1b[4D", out.buffer[0..out.pos]);
}

// ============================================================
// BEHAVIOR TESTS - Output screen clearing
// ============================================================

test "behavior: Output.clearScreen writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.clearScreen();
    try std.testing.expectEqualStrings("\x1b[2J", out.buffer[0..out.pos]);
}

test "behavior: Output.clearToEndOfScreen writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.clearToEndOfScreen();
    try std.testing.expectEqualStrings("\x1b[0J", out.buffer[0..out.pos]);
}

test "behavior: Output.clearLine writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.clearLine();
    try std.testing.expectEqualStrings("\x1b[2K", out.buffer[0..out.pos]);
}

test "behavior: Output.clearToEndOfLine writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.clearToEndOfLine();
    try std.testing.expectEqualStrings("\x1b[0K", out.buffer[0..out.pos]);
}

// ============================================================
// BEHAVIOR TESTS - Output cursor visibility
// ============================================================

test "behavior: Output.showCursor writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.showCursor();
    try std.testing.expectEqualStrings("\x1b[?25h", out.buffer[0..out.pos]);
}

test "behavior: Output.hideCursor writes correct sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.hideCursor();
    try std.testing.expectEqualStrings("\x1b[?25l", out.buffer[0..out.pos]);
}

// ============================================================
// BEHAVIOR TESTS - Output style rendering
// ============================================================

test "behavior: Output.setStyle uses rich_zig rendering" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    const style = Style.init().bold().fg(.red);
    out.setStyle(style);

    const written = out.buffer[0..out.pos];
    try std.testing.expect(written[0] == 0x1b);
    try std.testing.expect(written[1] == '[');
    try std.testing.expect(written[written.len - 1] == 'm');
}

test "behavior: Output.resetStyle writes reset sequence" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.resetStyle();
    try std.testing.expectEqualStrings("\x1b[0m", out.buffer[0..out.pos]);
}

test "behavior: Output.setStyle skips duplicate styles" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    const style = Style.init().bold();
    out.setStyle(style);
    const first_len = out.pos;

    out.setStyle(style);
    try std.testing.expectEqual(first_len, out.pos);
}

test "behavior: Output.writeStyled combines style and text" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    const style = Style.init().bold();
    out.writeStyled("Hello", style);

    const written = out.buffer[0..out.pos];
    try std.testing.expect(std.mem.indexOf(u8, written, "Hello") != null);
}

test "behavior: Output.writeChar writes styled character" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.writeChar('X', Style.empty);
    try std.testing.expectEqualStrings("X", out.buffer[0..out.pos]);
}

test "behavior: Output.writeChar handles UTF-8" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.writeChar(0x4E2D, Style.empty);
    try std.testing.expectEqual(@as(usize, 3), out.pos);
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
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.cursorUp(0);
    try std.testing.expect(out.isEmpty());
}

test "regression: Output.cursorDown with zero does nothing" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    out.cursorDown(0);
    try std.testing.expect(out.isEmpty());
}

test "regression: Output writer interface works with fmt" {
    const TestOutput = Output(256);
    const handle = if (is_windows)
        (windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, .truecolor);

    const w = out.writer();
    try std.fmt.format(w, "Value: {d}", .{42});
    try std.testing.expectEqualStrings("Value: 42", out.buffer[0..out.pos]);
}
