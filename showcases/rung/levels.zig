//! Level definitions for Rung.
//!
//! Each level specifies:
//! - A truth table the player must satisfy
//! - Initial diagram setup (rails, any pre-placed components)
//! - Hints and description
//! - Difficulty, par moves, story, and available components

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

pub const Difficulty = enum { beginner, intermediate, advanced, expert };

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

    // Metadata
    difficulty: Difficulty,
    par_moves: usize,
    story_text: []const u8,
    available_components: []const game.ComponentType,
};

fn setupRails(diagram: *Diagram) void {
    for (0..diagram.height) |y| {
        diagram.set(0, y, .rail_left);
        diagram.set(diagram.width - 1, y, .rail_right);
    }
}

// Component sets by complexity tier
const basic_components = &[_]game.ComponentType{
    .wire_horizontal,
    .contact_no,
    .coil,
    .empty,
};

const gate_components = &[_]game.ComponentType{
    .wire_horizontal,
    .wire_vertical,
    .contact_no,
    .contact_nc,
    .coil,
    .junction,
    .empty,
};

const latch_components = &[_]game.ComponentType{
    .wire_horizontal,
    .wire_vertical,
    .contact_no,
    .contact_nc,
    .coil,
    .coil_latch,
    .coil_unlatch,
    .junction,
    .empty,
};

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
        .difficulty = .beginner,
        .par_moves = 2,
        .story_text = "A warehouse door opens when the proximity sensor detects a forklift.",
        .available_components = basic_components,
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
        .difficulty = .beginner,
        .par_moves = 2,
        .story_text = "An alarm sounds whenever the safety guard is removed from the machine.",
        .available_components = &[_]game.ComponentType{
            .wire_horizontal,
            .contact_no,
            .contact_nc,
            .coil,
            .empty,
        },
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
        .difficulty = .beginner,
        .par_moves = 3,
        .story_text = "A press only activates when both the operator's hands are on the safety buttons.",
        .available_components = basic_components,
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
        .difficulty = .intermediate,
        .par_moves = 6,
        .story_text = "A factory conveyor activates when sensor A detects a package or sensor B detects one.",
        .available_components = gate_components,
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
        .difficulty = .intermediate,
        .par_moves = 6,
        .story_text = "An emergency vent stays open unless both pressure sensors confirm normal levels.",
        .available_components = gate_components,
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
        .difficulty = .intermediate,
        .par_moves = 3,
        .story_text = "A clean room blower runs only when neither door is open.",
        .available_components = gate_components,
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
        .difficulty = .advanced,
        .par_moves = 10,
        .story_text = "A mixing valve opens when exactly one of two ingredient tanks is selected.",
        .available_components = gate_components,
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
        .difficulty = .advanced,
        .par_moves = 4,
        .story_text = "A conveyor belt starts with a push button and stays running until the stop button is pressed.",
        .available_components = latch_components,
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
        .difficulty = .advanced,
        .par_moves = 5,
        .story_text = "Two pumps share a power bus. The primary pump always takes precedence over the backup.",
        .available_components = gate_components,
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
        .difficulty = .advanced,
        .par_moves = 6,
        .story_text = "A grinding motor starts with a momentary button and seals in until the emergency stop is hit.",
        .available_components = latch_components,
    },

    // Level 11: XNOR Gate
    .{
        .name = "XNOR Gate",
        .description = "Output Y is ON when both inputs match (both ON or both OFF).",
        .hint = "XNOR = (A AND B) OR (NOT A AND NOT B)",
        .width = 14,
        .height = 3,
        .input_names = &.{ "A", "B" },
        .output_names = &.{"Y"},
        .truth_table = &.{
            TruthRow.init(&.{ false, false }, &.{true}),
            TruthRow.init(&.{ false, true }, &.{false}),
            TruthRow.init(&.{ true, false }, &.{false}),
            TruthRow.init(&.{ true, true }, &.{true}),
        },
        .setup = setupRails,
        .difficulty = .advanced,
        .par_moves = 10,
        .story_text = "Two safety sensors must agree before enabling the press.",
        .available_components = gate_components,
    },

    // Level 12: 2-bit Decoder
    .{
        .name = "2-bit Decoder",
        .description = "Route power to one of four outputs based on two input bits.",
        .hint = "Each output needs a unique combination of NO/NC contacts for A and B.",
        .width = 14,
        .height = 4,
        .input_names = &.{ "A", "B" },
        .output_names = &.{ "Y0", "Y1", "Y2", "Y3" },
        .truth_table = &.{
            TruthRow.init(&.{ false, false }, &.{ true, false, false, false }),
            TruthRow.init(&.{ false, true }, &.{ false, true, false, false }),
            TruthRow.init(&.{ true, false }, &.{ false, false, true, false }),
            TruthRow.init(&.{ true, true }, &.{ false, false, false, true }),
        },
        .setup = setupRails,
        .difficulty = .expert,
        .par_moves = 12,
        .story_text = "A conveyor sorting system routes packages to four bins based on two barcode bits.",
        .available_components = gate_components,
    },

    // Level 13: Majority Vote
    .{
        .name = "Majority Vote",
        .description = "Output ON when 2 or more of 3 inputs are ON.",
        .hint = "Three parallel paths: (A AND B), (A AND C), (B AND C).",
        .width = 14,
        .height = 4,
        .input_names = &.{ "A", "B", "C" },
        .output_names = &.{"Y"},
        .truth_table = &.{
            TruthRow.init(&.{ false, false, false }, &.{false}),
            TruthRow.init(&.{ false, false, true }, &.{false}),
            TruthRow.init(&.{ false, true, false }, &.{false}),
            TruthRow.init(&.{ false, true, true }, &.{true}),
            TruthRow.init(&.{ true, false, false }, &.{false}),
            TruthRow.init(&.{ true, false, true }, &.{true}),
            TruthRow.init(&.{ true, true, false }, &.{true}),
            TruthRow.init(&.{ true, true, true }, &.{true}),
        },
        .setup = setupRails,
        .difficulty = .expert,
        .par_moves = 12,
        .story_text = "A reactor safety system requires agreement from at least 2 of 3 sensors.",
        .available_components = gate_components,
    },

    // Level 14: Cascade Latch
    .{
        .name = "Cascade Latch",
        .description = "SET1 latches Y1, which enables SET2 to latch Y2.",
        .hint = "Y1 latches from SET1. Y2 requires Y1 latched AND SET2. RESET clears both.",
        .width = 14,
        .height = 3,
        .input_names = &.{ "SET1", "SET2", "RESET" },
        .output_names = &.{ "Y1", "Y2" },
        .truth_table = &.{
            TruthRow.init(&.{ true, false, false }, &.{ true, false }),
            TruthRow.init(&.{ false, true, false }, &.{ false, false }),
            TruthRow.init(&.{ true, true, false }, &.{ true, true }),
            TruthRow.init(&.{ false, false, true }, &.{ false, false }),
        },
        .setup = setupRails,
        .difficulty = .expert,
        .par_moves = 8,
        .story_text = "A two-stage startup sequence: hydraulics first, then main drive.",
        .available_components = latch_components,
    },

    // Level 15: Traffic Light
    .{
        .name = "Traffic Light",
        .description = "Green when GO is on and STOP is off. Red when STOP is on. Yellow when both on.",
        .hint = "GREEN: GO AND NOT STOP. RED: STOP AND NOT GO. YELLOW: GO AND STOP.",
        .width = 14,
        .height = 4,
        .input_names = &.{ "GO", "STOP" },
        .output_names = &.{ "GREEN", "YELLOW", "RED" },
        .truth_table = &.{
            TruthRow.init(&.{ false, false }, &.{ false, false, false }),
            TruthRow.init(&.{ true, false }, &.{ true, false, false }),
            TruthRow.init(&.{ false, true }, &.{ false, false, true }),
            TruthRow.init(&.{ true, true }, &.{ false, true, false }),
        },
        .setup = setupRails,
        .difficulty = .expert,
        .par_moves = 9,
        .story_text = "Control a traffic signal at a factory gate crossing.",
        .available_components = gate_components,
    },
};

pub fn get(index: usize) Level {
    if (index >= levels.len) {
        return levels[levels.len - 1]; // Return last level if out of bounds
    }
    return levels[index];
}

pub fn count() usize {
    return levels.len;
}
