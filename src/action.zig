// Action types for zithril TUI framework
// Actions are returned by the update function to control application flow.

const std = @import("std");

/// Actions returned by the update function to control the application.
/// The main loop inspects these to determine what to do next.
pub const Action = union(enum) {
    /// Continue running, no special action needed.
    none: void,

    /// Exit the application cleanly.
    quit: void,

    /// Execute an async command (future feature).
    /// Commands are executed by the runtime and results come back as events.
    command: Command,

    /// Convenience constant for the common case of "do nothing".
    pub const none_action: Action = .{ .none = {} };

    /// Convenience constant for quitting.
    pub const quit_action: Action = .{ .quit = {} };

    /// Check if this action will terminate the application.
    pub fn isQuit(self: Action) bool {
        return self == .quit;
    }

    /// Check if this is a no-op action.
    pub fn isNone(self: Action) bool {
        return self == .none;
    }

    /// Check if this is a command action.
    pub fn isCommand(self: Action) bool {
        return self == .command;
    }
};

/// Command type for async operations.
/// Commands are returned from update, executed by the runtime,
/// and results come back as events via Event.command_result.
///
/// Command execution flow:
/// 1. update() returns Action{ .command = cmd }
/// 2. Runtime processes the command
/// 3. Result delivered via Event{ .command_result = result }
/// 4. update() handles the result event
pub const Command = union(enum) {
    /// No command (placeholder for future expansion).
    none: void,

    /// Batch multiple commands together.
    /// All commands execute, results delivered individually.
    batch: []const Command,

    /// Custom command with user-defined ID and data.
    /// The id allows matching results to requests.
    custom: struct {
        id: u32,
        data: ?*anyopaque,
    },

    /// Request a tick event after a delay.
    /// Unlike tick_rate_ms, this is a one-shot delay.
    delay_tick: u32, // milliseconds

    /// Create an empty command.
    pub fn empty() Command {
        return .{ .none = {} };
    }

    /// Create a custom command with the given ID.
    pub fn customCmd(id: u32, data: ?*anyopaque) Command {
        return .{ .custom = .{ .id = id, .data = data } };
    }

    /// Create a batch of commands.
    pub fn batchCmd(commands: []const Command) Command {
        return .{ .batch = commands };
    }

    /// Create a delayed tick command.
    pub fn delayTick(ms: u32) Command {
        return .{ .delay_tick = ms };
    }

    /// Check if this is a no-op command.
    pub fn isNone(self: Command) bool {
        return self == .none;
    }

    /// Check if this is a batch command.
    pub fn isBatch(self: Command) bool {
        return self == .batch;
    }
};

/// Result of a command execution, delivered back via Event.command_result.
pub const CommandResult = struct {
    /// The command ID that generated this result (from Command.custom.id).
    /// For non-custom commands, this will be 0.
    id: u32,

    /// Result status.
    status: Status,

    /// Optional result data (user-managed lifetime).
    data: ?*anyopaque,

    pub const Status = enum {
        /// Command completed successfully.
        success,
        /// Command failed.
        failed,
        /// Command was cancelled.
        cancelled,
    };

    /// Create a success result.
    pub fn success(id: u32, data: ?*anyopaque) CommandResult {
        return .{ .id = id, .status = .success, .data = data };
    }

    /// Create a failure result.
    pub fn failed(id: u32) CommandResult {
        return .{ .id = id, .status = .failed, .data = null };
    }

    /// Check if the command succeeded.
    pub fn isSuccess(self: CommandResult) bool {
        return self.status == .success;
    }
};

// ============================================================
// SANITY TESTS - Basic type construction
// ============================================================

test "sanity: Action.none construction" {
    const action = Action{ .none = {} };
    try std.testing.expect(action == .none);
    try std.testing.expect(action.isNone());
    try std.testing.expect(!action.isQuit());
}

test "sanity: Action.quit construction" {
    const action = Action{ .quit = {} };
    try std.testing.expect(action == .quit);
    try std.testing.expect(action.isQuit());
    try std.testing.expect(!action.isNone());
}

test "sanity: Action.command construction" {
    const action = Action{ .command = Command.empty() };
    try std.testing.expect(action == .command);
    try std.testing.expect(action.isCommand());
    try std.testing.expect(!action.isQuit());
}

test "sanity: Action convenience constants" {
    try std.testing.expect(Action.none_action.isNone());
    try std.testing.expect(Action.quit_action.isQuit());
}

// ============================================================
// BEHAVIOR TESTS - Command types
// ============================================================

test "behavior: Command.empty creates none command" {
    const cmd = Command.empty();
    try std.testing.expect(cmd == .none);
    try std.testing.expect(cmd.isNone());
}

test "behavior: Command.custom construction" {
    const cmd = Command{ .custom = .{ .id = 42, .data = null } };
    try std.testing.expect(cmd == .custom);
    try std.testing.expectEqual(@as(u32, 42), cmd.custom.id);
    try std.testing.expect(cmd.custom.data == null);
}

test "behavior: Command.customCmd helper" {
    const cmd = Command.customCmd(99, null);
    try std.testing.expect(cmd == .custom);
    try std.testing.expectEqual(@as(u32, 99), cmd.custom.id);
}

test "behavior: Command.delayTick construction" {
    const cmd = Command.delayTick(500);
    try std.testing.expect(cmd == .delay_tick);
    try std.testing.expectEqual(@as(u32, 500), cmd.delay_tick);
}

test "behavior: Command.batchCmd construction" {
    const cmds = [_]Command{
        Command.customCmd(1, null),
        Command.customCmd(2, null),
    };
    const batch = Command.batchCmd(&cmds);
    try std.testing.expect(batch.isBatch());
    try std.testing.expectEqual(@as(usize, 2), batch.batch.len);
}

test "behavior: Action with custom command" {
    const cmd = Command{ .custom = .{ .id = 123, .data = null } };
    const action = Action{ .command = cmd };
    try std.testing.expect(action.isCommand());
    try std.testing.expectEqual(@as(u32, 123), action.command.custom.id);
}

// ============================================================
// BEHAVIOR TESTS - CommandResult
// ============================================================

test "behavior: CommandResult.success construction" {
    const result = CommandResult.success(42, null);
    try std.testing.expectEqual(@as(u32, 42), result.id);
    try std.testing.expect(result.isSuccess());
    try std.testing.expect(result.status == .success);
}

test "behavior: CommandResult.failed construction" {
    const result = CommandResult.failed(42);
    try std.testing.expectEqual(@as(u32, 42), result.id);
    try std.testing.expect(!result.isSuccess());
    try std.testing.expect(result.status == .failed);
}
