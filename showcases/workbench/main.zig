// Workbench - Interactive Workbench Showcase
//
// A multi-panel app with 3 modes demonstrating complex interaction patterns:
// focus management, mouse handling, text input, tree navigation, and code preview.
//
// Modes (1-3 or Tab bar):
//   1. Explorer  - Tree + CodeEditor + TextInput + Menu
//   2. Agents    - Agent list + detail panel + scrollable log + Scrollbar
//   3. Mouse Lab - Hit-test regions + Hover + Drag + Scroll + event log
//
// Controls:
//   1-3: switch mode
//   Tab/Shift-Tab: cycle focus within mode
//   q / Ctrl-C: quit
//   Mode-specific keys documented per mode

const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);

const Mode = enum(usize) {
    explorer = 0,
    agents = 1,
    mouse_lab = 2,
};

const mode_count = 3;
const mode_titles = [mode_count][]const u8{
    "Explorer",
    "Agents",
    "Mouse Lab",
};

// -- Focus areas per mode --

const ExplorerFocus = enum { tree, search, preview };
const AgentsFocus = enum { agents, logs };

// -- Data types --

const AgentStatus = enum {
    idle,
    running,
    failed,
    offline,

    fn symbol(self: AgentStatus) []const u8 {
        return switch (self) {
            .idle => "[*]",
            .running => "[>]",
            .failed => "[!]",
            .offline => "[-]",
        };
    }

    fn color(self: AgentStatus) zithril.Color {
        return switch (self) {
            .idle => .green,
            .running => .cyan,
            .failed => .red,
            .offline => .white,
        };
    }
};

const Agent = struct {
    name: []const u8,
    status: AgentStatus,
    tasks_completed: u32,
    tasks_total: u32,
    last_activity: []const u8,
};

const LogEntry = struct {
    timestamp: []const u8,
    level: LogLevel,
    message: []const u8,
};

const LogLevel = enum {
    info,
    warning,
    err,
    debug,

    fn prefix(self: LogLevel) []const u8 {
        return switch (self) {
            .info => "[INFO]",
            .warning => "[WARN]",
            .err => "[ERR ]",
            .debug => "[DBG ]",
        };
    }

    fn levelColor(self: LogLevel) zithril.Color {
        return switch (self) {
            .info => .cyan,
            .warning => .yellow,
            .err => .red,
            .debug => .white,
        };
    }
};

const RegionId = enum(u8) { red = 0, green = 1, blue = 2, yellow = 3 };
const region_count = 4;
const region_colors = [region_count]zithril.Color{ .red, .green, .blue, .yellow };
const region_labels = [region_count][]const u8{ "Red", "Green", "Blue", "Yellow" };

const max_log_entries = 32;

// -- State --

const State = struct {
    current_mode: Mode = .explorer,

    // Explorer mode
    exp_focus: ExplorerFocus = .tree,
    exp_tree_selected: usize = 0,
    exp_src_expanded: bool = true,
    exp_docs_expanded: bool = false,
    exp_show_menu: bool = false,
    exp_menu_state: zithril.MenuState = .{},
    exp_search_buf: [256]u8 = [_]u8{0} ** 256,
    exp_search_state: ?zithril.TextInputState = null,

    // Agents mode
    agt_focus: AgentsFocus = .agents,
    agt_selected_agent: usize = 0,
    agt_log_scroll: usize = 0,

    // Mouse Lab mode
    mouse_x: u16 = 0,
    mouse_y: u16 = 0,
    mouse_kind: ?zithril.MouseKind = null,
    hit_tester: zithril.HitTester(RegionId, region_count) = zithril.HitTester(RegionId, region_count).init(),
    hover_states: [region_count]zithril.HoverState = [_]zithril.HoverState{.{}} ** region_count,
    active_region: ?RegionId = null,
    drag: zithril.DragState = .{},
    scroll: zithril.ScrollAccumulator = .{},
    ml_log_buf: [max_log_entries][80]u8 = undefined,
    ml_log_lens: [max_log_entries]u8 = [_]u8{0} ** max_log_entries,
    ml_log_count: usize = 0,
    scroll_total: i32 = 0,
    click_count: u32 = 0,

    fn getSearchState(self: *State) *zithril.TextInputState {
        if (self.exp_search_state == null) {
            self.exp_search_state = zithril.TextInputState.init(&self.exp_search_buf);
        }
        return &self.exp_search_state.?;
    }

    fn visibleItems(self: *const State) []const []const u8 {
        if (self.exp_src_expanded and self.exp_docs_expanded) return &tree_order_all;
        if (self.exp_src_expanded) return &tree_order_src_only;
        if (self.exp_docs_expanded) return &tree_order_docs_only;
        return &tree_order_none;
    }

    fn selectedKey(self: *const State) []const u8 {
        const items = self.visibleItems();
        return if (self.exp_tree_selected < items.len) items[self.exp_tree_selected] else "src/";
    }

    fn moveTree(self: *State, delta: i32) void {
        const max = self.visibleItems().len;
        if (delta > 0) {
            self.exp_tree_selected = @min(self.exp_tree_selected + 1, max - 1);
        } else if (self.exp_tree_selected > 0) {
            self.exp_tree_selected -= 1;
        }
    }

    fn addMouseLog(self: *State, msg: []const u8) void {
        if (self.ml_log_count >= max_log_entries) {
            var i: usize = 0;
            while (i < max_log_entries - 1) : (i += 1) {
                self.ml_log_buf[i] = self.ml_log_buf[i + 1];
                self.ml_log_lens[i] = self.ml_log_lens[i + 1];
            }
            self.ml_log_count = max_log_entries - 1;
        }
        const idx = self.ml_log_count;
        const len = @min(msg.len, 80);
        @memcpy(self.ml_log_buf[idx][0..len], msg[0..len]);
        self.ml_log_lens[idx] = @intCast(len);
        self.ml_log_count += 1;
    }

    fn getMouseLog(self: *const State, idx: usize) []const u8 {
        return self.ml_log_buf[idx][0..self.ml_log_lens[idx]];
    }
};

// -- Explorer file data --

const FileEntry = struct {
    name: []const u8,
    content: []const u8,
    is_code: bool = false,
};

const file_entries = std.StaticStringMap(FileEntry).initComptime(.{
    .{ "src/", FileEntry{ .name = "src/", .content = "Directory: src/\nContains Zig source files for the project." } },
    .{ "main.zig", FileEntry{ .name = "main.zig", .is_code = true, .content = "const std = @import(\"std\");\n\npub fn main() !void {\n    const stdout = std.io.getStdOut().writer();\n    try stdout.print(\"Hello, {s}!\\n\", .{\"World\"});\n}" } },
    .{ "lib.zig", FileEntry{ .name = "lib.zig", .is_code = true, .content = "const std = @import(\"std\");\n\npub fn add(a: i32, b: i32) i32 {\n    return a + b;\n}" } },
    .{ "docs/", FileEntry{ .name = "docs/", .content = "Directory: docs/\nContains project documentation and guides." } },
    .{ "README.md", FileEntry{ .name = "README.md", .content = "# Project Documentation\n\nWelcome to the file explorer!\n\n## Controls\n- j/k: navigate\n- Tab: cycle focus\n- Enter: expand/collapse\n- m: context menu\n- q: quit" } },
    .{ "build.zig", FileEntry{ .name = "build.zig", .is_code = true, .content = "const std = @import(\"std\");\n\npub fn build(b: *std.Build) void {\n    const target = b.standardTargetOptions(.{});\n    _ = target;\n}" } },
});

const tree_order_all = [_][]const u8{ "src/", "main.zig", "lib.zig", "docs/", "README.md", "build.zig" };
const tree_order_src_only = [_][]const u8{ "src/", "main.zig", "lib.zig", "docs/", "build.zig" };
const tree_order_docs_only = [_][]const u8{ "src/", "docs/", "README.md", "build.zig" };
const tree_order_none = [_][]const u8{ "src/", "docs/", "build.zig" };

// -- Agent sample data --

const sample_agents = [_]Agent{
    .{ .name = "agent-alpha", .status = .running, .tasks_completed = 42, .tasks_total = 100, .last_activity = "2m ago" },
    .{ .name = "agent-beta", .status = .idle, .tasks_completed = 100, .tasks_total = 100, .last_activity = "5m ago" },
    .{ .name = "agent-gamma", .status = .failed, .tasks_completed = 23, .tasks_total = 50, .last_activity = "1m ago" },
    .{ .name = "agent-delta", .status = .running, .tasks_completed = 78, .tasks_total = 200, .last_activity = "30s ago" },
    .{ .name = "agent-epsilon", .status = .offline, .tasks_completed = 0, .tasks_total = 0, .last_activity = "1h ago" },
    .{ .name = "agent-zeta", .status = .idle, .tasks_completed = 50, .tasks_total = 50, .last_activity = "10m ago" },
};

const sample_logs = [_]LogEntry{
    .{ .timestamp = "10:42:01", .level = .info, .message = "agent-alpha started task batch #42" },
    .{ .timestamp = "10:42:05", .level = .debug, .message = "Heartbeat received from agent-delta" },
    .{ .timestamp = "10:42:10", .level = .warning, .message = "agent-gamma memory usage at 85%" },
    .{ .timestamp = "10:42:15", .level = .err, .message = "agent-gamma: Task failed - timeout" },
    .{ .timestamp = "10:42:20", .level = .info, .message = "agent-beta completed all tasks" },
    .{ .timestamp = "10:42:25", .level = .info, .message = "agent-delta processing item 78/200" },
    .{ .timestamp = "10:42:30", .level = .debug, .message = "Connection pool: 5 active, 3 idle" },
    .{ .timestamp = "10:42:35", .level = .info, .message = "agent-alpha checkpoint saved" },
    .{ .timestamp = "10:42:40", .level = .warning, .message = "agent-epsilon: No heartbeat in 60s" },
    .{ .timestamp = "10:42:45", .level = .err, .message = "agent-epsilon marked offline" },
    .{ .timestamp = "10:42:50", .level = .info, .message = "agent-zeta task batch complete" },
    .{ .timestamp = "10:42:55", .level = .debug, .message = "Metrics: 250 tasks/min avg" },
    .{ .timestamp = "10:43:00", .level = .info, .message = "System health: OK" },
    .{ .timestamp = "10:43:05", .level = .info, .message = "New task batch queued for agent-alpha" },
    .{ .timestamp = "10:43:10", .level = .debug, .message = "Cache hit ratio: 94.2%" },
};

// -- Update --

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            switch (key.code) {
                .char => |c| {
                    if (c == 'q' and !key.modifiers.any()) return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;

                    if (!key.modifiers.any()) {
                        // Mode switching
                        if (c >= '1' and c <= '3') {
                            state.current_mode = @enumFromInt(c - '1');
                            return .none;
                        }

                        switch (state.current_mode) {
                            .explorer => updateExplorer(state, key),
                            .agents => updateAgents(state, c),
                            .mouse_lab => {},
                        }
                    } else if (state.current_mode == .explorer and state.exp_focus == .search) {
                        _ = state.getSearchState().handleKey(key);
                    }
                },
                .tab => if (!key.modifiers.any()) {
                    switch (state.current_mode) {
                        .explorer => state.exp_focus = switch (state.exp_focus) {
                            .tree => .search,
                            .search => .preview,
                            .preview => .tree,
                        },
                        .agents => state.agt_focus = switch (state.agt_focus) {
                            .agents => .logs,
                            .logs => .agents,
                        },
                        .mouse_lab => {},
                    }
                },
                .backtab => {
                    switch (state.current_mode) {
                        .explorer => state.exp_focus = switch (state.exp_focus) {
                            .tree => .preview,
                            .search => .tree,
                            .preview => .search,
                        },
                        .agents => state.agt_focus = switch (state.agt_focus) {
                            .agents => .logs,
                            .logs => .agents,
                        },
                        .mouse_lab => {},
                    }
                },
                .enter => {
                    if (state.current_mode == .explorer and state.exp_focus == .tree) {
                        const key_name = state.selectedKey();
                        if (std.mem.eql(u8, key_name, "src/")) state.exp_src_expanded = !state.exp_src_expanded;
                        if (std.mem.eql(u8, key_name, "docs/")) state.exp_docs_expanded = !state.exp_docs_expanded;
                    }
                },
                .escape => {
                    if (state.current_mode == .explorer) state.exp_show_menu = false;
                },
                .up => if (!key.modifiers.any()) switch (state.current_mode) {
                    .explorer => if (state.exp_focus == .tree) state.moveTree(-1),
                    .agents => switch (state.agt_focus) {
                        .agents => {
                            if (state.agt_selected_agent > 0) state.agt_selected_agent -= 1;
                        },
                        .logs => {
                            if (state.agt_log_scroll > 0) state.agt_log_scroll -= 1;
                        },
                    },
                    .mouse_lab => {},
                },
                .down => if (!key.modifiers.any()) switch (state.current_mode) {
                    .explorer => if (state.exp_focus == .tree) state.moveTree(1),
                    .agents => switch (state.agt_focus) {
                        .agents => {
                            if (state.agt_selected_agent < sample_agents.len - 1) state.agt_selected_agent += 1;
                        },
                        .logs => state.agt_log_scroll +|= 1,
                    },
                    .mouse_lab => {},
                },
                else => {
                    if (state.current_mode == .explorer and state.exp_focus == .search) {
                        _ = state.getSearchState().handleKey(key);
                    }
                },
            }
        },
        .mouse => |mouse| {
            if (state.current_mode == .mouse_lab) {
                updateMouseLab(state, mouse);
            }
        },
        else => {},
    }
    return .none;
}

fn updateExplorer(state: *State, key: zithril.Key) void {
    if (state.exp_show_menu) {
        switch (key.code) {
            .char => |c| {
                if (c == 'j') {
                    state.exp_menu_state.path[0] = @min(state.exp_menu_state.path[0] + 1, 3);
                } else if (c == 'k' and state.exp_menu_state.path[0] > 0) {
                    state.exp_menu_state.path[0] -= 1;
                }
            },
            else => {},
        }
        return;
    }

    switch (key.code) {
        .char => |c| switch (c) {
            'j' => if (state.exp_focus == .tree) state.moveTree(1),
            'k' => if (state.exp_focus == .tree) state.moveTree(-1),
            'm' => state.exp_show_menu = !state.exp_show_menu,
            else => if (state.exp_focus == .search) {
                _ = state.getSearchState().handleKey(key);
            },
        },
        else => {},
    }
}

fn updateAgents(state: *State, c: u21) void {
    switch (c) {
        'j' => switch (state.agt_focus) {
            .agents => {
                if (state.agt_selected_agent < sample_agents.len - 1)
                    state.agt_selected_agent += 1;
            },
            .logs => state.agt_log_scroll +|= 1,
        },
        'k' => switch (state.agt_focus) {
            .agents => {
                if (state.agt_selected_agent > 0) state.agt_selected_agent -= 1;
            },
            .logs => {
                if (state.agt_log_scroll > 0) state.agt_log_scroll -= 1;
            },
        },
        else => {},
    }
}

fn updateMouseLab(state: *State, mouse: zithril.Mouse) void {
    state.mouse_x = mouse.x;
    state.mouse_y = mouse.y;
    state.mouse_kind = mouse.kind;

    state.active_region = state.hit_tester.hitTest(mouse);

    for (0..region_count) |i| {
        const region_idx: u8 = @intCast(i);
        if (region_idx < state.hit_tester.count) {
            const rect = state.hit_tester.regions[i].rect;
            const transition = state.hover_states[i].update(rect, mouse);
            if (transition == .entered) {
                var buf: [80]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Hover entered: {s}", .{region_labels[i]}) catch "hover enter";
                state.addMouseLog(msg);
            } else if (transition == .exited) {
                var buf: [80]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Hover exited: {s}", .{region_labels[i]}) catch "hover exit";
                state.addMouseLog(msg);
            }
        }
    }

    if (state.drag.handleMouse(mouse)) {
        if (mouse.kind == .down) {
            var buf: [80]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Drag start: ({d},{d})", .{ mouse.x, mouse.y }) catch "drag start";
            state.addMouseLog(msg);
        } else if (mouse.kind == .up and state.drag.hasMoved()) {
            const d = state.drag.delta();
            var buf: [80]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Drag end: delta=({d},{d})", .{ d.dx, d.dy }) catch "drag end";
            state.addMouseLog(msg);
        }
    }

    if (mouse.kind == .down) state.click_count += 1;

    if (state.scroll.handleMouse(mouse)) |delta| {
        state.scroll_total += delta;
        var buf: [80]u8 = undefined;
        const dir: []const u8 = if (delta < 0) "up" else "down";
        const msg = std.fmt.bufPrint(&buf, "Scroll {s} (total: {d})", .{ dir, state.scroll_total }) catch "scroll";
        state.addMouseLog(msg);
    }
}

// -- View --

fn view(state: *State, frame: *FrameType) void {
    const area = frame.size();

    const main_layout = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    // Mode tabs
    frame.render(zithril.Tabs{
        .titles = &mode_titles,
        .selected = @intFromEnum(state.current_mode),
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bold().fg(.yellow).bg(.blue),
        .divider = " | ",
    }, main_layout.get(0));

    // Content
    const content_area = main_layout.get(1);
    switch (state.current_mode) {
        .explorer => renderExplorer(state, frame, content_area),
        .agents => renderAgents(state, frame, content_area),
        .mouse_lab => renderMouseLab(state, frame, content_area),
    }

    // Status bar
    var status_buf: [80]u8 = undefined;
    const mode_str = mode_titles[@intFromEnum(state.current_mode)];
    const status = std.fmt.bufPrint(&status_buf, " Workbench | {s} | 1-3:mode Tab:focus j/k:nav q:quit", .{mode_str}) catch " Workbench";
    frame.render(zithril.Text{
        .content = status,
        .style = zithril.Style.init().bg(.blue).fg(.white).bold(),
    }, main_layout.get(2));
}

// ============================================================
// MODE 1: EXPLORER (from explorer/main.zig)
// ============================================================

fn focusBorderStyle(focused: bool) zithril.Style {
    return if (focused) zithril.Style.init().fg(.yellow).bold() else zithril.Style.init().fg(.cyan);
}

fn renderExplorer(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const rows = zithril.layout(area, .vertical, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(3),
    });
    const content = zithril.layout(rows.get(0), .horizontal, &.{
        zithril.Constraint.fractional(1, 3),
        zithril.Constraint.fractional(2, 3),
    });

    renderExpTree(state, frame, content.get(0));
    renderExpPreview(state, frame, content.get(1));
    renderExpSearch(state, frame, rows.get(1));

    if (state.exp_show_menu) renderExpMenu(state, frame);
}

fn renderExpTree(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .title = " File Tree ", .border = .rounded, .border_style = focusBorderStyle(state.exp_focus == .tree) };
    frame.render(block, area);

    const FileTree = zithril.Tree([]const u8);
    const Item = zithril.TreeItem([]const u8);

    const src_children = [_]Item{
        .{ .data = "main.zig", .children = &.{} },
        .{ .data = "lib.zig", .children = &.{} },
    };
    const docs_children = [_]Item{
        .{ .data = "README.md", .children = &.{} },
    };
    const tree_items = [_]Item{
        .{ .data = "src/", .expanded = state.exp_src_expanded, .children = &src_children },
        .{ .data = "docs/", .expanded = state.exp_docs_expanded, .children = &docs_children },
        .{ .data = "build.zig", .children = &.{} },
    };

    frame.render(FileTree{
        .items = &tree_items,
        .selected = state.exp_tree_selected,
        .offset = 0,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white).bold(),
        .indent = 2,
        .render_fn = &struct {
            fn f(data: []const u8) []const u8 {
                return data;
            }
        }.f,
        .symbols = .{},
    }, block.inner(area));
}

fn renderExpPreview(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .title = " Preview ", .border = .rounded, .border_style = focusBorderStyle(state.exp_focus == .preview) };
    frame.render(block, area);
    const inner = block.inner(area);

    const entry = file_entries.get(state.selectedKey());
    if (entry) |e| {
        if (e.is_code) {
            frame.render(zithril.CodeEditor{
                .content = e.content,
                .language = .zig,
                .theme = zithril.CodeEditorTheme.default,
                .show_line_numbers = true,
                .current_line = 0,
                .scroll_y = 0,
                .style = zithril.Style.empty,
            }, inner);
        } else {
            frame.render(zithril.Paragraph{
                .text = e.content,
                .style = zithril.Style.init().fg(.white),
                .wrap = .word,
            }, inner);
        }
    } else {
        frame.render(zithril.Paragraph{
            .text = "No file selected",
            .style = zithril.Style.init().fg(.bright_black),
            .wrap = .word,
        }, inner);
    }
}

fn renderExpSearch(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .title = " Search ", .border = .rounded, .border_style = focusBorderStyle(state.exp_focus == .search) };
    frame.render(block, area);
    frame.render(zithril.TextInput{
        .state = state.getSearchState(),
        .style = zithril.Style.init().fg(.white),
        .cursor_style = zithril.Style.init().reverse(),
        .placeholder = "Type to search files...",
        .placeholder_style = zithril.Style.init().fg(.bright_black),
    }, block.inner(area));
}

fn renderExpMenu(state: *State, frame: *FrameType) void {
    const menu_items = [_]zithril.MenuItem{
        .{ .label = "Open", .shortcut = "Enter" },
        .{ .label = "Copy", .shortcut = "c" },
        .{ .separator = true },
        .{ .label = "Delete", .shortcut = "d", .enabled = false },
    };

    const menu = zithril.Menu{
        .items = &menu_items,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white),
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    menu.render(zithril.Rect.init(25, 8, 28, 8), frame.buffer, state.exp_menu_state);
}

// ============================================================
// MODE 2: AGENTS (from ralph.zig)
// ============================================================

fn renderAgents(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const h_chunks = zithril.layout(area, .horizontal, &.{
        zithril.Constraint.len(30),
        zithril.Constraint.flexible(1),
    });

    renderAgtList(state, frame, h_chunks.get(0));
    renderAgtRight(state, frame, h_chunks.get(1));
}

fn renderAgtList(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const is_focused = state.agt_focus == .agents;
    const border_color: zithril.Color = if (is_focused) .cyan else .white;

    const block = zithril.Block{
        .title = if (is_focused) "Agents [*]" else "Agents",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(border_color),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    var items: [16][]const u8 = undefined;
    var bufs: [16][64]u8 = undefined;
    const count = @min(sample_agents.len, 16);

    for (sample_agents[0..count], 0..count) |agent, i| {
        const display = std.fmt.bufPrint(&bufs[i], "{s} {s}", .{ agent.status.symbol(), agent.name }) catch agent.name;
        items[i] = display;
    }

    const list = zithril.List{
        .items = items[0..count],
        .selected = if (is_focused) state.agt_selected_agent else null,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white).bold(),
        .highlight_symbol = "> ",
    };
    frame.render(list, inner);
}

fn renderAgtRight(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const v_chunks = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(10),
        zithril.Constraint.flexible(1),
    });

    renderAgtDetail(state, frame, v_chunks.get(0));
    renderAgtLogs(state, frame, v_chunks.get(1));
}

fn renderAgtDetail(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Agent Details",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.white),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    const idx = @min(state.agt_selected_agent, sample_agents.len - 1);
    const agent = sample_agents[idx];

    const detail_chunks = zithril.layout(inner, .vertical, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    var buf: [256]u8 = undefined;
    const info_text = std.fmt.bufPrint(&buf,
        \\Name: {s}
        \\Status: {s}
        \\Last Activity: {s}
        \\Tasks: {d}/{d}
    , .{
        agent.name,
        @tagName(agent.status),
        agent.last_activity,
        agent.tasks_completed,
        agent.tasks_total,
    }) catch "No data";

    frame.render(zithril.Paragraph{
        .text = info_text,
        .style = zithril.Style.init().fg(.white),
        .wrap = .none,
    }, detail_chunks.get(0));

    const ratio: f32 = if (agent.tasks_total > 0)
        @as(f32, @floatFromInt(agent.tasks_completed)) / @as(f32, @floatFromInt(agent.tasks_total))
    else
        0.0;

    var gauge_label_buf: [16]u8 = undefined;
    const gauge_label = std.fmt.bufPrint(&gauge_label_buf, "{d}%", .{@as(u8, @intFromFloat(ratio * 100))}) catch "";

    frame.render(zithril.Gauge{
        .ratio = ratio,
        .label = gauge_label,
        .style = zithril.Style.init().bg(.black),
        .gauge_style = zithril.Style.init().bg(agent.status.color()),
    }, detail_chunks.get(1));
}

fn renderAgtLogs(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const is_focused = state.agt_focus == .logs;
    const border_color: zithril.Color = if (is_focused) .cyan else .white;

    const block = zithril.Block{
        .title = if (is_focused) "Logs [*]" else "Logs",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(border_color),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    const visible_lines = inner.height;
    const max_scroll = if (sample_logs.len > visible_lines)
        sample_logs.len - visible_lines
    else
        0;
    const scroll_offset = @min(state.agt_log_scroll, max_scroll);

    var y: u16 = 0;
    const end_idx = @min(scroll_offset + visible_lines, sample_logs.len);

    for (sample_logs[scroll_offset..end_idx]) |entry| {
        if (y >= inner.height) break;

        var line_buf: [128]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{s} {s} {s}", .{
            entry.timestamp,
            entry.level.prefix(),
            entry.message,
        }) catch entry.message;

        const text = zithril.Text{
            .content = line,
            .style = zithril.Style.init().fg(entry.level.levelColor()),
            .alignment = .left,
        };

        const line_area = zithril.Rect.init(inner.x, inner.y + y, inner.width, 1);
        frame.render(text, line_area);
        y += 1;
    }

    if (sample_logs.len > visible_lines) {
        const scrollbar_area = zithril.Rect.init(area.right() -| 1, inner.y, 1, inner.height);
        frame.render(zithril.Scrollbar{
            .total = sample_logs.len,
            .position = scroll_offset,
            .viewport = visible_lines,
            .style = zithril.Style.init().fg(.white),
            .orientation = .vertical,
        }, scrollbar_area);
    }
}

// ============================================================
// MODE 3: MOUSE LAB (from mouse_demo.zig)
// ============================================================

fn renderMouseLab(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const main_chunks = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.flexible(1),
    });

    renderMlHeader(state, frame, main_chunks.get(0));
    renderMlContent(state, frame, main_chunks.get(1));
}

fn renderMlHeader(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Mouse Lab",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    var buf: [128]u8 = undefined;
    const kind_str: []const u8 = if (state.mouse_kind) |k| @tagName(k) else "none";
    const region_str: []const u8 = if (state.active_region) |r| region_labels[@intFromEnum(r)] else "none";
    const info = std.fmt.bufPrint(&buf, "Pos: ({d},{d})  Event: {s}  Region: {s}  Clicks: {d}", .{
        state.mouse_x,
        state.mouse_y,
        kind_str,
        region_str,
        state.click_count,
    }) catch "???";

    frame.render(zithril.Text{
        .content = info,
        .style = zithril.Style.init().fg(.white),
        .alignment = .left,
    }, inner);
}

fn renderMlContent(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const h_chunks = zithril.layout(area, .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    renderMlRegions(state, frame, h_chunks.get(0));
    renderMlEventLog(state, frame, h_chunks.get(1));
}

fn renderMlRegions(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Hover Regions",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.white),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    const v_chunks = zithril.layout(inner, .vertical, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });
    const top_h = zithril.layout(v_chunks.get(0), .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });
    const bot_h = zithril.layout(v_chunks.get(1), .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    const regions = [region_count]zithril.Rect{
        top_h.get(0),
        top_h.get(1),
        bot_h.get(0),
        bot_h.get(1),
    };

    state.hit_tester.clear();
    for (0..region_count) |i| {
        _ = state.hit_tester.register(@enumFromInt(i), regions[i]);
    }

    for (0..region_count) |i| {
        const hovered = state.hover_states[i].isHovering();
        const clr = region_colors[i];
        const border_style = if (hovered)
            zithril.Style.init().fg(clr).bold()
        else
            zithril.Style.init().fg(clr);

        const region_block = zithril.Block{
            .title = region_labels[i],
            .border = if (hovered) .double else .rounded,
            .border_style = border_style,
        };
        frame.render(region_block, regions[i]);

        const region_inner = region_block.inner(regions[i]);
        if (!region_inner.isEmpty()) {
            const fill_style = if (hovered)
                zithril.Style.init().bg(clr)
            else
                zithril.Style.init();
            frame.render(zithril.Clear{ .style = fill_style }, region_inner);

            if (hovered) {
                frame.render(zithril.Text{
                    .content = "[HOVER]",
                    .style = zithril.Style.init().fg(.white).bold(),
                    .alignment = .center,
                }, region_inner);
            }
        }
    }

    if (state.drag.active) {
        if (state.drag.selectionRect()) |sel| {
            frame.render(zithril.Block{
                .border = .plain,
                .border_style = zithril.Style.init().fg(.magenta).bold(),
            }, sel);
        }
    }
}

fn renderMlEventLog(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Event Log",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.white),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    const visible: usize = inner.height;
    const start = if (state.ml_log_count > visible) state.ml_log_count - visible else 0;
    const end = state.ml_log_count;

    var y: u16 = 0;
    for (start..end) |i| {
        if (y >= inner.height) break;
        const line_area = zithril.Rect.init(inner.x, inner.y + y, inner.width, 1);
        frame.render(zithril.Text{
            .content = state.getMouseLog(i),
            .style = zithril.Style.init().fg(.cyan),
            .alignment = .left,
        }, line_area);
        y += 1;
    }

    if (state.ml_log_count == 0) {
        frame.render(zithril.Text{
            .content = "Move, click, or scroll...",
            .style = zithril.Style.init().fg(.white).italic(),
            .alignment = .center,
        }, inner);
    }
}

// -- Main --

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var state = State{};
    var app = zithril.App(State).init(.{
        .state = &state,
        .update = update,
        .view = view,
        .mouse_capture = true,
    });
    try app.run(gpa.allocator());
}

pub const panic = zithril.terminal_panic;

// ============================================================
// QA COMPANION TESTS
// ============================================================
// Demonstrate TestHarness, MockBackend, TestRecorder/TestPlayer,
// auditKeyboardNav, auditFocusVisibility, auditContrast, and
// ScenarioRunner using the Workbench's own State/update/view.

const testing_alloc = std.testing.allocator;

test "workbench: initial render shows Explorer mode" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    try std.testing.expectEqual(Mode.explorer, state.current_mode);
    // Tab bar should show the Explorer tab
    try harness.expectString(0, 0, "Explorer");
}

test "workbench: mode switching via number keys" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    harness.pressKey('2');
    try std.testing.expectEqual(Mode.agents, state.current_mode);

    harness.pressKey('3');
    try std.testing.expectEqual(Mode.mouse_lab, state.current_mode);

    harness.pressKey('1');
    try std.testing.expectEqual(Mode.explorer, state.current_mode);
}

test "workbench: explorer focus cycling via Tab" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    try std.testing.expectEqual(ExplorerFocus.tree, state.exp_focus);

    harness.pressSpecial(.tab);
    try std.testing.expectEqual(ExplorerFocus.search, state.exp_focus);

    harness.pressSpecial(.tab);
    try std.testing.expectEqual(ExplorerFocus.preview, state.exp_focus);

    harness.pressSpecial(.tab);
    try std.testing.expectEqual(ExplorerFocus.tree, state.exp_focus);
}

test "workbench: agents focus cycling via Tab" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    harness.pressKey('2');
    try std.testing.expectEqual(AgentsFocus.agents, state.agt_focus);

    harness.pressSpecial(.tab);
    try std.testing.expectEqual(AgentsFocus.logs, state.agt_focus);

    harness.pressSpecial(.tab);
    try std.testing.expectEqual(AgentsFocus.agents, state.agt_focus);
}

test "workbench: quit via q key" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    harness.pressKey('q');
    try harness.expectQuit();
}

test "workbench: explorer tree navigation" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    // Navigate down in tree
    harness.pressKey('j');
    try std.testing.expectEqual(@as(usize, 1), state.exp_tree_selected);

    harness.pressKey('j');
    try std.testing.expectEqual(@as(usize, 2), state.exp_tree_selected);

    // Navigate up
    harness.pressKey('k');
    try std.testing.expectEqual(@as(usize, 1), state.exp_tree_selected);
}

test "workbench: agents list navigation" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    harness.pressKey('2');
    try std.testing.expectEqual(Mode.agents, state.current_mode);

    harness.pressKey('j');
    try std.testing.expectEqual(@as(usize, 1), state.agt_selected_agent);

    harness.pressKey('k');
    try std.testing.expectEqual(@as(usize, 0), state.agt_selected_agent);
}

test "workbench: mouse lab click tracking" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    harness.pressKey('3');
    try std.testing.expectEqual(Mode.mouse_lab, state.current_mode);

    // Click updates mouse position
    harness.click(10, 10);
    try std.testing.expectEqual(@as(u16, 10), state.mouse_x);
    try std.testing.expectEqual(@as(u16, 10), state.mouse_y);
}

test "workbench: MockBackend headless demo" {
    var mock = try zithril.MockBackend.init(testing_alloc, 80, 24);
    defer mock.deinit();

    try std.testing.expectEqual(@as(u16, 80), mock.width);
    try std.testing.expectEqual(@as(u16, 24), mock.height);

    mock.enterRawMode();
    mock.enterAlternateScreen();
    try std.testing.expect(mock.raw_mode);
    try std.testing.expect(mock.alternate_screen);

    try mock.write("Workbench test output");
    try std.testing.expect(mock.outputContains("Workbench"));
    try std.testing.expectEqual(@as(usize, 1), mock.write_count);

    mock.reset();
    try std.testing.expect(!mock.raw_mode);
}

test "workbench: TestRecorder and TestPlayer demo" {
    var recorder = zithril.TestRecorder(256).init();

    const key_j = zithril.testing.keyEvent('j');
    const key_k = zithril.testing.keyEvent('k');
    const tab_ev = zithril.testing.specialKeyEvent(.tab);

    _ = recorder.recordSimple(key_j);
    _ = recorder.recordSimple(key_j);
    _ = recorder.recordSimple(tab_ev);
    _ = recorder.recordSimple(key_k);
    try std.testing.expectEqual(@as(usize, 4), recorder.len());

    var player = zithril.TestPlayer(256).init(recorder.getEvents());
    try std.testing.expectEqual(@as(usize, 4), player.remaining());

    // Play events into a harness
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    while (player.next()) |ev| {
        harness.inject(ev);
    }
    try std.testing.expect(player.isDone());
}

test "workbench: auditContrast on rendered buffer" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    const buf = harness.getBuffer();
    var result = try zithril.auditContrast(testing_alloc, buf);
    defer result.deinit();

    try std.testing.expectEqual(zithril.AuditCategory.contrast, result.category);
}

test "workbench: auditKeyboardNav detects focus cycling" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    var result = try zithril.auditKeyboardNav(State, testing_alloc, &harness, .{});
    defer result.deinit();

    try std.testing.expectEqual(zithril.AuditCategory.keyboard_navigation, result.category);
    // Explorer mode has tab stops, so we should find some
    try std.testing.expect(result.findings.len > 0);
}

test "workbench: auditFocusVisibility detects style changes" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    var result = try zithril.auditFocusVisibility(State, testing_alloc, &harness, .{});
    defer result.deinit();

    try std.testing.expectEqual(zithril.AuditCategory.focus_visibility, result.category);
}

test "workbench: ScenarioRunner mode switching" {
    var state = State{};
    var runner = zithril.ScenarioRunner(State).init(
        testing_alloc,
        &state,
        update,
        view,
    );

    const scenario =
        \\size 80 24
        \\# Switch through modes
        \\key 2
        \\key 3
        \\key 1
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
    try std.testing.expectEqual(Mode.explorer, state.current_mode);
}

test "workbench: snapshot comparison" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    var snap1 = try harness.snapshot(testing_alloc);
    defer snap1.deinit();

    // After switching mode, snapshot should differ
    harness.pressKey('2');

    var snap2 = try harness.snapshot(testing_alloc);
    defer snap2.deinit();

    try std.testing.expect(!snap1.eql(snap2));
}
