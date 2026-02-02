//! Ladder logic simulation engine.
//!
//! Simulates power flow through a ladder diagram given input states.

const std = @import("std");
const game = @import("game.zig");

const Cell = game.Cell;
const Diagram = game.Diagram;

/// Maximum number of inputs/outputs supported
pub const MAX_IO = 8;

/// Simulate the ladder diagram with given inputs.
/// Returns the resulting output states.
pub fn simulate(diagram: *const Diagram, inputs: [MAX_IO]bool) [MAX_IO]bool {
    var outputs: [MAX_IO]bool = [_]bool{false} ** MAX_IO;
    var latches: [MAX_IO]bool = [_]bool{false} ** MAX_IO;

    // Process each rung (row)
    for (0..diagram.height) |y| {
        const power = evaluateRung(diagram, y, inputs, &latches);

        // Find and set any coils on this rung
        for (0..diagram.width) |x| {
            switch (diagram.get(x, y)) {
                .coil => |idx| {
                    if (idx < MAX_IO) outputs[idx] = power;
                },
                .coil_latch => |idx| {
                    if (idx < MAX_IO and power) latches[idx] = true;
                },
                .coil_unlatch => |idx| {
                    if (idx < MAX_IO and power) latches[idx] = false;
                },
                else => {},
            }
        }
    }

    // Apply latches to outputs
    for (0..MAX_IO) |i| {
        if (latches[i]) outputs[i] = true;
    }

    return outputs;
}

/// Evaluate if power reaches the right rail on a given rung.
/// Uses a simple left-to-right scan with continuity tracking.
fn evaluateRung(
    diagram: *const Diagram,
    y: usize,
    inputs: [MAX_IO]bool,
    latches: *const [MAX_IO]bool,
) bool {
    _ = latches; // TODO: use for latch state

    // Start with power from left rail
    var has_power = true;

    // Scan left to right
    for (1..diagram.width - 1) |x| {
        if (!has_power) break;

        const cell = diagram.get(x, y);
        has_power = evaluateCell(cell, inputs);
    }

    return has_power;
}

/// Evaluate if a single cell conducts power.
fn evaluateCell(cell: Cell, inputs: [MAX_IO]bool) bool {
    return switch (cell) {
        .empty => false, // Break in circuit
        .wire_h, .wire_v, .junction => true, // Conductors
        .contact_no => |idx| if (idx < MAX_IO) inputs[idx] else false,
        .contact_nc => |idx| if (idx < MAX_IO) !inputs[idx] else true,
        .coil, .coil_latch, .coil_unlatch => true, // Coils conduct
        .rail_left, .rail_right => true, // Rails conduct
    };
}

/// Check if a diagram is valid (has proper structure).
pub fn validate(diagram: *const Diagram) ValidationResult {
    var result = ValidationResult{};

    // Check each rung
    for (0..diagram.height) |y| {
        // Left rail should be present or empty
        const left = diagram.get(0, y);
        if (left != .rail_left and left != .empty) {
            result.errors += 1;
        }

        // Right rail should be present or empty
        const right = diagram.get(diagram.width - 1, y);
        if (right != .rail_right and right != .empty) {
            result.errors += 1;
        }

        // Check for at least one coil on populated rungs
        var has_content = false;
        var has_coil = false;
        for (1..diagram.width - 1) |x| {
            const cell = diagram.get(x, y);
            if (cell != .empty) has_content = true;
            if (cell == .coil or cell == .coil_latch or cell == .coil_unlatch) {
                has_coil = true;
            }
        }

        if (has_content and !has_coil) {
            result.warnings += 1; // Rung with no output
        }
    }

    return result;
}

pub const ValidationResult = struct {
    errors: usize = 0,
    warnings: usize = 0,

    pub fn isValid(self: ValidationResult) bool {
        return self.errors == 0;
    }
};

// Tests
test "simple wire conducts" {
    const std_test = std.testing;

    // TODO: Add proper test when Diagram can be created in tests
    _ = std_test;
}

test "NO contact logic" {
    const inputs_off = [_]bool{false} ** MAX_IO;
    const inputs_on = [_]bool{true} ** MAX_IO;

    // NO contact with input OFF = no conduction
    try std.testing.expect(!evaluateCell(.{ .contact_no = 0 }, inputs_off));

    // NO contact with input ON = conduction
    try std.testing.expect(evaluateCell(.{ .contact_no = 0 }, inputs_on));
}

test "NC contact logic" {
    const inputs_off = [_]bool{false} ** MAX_IO;
    const inputs_on = [_]bool{true} ** MAX_IO;

    // NC contact with input OFF = conduction
    try std.testing.expect(evaluateCell(.{ .contact_nc = 0 }, inputs_off));

    // NC contact with input ON = no conduction
    try std.testing.expect(!evaluateCell(.{ .contact_nc = 0 }, inputs_on));
}
