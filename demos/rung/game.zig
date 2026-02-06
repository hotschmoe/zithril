//! Game state machine and core logic for Rung.

const std = @import("std");
const zithril = @import("zithril");
const Allocator = std.mem.Allocator;

const ladder = @import("ladder.zig");
const levels = @import("levels.zig");
const widgets = @import("widgets.zig");

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

pub const Position = struct {
    x: usize,
    y: usize,
};

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

pub const Mode = enum {
    editing,
    simulating,
    solved,
};

pub const SimPhase = enum {
    idle,
    propagating,
    showing_result,
    summary,
};

// Hit ID ranges for mouse interaction
// 0-511: diagram cells (y * 32 + x)
// 1000-1008: palette items
// 2000-2099: truth table rows
// 3000-3099: buttons
pub const HIT_DIAGRAM_BASE: u32 = 0;
pub const HIT_PALETTE_BASE: u32 = 1000;
pub const HIT_TRUTH_TABLE_BASE: u32 = 2000;
pub const HIT_BTN_BASE: u32 = 3000;

pub const HIT_BTN_SIMULATE: u32 = HIT_BTN_BASE + 0;
pub const HIT_BTN_RESET: u32 = HIT_BTN_BASE + 1;
pub const HIT_BTN_HELP: u32 = HIT_BTN_BASE + 2;
pub const HIT_BTN_LEVELS: u32 = HIT_BTN_BASE + 3;
pub const HIT_BTN_UNDO: u32 = HIT_BTN_BASE + 4;
pub const HIT_BTN_REDO: u32 = HIT_BTN_BASE + 5;
pub const HIT_BTN_NEXT: u32 = HIT_BTN_BASE + 6;
pub const HIT_BTN_PREV: u32 = HIT_BTN_BASE + 7;
pub const HIT_BTN_DESCRIPTION: u32 = HIT_BTN_BASE + 8;

const MAX_UNDO = 32;
const MAX_SNAPSHOT_DIM = 16;
const TOAST_DURATION_MS: u32 = 2000;

const DiagramSnapshot = struct {
    cells: [MAX_SNAPSHOT_DIM][MAX_SNAPSHOT_DIM]Cell,
    width: usize,
    height: usize,
    valid: bool,

    const BLANK: DiagramSnapshot = .{
        .cells = [_][MAX_SNAPSHOT_DIM]Cell{[_]Cell{.empty} ** MAX_SNAPSHOT_DIM} ** MAX_SNAPSHOT_DIM,
        .width = 0,
        .height = 0,
        .valid = false,
    };
};

const PALETTE_WIRE_H: u32 = 0;
const PALETTE_WIRE_V: u32 = 1;
const PALETTE_CONTACT_NO: u32 = 2;
const PALETTE_CONTACT_NC: u32 = 3;
const PALETTE_COIL: u32 = 4;
const PALETTE_COIL_LATCH: u32 = 5;
const PALETTE_COIL_UNLATCH: u32 = 6;
const PALETTE_JUNCTION: u32 = 7;
const PALETTE_EMPTY: u32 = 8;

pub const GameState = struct {
    allocator: Allocator,
    level_index: usize,
    diagram: Diagram,
    cursor: Position,
    selected_component: ComponentType,
    selected_index: u8, // 0=A, 1=B, etc.
    mode: Mode,
    results: []bool,
    sim_row: usize,
    show_help: bool,
    show_level_select: bool,

    hit_tester: zithril.HitTester(u32, 64),
    hover_state: zithril.HoverState,
    drag_state: zithril.DragState,
    scroll_accum: zithril.ScrollAccumulator,

    power_anim: zithril.Animation,
    victory_anim: zithril.Animation,
    mode_anim: zithril.Animation,

    undo_stack: [MAX_UNDO]DiagramSnapshot,
    undo_count: usize,
    undo_pos: usize,

    show_description: bool,
    toast_message: [64]u8,
    toast_len: usize,
    toast_timer: u32,
    moves_count: usize,

    sim_phase: SimPhase,
    sim_result: ladder.SimResult,
    sim_visible_depth: u8,
    sim_row_results: [32]?bool,
    sim_actual_outputs: [32][ladder.MAX_IO]bool,
    sim_phase_timer: u32,
    powered_cells: [MAX_SNAPSHOT_DIM][MAX_SNAPSHOT_DIM]bool,

    pub fn init(allocator: Allocator) !GameState {
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

            .hit_tester = zithril.HitTester(u32, 64).init(),
            .hover_state = zithril.HoverState{},
            .drag_state = zithril.DragState{},
            .scroll_accum = zithril.ScrollAccumulator{},

            .power_anim = zithril.Animation.init(500),
            .victory_anim = zithril.Animation.initWithEasing(1000, .elastic_out),
            .mode_anim = zithril.Animation.init(200),

            .undo_stack = [_]DiagramSnapshot{DiagramSnapshot.BLANK} ** MAX_UNDO,
            .undo_count = 0,
            .undo_pos = 0,

            .show_description = false,
            .toast_message = [_]u8{0} ** 64,
            .toast_len = 0,
            .toast_timer = 0,
            .moves_count = 0,

            .sim_phase = .idle,
            .sim_result = ladder.SimResult.init(),
            .sim_visible_depth = 0,
            .sim_row_results = [_]?bool{null} ** 32,
            .sim_actual_outputs = [_][ladder.MAX_IO]bool{[_]bool{false} ** ladder.MAX_IO} ** 32,
            .sim_phase_timer = 0,
            .powered_cells = [_][MAX_SNAPSHOT_DIM]bool{[_]bool{false} ** MAX_SNAPSHOT_DIM} ** MAX_SNAPSHOT_DIM,
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

        self.diagram.deinit();
        self.diagram = try Diagram.init(self.allocator, level.width, level.height);
        level.setup(&self.diagram);

        self.allocator.free(self.results);
        self.results = try self.allocator.alloc(bool, level.truth_table.len);
        @memset(self.results, false);

        self.cursor = .{ .x = 1, .y = 0 };
        self.mode = .editing;
        self.sim_row = 0;
        self.selected_index = 0;
        self.show_help = false;
        self.show_level_select = false;
        self.show_description = false;
        self.moves_count = 0;
        self.undo_count = 0;
        self.undo_pos = 0;
        self.toast_len = 0;
        self.toast_timer = 0;
        self.sim_phase = .idle;
        self.sim_result = ladder.SimResult.init();
        self.sim_visible_depth = 0;
        self.sim_row_results = [_]?bool{null} ** 32;
        self.sim_actual_outputs = [_][ladder.MAX_IO]bool{[_]bool{false} ** ladder.MAX_IO} ** 32;
        self.sim_phase_timer = 0;
        self.powered_cells = [_][MAX_SNAPSHOT_DIM]bool{[_]bool{false} ** MAX_SNAPSHOT_DIM} ** MAX_SNAPSHOT_DIM;

        self.power_anim.reset();
        self.victory_anim.reset();
        self.mode_anim.reset();
        self.hover_state.reset();
        self.drag_state.reset();
        self.scroll_accum.reset();
    }

    pub fn runSimulation(self: *GameState) void {
        // Reset all row results
        self.sim_row_results = [_]?bool{null} ** 32;
        self.sim_actual_outputs = [_][ladder.MAX_IO]bool{[_]bool{false} ** ladder.MAX_IO} ** 32;
        @memset(self.results, false);

        self.mode = .simulating;
        self.sim_row = 0;
        self.power_anim.reset();
        self.startRowSimulation(0);
    }

    fn startRowSimulation(self: *GameState, row_index: usize) void {
        const level = levels.get(self.level_index);
        if (row_index >= level.truth_table.len) return;

        self.sim_row = row_index;
        const row = level.truth_table[row_index];
        self.sim_result = ladder.simulateWithPower(&self.diagram, row.inputs);

        // Store actual outputs for this row
        if (row_index < 32) {
            self.sim_actual_outputs[row_index] = self.sim_result.outputs;
        }

        // Update powered_cells from depth grid at visible depth
        self.sim_visible_depth = 1;
        self.updatePoweredFromDepth();
        self.sim_phase = .propagating;
        self.sim_phase_timer = 200;
    }

    fn updatePoweredFromDepth(self: *GameState) void {
        self.powered_cells = [_][MAX_SNAPSHOT_DIM]bool{[_]bool{false} ** MAX_SNAPSHOT_DIM} ** MAX_SNAPSHOT_DIM;
        for (0..self.diagram.height) |y| {
            if (y >= MAX_SNAPSHOT_DIM) break;
            for (0..self.diagram.width) |x| {
                if (x >= MAX_SNAPSHOT_DIM) break;
                if (self.sim_result.depth[y][x] > 0 and
                    self.sim_result.depth[y][x] <= self.sim_visible_depth)
                {
                    self.powered_cells[y][x] = true;
                }
            }
        }
    }

    fn finishRowSimulation(self: *GameState) void {
        const level = levels.get(self.level_index);
        const row_index = self.sim_row;
        if (row_index >= level.truth_table.len) return;

        const row = level.truth_table[row_index];
        const pass = std.mem.eql(bool, &self.sim_result.outputs, &row.outputs);
        if (row_index < 32) {
            self.sim_row_results[row_index] = pass;
        }
        if (row_index < self.results.len) {
            self.results[row_index] = pass;
        }
    }

    fn finishAllRows(self: *GameState) void {
        const level = levels.get(self.level_index);

        var all_pass = true;
        for (level.truth_table, 0..) |row, i| {
            if (i < 32 and self.sim_row_results[i] != null) {
                if (!self.sim_row_results[i].?) all_pass = false;
                continue;
            }
            const actual = ladder.simulate(&self.diagram, row.inputs);
            const pass = std.mem.eql(bool, &actual, &row.outputs);
            if (i < 32) {
                self.sim_row_results[i] = pass;
                self.sim_actual_outputs[i] = actual;
            }
            if (i < self.results.len) self.results[i] = pass;
            if (!pass) all_pass = false;
        }

        self.sim_phase = .summary;
        self.mode = if (all_pass) .solved else .simulating;

        if (all_pass) {
            self.victory_anim.reset();
            self.showToast("SOLVED!");
        } else {
            self.showToast("Simulation complete");
        }
    }

    fn cancelSimulation(self: *GameState) void {
        self.sim_phase = .idle;
        self.mode = .editing;
        self.powered_cells = [_][MAX_SNAPSHOT_DIM]bool{[_]bool{false} ** MAX_SNAPSHOT_DIM} ** MAX_SNAPSHOT_DIM;
        self.showToast("Simulation cancelled");
    }

    pub fn currentLevel(self: *const GameState) levels.Level {
        return levels.get(self.level_index);
    }

    fn captureSnapshot(self: *const GameState) ?DiagramSnapshot {
        if (self.diagram.width > MAX_SNAPSHOT_DIM or self.diagram.height > MAX_SNAPSHOT_DIM) return null;

        var snapshot = DiagramSnapshot.BLANK;
        snapshot.width = self.diagram.width;
        snapshot.height = self.diagram.height;
        snapshot.valid = true;

        for (0..self.diagram.height) |y| {
            for (0..self.diagram.width) |x| {
                snapshot.cells[y][x] = self.diagram.get(x, y);
            }
        }
        return snapshot;
    }

    pub fn pushUndo(self: *GameState) void {
        const snapshot = self.captureSnapshot() orelse return;

        // Truncate any redo history beyond current position
        self.undo_count = self.undo_pos;

        if (self.undo_count < MAX_UNDO) {
            self.undo_stack[self.undo_count] = snapshot;
            self.undo_count += 1;
            self.undo_pos = self.undo_count;
        } else {
            for (0..MAX_UNDO - 1) |i| {
                self.undo_stack[i] = self.undo_stack[i + 1];
            }
            self.undo_stack[MAX_UNDO - 1] = snapshot;
            self.undo_pos = MAX_UNDO;
        }
    }

    pub fn undo(self: *GameState) void {
        if (self.undo_pos == 0) return;

        // Save current state for redo if we're at the tip
        if (self.undo_pos == self.undo_count) {
            self.pushCurrentAsRedo();
        }

        self.undo_pos -= 1;
        self.restoreSnapshot(self.undo_pos);
        self.mode = .editing;
        self.showToast("Undo");
    }

    pub fn redo(self: *GameState) void {
        if (self.undo_pos >= self.undo_count) return;

        self.undo_pos += 1;
        if (self.undo_pos < self.undo_count) {
            self.restoreSnapshot(self.undo_pos);
        } else if (self.undo_count > 0) {
            self.restoreSnapshot(self.undo_count - 1);
        }
        self.mode = .editing;
        self.showToast("Redo");
    }

    fn pushCurrentAsRedo(self: *GameState) void {
        const snapshot = self.captureSnapshot() orelse return;
        if (self.undo_count < MAX_UNDO) {
            self.undo_stack[self.undo_count] = snapshot;
            self.undo_count += 1;
        }
    }

    fn restoreSnapshot(self: *GameState, index: usize) void {
        if (index >= MAX_UNDO) return;
        const snapshot = self.undo_stack[index];
        if (!snapshot.valid) return;

        for (0..snapshot.height) |y| {
            for (0..snapshot.width) |x| {
                self.diagram.set(x, y, snapshot.cells[y][x]);
            }
        }
    }

    pub fn showToast(self: *GameState, msg: []const u8) void {
        const len = @min(msg.len, self.toast_message.len);
        @memcpy(self.toast_message[0..len], msg[0..len]);
        self.toast_len = len;
        self.toast_timer = TOAST_DURATION_MS;
    }

    pub fn selectPaletteItem(self: *GameState, idx: u32) void {
        self.selected_component = switch (idx) {
            PALETTE_WIRE_H => .wire_horizontal,
            PALETTE_WIRE_V => .wire_vertical,
            PALETTE_CONTACT_NO => .contact_no,
            PALETTE_CONTACT_NC => .contact_nc,
            PALETTE_COIL => .coil,
            PALETTE_COIL_LATCH => .coil_latch,
            PALETTE_COIL_UNLATCH => .coil_unlatch,
            PALETTE_JUNCTION => .junction,
            PALETTE_EMPTY => .empty,
            else => return,
        };
        self.mode_anim.reset();
    }

    pub fn handleClick(self: *GameState, id: u32) void {
        if (id < HIT_PALETTE_BASE) {
            // Diagram cell
            const pos_x = id % 32;
            const pos_y = id / 32;
            if (pos_x < self.diagram.width and pos_y < self.diagram.height) {
                self.cursor = .{ .x = pos_x, .y = pos_y };
                placeComponent(self);
            }
        } else if (id >= HIT_PALETTE_BASE and id < HIT_TRUTH_TABLE_BASE) {
            self.selectPaletteItem(id - HIT_PALETTE_BASE);
        } else if (id >= HIT_TRUTH_TABLE_BASE and id < HIT_BTN_BASE) {
            self.sim_row = id - HIT_TRUTH_TABLE_BASE;
        } else {
            self.handleButtonClick(id);
        }
    }

    fn handleButtonClick(self: *GameState, id: u32) void {
        switch (id) {
            HIT_BTN_SIMULATE => {
                self.sim_phase = .idle;
                self.runSimulation();
            },
            HIT_BTN_RESET => {
                self.loadLevel(self.level_index) catch {};
                self.showToast("Level reset");
            },
            HIT_BTN_HELP => self.show_help = !self.show_help,
            HIT_BTN_LEVELS => self.show_level_select = !self.show_level_select,
            HIT_BTN_UNDO => self.undo(),
            HIT_BTN_REDO => self.redo(),
            HIT_BTN_NEXT => {
                if (self.level_index + 1 < levels.count()) {
                    self.loadLevel(self.level_index + 1) catch {};
                }
            },
            HIT_BTN_PREV => {
                if (self.level_index > 0) {
                    self.loadLevel(self.level_index - 1) catch {};
                }
            },
            HIT_BTN_DESCRIPTION => self.show_description = !self.show_description,
            else => {},
        }
    }

    pub fn handleDragEnd(self: *GameState, mouse: zithril.Mouse) void {
        if (self.drag_state.hasMoved()) {
            // Place component at drag end position
            if (self.hit_tester.hitTest(mouse)) |id| {
                if (id < HIT_PALETTE_BASE) {
                    const pos_x = id % 32;
                    const pos_y = id / 32;
                    if (pos_x < self.diagram.width and pos_y < self.diagram.height) {
                        self.cursor = .{ .x = pos_x, .y = pos_y };
                        placeComponent(self);
                    }
                }
            }
        }
    }

    pub fn handleScroll(self: *GameState, delta: i32) void {
        if (delta < 0) {
            // Scroll up = previous component
            self.selected_component = cycleComponentReverse(self.selected_component);
        } else {
            self.selected_component = cycleComponent(self.selected_component);
        }
        self.mode_anim.reset();
    }
};

pub fn update(self: *GameState, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            // During animation, only allow escape/space/enter
            if (self.sim_phase != .idle and self.sim_phase != .summary) {
                switch (key.code) {
                    .escape => {
                        self.cancelSimulation();
                        return .none;
                    },
                    .char => |c| {
                        if (c == ' ') {
                            // Skip current row animation
                            self.sim_visible_depth = self.sim_result.max_depth;
                            self.updatePoweredFromDepth();
                            self.finishRowSimulation();
                            self.sim_phase = .showing_result;
                            self.sim_phase_timer = 200;
                            return .none;
                        } else if (c == 'q' or c == 'Q') {
                            return .quit;
                        }
                    },
                    .enter => {
                        // Skip all remaining rows
                        self.finishAllRows();
                        return .none;
                    },
                    else => {},
                }
                return .none;
            }

            if (self.show_help) {
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

            if (key.modifiers.ctrl) {
                switch (key.code) {
                    .char => |c| {
                        switch (c) {
                            'z', 'Z' => self.undo(),
                            'y', 'Y' => self.redo(),
                            'r', 'R' => {
                                self.loadLevel(self.level_index) catch {};
                                self.showToast("Level reset");
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
                return .none;
            }

            switch (key.code) {
                .char => |c| {
                    switch (c) {
                        'q', 'Q' => return .quit,
                        'r', 'R' => {
                            self.loadLevel(self.level_index) catch {};
                        },
                        'n', 'N' => {
                            if (self.mode == .solved or self.level_index + 1 < levels.count()) {
                                self.loadLevel(self.level_index + 1) catch {};
                            }
                        },
                        'p', 'P' => {
                            if (self.level_index > 0) {
                                self.loadLevel(self.level_index - 1) catch {};
                            }
                        },
                        ' ' => {
                            placeComponent(self);
                        },
                        '?' => {
                            self.show_help = true;
                        },
                        'l', 'L' => {
                            self.show_level_select = true;
                        },
                        'd', 'D' => {
                            self.show_description = !self.show_description;
                        },
                        '0'...'9' => {
                            self.selected_index = @intCast(c - '0');
                        },
                        else => {},
                    }
                },
                .enter => {
                    self.sim_phase = .idle;
                    self.runSimulation();
                },
                .tab => {
                    self.selected_component = cycleComponent(self.selected_component);
                    self.mode_anim.reset();
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
                    self.show_help = false;
                    self.show_level_select = false;
                    self.show_description = false;
                },
                else => {},
            }
        },
        .mouse => |mouse| {
            _ = self.hover_state.update(zithril.Rect.init(0, 0, 0, 0), mouse);

            // Block mouse during animation
            if (self.sim_phase != .idle and self.sim_phase != .summary) return .none;

            switch (mouse.kind) {
                .down => {
                    if (self.hit_tester.hitTest(mouse)) |id| {
                        self.handleClick(id);
                    }
                    _ = self.drag_state.handleMouse(mouse);
                },
                .up => {
                    if (self.drag_state.active) {
                        self.handleDragEnd(mouse);
                    }
                    _ = self.drag_state.handleMouse(mouse);
                },
                .drag => {
                    _ = self.drag_state.handleMouse(mouse);
                },
                .scroll_up, .scroll_down => {
                    if (self.scroll_accum.handleMouse(mouse)) |delta| {
                        self.handleScroll(delta);
                    }
                },
                .move => {},
            }
        },
        .tick => {
            _ = self.power_anim.update(100);
            _ = self.victory_anim.update(100);
            _ = self.mode_anim.update(100);

            if (self.toast_timer > 0) {
                self.toast_timer -|= 100;
                if (self.toast_timer == 0) self.toast_len = 0;
            }

            // Advance simulation animation
            if (self.sim_phase == .propagating) {
                self.sim_phase_timer -|= 100;
                if (self.sim_phase_timer == 0) {
                    self.sim_visible_depth +|= 1;
                    if (self.sim_visible_depth > self.sim_result.max_depth) {
                        self.finishRowSimulation();
                        self.updatePoweredFromDepth();
                        self.sim_phase = .showing_result;
                        self.sim_phase_timer = 800;
                    } else {
                        self.updatePoweredFromDepth();
                        self.sim_phase_timer = 200;
                    }
                }
            } else if (self.sim_phase == .showing_result) {
                self.sim_phase_timer -|= 100;
                if (self.sim_phase_timer == 0) {
                    const level = levels.get(self.level_index);
                    const next_row = self.sim_row + 1;
                    if (next_row >= level.truth_table.len) {
                        self.finishAllRows();
                    } else {
                        self.startRowSimulation(next_row);
                    }
                }
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

fn cycleComponentReverse(current: ComponentType) ComponentType {
    return switch (current) {
        .wire_horizontal => .empty,
        .wire_vertical => .wire_horizontal,
        .contact_no => .wire_vertical,
        .contact_nc => .contact_no,
        .coil => .contact_nc,
        .coil_latch => .coil,
        .coil_unlatch => .coil_latch,
        .junction => .coil_unlatch,
        .empty => .junction,
    };
}

fn componentName(comp: ComponentType) []const u8 {
    return switch (comp) {
        .wire_horizontal => "Wire (H)",
        .wire_vertical => "Wire (V)",
        .contact_no => "Contact NO",
        .contact_nc => "Contact NC",
        .coil => "Coil",
        .coil_latch => "Coil Latch",
        .coil_unlatch => "Coil Unlatch",
        .junction => "Junction",
        .empty => "Erase",
    };
}

fn placeComponent(state: *GameState) void {
    const x = state.cursor.x;
    const y = state.cursor.y;

    if (x == 0 or x == state.diagram.width - 1) return;

    state.pushUndo();
    state.moves_count += 1;

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
    state.mode = .editing;
    state.mode_anim.reset();
    state.showToast(componentName(state.selected_component));
}

pub const FrameType = zithril.Frame(zithril.App(GameState).DefaultMaxWidgets);

pub fn view(self: *GameState, frame: *FrameType) void {
    const area = frame.size();
    const level = self.currentLevel();

    self.hit_tester.clear();

    const main_chunks = frame.layout(area, .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(3),
    });

    frame.render(widgets.HeaderWidget{
        .level = self.level_index + 1,
        .title = level.name,
        .mode = self.mode,
    }, main_chunks.get(0));

    const content_chunks = frame.layout(main_chunks.get(1), .horizontal, &.{
        zithril.Constraint.flexible(2),
        zithril.Constraint.flexible(1),
    });

    const sim_active = self.sim_phase == .propagating or self.sim_phase == .showing_result;
    frame.render(widgets.DiagramWidget{
        .diagram = &self.diagram,
        .cursor = self.cursor,
        .editing = self.mode == .editing,
        .input_names = level.input_names,
        .output_names = level.output_names,
        .powered_cells = &self.powered_cells,
        .sim_depth = &self.sim_result.depth,
        .sim_visible_depth = self.sim_visible_depth,
        .sim_active = sim_active,
    }, content_chunks.get(0));

    frame.render(widgets.TruthTableWidget{
        .level = level,
        .results = self.results,
        .sim_row = self.sim_row,
        .sim_phase = self.sim_phase,
        .sim_actual_outputs = &self.sim_actual_outputs,
        .sim_row_results = &self.sim_row_results,
    }, content_chunks.get(1));

    frame.render(widgets.PaletteWidget{
        .selected = self.selected_component,
        .selected_index = self.selected_index,
        .input_names = level.input_names,
        .output_names = level.output_names,
    }, main_chunks.get(2));

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

    if (self.show_description) {
        frame.render(widgets.DescriptionOverlay{
            .level = level,
        }, area);
    }

    if (self.toast_len > 0) {
        frame.render(widgets.ToastWidget{
            .message = self.toast_message[0..self.toast_len],
            .timer = self.toast_timer,
            .max_timer = TOAST_DURATION_MS,
        }, area);
    }
}
