const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);

const State = struct {
    tick_count: u32 = 0,
    selected_process: usize = 0,

    const cpu_data_full = [_]f64{ 23.0, 45.0, 67.0, 78.0, 65.0, 54.0, 43.0, 56.0, 67.0, 78.0, 89.0, 76.0, 65.0, 54.0, 67.0, 78.0, 85.0, 72.0, 68.0, 75.0 };
    const mem_data_full = [_]f64{ 45.0, 47.0, 49.0, 52.0, 54.0, 56.0, 58.0, 61.0, 63.0, 65.0, 67.0, 69.0, 71.0, 73.0, 75.0, 76.0, 78.0, 79.0, 80.0, 82.0 };
    const net_data_full = [_]f64{ 12.0, 34.0, 56.0, 23.0, 45.0, 67.0, 34.0, 12.0, 45.0, 78.0, 56.0, 34.0, 67.0, 89.0, 45.0, 23.0, 56.0, 78.0, 34.0, 67.0 };

    const process_names = [_][]const u8{ "systemd", "chrome", "firefox", "code", "zithril", "postgres", "nginx", "docker" };
    const process_pids = [_][]const u8{ "1", "1234", "1256", "1890", "2341", "3456", "4567", "5678" };
    const process_cpus = [_][]const u8{ "0.1", "23.4", "18.7", "12.3", "8.9", "5.6", "2.3", "1.2" };
    const process_mems = [_][]const u8{ "2.1", "1024.5", "856.2", "512.8", "128.4", "256.7", "64.3", "32.1" };

    fn get_cpu_data(self: *const State) []const f64 {
        const offset = (self.tick_count % 10);
        const len = @min(20, cpu_data_full.len);
        return cpu_data_full[offset..@min(offset + len, cpu_data_full.len)];
    }

    fn get_mem_data(self: *const State) []const f64 {
        const offset = (self.tick_count % 10);
        const len = @min(20, mem_data_full.len);
        return mem_data_full[offset..@min(offset + len, mem_data_full.len)];
    }

    fn get_net_data(self: *const State) []const f64 {
        const offset = (self.tick_count % 10);
        const len = @min(20, net_data_full.len);
        return net_data_full[offset..@min(offset + len, net_data_full.len)];
    }

    fn process_count(self: *const State) usize {
        _ = self;
        return process_names.len;
    }
};

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            switch (key.code) {
                .char => |c| {
                    if (c == 'q') return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;
                    if (c == 'j') {
                        if (state.selected_process + 1 < state.process_count()) {
                            state.selected_process += 1;
                        }
                    }
                    if (c == 'k') {
                        if (state.selected_process > 0) {
                            state.selected_process -= 1;
                        }
                    }
                },
                .down => {
                    if (state.selected_process + 1 < state.process_count()) {
                        state.selected_process += 1;
                    }
                },
                .up => {
                    if (state.selected_process > 0) {
                        state.selected_process -= 1;
                    }
                },
                else => {},
            }
        },
        .tick => {
            state.tick_count +%= 1;
        },
        else => {},
    }
    return .none;
}

fn view(state: *State, frame: *FrameType) void {
    const area = frame.size();

    const main_layout = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(4),
        zithril.Constraint.len(5),
        zithril.Constraint.len(10),
        zithril.Constraint.len(5),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    render_title(frame, main_layout.get(0));
    render_sparklines(state, frame, main_layout.get(1));
    render_bar_chart(state, frame, main_layout.get(2));
    render_gauges(state, frame, main_layout.get(3));
    render_process_table(state, frame, main_layout.get(4));
    render_status_bar(state, frame, main_layout.get(5));
}

fn render_title(frame: *FrameType, area: zithril.Rect) void {
    frame.render(zithril.BigText{
        .text = "DASH",
        .style = zithril.Style.init().fg(.cyan).bold(),
        .pixel_size = .half,
    }, area);
}

fn render_sparklines(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    const cpu_block = zithril.Block{
        .title = "CPU %",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.green),
    };
    frame.render(cpu_block, layout.get(0));
    const cpu_inner = cpu_block.inner(layout.get(0));
    frame.render(zithril.Sparkline{
        .data = state.get_cpu_data(),
        .style = zithril.Style.init().fg(.green),
        .direction = .left_to_right,
        .max = 100.0,
    }, cpu_inner);

    const mem_block = zithril.Block{
        .title = "Memory %",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.yellow),
    };
    frame.render(mem_block, layout.get(1));
    const mem_inner = mem_block.inner(layout.get(1));
    frame.render(zithril.Sparkline{
        .data = state.get_mem_data(),
        .style = zithril.Style.init().fg(.yellow),
        .direction = .left_to_right,
        .max = 100.0,
    }, mem_inner);

    const net_block = zithril.Block{
        .title = "Network MB/s",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.magenta),
    };
    frame.render(net_block, layout.get(2));
    const net_inner = net_block.inner(layout.get(2));
    frame.render(zithril.Sparkline{
        .data = state.get_net_data(),
        .style = zithril.Style.init().fg(.magenta),
        .direction = .left_to_right,
        .max = 100.0,
    }, net_inner);
}

fn render_bar_chart(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Process Resource Usage",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(block, area);
    const inner = block.inner(area);

    const cpu_val = 23.4 + @as(f64, @floatFromInt(state.tick_count % 20));
    const mem_val = 45.8 + @as(f64, @floatFromInt((state.tick_count * 2) % 15));
    const disk_val = 67.2 + @as(f64, @floatFromInt((state.tick_count * 3) % 10));

    const group1_bars = [_]zithril.Bar{
        .{ .value = cpu_val, .label = "CPU", .style = zithril.Style.init().fg(.green) },
        .{ .value = mem_val, .label = "Mem", .style = zithril.Style.init().fg(.yellow) },
        .{ .value = disk_val, .label = "Dsk", .style = zithril.Style.init().fg(.red) },
    };

    const cpu_val2 = 34.5 + @as(f64, @floatFromInt((state.tick_count + 5) % 20));
    const mem_val2 = 56.7 + @as(f64, @floatFromInt((state.tick_count * 2 + 3) % 15));
    const disk_val2 = 78.9 + @as(f64, @floatFromInt((state.tick_count * 3 + 7) % 10));

    const group2_bars = [_]zithril.Bar{
        .{ .value = cpu_val2, .label = "CPU", .style = zithril.Style.init().fg(.green) },
        .{ .value = mem_val2, .label = "Mem", .style = zithril.Style.init().fg(.yellow) },
        .{ .value = disk_val2, .label = "Dsk", .style = zithril.Style.init().fg(.red) },
    };

    const groups = [_]zithril.BarGroup{
        .{ .label = "chrome", .bars = &group1_bars },
        .{ .label = "firefox", .bars = &group2_bars },
    };

    frame.render(zithril.BarChart{
        .groups = &groups,
        .orientation = .vertical,
        .bar_width = 3,
        .bar_gap = 1,
        .group_gap = 2,
        .show_values = true,
        .default_bar_style = zithril.Style.init().fg(.green),
    }, inner);
}

fn render_gauges(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    const cpu_ratio: f32 = @floatCast(0.75 + (@as(f64, @floatFromInt(state.tick_count % 20)) / 100.0));
    var cpu_buf: [16]u8 = undefined;
    const cpu_label = std.fmt.bufPrint(&cpu_buf, "CPU {d:.0}%", .{cpu_ratio * 100.0}) catch "CPU";

    const cpu_block = zithril.Block{
        .title = "CPU Usage",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.green),
    };
    frame.render(cpu_block, layout.get(0));
    const cpu_inner = cpu_block.inner(layout.get(0));
    frame.render(zithril.LineGauge{
        .ratio = cpu_ratio,
        .label = cpu_label,
        .style = zithril.Style.init().fg(.white),
        .gauge_style = zithril.Style.init().fg(.cyan),
        .line_set = .normal,
    }, cpu_inner);

    const mem_ratio = 0.82;
    const mem_block = zithril.Block{
        .title = "Memory",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.yellow),
    };
    frame.render(mem_block, layout.get(1));
    const mem_inner = mem_block.inner(layout.get(1));
    frame.render(zithril.LineGauge{
        .ratio = mem_ratio,
        .label = "82%",
        .style = zithril.Style.init().fg(.white),
        .gauge_style = zithril.Style.init().fg(.yellow),
        .line_set = .normal,
    }, mem_inner);

    const disk_ratio = 0.65;
    var disk_buf: [16]u8 = undefined;
    const disk_label = std.fmt.bufPrint(&disk_buf, "65%", .{}) catch "65%";

    const disk_block = zithril.Block{
        .title = "Disk Usage",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.red),
    };
    frame.render(disk_block, layout.get(2));
    const disk_inner = disk_block.inner(layout.get(2));
    frame.render(zithril.Gauge{
        .ratio = disk_ratio,
        .label = disk_label,
        .style = zithril.Style.init().bg(.black),
        .gauge_style = zithril.Style.init().bg(.red),
    }, disk_inner);
}

fn render_process_table(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Processes (j/k to navigate)",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(block, area);
    const inner = block.inner(area);

    const header = [_][]const u8{ "Name", "PID", "CPU%", "MEM(MB)" };

    const row0 = [_][]const u8{ State.process_names[0], State.process_pids[0], State.process_cpus[0], State.process_mems[0] };
    const row1 = [_][]const u8{ State.process_names[1], State.process_pids[1], State.process_cpus[1], State.process_mems[1] };
    const row2 = [_][]const u8{ State.process_names[2], State.process_pids[2], State.process_cpus[2], State.process_mems[2] };
    const row3 = [_][]const u8{ State.process_names[3], State.process_pids[3], State.process_cpus[3], State.process_mems[3] };
    const row4 = [_][]const u8{ State.process_names[4], State.process_pids[4], State.process_cpus[4], State.process_mems[4] };
    const row5 = [_][]const u8{ State.process_names[5], State.process_pids[5], State.process_cpus[5], State.process_mems[5] };
    const row6 = [_][]const u8{ State.process_names[6], State.process_pids[6], State.process_cpus[6], State.process_mems[6] };
    const row7 = [_][]const u8{ State.process_names[7], State.process_pids[7], State.process_cpus[7], State.process_mems[7] };

    const rows = [_][]const []const u8{ &row0, &row1, &row2, &row3, &row4, &row5, &row6, &row7 };

    const widths = [_]zithril.Constraint{
        zithril.Constraint.flexible(2),
        zithril.Constraint.len(8),
        zithril.Constraint.len(8),
        zithril.Constraint.len(10),
    };

    frame.render(zithril.Table{
        .header = &header,
        .rows = &rows,
        .widths = &widths,
        .selected = state.selected_process,
        .style = zithril.Style.init().fg(.white),
        .header_style = zithril.Style.init().bold().fg(.cyan),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white),
    }, inner);
}

fn render_status_bar(state: *State, frame: *FrameType, area: zithril.Rect) void {
    var buf: [64]u8 = undefined;
    const status = std.fmt.bufPrint(&buf, " q:quit | j/k:navigate | Tick: {d}", .{state.tick_count}) catch " q:quit";

    frame.render(zithril.Text{
        .content = status,
        .style = zithril.Style.init().bg(.blue).fg(.white),
    }, area);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = State{};

    var app = zithril.App(State).init(.{
        .state = &state,
        .update = update,
        .view = view,
        .tick_rate_ms = 1000,
    });

    try app.run(allocator);
}

pub const panic = zithril.terminal_panic;
