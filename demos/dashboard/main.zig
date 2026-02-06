const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);

const State = struct {
    tick_count: u32 = 0,
    selected_process: usize = 0,

    const cpu_data = [_]f64{ 23, 45, 67, 78, 65, 54, 43, 56, 67, 78, 89, 76, 65, 54, 67, 78, 85, 72, 68, 75 };
    const mem_data = [_]f64{ 45, 47, 49, 52, 54, 56, 58, 61, 63, 65, 67, 69, 71, 73, 75, 76, 78, 79, 80, 82 };
    const net_data = [_]f64{ 12, 34, 56, 23, 45, 67, 34, 12, 45, 78, 56, 34, 67, 89, 45, 23, 56, 78, 34, 67 };

    const process_names = [_][]const u8{ "systemd", "chrome", "firefox", "code", "zithril", "postgres", "nginx", "docker" };
    const process_pids = [_][]const u8{ "1", "1234", "1256", "1890", "2341", "3456", "4567", "5678" };
    const process_cpus = [_][]const u8{ "0.1", "23.4", "18.7", "12.3", "8.9", "5.6", "2.3", "1.2" };
    const process_mems = [_][]const u8{ "2.1", "1024.5", "856.2", "512.8", "128.4", "256.7", "64.3", "32.1" };

    fn getData(self: *const State, comptime series: []const f64) []const f64 {
        const offset = self.tick_count % 10;
        return series[offset..@min(offset + 20, series.len)];
    }
};

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            switch (key.code) {
                .char => |c| {
                    if (c == 'q') return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;
                    if (c == 'j') state.selected_process = @min(state.selected_process + 1, State.process_names.len - 1);
                    if (c == 'k') state.selected_process -|= 1;
                },
                .down => state.selected_process = @min(state.selected_process + 1, State.process_names.len - 1),
                .up => state.selected_process -|= 1,
                else => {},
            }
        },
        .tick => state.tick_count +%= 1,
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

    frame.render(zithril.BigText{
        .text = "DASH",
        .style = zithril.Style.init().fg(.cyan).bold(),
        .pixel_size = .half,
    }, main_layout.get(0));

    renderSparklines(state, frame, main_layout.get(1));
    renderBarChart(state, frame, main_layout.get(2));
    renderGauges(state, frame, main_layout.get(3));
    renderProcessTable(state, frame, main_layout.get(4));

    var status_buf: [64]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, " q:quit | j/k:navigate | Tick: {d}", .{state.tick_count}) catch " q:quit";
    frame.render(zithril.Text{
        .content = status,
        .style = zithril.Style.init().bg(.blue).fg(.white),
    }, main_layout.get(5));
}

fn renderSparklines(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    const panels = [_]struct { title: []const u8, data: []const f64, color: zithril.Color }{
        .{ .title = "CPU %", .data = state.getData(&State.cpu_data), .color = .green },
        .{ .title = "Memory %", .data = state.getData(&State.mem_data), .color = .yellow },
        .{ .title = "Network MB/s", .data = state.getData(&State.net_data), .color = .magenta },
    };

    for (panels, 0..) |panel, i| {
        const block = zithril.Block{ .title = panel.title, .border = .rounded, .border_style = zithril.Style.init().fg(panel.color) };
        frame.render(block, layout.get(i));
        frame.render(zithril.Sparkline{
            .data = panel.data,
            .style = zithril.Style.init().fg(panel.color),
            .direction = .left_to_right,
            .max = 100.0,
        }, block.inner(layout.get(i)));
    }
}

fn renderBarChart(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .title = "Process Resource Usage", .border = .rounded, .border_style = zithril.Style.init().fg(.cyan) };
    frame.render(block, area);

    const tick: f64 = @floatFromInt(state.tick_count);
    const group1_bars = [_]zithril.Bar{
        .{ .value = 23.4 + @mod(tick, 20), .label = "CPU", .style = zithril.Style.init().fg(.green) },
        .{ .value = 45.8 + @mod(tick * 2, 15), .label = "Mem", .style = zithril.Style.init().fg(.yellow) },
        .{ .value = 67.2 + @mod(tick * 3, 10), .label = "Dsk", .style = zithril.Style.init().fg(.red) },
    };
    const group2_bars = [_]zithril.Bar{
        .{ .value = 34.5 + @mod(tick + 5, 20), .label = "CPU", .style = zithril.Style.init().fg(.green) },
        .{ .value = 56.7 + @mod(tick * 2 + 3, 15), .label = "Mem", .style = zithril.Style.init().fg(.yellow) },
        .{ .value = 78.9 + @mod(tick * 3 + 7, 10), .label = "Dsk", .style = zithril.Style.init().fg(.red) },
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
    }, block.inner(area));
}

fn renderGauges(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    const cpu_ratio: f32 = @floatCast(0.75 + (@as(f64, @floatFromInt(state.tick_count % 20)) / 100.0));
    var cpu_buf: [16]u8 = undefined;
    const cpu_label = std.fmt.bufPrint(&cpu_buf, "CPU {d:.0}%", .{cpu_ratio * 100.0}) catch "CPU";

    const cpu_block = zithril.Block{ .title = "CPU Usage", .border = .rounded, .border_style = zithril.Style.init().fg(.green) };
    frame.render(cpu_block, layout.get(0));
    frame.render(zithril.LineGauge{
        .ratio = cpu_ratio,
        .label = cpu_label,
        .style = zithril.Style.init().fg(.white),
        .gauge_style = zithril.Style.init().fg(.cyan),
        .line_set = .normal,
    }, cpu_block.inner(layout.get(0)));

    const mem_block = zithril.Block{ .title = "Memory", .border = .rounded, .border_style = zithril.Style.init().fg(.yellow) };
    frame.render(mem_block, layout.get(1));
    frame.render(zithril.LineGauge{
        .ratio = 0.82,
        .label = "82%",
        .style = zithril.Style.init().fg(.white),
        .gauge_style = zithril.Style.init().fg(.yellow),
        .line_set = .normal,
    }, mem_block.inner(layout.get(1)));

    const disk_block = zithril.Block{ .title = "Disk Usage", .border = .rounded, .border_style = zithril.Style.init().fg(.red) };
    frame.render(disk_block, layout.get(2));
    frame.render(zithril.Gauge{
        .ratio = 0.65,
        .label = "65%",
        .style = zithril.Style.init().bg(.black),
        .gauge_style = zithril.Style.init().bg(.red),
    }, disk_block.inner(layout.get(2)));
}

fn renderProcessTable(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .title = "Processes (j/k to navigate)", .border = .rounded, .border_style = zithril.Style.init().fg(.cyan) };
    frame.render(block, area);

    const header = [_][]const u8{ "Name", "PID", "CPU%", "MEM(MB)" };

    const rows = comptime blk: {
        var r: [State.process_names.len][4][]const u8 = undefined;
        for (0..State.process_names.len) |i| {
            r[i] = .{ State.process_names[i], State.process_pids[i], State.process_cpus[i], State.process_mems[i] };
        }
        break :blk r;
    };
    const row_ptrs = comptime blk: {
        var ptrs: [rows.len][]const []const u8 = undefined;
        for (0..rows.len) |i| {
            ptrs[i] = &rows[i];
        }
        break :blk ptrs;
    };

    frame.render(zithril.Table{
        .header = &header,
        .rows = &row_ptrs,
        .widths = &.{ zithril.Constraint.flexible(2), zithril.Constraint.len(8), zithril.Constraint.len(8), zithril.Constraint.len(10) },
        .selected = state.selected_process,
        .style = zithril.Style.init().fg(.white),
        .header_style = zithril.Style.init().bold().fg(.cyan),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white),
    }, block.inner(area));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var state = State{};
    var app = zithril.App(State).init(.{
        .state = &state,
        .update = update,
        .view = view,
        .tick_rate_ms = 1000,
    });
    try app.run(gpa.allocator());
}

pub const panic = zithril.terminal_panic;
