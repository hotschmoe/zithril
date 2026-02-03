// Ralph - zithril Reference Application
//
// A full-featured demonstration of zithril TUI framework capabilities:
// - Agent list panel with navigation
// - Agent detail panel showing selected agent info
// - Scrollable log panel with message history
// - Status bar showing connection state and timestamps
// - Progress gauges for task completion
// - Focus management between panels (Tab/Shift+Tab)
//
// Controls:
// - Tab/Shift+Tab: Cycle focus between panels
// - j/k or arrows: Navigate within focused panel
// - q: Quit

const std = @import("std");
const zithril = @import("zithril");

// Focus areas in the application
const Focus = enum {
    agents,
    logs,
};

// Agent status
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

// Agent data
const Agent = struct {
    name: []const u8,
    status: AgentStatus,
    tasks_completed: u32,
    tasks_total: u32,
    last_activity: []const u8,
};

// Log entry
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

    fn color(self: LogLevel) zithril.Color {
        return switch (self) {
            .info => .cyan,
            .warning => .yellow,
            .err => .red,
            .debug => .white,
        };
    }
};

// Frame type alias for view functions
const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);

// Application state
const State = struct {
    focus: Focus = .agents,
    selected_agent: usize = 0,
    log_scroll: usize = 0,
    agents: []const Agent,
    logs: []const LogEntry,

    fn selectNextAgent(self: *State) void {
        if (self.agents.len == 0) return;
        if (self.selected_agent < self.agents.len - 1) {
            self.selected_agent += 1;
        }
    }

    fn selectPrevAgent(self: *State) void {
        if (self.selected_agent > 0) {
            self.selected_agent -= 1;
        }
    }

    fn scrollLogsDown(self: *State) void {
        if (self.logs.len > 0) {
            self.log_scroll +|= 1;
        }
    }

    fn scrollLogsUp(self: *State) void {
        if (self.log_scroll > 0) {
            self.log_scroll -= 1;
        }
    }

    fn cycleFocus(self: *State) void {
        self.focus = switch (self.focus) {
            .agents => .logs,
            .logs => .agents,
        };
    }

    fn getSelectedAgent(self: *State) ?*const Agent {
        if (self.agents.len == 0) return null;
        const idx = @min(self.selected_agent, self.agents.len - 1);
        return &self.agents[idx];
    }
};

// Handle events
fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            switch (key.code) {
                .char => |c| {
                    if (key.modifiers.ctrl and c == 'c') return .quit;
                    if (!key.modifiers.any()) {
                        switch (c) {
                            'q' => return .quit,
                            'j' => handleDown(state),
                            'k' => handleUp(state),
                            else => {},
                        }
                    }
                },
                .up => if (!key.modifiers.any()) handleUp(state),
                .down => if (!key.modifiers.any()) handleDown(state),
                .tab => if (!key.modifiers.any()) state.cycleFocus(),
                .backtab => if (key.modifiers.shift) state.cycleFocus(),
                else => {},
            }
        },
        else => {},
    }
    return .none;
}

fn handleDown(state: *State) void {
    switch (state.focus) {
        .agents => state.selectNextAgent(),
        .logs => state.scrollLogsDown(),
    }
}

fn handleUp(state: *State) void {
    switch (state.focus) {
        .agents => state.selectPrevAgent(),
        .logs => state.scrollLogsUp(),
    }
}

// Render the UI
fn view(state: *State, frame: *FrameType) void {
    const area = frame.size();

    // Main layout: status bar at bottom
    const main_chunks = zithril.layout(area, .vertical, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    renderMainContent(state, frame, main_chunks.get(0));
    renderStatusBar(state, frame, main_chunks.get(1));
}

fn renderMainContent(state: *State, frame: *FrameType, area: zithril.Rect) void {
    // Split into left (agents) and right (detail + logs)
    const h_chunks = zithril.layout(area, .horizontal, &.{
        zithril.Constraint.len(30),
        zithril.Constraint.flexible(1),
    });

    renderAgentList(state, frame, h_chunks.get(0));
    renderRightPanel(state, frame, h_chunks.get(1));
}

fn renderAgentList(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const is_focused = state.focus == .agents;
    const border_color: zithril.Color = if (is_focused) .cyan else .white;

    const block = zithril.Block{
        .title = if (is_focused) "Agents [*]" else "Agents",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(border_color),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    // Build agent display strings
    var items: [16][]const u8 = undefined;
    var bufs: [16][64]u8 = undefined;
    const count = @min(state.agents.len, 16);

    for (state.agents[0..count], 0..count) |agent, i| {
        const display = std.fmt.bufPrint(&bufs[i], "{s} {s}", .{ agent.status.symbol(), agent.name }) catch agent.name;
        items[i] = display;
    }

    const list = zithril.List{
        .items = items[0..count],
        .selected = if (is_focused) state.selected_agent else null,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white).bold(),
        .highlight_symbol = "> ",
    };
    frame.render(list, inner);
}

fn renderRightPanel(state: *State, frame: *FrameType, area: zithril.Rect) void {
    // Split into detail (top) and logs (bottom)
    const v_chunks = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(10),
        zithril.Constraint.flexible(1),
    });

    renderAgentDetail(state, frame, v_chunks.get(0));
    renderLogPanel(state, frame, v_chunks.get(1));
}

fn renderAgentDetail(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Agent Details",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.white),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    if (state.getSelectedAgent()) |agent| {
        // Split inner area for details and gauge
        const detail_chunks = zithril.layout(inner, .vertical, &.{
            zithril.Constraint.flexible(1),
            zithril.Constraint.len(1),
        });

        // Agent info
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

        const para = zithril.Paragraph{
            .text = info_text,
            .style = zithril.Style.init().fg(.white),
            .wrap = .none,
        };
        frame.render(para, detail_chunks.get(0));

        // Progress gauge
        const ratio: f32 = if (agent.tasks_total > 0)
            @as(f32, @floatFromInt(agent.tasks_completed)) / @as(f32, @floatFromInt(agent.tasks_total))
        else
            0.0;

        var gauge_label_buf: [16]u8 = undefined;
        const gauge_label = std.fmt.bufPrint(&gauge_label_buf, "{d}%", .{@as(u8, @intFromFloat(ratio * 100))}) catch "";

        const gauge = zithril.Gauge{
            .ratio = ratio,
            .label = gauge_label,
            .style = zithril.Style.init().bg(.black),
            .gauge_style = zithril.Style.init().bg(agent.status.color()),
        };
        frame.render(gauge, detail_chunks.get(1));
    } else {
        const text = zithril.Text{
            .content = "No agent selected",
            .style = zithril.Style.init().fg(.white).italic(),
            .alignment = .center,
        };
        frame.render(text, inner);
    }
}

fn renderLogPanel(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const is_focused = state.focus == .logs;
    const border_color: zithril.Color = if (is_focused) .cyan else .white;

    const block = zithril.Block{
        .title = if (is_focused) "Logs [*]" else "Logs",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(border_color),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    // Calculate visible log range
    const visible_lines = inner.height;
    const max_scroll = if (state.logs.len > visible_lines)
        state.logs.len - visible_lines
    else
        0;
    const scroll_offset = @min(state.log_scroll, max_scroll);

    // Render visible logs
    var y: u16 = 0;
    const end_idx = @min(scroll_offset + visible_lines, state.logs.len);

    for (state.logs[scroll_offset..end_idx]) |entry| {
        if (y >= inner.height) break;

        // Format log line
        var line_buf: [128]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{s} {s} {s}", .{
            entry.timestamp,
            entry.level.prefix(),
            entry.message,
        }) catch entry.message;

        const text = zithril.Text{
            .content = line,
            .style = zithril.Style.init().fg(entry.level.color()),
            .alignment = .left,
        };

        const line_area = zithril.Rect.init(inner.x, inner.y + y, inner.width, 1);
        frame.render(text, line_area);
        y += 1;
    }

    // Render scrollbar if content overflows
    if (state.logs.len > visible_lines) {
        const scrollbar_area = zithril.Rect.init(area.right() -| 1, inner.y, 1, inner.height);
        const scrollbar = zithril.Scrollbar{
            .total = state.logs.len,
            .position = scroll_offset,
            .viewport = visible_lines,
            .style = zithril.Style.init().fg(.white),
            .orientation = .vertical,
        };
        frame.render(scrollbar, scrollbar_area);
    }
}

fn renderStatusBar(state: *State, frame: *FrameType, area: zithril.Rect) void {
    _ = state;

    // Status bar background
    const clear = zithril.Clear{
        .style = zithril.Style.init().bg(.blue),
    };
    frame.render(clear, area);

    // Status text
    const status_text = "Ralph | Connected | q/Ctrl-C:Quit Tab:Focus j/k:Navigate";
    const text = zithril.Text{
        .content = status_text,
        .style = zithril.Style.init().fg(.white).bg(.blue).bold(),
        .alignment = .left,
    };
    frame.render(text, area);
}

// Sample data
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = State{
        .agents = &sample_agents,
        .logs = &sample_logs,
    };
    var app = zithril.App(State).init(.{
        .state = &state,
        .update = update,
        .view = view,
    });

    try app.run(allocator);
}

// Use zithril's panic handler to ensure terminal cleanup on abnormal exit
pub const panic = zithril.terminal_panic;
