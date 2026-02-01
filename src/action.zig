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

/// Command type for async operations (future feature).
/// Commands are returned from update, executed by the runtime,
/// and results come back as events.
pub const Command = union(enum) {
    /// No command (placeholder for future expansion).
    none: void,

    /// Batch multiple commands together.
    batch: []const Command,

    /// Custom command with user-defined ID and data.
    custom: struct {
        id: u32,
        data: ?*anyopaque,
    },

    /// Create an empty command.
    pub fn empty() Command {
        return .{ .none = {} };
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
}

test "behavior: Command.custom construction" {
    const cmd = Command{ .custom = .{ .id = 42, .data = null } };
    try std.testing.expect(cmd == .custom);
    try std.testing.expectEqual(@as(u32, 42), cmd.custom.id);
    try std.testing.expect(cmd.custom.data == null);
}

test "behavior: Action with custom command" {
    const cmd = Command{ .custom = .{ .id = 123, .data = null } };
    const action = Action{ .command = cmd };
    try std.testing.expect(action.isCommand());
    try std.testing.expectEqual(@as(u32, 123), action.command.custom.id);
}
