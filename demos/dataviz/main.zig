const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);

const temp_data = [_][2]f64{
    .{ 0, 20 },  .{ 1, 25 },  .{ 2, 30 },  .{ 3, 28 },  .{ 4, 35 },
    .{ 5, 40 },  .{ 6, 38 },  .{ 7, 45 },  .{ 8, 50 },  .{ 9, 55 },  .{ 10, 60 },
};

const humidity_data = [_][2]f64{
    .{ 0, 60 },  .{ 1, 58 },  .{ 2, 55 },  .{ 3, 60 },  .{ 4, 65 },
    .{ 5, 70 },  .{ 6, 68 },  .{ 7, 72 },  .{ 8, 75 },  .{ 9, 80 },  .{ 10, 85 },
};

const scatter_data = [_][2]f64{
    .{ 1.5, 42 }, .{ 3.2, 55 }, .{ 5.5, 68 }, .{ 7.8, 48 }, .{ 9.1, 72 },
};

const cpu_data = [_]f64{ 20, 30, 45, 60, 55, 70, 65, 80, 75, 60, 50, 45, 55, 65, 70, 85, 90, 75, 60, 55 };
const mem_data = [_]f64{ 40, 42, 45, 47, 50, 52, 55, 58, 60, 62, 65, 68, 70, 68, 65, 60, 58, 55, 52, 50 };
const net_data = [_]f64{ 10, 15, 25, 35, 30, 40, 60, 80, 70, 50, 30, 20, 25, 35, 45, 55, 60, 50, 40, 30 };

const State = struct {
    current_page: usize = 0,

    const page_names = [_][]const u8{
        "Charts",
        "Bar Charts",
        "Sparklines & Gauges",
        "Canvas",
        "Calendar & BigText",
    };
};

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            switch (key.code) {
                .char => |c| {
                    if (c == 'q') return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;
                    if (c == 'h' or c == 'H') {
                        if (state.current_page > 0) state.current_page -= 1;
                    }
                    if (c == 'l' or c == 'L') {
                        if (state.current_page < State.page_names.len - 1) state.current_page += 1;
                    }
                },
                .left => {
                    if (state.current_page > 0) state.current_page -= 1;
                },
                .right => {
                    if (state.current_page < State.page_names.len - 1) state.current_page += 1;
                },
                else => {},
            }
        },
        else => {},
    }
    return .none;
}

fn view(state: *State, frame: *FrameType) void {
    const main_layout = zithril.layout(frame.size(), .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    frame.render(zithril.Tabs{
        .titles = &State.page_names,
        .selected = state.current_page,
        .style = zithril.Style.empty,
        .highlight_style = zithril.Style.init().bold().fg(.cyan),
        .divider = "|",
    }, main_layout.get(0));

    frame.render(zithril.Block{
        .title = State.page_names[state.current_page],
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.yellow),
    }, main_layout.get(1));

    const content_area = main_layout.get(2);
    switch (state.current_page) {
        0 => renderChartsPage(frame, content_area),
        1 => renderBarChartsPage(frame, content_area),
        2 => renderSparklinesPage(frame, content_area),
        3 => renderCanvasPage(frame, content_area),
        4 => renderCalendarPage(frame, content_area),
        else => {},
    }

    frame.render(zithril.Text{
        .content = "left/right (h/l) to navigate | q to quit",
        .style = zithril.Style.init().fg(.white).bg(.blue),
    }, main_layout.get(3));
}

fn renderChartsPage(frame: *FrameType, area: zithril.Rect) void {
    frame.render(zithril.Chart{
        .x_axis = .{
            .title = "Time (s)",
            .bounds = .{ 0.0, 10.0 },
            .style = zithril.Style.init().fg(.white),
            .title_style = zithril.Style.init().fg(.cyan),
            .labels_style = zithril.Style.init().fg(.white),
        },
        .y_axis = .{
            .title = "Value",
            .bounds = .{ 0.0, 100.0 },
            .style = zithril.Style.init().fg(.white),
            .title_style = zithril.Style.init().fg(.cyan),
            .labels_style = zithril.Style.init().fg(.white),
        },
        .datasets = &.{
            .{ .name = "Temperature", .data = &temp_data, .style = zithril.Style.init().fg(.red), .marker = 0x25CF },
            .{ .name = "Humidity", .data = &humidity_data, .style = zithril.Style.init().fg(.blue) },
        },
        .scatter_datasets = &.{
            .{ .name = "Samples", .data = &scatter_data, .marker = 0x25A0, .style = zithril.Style.init().fg(.yellow) },
        },
    }, area);
}

fn renderBarChartsPage(frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .vertical, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    frame.render(zithril.BarChart{
        .groups = &.{
            .{ .label = "Q1", .bars = &.{
                .{ .value = 80.0, .label = "Sales", .style = zithril.Style.init().fg(.green) },
                .{ .value = 60.0, .label = "Cost", .style = zithril.Style.init().fg(.red) },
            } },
            .{ .label = "Q2", .bars = &.{
                .{ .value = 95.0, .label = "Sales", .style = zithril.Style.init().fg(.green) },
                .{ .value = 70.0, .label = "Cost", .style = zithril.Style.init().fg(.red) },
            } },
            .{ .label = "Q3", .bars = &.{
                .{ .value = 110.0, .label = "Sales", .style = zithril.Style.init().fg(.green) },
                .{ .value = 75.0, .label = "Cost", .style = zithril.Style.init().fg(.red) },
            } },
            .{ .label = "Q4", .bars = &.{
                .{ .value = 125.0, .label = "Sales", .style = zithril.Style.init().fg(.green) },
                .{ .value = 80.0, .label = "Cost", .style = zithril.Style.init().fg(.red) },
            } },
        },
        .orientation = .vertical,
        .bar_width = 3,
        .show_values = true,
    }, layout.get(0));

    frame.render(zithril.BarChart{
        .groups = &.{
            .{ .label = "Product A", .bars = &.{
                .{ .value = 150.0, .label = "Rev", .style = zithril.Style.init().fg(.cyan) },
            } },
            .{ .label = "Product B", .bars = &.{
                .{ .value = 230.0, .label = "Rev", .style = zithril.Style.init().fg(.magenta) },
            } },
            .{ .label = "Product C", .bars = &.{
                .{ .value = 180.0, .label = "Rev", .style = zithril.Style.init().fg(.yellow) },
            } },
        },
        .orientation = .horizontal,
        .bar_width = 1,
        .show_values = true,
    }, layout.get(1));
}

fn renderSparklinesPage(frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
        zithril.Constraint.len(1),
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
        zithril.Constraint.len(1),
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
    });

    const cpu_block = zithril.Block{ .title = "CPU Usage", .border = .rounded, .border_style = zithril.Style.init().fg(.green) };
    frame.render(cpu_block, layout.get(0));
    frame.render(zithril.Sparkline{
        .data = &cpu_data,
        .style = zithril.Style.init().fg(.green),
        .max = 100.0,
    }, cpu_block.inner(layout.get(0)));

    const mem_block = zithril.Block{ .title = "Memory Usage", .border = .rounded, .border_style = zithril.Style.init().fg(.yellow) };
    frame.render(mem_block, layout.get(1));
    frame.render(zithril.Sparkline{
        .data = &mem_data,
        .style = zithril.Style.init().fg(.yellow),
        .max = 100.0,
    }, mem_block.inner(layout.get(1)));

    const net_block = zithril.Block{ .title = "Network Traffic", .border = .rounded, .border_style = zithril.Style.init().fg(.cyan) };
    frame.render(net_block, layout.get(2));
    frame.render(zithril.Sparkline{
        .data = &net_data,
        .style = zithril.Style.init().fg(.cyan),
        .max = 100.0,
    }, net_block.inner(layout.get(2)));

    frame.render(zithril.LineGauge{
        .ratio = 0.73,
        .label = "Upload: 73%",
        .gauge_style = zithril.Style.init().fg(.green),
        .line_set = .normal,
    }, layout.get(4));

    frame.render(zithril.LineGauge{
        .ratio = 0.45,
        .label = "Download: 45%",
        .gauge_style = zithril.Style.init().fg(.cyan),
        .line_set = .thick,
    }, layout.get(5));

    frame.render(zithril.Gauge{
        .ratio = 0.85,
        .label = "Disk A: 85%",
        .gauge_style = zithril.Style.init().bg(.green),
    }, layout.get(7));

    frame.render(zithril.Gauge{
        .ratio = 0.45,
        .label = "Disk B: 45%",
        .gauge_style = zithril.Style.init().bg(.yellow),
    }, layout.get(8));
}

fn renderCanvasPage(frame: *FrameType, area: zithril.Rect) void {
    var canvas = zithril.Canvas{
        .x_bounds = .{ 0.0, 100.0 },
        .y_bounds = .{ 0.0, 50.0 },
    };
    canvas.render(area, frame.buffer);

    const circle1 = zithril.CanvasCircle{ .x = 25.0, .y = 25.0, .radius = 15.0, .color = .red };
    const line1 = zithril.CanvasLine{ .x1 = 0.0, .y1 = 0.0, .x2 = 100.0, .y2 = 50.0, .color = .green };
    const rect1 = zithril.CanvasRectangle{ .x = 60.0, .y = 10.0, .width = 30.0, .height = 20.0, .color = .blue };
    const circle2 = zithril.CanvasCircle{ .x = 75.0, .y = 40.0, .radius = 8.0, .color = .yellow };
    const line2 = zithril.CanvasLine{ .x1 = 0.0, .y1 = 50.0, .x2 = 100.0, .y2 = 0.0, .color = .magenta };

    const shape_list = [_]zithril.CanvasShape{
        circle1.shape(),
        line1.shape(),
        rect1.shape(),
        circle2.shape(),
        line2.shape(),
    };

    canvas.draw(area, frame.buffer, &shape_list);
}

fn renderCalendarPage(frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(10),
        zithril.Constraint.flexible(1),
    });

    frame.render(zithril.Calendar{
        .year = 2026,
        .month = 2,
        .selected_day = 14,
        .show_adjacent_months = true,
        .style = zithril.Style.init().fg(.white),
        .today_style = zithril.Style.init().bold().fg(.cyan),
        .selected_style = zithril.Style.init().reverse(),
        .header_style = zithril.Style.init().bold().fg(.yellow),
        .today = .{ .year = 2026, .month = 2, .day = 6 },
    }, layout.get(0));

    frame.render(zithril.BigText{
        .text = "2026",
        .style = zithril.Style.init().fg(.cyan),
        .pixel_size = .half,
    }, layout.get(1));
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
    });

    try app.run(allocator);
}

pub const panic = zithril.terminal_panic;
