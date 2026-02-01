// Error types for zithril TUI framework
// All errors are explicit and must be handled.
// No panics in library code.

const std = @import("std");

/// Core error types for zithril operations.
/// These errors are explicit and must be handled by callers.
/// Library code never panics - all fallible operations return error unions.
pub const Error = error{
    /// Terminal initialization failed (could not set up raw mode or alternate screen).
    TerminalInitFailed,

    /// Terminal query operation failed (could not get terminal attributes or size).
    TerminalQueryFailed,

    /// Buffer capacity exceeded (too much data for available space).
    BufferOverflow,

    /// Invalid UTF-8 sequence encountered.
    InvalidUtf8,

    /// I/O error during terminal read or write.
    IoError,

    /// Memory allocation failed.
    OutOfMemory,
};

/// Maps a standard library allocator error to our OutOfMemory.
pub fn mapAllocError(err: std.mem.Allocator.Error) Error {
    _ = err;
    return Error.OutOfMemory;
}

/// Maps a POSIX read/write error to our IoError.
/// Some specific errors are mapped to more specific zithril errors.
pub fn mapPosixError(err: std.posix.ReadError) Error {
    return switch (err) {
        error.WouldBlock, error.ConnectionResetByPeer, error.ConnectionTimedOut => Error.IoError,
        else => Error.IoError,
    };
}

/// Maps a write error to our IoError.
pub fn mapWriteError(err: std.posix.WriteError) Error {
    _ = err;
    return Error.IoError;
}

/// Error context for diagnostic output.
/// Provides additional information about where and why an error occurred.
pub const ErrorContext = struct {
    /// The underlying error.
    err: Error,
    /// Human-readable description of the context.
    context: []const u8,
    /// Optional source location information.
    source: ?std.builtin.SourceLocation,

    /// Create an error context with location information.
    pub fn init(err: Error, context: []const u8, source: ?std.builtin.SourceLocation) ErrorContext {
        return .{
            .err = err,
            .context = context,
            .source = source,
        };
    }

    /// Create an error context at the current location.
    pub fn here(err: Error, context: []const u8) ErrorContext {
        return init(err, context, @src());
    }

    /// Format for display.
    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("error.{s}: {s}", .{ @errorName(self.err), self.context });

        if (self.source) |src| {
            try writer.print(" at {s}:{d}:{d}", .{ src.file, src.line, src.column });
        }
    }
};

/// Wraps an error with context for better diagnostics.
/// Use this when you want to add information about what operation failed.
pub fn withContext(err: Error, context: []const u8) ErrorContext {
    return ErrorContext.init(err, context, null);
}

/// Wraps an error with context and source location.
pub fn withContextHere(err: Error, context: []const u8) ErrorContext {
    return ErrorContext.here(err, context);
}

// ============================================================
// SANITY TESTS - Error types exist
// ============================================================

test "sanity: Error enum has all required variants" {
    _ = Error.TerminalInitFailed;
    _ = Error.TerminalQueryFailed;
    _ = Error.BufferOverflow;
    _ = Error.InvalidUtf8;
    _ = Error.IoError;
    _ = Error.OutOfMemory;
}

test "sanity: Error can be used in error unions" {
    const TestResult = Error!u32;

    const success: TestResult = 42;
    try std.testing.expectEqual(@as(u32, 42), success);

    const failure: TestResult = Error.IoError;
    try std.testing.expectError(Error.IoError, failure);
}

// ============================================================
// BEHAVIOR TESTS - Error mapping functions
// ============================================================

test "behavior: mapAllocError returns OutOfMemory" {
    const mapped = mapAllocError(error.OutOfMemory);
    try std.testing.expectEqual(Error.OutOfMemory, mapped);
}

test "behavior: mapWriteError returns IoError" {
    // Test with a representative write error
    const mapped = mapWriteError(error.BrokenPipe);
    try std.testing.expectEqual(Error.IoError, mapped);
}

// ============================================================
// BEHAVIOR TESTS - Error context
// ============================================================

test "behavior: ErrorContext init" {
    const ctx = ErrorContext.init(Error.IoError, "failed to write", null);
    try std.testing.expectEqual(Error.IoError, ctx.err);
    try std.testing.expectEqualStrings("failed to write", ctx.context);
    try std.testing.expect(ctx.source == null);
}

test "behavior: ErrorContext here captures location" {
    const ctx = ErrorContext.here(Error.BufferOverflow, "buffer full");
    try std.testing.expectEqual(Error.BufferOverflow, ctx.err);
    try std.testing.expect(ctx.source != null);
}

test "behavior: withContext creates context without location" {
    const ctx = withContext(Error.InvalidUtf8, "invalid sequence");
    try std.testing.expect(ctx.source == null);
}

test "behavior: withContextHere creates context with location" {
    const ctx = withContextHere(Error.TerminalInitFailed, "raw mode failed");
    try std.testing.expect(ctx.source != null);
}

test "behavior: ErrorContext format output" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const ctx = ErrorContext.init(Error.IoError, "test error", null);
    try ctx.format("", .{}, stream.writer());

    const written = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "IoError") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "test error") != null);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: errors can be caught and compared" {
    const testFn = struct {
        fn fail() Error!void {
            return Error.TerminalQueryFailed;
        }
    };

    testFn.fail() catch |err| {
        try std.testing.expectEqual(Error.TerminalQueryFailed, err);
        return;
    };
    try std.testing.expect(false); // Should not reach here
}

test "regression: errors can be used in switch" {
    const err = Error.BufferOverflow;
    const code: u8 = switch (err) {
        Error.TerminalInitFailed => 1,
        Error.TerminalQueryFailed => 2,
        Error.BufferOverflow => 3,
        Error.InvalidUtf8 => 4,
        Error.IoError => 5,
        Error.OutOfMemory => 6,
    };
    try std.testing.expectEqual(@as(u8, 3), code);
}

test "regression: ErrorContext format with source location" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const ctx = ErrorContext.here(Error.OutOfMemory, "allocation failed");
    try ctx.format("", .{}, stream.writer());

    const written = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "OutOfMemory") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "allocation failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "errors.zig") != null);
}
