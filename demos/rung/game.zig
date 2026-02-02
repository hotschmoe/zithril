//! Game state machine and core logic for Rung.

const std = @import("std");
const zithril = @import("zithril");
const Allocator = std.mem.Allocator;

const ladder = @import("ladder.zig");
const levels = @import("levels.zig");
const widgets = @import("widgets.zig");

/// Component types available for placement
pub const ComponentType = enum {
    wire_horizontal,
    wire_vertical,
    contact_no, // Normally Open
    contact_nc, // Normally Closed
    coil,
    coil_latch,
    coil_unlatch,
    junction,
    empty,
};

/// A single cell in the ladder diagram
pub const Cell = union(enum) {
    empty,
    wire_h,
    wire_v,
    contact_no: u8, // input index
    contact_nc: u8, // input index
    coil: u8, // output index
    coil_latch: u8,
    coil_unlatch: u8,
    junction,
    rail_left,
    rail_right,
};

/// Position in the diagram grid
pub const Position = struct {
    x: usize,
    y: usize,
};

/// The ladder diagram grid
pub const Diagram = struct {
    cells: [][]Cell,
    width: usize,
    height: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, width: usize, height: usize) !Diagram {
        const cells = try allocator.alloc([]Cell, height);
        for (cells) |*row| {
            row.* = try allocator.alloc(Cell, width);
            @memset(row.*, .empty);
        }

        return .{
            .cells = cells,
            .width = width,
            .height = height,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Diagram) void {
        for (self.cells) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.cells);
    }

    pub fn get(self: *const Diagram, x: usize, y: usize) Cell {
        if (x >= self.width or y >= self.height) return .empty;
        return self.cells[y][x];
    }

    pub fn set(self: *Diagram, x: usize, y: usize, cell: Cell) void {
        if (x >= self.width or y >= self.height) return;
        self.cells[y][x] = cell;
    }

    pub fn clear(self: *Diagram) void {
        for (self.cells) |row| {
            @memset(row, .empty);
        }
    }
};

/// Game mode
pub const Mode = enum {
    editing,
    simulating,
    solved,
};

/// Main game state
pub const GameState = struct {
    allocator: Allocator,

    // Current level (0-indexed)
    level_index: usize,

    // The editable diagram
    diagram: Diagram,

    // Cursor position in the diagram
    cursor: Position,

    // Currently selected component for placement
    selected_component: ComponentType,

    // Game mode
    mode: Mode,

    // Simulation results for each truth table row
    results: []bool,

    // Current simulation row being shown
    sim_row: usize,

    pub fn init(allocator: Allocator) !GameState {
        // Start with level 0
        const level = levels.get(0);

        var diagram = try Diagram.init(allocator, level.width, level.height);
        level.setup(&diagram);

        const results = try allocator.alloc(bool, level.truth_table.len);
        @memset(results, false);

        return .{
            .allocator = allocator,
            .level_index = 0,
            .diagram = diagram,
            .cursor = .{ .x = 1, .y = 0 },
            .selected_component = .contact_no,
            .mode = .editing,
            .results = results,
            .sim_row = 0,
        };
    }

    pub fn deinit(self: *GameState) void {
        self.diagram.deinit();
        self.allocator.free(self.results);
    }

    pub fn loadLevel(self: *GameState, index: usize) !void {
        if (index >= levels.count()) return;

        const level = levels.get(index);
        self.level_index = index;

        // Resize diagram if needed
        self.diagram.deinit();
        self.diagram = try Diagram.init(self.allocator, level.width, level.height);
        level.setup(&self.diagram);

        // Reset results
        self.allocator.free(self.results);
        self.results = try self.allocator.alloc(bool, level.truth_table.len);
        @memset(self.results, false);

        // Reset state
        self.cursor = .{ .x = 1, .y = 0 };
        self.mode = .editing;
        self.sim_row = 0;
    }

    pub fn runSimulation(self: *GameState) void {
        const level = levels.get(self.level_index);

        // Test each row of the truth table
        var all_pass = true;
        for (level.truth_table, 0..) |row, i| {
            const actual = ladder.simulate(&self.diagram, row.inputs);
            self.results[i] = std.mem.eql(bool, &actual, &row.outputs);
            if (!self.results[i]) all_pass = false;
        }

        self.mode = if (all_pass) .solved else .simulating;
    }

    pub fn currentLevel(self: *const GameState) levels.Level {
        return levels.get(self.level_index);
    }
};

/// Handle input events
pub fn update(state: **GameState, event: zithril.Event) zithril.Action {
    const self = state.*;
    switch (event) {
        .key => |key| {
            // Global keys
            switch (key.code) {
                .char => |c| {
                    switch (c) {
                        'q', 'Q' => return .quit,
                        'r', 'R' => {
                            // Reset level
                            self.loadLevel(self.level_index) catch {};
                        },
                        'n', 'N' => {
                            // Next level (only if solved)
                            if (self.mode == .solved) {
                                self.loadLevel(self.level_index + 1) catch {};
                            }
                        },
                        ' ' => {
                            // Space: place component at cursor
                            placeComponent(self);
                        },
                        else => {},
                    }
                },
                .enter => {
                    // Run simulation
                    self.runSimulation();
                },
                .tab => {
                    // Cycle component
                    self.selected_component = cycleComponent(self.selected_component);
                },
                .left => {
                    if (self.cursor.x > 1) self.cursor.x -= 1;
                },
                .right => {
                    if (self.cursor.x < self.diagram.width - 2) self.cursor.x += 1;
                },
                .up => {
                    if (self.cursor.y > 0) self.cursor.y -= 1;
                },
                .down => {
                    if (self.cursor.y < self.diagram.height - 1) self.cursor.y += 1;
                },
                else => {},
            }
        },
        else => {},
    }

    return .none;
}

fn cycleComponent(current: ComponentType) ComponentType {
    return switch (current) {
        .wire_horizontal => .wire_vertical,
        .wire_vertical => .contact_no,
        .contact_no => .contact_nc,
        .contact_nc => .coil,
        .coil => .coil_latch,
        .coil_latch => .coil_unlatch,
        .coil_unlatch => .junction,
        .junction => .empty,
        .empty => .wire_horizontal,
    };
}

fn placeComponent(state: *GameState) void {
    const x = state.cursor.x;
    const y = state.cursor.y;

    // Don't allow editing rails (first and last columns)
    if (x == 0 or x == state.diagram.width - 1) return;

    const cell: Cell = switch (state.selected_component) {
        .wire_horizontal => .wire_h,
        .wire_vertical => .wire_v,
        .contact_no => .{ .contact_no = 0 }, // TODO: assign input
        .contact_nc => .{ .contact_nc = 0 },
        .coil => .{ .coil = 0 }, // TODO: assign output
        .coil_latch => .{ .coil_latch = 0 },
        .coil_unlatch => .{ .coil_unlatch = 0 },
        .junction => .junction,
        .empty => .empty,
    };

    state.diagram.set(x, y, cell);
    state.mode = .editing; // Clear simulation results on edit
}

/// Frame type alias for convenience
pub const FrameType = zithril.Frame(zithril.App(*GameState).DefaultMaxWidgets);

/// Render the game UI
pub fn view(state: **GameState, frame: *FrameType) void {
    const self = state.*;
    const area = frame.size();

    // Main layout: header, content, footer
    const main_chunks = frame.layout(area, .vertical, &.{
        zithril.Constraint.len(3), // Header
        zithril.Constraint.flexible(1), // Content
        zithril.Constraint.len(3), // Footer
    });

    // Header: level info and status
    frame.render(widgets.HeaderWidget{
        .level = self.level_index + 1,
        .title = self.currentLevel().name,
        .mode = self.mode,
    }, main_chunks.get(0));

    // Content: diagram on left, truth table on right
    const content_chunks = frame.layout(main_chunks.get(1), .horizontal, &.{
        zithril.Constraint.flexible(2), // Diagram (larger)
        zithril.Constraint.flexible(1), // Truth table
    });

    // Diagram panel
    frame.render(widgets.DiagramWidget{
        .diagram = &self.diagram,
        .cursor = self.cursor,
        .editing = self.mode == .editing,
    }, content_chunks.get(0));

    // Truth table panel
    frame.render(widgets.TruthTableWidget{
        .level = self.currentLevel(),
        .results = self.results,
    }, content_chunks.get(1));

    // Footer: controls and component palette
    frame.render(widgets.PaletteWidget{
        .selected = self.selected_component,
    }, main_chunks.get(2));
}
