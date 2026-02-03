//! Level definitions for Rung.
//!
//! Each level specifies:
//! - A truth table the player must satisfy
//! - Initial diagram setup (rails, any pre-placed components)
//! - Hints and description

const game = @import("game.zig");
const ladder = @import("ladder.zig");

const Cell = game.Cell;
const Diagram = game.Diagram;

/// A row in a truth table
pub const TruthRow = struct {
    inputs: [ladder.MAX_IO]bool,
    outputs: [ladder.MAX_IO]bool,

    pub fn init(ins: []const bool, outs: []const bool) TruthRow {
        var row = TruthRow{
            .inputs = [_]bool{false} ** ladder.MAX_IO,
            .outputs = [_]bool{false} ** ladder.MAX_IO,
        };
        for (ins, 0..) |v, i| {
            if (i < ladder.MAX_IO) row.inputs[i] = v;
        }
        for (outs, 0..) |v, i| {
            if (i < ladder.MAX_IO) row.outputs[i] = v;
        }
        return row;
    }
};

/// Level definition
pub const Level = struct {
    name: []const u8,
    description: []const u8,
    hint: []const u8,

    // Diagram dimensions
    width: usize,
    height: usize,

    // Input/output labels
    input_names: []const []const u8,
    output_names: []const []const u8,

    // Required truth table
    truth_table: []const TruthRow,

    // Setup function to initialize the diagram
    setup: *const fn (*Diagram) void,
};

/// Standard level setup: place power rails on left and right edges.
fn setupRails(diagram: *Diagram) void {
    for (0..diagram.height) |y| {
        diagram.set(0, y, .rail_left);
        diagram.set(diagram.width - 1, y, .rail_right);
    }
}

// Level definitions

const levels = [_]Level{
    // Level 1: Direct Wire
    .{
        .name = "Direct Wire",
        .description = "Connect input A directly to output Y.",
        .hint = "Place a NO contact for A and a coil for Y.",
        .width = 8,
        .height = 1,
        .input_names = &.{"A"},
        .output_names = &.{"Y"},
        .truth_table = &.{
            TruthRow.init(&.{false}, &.{false}),
            TruthRow.init(&.{true}, &.{true}),
        },
        .setup = setupRails,
    },

    // Level 2: NOT Gate
    .{
        .name = "NOT Gate",
        .description = "Output Y should be the inverse of input A.",
        .hint = "Use a Normally Closed (NC) contact.",
        .width = 8,
        .height = 1,
        .input_names = &.{"A"},
        .output_names = &.{"Y"},
        .truth_table = &.{
            TruthRow.init(&.{false}, &.{true}),
            TruthRow.init(&.{true}, &.{false}),
        },
        .setup = setupRails,
    },

    // Level 3: AND Gate
    .{
        .name = "AND Gate",
        .description = "Output Y is ON only when both A AND B are ON.",
        .hint = "Place contacts in series (one after another).",
        .width = 10,
        .height = 1,
        .input_names = &.{ "A", "B" },
        .output_names = &.{"Y"},
        .truth_table = &.{
            TruthRow.init(&.{ false, false }, &.{false}),
            TruthRow.init(&.{ false, true }, &.{false}),
            TruthRow.init(&.{ true, false }, &.{false}),
            TruthRow.init(&.{ true, true }, &.{true}),
        },
        .setup = setupRails,
    },

    // Level 4: OR Gate
    .{
        .name = "OR Gate",
        .description = "Output Y is ON when A OR B (or both) are ON.",
        .hint = "Use parallel rungs - two paths to the same output.",
        .width = 10,
        .height = 3,
        .input_names = &.{ "A", "B" },
        .output_names = &.{"Y"},
        .truth_table = &.{
            TruthRow.init(&.{ false, false }, &.{false}),
            TruthRow.init(&.{ false, true }, &.{true}),
            TruthRow.init(&.{ true, false }, &.{true}),
            TruthRow.init(&.{ true, true }, &.{true}),
        },
        .setup = setupRails,
    },

    // Level 5: NAND Gate
    .{
        .name = "NAND Gate",
        .description = "Output Y is OFF only when both A AND B are ON.",
        .hint = "Think: NOT(AND). Use NC contacts in parallel.",
        .width = 10,
        .height = 3,
        .input_names = &.{ "A", "B" },
        .output_names = &.{"Y"},
        .truth_table = &.{
            TruthRow.init(&.{ false, false }, &.{true}),
            TruthRow.init(&.{ false, true }, &.{true}),
            TruthRow.init(&.{ true, false }, &.{true}),
            TruthRow.init(&.{ true, true }, &.{false}),
        },
        .setup = setupRails,
    },

    // Level 6: NOR Gate
    .{
        .name = "NOR Gate",
        .description = "Output Y is ON only when both A AND B are OFF.",
        .hint = "Think: NOT(OR). Use NC contacts in series.",
        .width = 10,
        .height = 1,
        .input_names = &.{ "A", "B" },
        .output_names = &.{"Y"},
        .truth_table = &.{
            TruthRow.init(&.{ false, false }, &.{true}),
            TruthRow.init(&.{ false, true }, &.{false}),
            TruthRow.init(&.{ true, false }, &.{false}),
            TruthRow.init(&.{ true, true }, &.{false}),
        },
        .setup = setupRails,
    },

    // Level 7: XOR Gate
    .{
        .name = "XOR Gate",
        .description = "Output Y is ON when A and B are different.",
        .hint = "XOR = (A AND NOT B) OR (NOT A AND B)",
        .width = 12,
        .height = 3,
        .input_names = &.{ "A", "B" },
        .output_names = &.{"Y"},
        .truth_table = &.{
            TruthRow.init(&.{ false, false }, &.{false}),
            TruthRow.init(&.{ false, true }, &.{true}),
            TruthRow.init(&.{ true, false }, &.{true}),
            TruthRow.init(&.{ true, true }, &.{false}),
        },
        .setup = setupRails,
    },

    // Level 8: Latching Circuit
    .{
        .name = "Latch",
        .description = "SET turns output ON, RESET turns it OFF. Output stays.",
        .hint = "Use a latch coil for SET, unlatch coil for RESET.",
        .width = 12,
        .height = 2,
        .input_names = &.{ "SET", "RESET" },
        .output_names = &.{"Y"},
        .truth_table = &.{
            // After SET, Y stays on until RESET
            TruthRow.init(&.{ true, false }, &.{true}),
            TruthRow.init(&.{ false, true }, &.{false}),
        },
        .setup = setupRails,
    },

    // Level 9: Priority Circuit
    .{
        .name = "Priority",
        .description = "A has priority over B. If both on, only A output.",
        .hint = "Use A directly, but B needs A to be off.",
        .width = 12,
        .height = 2,
        .input_names = &.{ "A", "B" },
        .output_names = &.{ "Y1", "Y2" },
        .truth_table = &.{
            TruthRow.init(&.{ false, false }, &.{ false, false }),
            TruthRow.init(&.{ false, true }, &.{ false, true }),
            TruthRow.init(&.{ true, false }, &.{ true, false }),
            TruthRow.init(&.{ true, true }, &.{ true, false }), // A has priority
        },
        .setup = setupRails,
    },

    // Level 10: Start/Stop Motor Control
    .{
        .name = "Motor Control",
        .description = "Classic start/stop circuit with seal-in.",
        .hint = "START momentarily. STOP breaks the seal-in. Use the motor output as a seal.",
        .width = 14,
        .height = 2,
        .input_names = &.{ "START", "STOP" },
        .output_names = &.{"MOTOR"},
        .truth_table = &.{
            // START pulse turns on, STOP turns off
            TruthRow.init(&.{ true, false }, &.{true}),
            TruthRow.init(&.{ false, true }, &.{false}),
            TruthRow.init(&.{ false, false }, &.{false}), // Initial state
        },
        .setup = setupRails,
    },
};

/// Get a level by index
pub fn get(index: usize) Level {
    if (index >= levels.len) {
        return levels[levels.len - 1]; // Return last level if out of bounds
    }
    return levels[index];
}

/// Total number of levels
pub fn count() usize {
    return levels.len;
}
