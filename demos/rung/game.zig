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

    // Selected input/output index for contacts/coils (0=A, 1=B, etc.)
    selected_index: u8,

    // Game mode
    mode: Mode,

    // Simulation results for each truth table row
    results: []bool,

    // Current simulation row being shown
    sim_row: usize,

    // UI state
    show_help: bool,
    show_level_select: bool,

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
            .selected_index = 0,
            .mode = .editing,
            .results = results,
            .sim_row = 0,
            .show_help = false,
            .show_level_select = false,
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
        self.selected_index = 0;
        self.show_help = false;
        self.show_level_select = false;
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
pub fn update(self: *GameState, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            // Handle overlay-specific input first
            if (self.show_help) {
                // Any key closes help
                self.show_help = false;
                return .none;
            }

            if (self.show_level_select) {
                switch (key.code) {
                    .char => |c| {
                        if (c >= '1' and c <= '9') {
                            const level_num: usize = @intCast(c - '1');
                            if (level_num < levels.count()) {
                                self.loadLevel(level_num) catch {};
                                self.show_level_select = false;
                            }
                        } else if (c == '0') {
                            // 0 = level 10
                            if (levels.count() >= 10) {
                                self.loadLevel(9) catch {};
                                self.show_level_select = false;
                            }
                        } else if (c == 'l' or c == 'L') {
                            self.show_level_select = false;
                        }
                    },
                    .escape => self.show_level_select = false,
                    else => {},
                }
                return .none;
            }

            // Normal game input
            switch (key.code) {
                .char => |c| {
                    switch (c) {
                        'q', 'Q' => return .quit,
                        'r', 'R' => {
                            // Reset level
                            self.loadLevel(self.level_index) catch {};
                        },
                        'n', 'N' => {
                            // Next level (only if solved or allow skipping)
                            if (self.mode == .solved or self.level_index + 1 < levels.count()) {
                                self.loadLevel(self.level_index + 1) catch {};
                            }
                        },
                        'p', 'P' => {
                            // Previous level
                            if (self.level_index > 0) {
                                self.loadLevel(self.level_index - 1) catch {};
                            }
                        },
                        ' ' => {
                            // Space: place component at cursor
                            placeComponent(self);
                        },
                        '?' => {
                            // Toggle help overlay
                            self.show_help = true;
                        },
                        'l', 'L' => {
                            // Toggle level select
                            self.show_level_select = true;
                        },
                        '0'...'9' => {
                            // Set selected index for contacts/coils
                            self.selected_index = @intCast(c - '0');
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
                .escape => {
                    // Close any overlay or exit edit mode
                    self.show_help = false;
                    self.show_level_select = false;
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

    const idx = state.selected_index;
    const cell: Cell = switch (state.selected_component) {
        .wire_horizontal => .wire_h,
        .wire_vertical => .wire_v,
        .contact_no => .{ .contact_no = idx },
        .contact_nc => .{ .contact_nc = idx },
        .coil => .{ .coil = idx },
        .coil_latch => .{ .coil_latch = idx },
        .coil_unlatch => .{ .coil_unlatch = idx },
        .junction => .junction,
        .empty => .empty,
    };

    state.diagram.set(x, y, cell);
    state.mode = .editing; // Clear simulation results on edit
}

/// Frame type alias for convenience
pub const FrameType = zithril.Frame(zithril.App(GameState).DefaultMaxWidgets);

/// Render the game UI
pub fn view(self: *GameState, frame: *FrameType) void {
    const area = frame.size();
    const level = self.currentLevel();

    // Main layout: header, content, footer
    const main_chunks = frame.layout(area, .vertical, &.{
        zithril.Constraint.len(3), // Header
        zithril.Constraint.flexible(1), // Content
        zithril.Constraint.len(3), // Footer
    });

    // Header: level info and status
    frame.render(widgets.HeaderWidget{
        .level = self.level_index + 1,
        .title = level.name,
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
        .input_names = level.input_names,
        .output_names = level.output_names,
    }, content_chunks.get(0));

    // Truth table panel
    frame.render(widgets.TruthTableWidget{
        .level = level,
        .results = self.results,
    }, content_chunks.get(1));

    // Footer: controls and component palette
    frame.render(widgets.PaletteWidget{
        .selected = self.selected_component,
        .selected_index = self.selected_index,
        .input_names = level.input_names,
        .output_names = level.output_names,
    }, main_chunks.get(2));

    // Overlays (rendered on top)
    if (self.mode == .solved) {
        frame.render(widgets.VictoryOverlay{
            .level = self.level_index + 1,
            .has_next = self.level_index + 1 < levels.count(),
        }, area);
    }

    if (self.show_help) {
        frame.render(widgets.HelpOverlay{}, area);
    }

    if (self.show_level_select) {
        frame.render(widgets.LevelSelectOverlay{
            .current_level = self.level_index,
            .total_levels = levels.count(),
        }, area);
    }
}
