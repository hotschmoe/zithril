//! Ladder logic simulation engine.
//!
//! Simulates power flow through a ladder diagram using BFS flood-fill
//! propagation. Supports parallel branches via junction cells that
//! split power flow vertically between rungs.

const std = @import("std");
const game = @import("game.zig");

const Cell = game.Cell;
const Diagram = game.Diagram;

pub const MAX_IO = 8;

pub const SimResult = struct {
    outputs: [MAX_IO]bool,
    powered: [MAX_ROWS][MAX_COLS]bool,
    depth: [MAX_ROWS][MAX_COLS]u8,
    max_depth: u8,

    pub const MAX_ROWS = 16;
    pub const MAX_COLS = 16;

    pub fn init() SimResult {
        return .{
            .outputs = [_]bool{false} ** MAX_IO,
            .powered = [_][MAX_COLS]bool{[_]bool{false} ** MAX_COLS} ** MAX_ROWS,
            .depth = [_][MAX_COLS]u8{[_]u8{0} ** MAX_COLS} ** MAX_ROWS,
            .max_depth = 0,
        };
    }
};

const Direction = enum { left, right, up, down };

const QueueEntry = struct {
    x: usize,
    y: usize,
    from: Direction,
};

pub fn simulate(diagram: *const Diagram, inputs: [MAX_IO]bool) [MAX_IO]bool {
    const result = simulateWithPower(diagram, inputs);
    return result.outputs;
}

pub fn simulateWithPower(diagram: *const Diagram, inputs: [MAX_IO]bool) SimResult {
    var result = SimResult.init();
    var latches_set: [MAX_IO]bool = [_]bool{false} ** MAX_IO;
    var latches_clear: [MAX_IO]bool = [_]bool{false} ** MAX_IO;

    const MAX_QUEUE = SimResult.MAX_ROWS * SimResult.MAX_COLS * 4;
    var queue: [MAX_QUEUE]QueueEntry = undefined;
    var head: usize = 0;
    var tail: usize = 0;

    var visited: [SimResult.MAX_ROWS][SimResult.MAX_COLS][4]bool =
        [_][SimResult.MAX_COLS][4]bool{[_][4]bool{[_]bool{false} ** 4} ** SimResult.MAX_COLS} ** SimResult.MAX_ROWS;

    var current_depth: u8 = 1;

    for (0..diagram.height) |y| {
        if (y >= SimResult.MAX_ROWS) break;
        const cell = diagram.get(0, y);
        if (cell == .rail_left) {
            result.powered[y][0] = true;
            result.depth[y][0] = current_depth;
            enqueue(&queue, &tail, MAX_QUEUE, .{ .x = 1, .y = y, .from = .left });
        }
    }

    var level_end = tail;

    while (head != tail) {
        if (head == level_end) {
            current_depth +|= 1;
            level_end = tail;
        }

        const entry = queue[head];
        head = (head + 1) % MAX_QUEUE;

        const x = entry.x;
        const y = entry.y;

        if (x >= diagram.width or y >= diagram.height) continue;
        if (x >= SimResult.MAX_COLS or y >= SimResult.MAX_ROWS) continue;

        const dir_idx = @intFromEnum(entry.from);
        if (visited[y][x][dir_idx]) continue;
        visited[y][x][dir_idx] = true;

        const cell = diagram.get(x, y);

        // Check if this cell conducts given the entry direction
        if (!cellConducts(cell, entry.from, inputs)) continue;

        result.powered[y][x] = true;
        if (result.depth[y][x] == 0) {
            result.depth[y][x] = current_depth;
        }

        switch (cell) {
            .coil => |idx| {
                if (idx < MAX_IO) result.outputs[idx] = true;
            },
            .coil_latch => |idx| {
                if (idx < MAX_IO) latches_set[idx] = true;
            },
            .coil_unlatch => |idx| {
                if (idx < MAX_IO) latches_clear[idx] = true;
            },
            else => {},
        }

        const exits = cellExits(cell, entry.from);

        if (exits.right and x + 1 < diagram.width and x + 1 < SimResult.MAX_COLS) {
            enqueue(&queue, &tail, MAX_QUEUE, .{ .x = x + 1, .y = y, .from = .left });
        }
        if (exits.left and x > 0) {
            enqueue(&queue, &tail, MAX_QUEUE, .{ .x = x - 1, .y = y, .from = .right });
        }
        if (exits.down and y + 1 < diagram.height and y + 1 < SimResult.MAX_ROWS) {
            enqueue(&queue, &tail, MAX_QUEUE, .{ .x = x, .y = y + 1, .from = .up });
        }
        if (exits.up and y > 0) {
            enqueue(&queue, &tail, MAX_QUEUE, .{ .x = x, .y = y - 1, .from = .down });
        }
    }

    result.max_depth = current_depth;

    // Apply latches: set wins over clear when both active
    for (0..MAX_IO) |i| {
        if (latches_set[i]) result.outputs[i] = true;
        if (latches_clear[i] and !latches_set[i]) result.outputs[i] = false;
    }

    return result;
}

const Exits = struct {
    left: bool = false,
    right: bool = false,
    up: bool = false,
    down: bool = false,
};

fn cellConducts(cell: Cell, from: Direction, inputs: [MAX_IO]bool) bool {
    return switch (cell) {
        .empty => false,
        .wire_h => from == .left or from == .right,
        .wire_v => from == .up or from == .down,
        .junction => true,
        .contact_no => |idx| if (from == .left) (if (idx < MAX_IO) inputs[idx] else false) else false,
        .contact_nc => |idx| if (from == .left) (if (idx < MAX_IO) !inputs[idx] else true) else false,
        .coil, .coil_latch, .coil_unlatch => from == .left,
        .rail_left => true,
        .rail_right => from == .left,
    };
}

fn cellExits(cell: Cell, from: Direction) Exits {
    return switch (cell) {
        .empty => .{},
        .wire_h => switch (from) {
            .left => .{ .right = true },
            .right => .{ .left = true },
            else => .{},
        },
        .wire_v => switch (from) {
            .up => .{ .down = true },
            .down => .{ .up = true },
            else => .{},
        },
        .junction => .{ .left = true, .right = true, .up = true, .down = true },
        .contact_no, .contact_nc => .{ .right = true },
        .coil, .coil_latch, .coil_unlatch => .{ .right = true },
        .rail_left => .{ .right = true },
        .rail_right => .{},
    };
}

fn enqueue(queue: []QueueEntry, tail: *usize, max: usize, entry: QueueEntry) void {
    queue[tail.*] = entry;
    tail.* = (tail.* + 1) % max;
}

pub fn validate(diagram: *const Diagram) ValidationResult {
    var result = ValidationResult{};

    for (0..diagram.height) |y| {
        const left = diagram.get(0, y);
        if (left != .rail_left and left != .empty) {
            result.errors += 1;
        }

        const right = diagram.get(diagram.width - 1, y);
        if (right != .rail_right and right != .empty) {
            result.errors += 1;
        }

        var has_content = false;
        var has_coil = false;
        for (1..diagram.width - 1) |x| {
            const cell = diagram.get(x, y);
            if (cell != .empty) has_content = true;
            switch (cell) {
                .coil, .coil_latch, .coil_unlatch => has_coil = true,
                else => {},
            }
        }

        if (has_content and !has_coil) {
            result.warnings += 1;
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

test "NO contact logic" {
    const inputs_off = [_]bool{false} ** MAX_IO;
    const inputs_on = [_]bool{true} ** MAX_IO;

    // NO contact with input OFF = no conduction (entering from left)
    try std.testing.expect(!cellConducts(.{ .contact_no = 0 }, .left, inputs_off));

    // NO contact with input ON = conduction
    try std.testing.expect(cellConducts(.{ .contact_no = 0 }, .left, inputs_on));

    // NO contact entered from wrong direction = no conduction
    try std.testing.expect(!cellConducts(.{ .contact_no = 0 }, .right, inputs_on));
}

test "NC contact logic" {
    const inputs_off = [_]bool{false} ** MAX_IO;
    const inputs_on = [_]bool{true} ** MAX_IO;

    // NC contact with input OFF = conduction
    try std.testing.expect(cellConducts(.{ .contact_nc = 0 }, .left, inputs_off));

    // NC contact with input ON = no conduction
    try std.testing.expect(!cellConducts(.{ .contact_nc = 0 }, .left, inputs_on));
}

test "wire direction constraints" {
    const inputs = [_]bool{false} ** MAX_IO;

    // wire_h conducts left/right only
    try std.testing.expect(cellConducts(.wire_h, .left, inputs));
    try std.testing.expect(cellConducts(.wire_h, .right, inputs));
    try std.testing.expect(!cellConducts(.wire_h, .up, inputs));
    try std.testing.expect(!cellConducts(.wire_h, .down, inputs));

    // wire_v conducts up/down only
    try std.testing.expect(!cellConducts(.wire_v, .left, inputs));
    try std.testing.expect(!cellConducts(.wire_v, .right, inputs));
    try std.testing.expect(cellConducts(.wire_v, .up, inputs));
    try std.testing.expect(cellConducts(.wire_v, .down, inputs));

    // junction conducts in all directions
    try std.testing.expect(cellConducts(.junction, .left, inputs));
    try std.testing.expect(cellConducts(.junction, .right, inputs));
    try std.testing.expect(cellConducts(.junction, .up, inputs));
    try std.testing.expect(cellConducts(.junction, .down, inputs));
}

test "simple series circuit" {
    // [rail_left] [contact_no:0] [wire_h] [coil:0] [rail_right]
    var cells: [1][5]Cell = undefined;
    cells[0] = .{ .rail_left, .{ .contact_no = 0 }, .wire_h, .{ .coil = 0 }, .rail_right };

    var rows: [1][]Cell = .{&cells[0]};
    const diagram = Diagram{
        .cells = &rows,
        .width = 5,
        .height = 1,
        .allocator = undefined,
    };

    // Input OFF -> output OFF
    var inputs = [_]bool{false} ** MAX_IO;
    var result = simulateWithPower(&diagram, inputs);
    try std.testing.expect(!result.outputs[0]);
    try std.testing.expect(!result.powered[0][1]); // contact not powered

    // Input ON -> output ON
    inputs[0] = true;
    result = simulateWithPower(&diagram, inputs);
    try std.testing.expect(result.outputs[0]);
    try std.testing.expect(result.powered[0][1]); // contact powered
    try std.testing.expect(result.powered[0][3]); // coil powered

    // Depth ordering: rail(1) < contact(2) < wire(3) < coil(4)
    try std.testing.expect(result.depth[0][0] == 1); // rail_left seeded at depth 1
    try std.testing.expect(result.depth[0][1] > 0); // contact powered
    try std.testing.expect(result.depth[0][2] > result.depth[0][1]); // wire after contact
    try std.testing.expect(result.depth[0][3] > result.depth[0][2]); // coil after wire
    try std.testing.expect(result.max_depth >= result.depth[0][3]);
}

test "OR gate parallel branches" {
    // Row 0: [rail_left] [contact_no:0] [wire_h] [coil:0] [rail_right]
    // Row 1: [rail_left] [wire_h]       [empty]  [wire_h] [rail_right]
    // Row 2: [rail_left] [contact_no:1] [wire_h] [coil:0] [rail_right]
    var cells: [3][5]Cell = undefined;
    cells[0] = .{ .rail_left, .{ .contact_no = 0 }, .wire_h, .{ .coil = 0 }, .rail_right };
    cells[1] = .{ .rail_left, .wire_h, .empty, .wire_h, .rail_right };
    cells[2] = .{ .rail_left, .{ .contact_no = 1 }, .wire_h, .{ .coil = 0 }, .rail_right };

    var rows: [3][]Cell = .{ &cells[0], &cells[1], &cells[2] };
    const diagram = Diagram{
        .cells = &rows,
        .width = 5,
        .height = 3,
        .allocator = undefined,
    };

    // Both OFF -> output OFF
    var inputs = [_]bool{false} ** MAX_IO;
    var result = simulate(&diagram, inputs);
    try std.testing.expect(!result[0]);

    // A ON -> output ON
    inputs[0] = true;
    inputs[1] = false;
    result = simulate(&diagram, inputs);
    try std.testing.expect(result[0]);

    // B ON -> output ON
    inputs[0] = false;
    inputs[1] = true;
    result = simulate(&diagram, inputs);
    try std.testing.expect(result[0]);

    // Both ON -> output ON
    inputs[0] = true;
    inputs[1] = true;
    result = simulate(&diagram, inputs);
    try std.testing.expect(result[0]);
}

test "junction splits power vertically" {
    // Row 0: [rail_left] [junction] [coil:0] [rail_right]
    // Row 1: [rail_left] [junction] [coil:1] [rail_right]
    var cells: [2][4]Cell = undefined;
    cells[0] = .{ .rail_left, .junction, .{ .coil = 0 }, .rail_right };
    cells[1] = .{ .rail_left, .junction, .{ .coil = 1 }, .rail_right };

    var rows: [2][]Cell = .{ &cells[0], &cells[1] };
    const diagram = Diagram{
        .cells = &rows,
        .width = 4,
        .height = 2,
        .allocator = undefined,
    };

    const inputs = [_]bool{false} ** MAX_IO;
    const result = simulateWithPower(&diagram, inputs);
    try std.testing.expect(result.outputs[0]);
    try std.testing.expect(result.outputs[1]);
    try std.testing.expect(result.powered[0][1]); // junction row 0
    try std.testing.expect(result.powered[1][1]); // junction row 1
}

test "multi-rung output OR aggregation" {
    // Two independent rungs driving the same coil index
    // Row 0: [rail_left] [contact_no:0] [coil:0] [rail_right]
    // Row 1: [rail_left] [contact_no:1] [coil:0] [rail_right]

    var cells: [2][4]Cell = undefined;
    cells[0] = .{ .rail_left, .{ .contact_no = 0 }, .{ .coil = 0 }, .rail_right };
    cells[1] = .{ .rail_left, .{ .contact_no = 1 }, .{ .coil = 0 }, .rail_right };

    var rows: [2][]Cell = .{ &cells[0], &cells[1] };
    const diagram = Diagram{
        .cells = &rows,
        .width = 4,
        .height = 2,
        .allocator = undefined,
    };

    // Neither input -> OFF
    var inputs = [_]bool{false} ** MAX_IO;
    try std.testing.expect(!simulate(&diagram, inputs)[0]);

    // Input 0 only -> ON (OR)
    inputs[0] = true;
    try std.testing.expect(simulate(&diagram, inputs)[0]);

    // Input 1 only -> ON (OR)
    inputs[0] = false;
    inputs[1] = true;
    try std.testing.expect(simulate(&diagram, inputs)[0]);
}

test "latch set and clear" {
    // Row 0: [rail_left] [contact_no:0] [coil_latch:0] [rail_right]
    // Row 1: [rail_left] [contact_no:1] [coil_unlatch:0] [rail_right]

    var cells: [2][4]Cell = undefined;
    cells[0] = .{ .rail_left, .{ .contact_no = 0 }, .{ .coil_latch = 0 }, .rail_right };
    cells[1] = .{ .rail_left, .{ .contact_no = 1 }, .{ .coil_unlatch = 0 }, .rail_right };

    var rows: [2][]Cell = .{ &cells[0], &cells[1] };
    const diagram = Diagram{
        .cells = &rows,
        .width = 4,
        .height = 2,
        .allocator = undefined,
    };

    // SET active -> output ON
    var inputs = [_]bool{false} ** MAX_IO;
    inputs[0] = true;
    try std.testing.expect(simulate(&diagram, inputs)[0]);

    // CLEAR active -> output OFF
    inputs[0] = false;
    inputs[1] = true;
    try std.testing.expect(!simulate(&diagram, inputs)[0]);

    // Both active -> SET wins
    inputs[0] = true;
    inputs[1] = true;
    try std.testing.expect(simulate(&diagram, inputs)[0]);
}
