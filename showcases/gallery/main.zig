// Gallery - Widget Gallery Showcase
//
// A tabbed app demonstrating every major zithril widget category.
// The first app a new user should run.
//
// Tabs:
//   1. Basics     - Counter, Block, Text, key events
//   2. Navigation - List, Scrollbar
//   3. Data Viz   - Chart, BarChart, Sparkline, Canvas, Calendar, BigText
//   4. Monitoring  - Dashboard with live sparklines, gauges, table
//   5. Rich Text  - 3x3 panel grid: Theme, Styles, Highlighter, etc.
//   6. QA Audit   - Live contrast audit on the app's own buffer
//
// Controls:
//   1-6 or left/right: switch tabs
//   q / Ctrl-C: quit
//   Tab-specific keys documented per tab

const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);
const ColorTriplet = zithril.ColorTriplet;

const GalleryTab = enum(usize) {
    basics = 0,
    navigation = 1,
    data_viz = 2,
    monitoring = 3,
    rich_text = 4,
    qa_audit = 5,
};

const tab_count = 6;
const tab_titles = [tab_count][]const u8{
    "Basics",
    "Navigation",
    "Data Viz",
    "Monitoring",
    "Rich Text",
    "QA Audit",
};

const State = struct {
    current_tab: GalleryTab = .basics,
    tick_count: u32 = 0,

    // Basics tab
    count: i32 = 0,

    // Navigation tab
    nav_selected: usize = 0,

    // Data Viz tab
    dataviz_page: usize = 0,

    // Monitoring tab
    mon_selected_process: usize = 0,

    // QA Audit tab
    audit_pass: u16 = 0,
    audit_warn: u16 = 0,
    audit_fail: u16 = 0,
    audit_lines: [16][80]u8 = undefined,
    audit_line_lens: [16]u8 = [_]u8{0} ** 16,
    audit_line_count: usize = 0,
    audit_ran: bool = false,

    fn nextTab(self: *State) void {
        const idx = @intFromEnum(self.current_tab);
        if (idx < tab_count - 1) {
            self.current_tab = @enumFromInt(idx + 1);
        }
    }

    fn prevTab(self: *State) void {
        const idx = @intFromEnum(self.current_tab);
        if (idx > 0) {
            self.current_tab = @enumFromInt(idx - 1);
        }
    }

    fn setAuditLine(self: *State, msg: []const u8) void {
        if (self.audit_line_count >= 16) return;
        const idx = self.audit_line_count;
        const len = @min(msg.len, 80);
        @memcpy(self.audit_lines[idx][0..len], msg[0..len]);
        self.audit_line_lens[idx] = @intCast(len);
        self.audit_line_count += 1;
    }

    fn getAuditLine(self: *const State, idx: usize) []const u8 {
        return self.audit_lines[idx][0..self.audit_line_lens[idx]];
    }
};

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            switch (key.code) {
                .char => |c| {
                    if (c == 'q' and !key.modifiers.any()) return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;

                    if (!key.modifiers.any()) {
                        if (c >= '1' and c <= '6') {
                            state.current_tab = @enumFromInt(c - '1');
                            return .none;
                        }
                        if (c == 'h' or c == 'H') {
                            state.prevTab();
                            return .none;
                        }
                        if (c == 'l' or c == 'L') {
                            state.nextTab();
                            return .none;
                        }

                        switch (state.current_tab) {
                            .basics => switch (c) {
                                '+' => state.count +|= 1,
                                '-' => state.count -|= 1,
                                else => {},
                            },
                            .navigation => switch (c) {
                                'j' => {
                                    if (state.nav_selected < nav_items.len - 1)
                                        state.nav_selected += 1;
                                },
                                'k' => {
                                    if (state.nav_selected > 0)
                                        state.nav_selected -= 1;
                                },
                                else => {},
                            },
                            .data_viz => switch (c) {
                                'n' => {
                                    if (state.dataviz_page < 4) state.dataviz_page += 1;
                                },
                                'p' => {
                                    if (state.dataviz_page > 0) state.dataviz_page -= 1;
                                },
                                else => {},
                            },
                            .monitoring => switch (c) {
                                'j' => state.mon_selected_process = @min(state.mon_selected_process + 1, process_names.len - 1),
                                'k' => state.mon_selected_process -|= 1,
                                else => {},
                            },
                            .qa_audit => switch (c) {
                                'r' => {
                                    state.audit_ran = false;
                                },
                                else => {},
                            },
                            else => {},
                        }
                    }
                },
                .left => if (!key.modifiers.any()) state.prevTab(),
                .right => if (!key.modifiers.any()) state.nextTab(),
                .up => if (!key.modifiers.any()) switch (state.current_tab) {
                    .basics => state.count +|= 1,
                    .navigation => {
                        if (state.nav_selected > 0) state.nav_selected -= 1;
                    },
                    .monitoring => state.mon_selected_process -|= 1,
                    else => {},
                },
                .down => if (!key.modifiers.any()) switch (state.current_tab) {
                    .basics => state.count -|= 1,
                    .navigation => {
                        if (state.nav_selected < nav_items.len - 1) state.nav_selected += 1;
                    },
                    .monitoring => state.mon_selected_process = @min(state.mon_selected_process + 1, process_names.len - 1),
                    else => {},
                },
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
        zithril.Constraint.len(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    const tabs = zithril.Tabs{
        .titles = &tab_titles,
        .selected = @intFromEnum(state.current_tab),
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bold().fg(.yellow).bg(.blue),
        .divider = " | ",
    };
    frame.render(tabs, main_layout.get(0));

    const content_area = main_layout.get(1);
    switch (state.current_tab) {
        .basics => renderBasics(state, frame, content_area),
        .navigation => renderNavigation(state, frame, content_area),
        .data_viz => renderDataViz(state, frame, content_area),
        .monitoring => renderMonitoring(state, frame, content_area),
        .rich_text => renderRichText(state, frame, content_area),
        .qa_audit => renderQaAudit(state, frame, content_area),
    }

    frame.render(zithril.Text{
        .content = " 1-6:tab | left/right:navigate | q:quit | Tab-specific: see each tab",
        .style = zithril.Style.init().bg(.blue).fg(.white),
    }, main_layout.get(2));
}

// ============================================================
// TAB 1: BASICS (from counter.zig)
// ============================================================

fn renderBasics(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Basics - Counter (up/down or +/-, demonstrates Block + Text)",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    var buf: [64]u8 = undefined;
    const count_str = std.fmt.bufPrint(&buf, "Count: {d}", .{state.count}) catch "???";

    const text = zithril.Text{
        .content = count_str,
        .style = zithril.Style.init().bold().fg(.green),
        .alignment = .center,
    };
    frame.render(text, inner);
}

// ============================================================
// TAB 2: NAVIGATION (from list.zig)
// ============================================================

const nav_items = [_][]const u8{
    "Apple",
    "Banana",
    "Cherry",
    "Date",
    "Elderberry",
    "Fig",
    "Grape",
    "Honeydew",
    "Jackfruit",
    "Kiwi",
};

fn renderNavigation(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Navigation - List (j/k or arrows)",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    const list = zithril.List{
        .items = &nav_items,
        .selected = state.nav_selected,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white).bold(),
        .highlight_symbol = "> ",
    };
    frame.render(list, inner);
}

// ============================================================
// TAB 3: DATA VIZ (from dataviz/main.zig)
// ============================================================

const temp_data = [_][2]f64{
    .{ 0, 20 },  .{ 1, 25 }, .{ 2, 30 }, .{ 3, 28 }, .{ 4, 35 },
    .{ 5, 40 },  .{ 6, 38 }, .{ 7, 45 }, .{ 8, 50 }, .{ 9, 55 },
    .{ 10, 60 },
};

const humidity_data = [_][2]f64{
    .{ 0, 60 },  .{ 1, 58 }, .{ 2, 55 }, .{ 3, 60 }, .{ 4, 65 },
    .{ 5, 70 },  .{ 6, 68 }, .{ 7, 72 }, .{ 8, 75 }, .{ 9, 80 },
    .{ 10, 85 },
};

const scatter_data = [_][2]f64{
    .{ 1.5, 42 }, .{ 3.2, 55 }, .{ 5.5, 68 }, .{ 7.8, 48 }, .{ 9.1, 72 },
};

const spark_cpu_data = [_]f64{ 20, 30, 45, 60, 55, 70, 65, 80, 75, 60, 50, 45, 55, 65, 70, 85, 90, 75, 60, 55 };
const spark_mem_data = [_]f64{ 40, 42, 45, 47, 50, 52, 55, 58, 60, 62, 65, 68, 70, 68, 65, 60, 58, 55, 52, 50 };
const spark_net_data = [_]f64{ 10, 15, 25, 35, 30, 40, 60, 80, 70, 50, 30, 20, 25, 35, 45, 55, 60, 50, 40, 30 };

const dataviz_page_names = [_][]const u8{
    "Charts",
    "Bar Charts",
    "Sparklines & Gauges",
    "Canvas",
    "Calendar & BigText",
};

fn renderDataViz(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    frame.render(zithril.Tabs{
        .titles = &dataviz_page_names,
        .selected = state.dataviz_page,
        .style = zithril.Style.empty,
        .highlight_style = zithril.Style.init().bold().fg(.cyan),
        .divider = "|",
    }, layout.get(0));

    const content_area = layout.get(1);
    switch (state.dataviz_page) {
        0 => renderDvCharts(frame, content_area),
        1 => renderDvBarCharts(frame, content_area),
        2 => renderDvSparklines(frame, content_area),
        3 => renderDvCanvas(frame, content_area),
        4 => renderDvCalendar(frame, content_area),
        else => {},
    }

    frame.render(zithril.Text{
        .content = "n/p: next/prev page",
        .style = zithril.Style.init().fg(.white).dim(),
    }, layout.get(2));
}

fn renderDvCharts(frame: *FrameType, area: zithril.Rect) void {
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

fn renderDvBarCharts(frame: *FrameType, area: zithril.Rect) void {
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

fn renderDvSparklines(frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
        zithril.Constraint.len(1),
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
        zithril.Constraint.flexible(1),
    });

    const sparklines = [_]struct { title: []const u8, data: []const f64, color: zithril.Color }{
        .{ .title = "CPU Usage", .data = &spark_cpu_data, .color = .green },
        .{ .title = "Memory Usage", .data = &spark_mem_data, .color = .yellow },
        .{ .title = "Network Traffic", .data = &spark_net_data, .color = .cyan },
    };
    for (sparklines, 0..) |s, i| {
        const block = zithril.Block{ .title = s.title, .border = .rounded, .border_style = zithril.Style.init().fg(s.color) };
        frame.render(block, layout.get(i));
        frame.render(zithril.Sparkline{
            .data = s.data,
            .style = zithril.Style.init().fg(s.color),
            .max = 100.0,
        }, block.inner(layout.get(i)));
    }

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
}

fn renderDvCanvas(frame: *FrameType, area: zithril.Rect) void {
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

fn renderDvCalendar(frame: *FrameType, area: zithril.Rect) void {
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

// ============================================================
// TAB 4: MONITORING (from dashboard/main.zig)
// ============================================================

const mon_cpu_data = [_]f64{ 23, 45, 67, 78, 65, 54, 43, 56, 67, 78, 89, 76, 65, 54, 67, 78, 85, 72, 68, 75 };
const mon_mem_data = [_]f64{ 45, 47, 49, 52, 54, 56, 58, 61, 63, 65, 67, 69, 71, 73, 75, 76, 78, 79, 80, 82 };
const mon_net_data = [_]f64{ 12, 34, 56, 23, 45, 67, 34, 12, 45, 78, 56, 34, 67, 89, 45, 23, 56, 78, 34, 67 };

const process_names = [_][]const u8{ "systemd", "chrome", "firefox", "code", "zithril", "postgres", "nginx", "docker" };
const process_pids = [_][]const u8{ "1", "1234", "1256", "1890", "2341", "3456", "4567", "5678" };
const process_cpus = [_][]const u8{ "0.1", "23.4", "18.7", "12.3", "8.9", "5.6", "2.3", "1.2" };
const process_mems = [_][]const u8{ "2.1", "1024.5", "856.2", "512.8", "128.4", "256.7", "64.3", "32.1" };

fn getMonData(tick_count: u32, comptime series: []const f64) []const f64 {
    const offset = tick_count % 10;
    return series[offset..@min(offset + 20, series.len)];
}

fn renderMonitoring(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const main_layout = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(4),
        zithril.Constraint.len(5),
        zithril.Constraint.len(5),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    frame.render(zithril.BigText{
        .text = "DASH",
        .style = zithril.Style.init().fg(.cyan).bold(),
        .pixel_size = .half,
    }, main_layout.get(0));

    renderMonSparklines(state, frame, main_layout.get(1));
    renderMonGauges(state, frame, main_layout.get(2));
    renderMonProcessTable(state, frame, main_layout.get(3));

    var status_buf: [64]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, " j/k:navigate | Tick: {d}", .{state.tick_count}) catch " j/k:navigate";
    frame.render(zithril.Text{
        .content = status,
        .style = zithril.Style.init().bg(.blue).fg(.white),
    }, main_layout.get(4));
}

fn renderMonSparklines(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const layout = zithril.layout(area, .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    const panels = [_]struct { title: []const u8, data: []const f64, color: zithril.Color }{
        .{ .title = "CPU %", .data = getMonData(state.tick_count, &mon_cpu_data), .color = .green },
        .{ .title = "Memory %", .data = getMonData(state.tick_count, &mon_mem_data), .color = .yellow },
        .{ .title = "Network MB/s", .data = getMonData(state.tick_count, &mon_net_data), .color = .magenta },
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

fn renderMonGauges(state: *State, frame: *FrameType, area: zithril.Rect) void {
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

fn renderMonProcessTable(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .title = "Processes (j/k to navigate)", .border = .rounded, .border_style = zithril.Style.init().fg(.cyan) };
    frame.render(block, area);

    const header = [_][]const u8{ "Name", "PID", "CPU%", "MEM(MB)" };

    const rows = comptime blk: {
        var r: [process_names.len][4][]const u8 = undefined;
        for (0..process_names.len) |i| {
            r[i] = .{ process_names[i], process_pids[i], process_cpus[i], process_mems[i] };
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
        .selected = state.mon_selected_process,
        .style = zithril.Style.init().fg(.white),
        .header_style = zithril.Style.init().bold().fg(.cyan),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white),
    }, block.inner(area));
}

// ============================================================
// TAB 5: RICH TEXT (from showcase/main.zig)
// ============================================================

fn panelLines(
    frame: *FrameType,
    area: zithril.Rect,
    title: ?[]const u8,
    border_color: zithril.Color,
) ?zithril.BoundedRects {
    const block = zithril.Block{
        .title = title,
        .border = .rounded,
        .border_style = zithril.Style.init().fg(border_color),
    };
    frame.render(block, area);
    const inner = block.inner(area);
    if (inner.height < 2 or inner.width < 4) return null;
    return zithril.layout(inner, .vertical, &([_]zithril.Constraint{zithril.Constraint.len(1)} ** 5));
}

fn renderRichText(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const panel_rows = zithril.layout(area, .vertical, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    const row1_cols = zithril.layout(panel_rows.get(0), .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });
    const row2_cols = zithril.layout(panel_rows.get(1), .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });
    const row3_cols = zithril.layout(panel_rows.get(2), .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    renderThemePanel(state, frame, row1_cols.get(0));
    renderNewStylesPanel(state, frame, row1_cols.get(1));
    renderHighlighterPanel(state, frame, row1_cols.get(2));

    renderAdaptivePanel(frame, row2_cols.get(0));
    renderGradientPanel(frame, row2_cols.get(1));
    renderWcagPanel(frame, row2_cols.get(2));

    renderAnsiPanel(state, frame, row3_cols.get(0));
    renderPrettyPanel(state, frame, row3_cols.get(1));
    renderMeasurementPanel(state, frame, row3_cols.get(2));
}

fn rtPhase(state: *const State) u32 {
    return state.tick_count % 4;
}

fn renderThemePanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Theme", .cyan) orelse return;
    const p = rtPhase(state);

    if (p == 0 or p == 2) {
        frame.render(zithril.Text{ .content = "[INFO] System ready", .style = zithril.Style.init().fg(.cyan) }, lines.get(0));
        frame.render(zithril.Text{ .content = "[WARN] Low memory", .style = zithril.Style.init().fg(.yellow).bold() }, lines.get(1));
        frame.render(zithril.Text{ .content = "[ERROR] Disk full", .style = zithril.Style.init().fg(.red).bold() }, lines.get(2));
        frame.render(zithril.Text{ .content = "[OK] Backup done", .style = zithril.Style.init().fg(.green) }, lines.get(3));
        frame.render(zithril.Text{ .content = "Muted hint text", .style = zithril.Style.init().dim() }, lines.get(4));
    } else {
        frame.render(zithril.Text{ .content = "Title Style", .style = zithril.Style.init().bold() }, lines.get(0));
        frame.render(zithril.Text{ .content = "Accent Style", .style = zithril.Style.init().fg(.blue).bold() }, lines.get(1));
        frame.render(zithril.Text{ .content = "Success Style", .style = zithril.Style.init().fg(.green) }, lines.get(2));
        frame.render(zithril.Text{ .content = "Info + Bold", .style = zithril.Style.init().fg(.cyan).bold() }, lines.get(3));
        frame.render(zithril.Text{ .content = "Error + Italic", .style = zithril.Style.init().fg(.red).italic() }, lines.get(4));
    }
}

fn renderNewStylesPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "New Styles", .red) orelse return;
    const p = rtPhase(state);

    if (p == 0 or p == 2) {
        frame.render(zithril.Text{ .content = "Double Underline", .style = zithril.Style.init().underline2().fg(.cyan) }, lines.get(0));
        frame.render(zithril.Text{ .content = "Frame (SGR 51)", .style = zithril.Style.init().frame().fg(.green) }, lines.get(1));
        frame.render(zithril.Text{ .content = "Encircle (SGR 52)", .style = zithril.Style.init().encircle().fg(.yellow) }, lines.get(2));
        frame.render(zithril.Text{ .content = "Overline (SGR 53)", .style = zithril.Style.init().overline().fg(.magenta) }, lines.get(3));
        frame.render(zithril.Text{ .content = "All combined!", .style = zithril.Style.init().underline2().overline().bold().fg(.red) }, lines.get(4));
    } else {
        frame.render(zithril.Text{ .content = "Bold + Overline", .style = zithril.Style.init().bold().overline().fg(.white) }, lines.get(0));
        frame.render(zithril.Text{ .content = "Italic + Frame", .style = zithril.Style.init().italic().frame().fg(.cyan) }, lines.get(1));
        frame.render(zithril.Text{ .content = "Dim + Encircle", .style = zithril.Style.init().dim().encircle().fg(.yellow) }, lines.get(2));
        frame.render(zithril.Text{ .content = "Strike + Underline2", .style = zithril.Style.init().strikethrough().underline2().fg(.red) }, lines.get(3));
        frame.render(zithril.Text{ .content = "Reverse + Overline", .style = zithril.Style.init().reverse().overline().fg(.blue) }, lines.get(4));
    }
}

fn renderHighlighterPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Highlighter", .yellow) orelse return;
    const p = rtPhase(state);

    if (p == 0 or p == 3) {
        frame.render(zithril.Text{ .content = "Numbers:", .style = zithril.Style.init().bold() }, lines.get(0));
        frame.render(zithril.Text{ .content = "  42", .style = zithril.Style.init().fg(.cyan).bold() }, lines.get(1));
        frame.render(zithril.Text{ .content = "  3.14159", .style = zithril.Style.init().fg(.cyan).bold() }, lines.get(2));
        frame.render(zithril.Text{ .content = "Booleans:", .style = zithril.Style.init().bold() }, lines.get(3));
        frame.render(zithril.Text{ .content = "  true / false", .style = zithril.Style.init().fg(.green).italic() }, lines.get(4));
    } else {
        frame.render(zithril.Text{ .content = "Strings:", .style = zithril.Style.init().bold() }, lines.get(0));
        frame.render(zithril.Text{ .content = "  \"hello world\"", .style = zithril.Style.init().fg(.yellow) }, lines.get(1));
        frame.render(zithril.Text{ .content = "URLs:", .style = zithril.Style.init().bold() }, lines.get(2));
        frame.render(zithril.Text{ .content = "  https://zithril.dev", .style = zithril.Style.init().fg(.blue).underline() }, lines.get(3));
        frame.render(zithril.Text{ .content = "  null", .style = zithril.Style.init().fg(.magenta).italic() }, lines.get(4));
    }
}

fn renderAdaptivePanel(frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Adaptive Colors", zithril.Color.fromRgb(255, 165, 0)) orelse return;

    const ac = zithril.AdaptiveColor.init(
        zithril.Color.fromRgb(255, 100, 50),
        zithril.Color.from256(208),
        zithril.Color.red,
    );

    frame.render(zithril.Text{ .content = "AdaptiveColor: RGB(255,100,50)", .style = zithril.Style.init().bold() }, lines.get(0));
    frame.render(zithril.Text{ .content = "  truecolor -> RGB direct", .style = zithril.Style.init().fg(ac.resolve(.truecolor)) }, lines.get(1));
    frame.render(zithril.Text{ .content = "  256-color -> index 208", .style = zithril.Style.init().fg(ac.resolve(.eight_bit)) }, lines.get(2));
    frame.render(zithril.Text{ .content = "  16-color  -> red", .style = zithril.Style.init().fg(ac.resolve(.standard)) }, lines.get(3));
    frame.render(zithril.Text{ .content = "Auto-degrades per terminal", .style = zithril.Style.init().dim() }, lines.get(4));
}

fn renderGradientSamples(frame: *FrameType, line: zithril.Rect, colors: *const [5]ColorTriplet) void {
    const samples = [_]usize{ 0, 2, 4 };
    var x_off: u16 = 1;
    for (samples) |i| {
        var buf: [8]u8 = undefined;
        const hex = std.fmt.bufPrint(&buf, "#{x:0>2}{x:0>2}{x:0>2}", .{
            colors[i].r, colors[i].g, colors[i].b,
        }) catch "#??????";
        const sub = zithril.Rect.init(line.x +| x_off, line.y, @min(7, line.width -| x_off), 1);
        frame.render(zithril.Text{
            .content = hex,
            .style = zithril.Style.init().fg(zithril.Color.fromRgb(colors[i].r, colors[i].g, colors[i].b)),
        }, sub);
        x_off +|= 8;
    }
}

fn renderGradientPanel(frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Color Gradients", zithril.Color.fromRgb(128, 0, 255)) orelse return;

    const rgb_stops = [_]ColorTriplet{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
    };
    var rgb_out: [5]ColorTriplet = undefined;
    zithril.gradient(&rgb_stops, &rgb_out, false);

    const hsl_stops = [_]ColorTriplet{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
    };
    var hsl_out: [5]ColorTriplet = undefined;
    zithril.gradient(&hsl_stops, &hsl_out, true);

    frame.render(zithril.Text{ .content = "RGB red->blue:", .style = zithril.Style.init().bold() }, lines.get(0));
    renderGradientSamples(frame, lines.get(1), &rgb_out);
    frame.render(zithril.Text{ .content = "HSL red->green:", .style = zithril.Style.init().bold() }, lines.get(2));
    renderGradientSamples(frame, lines.get(3), &hsl_out);
    frame.render(zithril.Text{ .content = "HSL avoids muddy midpoints", .style = zithril.Style.init().dim() }, lines.get(4));
}

fn wcagLevelStr(level: zithril.WcagLevel) []const u8 {
    return switch (level) {
        .fail => "FAIL",
        .aa_large => "AA-lg",
        .aa => "AA",
        .aaa => "AAA",
    };
}

fn renderWcagPanel(frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "WCAG Contrast", zithril.Color.fromRgb(0, 200, 100)) orelse return;

    const black = ColorTriplet{ .r = 0, .g = 0, .b = 0 };
    const white = ColorTriplet{ .r = 255, .g = 255, .b = 255 };
    const gray = ColorTriplet{ .r = 150, .g = 150, .b = 150 };

    var buf0: [40]u8 = undefined;
    var buf1: [40]u8 = undefined;
    var buf2: [40]u8 = undefined;

    const bw_ratio = black.contrastRatio(white);
    const s0 = std.fmt.bufPrint(&buf0, "Blk/Wht: {d:.1}:1 AAA", .{bw_ratio}) catch "?";
    frame.render(zithril.Text{ .content = "WCAG 2.1 Contrast Ratios:", .style = zithril.Style.init().bold() }, lines.get(0));
    frame.render(zithril.Text{ .content = s0, .style = zithril.Style.init().fg(.green) }, lines.get(1));

    const gw_ratio = gray.contrastRatio(white);
    const gw_level = gray.wcagLevel(white);
    const s1 = std.fmt.bufPrint(&buf1, "Gry/Wht: {d:.1}:1 {s}", .{ gw_ratio, wcagLevelStr(gw_level) }) catch "?";
    frame.render(zithril.Text{ .content = s1, .style = zithril.Style.init().fg(if (gw_level == .fail) zithril.Color.red else zithril.Color.yellow) }, lines.get(2));

    const gb_ratio = gray.contrastRatio(black);
    const gb_level = gray.wcagLevel(black);
    const s2 = std.fmt.bufPrint(&buf2, "Gry/Blk: {d:.1}:1 {s}", .{ gb_ratio, wcagLevelStr(gb_level) }) catch "?";
    frame.render(zithril.Text{ .content = s2, .style = zithril.Style.init().fg(.cyan) }, lines.get(3));

    frame.render(zithril.Text{ .content = "4.5:1=AA, 7:1=AAA", .style = zithril.Style.init().dim() }, lines.get(4));
}

fn renderAnsiPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "ANSI Parser", .green) orelse return;
    const p = rtPhase(state);

    if (p == 0 or p == 1) {
        frame.render(zithril.Text{ .content = "Raw: \\x1b[1mBold\\x1b[0m", .style = zithril.Style.init().dim() }, lines.get(0));
        frame.render(zithril.Text{ .content = "Parsed: Bold", .style = zithril.Style.init().bold() }, lines.get(1));
        frame.render(zithril.Text{ .content = "Raw: \\x1b[31mRed\\x1b[0m", .style = zithril.Style.init().dim() }, lines.get(2));
        frame.render(zithril.Text{ .content = "Parsed: Red", .style = zithril.Style.init().fg(.red) }, lines.get(3));
        frame.render(zithril.Text{ .content = "Strip: plain text only", .style = zithril.Style.init().fg(.white) }, lines.get(4));
    } else {
        frame.render(zithril.Text{ .content = "Raw: \\x1b[3mItalic\\x1b[0m", .style = zithril.Style.init().dim() }, lines.get(0));
        frame.render(zithril.Text{ .content = "Parsed: Italic", .style = zithril.Style.init().italic() }, lines.get(1));
        frame.render(zithril.Text{ .content = "Raw: \\x1b[34mBlue\\x1b[0m", .style = zithril.Style.init().dim() }, lines.get(2));
        frame.render(zithril.Text{ .content = "Parsed: Blue", .style = zithril.Style.init().fg(.blue) }, lines.get(3));
        frame.render(zithril.Text{ .content = "Segments -> styled spans", .style = zithril.Style.init().fg(.white) }, lines.get(4));
    }
}

fn renderPrettyPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Pretty Print", .magenta) orelse return;
    const p = rtPhase(state);

    if (p == 0 or p == 1) {
        frame.render(zithril.Text{ .content = "struct {", .style = zithril.Style.init().fg(.white) }, lines.get(0));
        frame.render(zithril.Text{ .content = "  .name = \"zithril\"", .style = zithril.Style.init().fg(.yellow) }, lines.get(1));
        frame.render(zithril.Text{ .content = "  .version = 10", .style = zithril.Style.init().fg(.cyan).bold() }, lines.get(2));
        frame.render(zithril.Text{ .content = "  .stable = true", .style = zithril.Style.init().fg(.green).italic() }, lines.get(3));
        frame.render(zithril.Text{ .content = "}", .style = zithril.Style.init().fg(.white) }, lines.get(4));
    } else {
        frame.render(zithril.Text{ .content = "[_]i32 {", .style = zithril.Style.init().fg(.white) }, lines.get(0));
        frame.render(zithril.Text{ .content = "  1, 2, 3,", .style = zithril.Style.init().fg(.cyan).bold() }, lines.get(1));
        frame.render(zithril.Text{ .content = "  4, 5, 6,", .style = zithril.Style.init().fg(.cyan).bold() }, lines.get(2));
        frame.render(zithril.Text{ .content = "  ... (30 items)", .style = zithril.Style.init().dim() }, lines.get(3));
        frame.render(zithril.Text{ .content = "}", .style = zithril.Style.init().fg(.white) }, lines.get(4));
    }
}

fn renderMeasurementPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Measurement", .blue) orelse return;
    const p = rtPhase(state);

    if (p == 0 or p == 3) {
        frame.render(zithril.Text{ .content = "\"Hello\" ->", .style = zithril.Style.init().bold() }, lines.get(0));
        frame.render(zithril.Text{ .content = "  min: 5, max: 5", .style = zithril.Style.init().fg(.cyan) }, lines.get(1));
        frame.render(zithril.Text{ .content = "\"Hello World\" ->", .style = zithril.Style.init().bold() }, lines.get(2));
        frame.render(zithril.Text{ .content = "  min: 5, max: 11", .style = zithril.Style.init().fg(.cyan) }, lines.get(3));
        frame.render(zithril.Text{ .content = "(min=word, max=line)", .style = zithril.Style.init().dim() }, lines.get(4));
    } else {
        var buf0: [40]u8 = undefined;
        var buf1: [40]u8 = undefined;
        var buf2: [40]u8 = undefined;
        var buf3: [40]u8 = undefined;
        const m_len = zithril.fromConstraint(zithril.Constraint.len(30), 100);
        const m_flex = zithril.fromConstraint(zithril.Constraint.flexible(1), 100);
        const s0 = std.fmt.bufPrint(&buf0, "len(30) -> {d},{d}", .{ m_len.minimum, m_len.maximum }) catch "?";
        const s1 = std.fmt.bufPrint(&buf1, "flex(1) -> {d},{d}", .{ m_flex.minimum, m_flex.maximum }) catch "?";
        const m_pct = zithril.fromConstraint(zithril.Constraint.percent(50), 200);
        const m_min = zithril.fromConstraint(zithril.Constraint.minSize(20), 100);
        const s2 = std.fmt.bufPrint(&buf2, "pct(50) -> {d},{d}", .{ m_pct.minimum, m_pct.maximum }) catch "?";
        const s3 = std.fmt.bufPrint(&buf3, "min(20) -> {d},{d}", .{ m_min.minimum, m_min.maximum }) catch "?";
        frame.render(zithril.Text{ .content = "Constraint -> Measurement:", .style = zithril.Style.init().bold() }, lines.get(0));
        frame.render(zithril.Text{ .content = s0, .style = zithril.Style.init().fg(.green) }, lines.get(1));
        frame.render(zithril.Text{ .content = s1, .style = zithril.Style.init().fg(.yellow) }, lines.get(2));
        frame.render(zithril.Text{ .content = s2, .style = zithril.Style.init().fg(.cyan) }, lines.get(3));
        frame.render(zithril.Text{ .content = s3, .style = zithril.Style.init().fg(.magenta) }, lines.get(4));
    }
}

// ============================================================
// TAB 6: QA AUDIT
// ============================================================

fn renderQaAudit(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "QA Audit - Live Contrast Analysis (r: re-run)",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    if (!state.audit_ran) {
        runBufferAudit(state, frame);
        state.audit_ran = true;
    }

    const content_layout = zithril.layout(inner, .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.flexible(1),
    });

    var summary_buf: [80]u8 = undefined;
    const summary = std.fmt.bufPrint(&summary_buf, "Contrast Analysis     [{d} pass] [{d} warn] [{d} fail]", .{
        state.audit_pass,
        state.audit_warn,
        state.audit_fail,
    }) catch "Audit results";

    const total = state.audit_pass + state.audit_warn + state.audit_fail;
    var rate_buf: [40]u8 = undefined;
    const rate_str = if (total > 0) blk: {
        const rate = @as(u32, state.audit_pass) * 100 / total;
        break :blk std.fmt.bufPrint(&rate_buf, "Overall: {d}% pass rate", .{rate}) catch "?";
    } else "No findings";

    const summary_block = zithril.Block{
        .border = .plain,
        .border_style = zithril.Style.init().fg(.white),
    };
    frame.render(summary_block, content_layout.get(0));
    const summary_inner = summary_block.inner(content_layout.get(0));
    if (!summary_inner.isEmpty()) {
        frame.render(zithril.Text{
            .content = summary,
            .style = zithril.Style.init().bold().fg(.white),
        }, zithril.Rect.init(summary_inner.x, summary_inner.y, summary_inner.width, 1));
    }

    const findings_area = content_layout.get(1);
    if (findings_area.isEmpty()) return;

    var y: u16 = 0;
    for (0..state.audit_line_count) |i| {
        if (y >= findings_area.height) break;
        const line_area = zithril.Rect.init(findings_area.x, findings_area.y + y, findings_area.width, 1);
        const line_text = state.getAuditLine(i);

        const style = if (std.mem.indexOf(u8, line_text, "PASS") != null)
            zithril.Style.init().fg(.green)
        else if (std.mem.indexOf(u8, line_text, "WARN") != null)
            zithril.Style.init().fg(.yellow)
        else if (std.mem.indexOf(u8, line_text, "FAIL") != null)
            zithril.Style.init().fg(.red)
        else if (std.mem.indexOf(u8, line_text, "Overall") != null)
            zithril.Style.init().fg(.white).bold()
        else
            zithril.Style.init().fg(.white);

        frame.render(zithril.Text{
            .content = line_text,
            .style = style,
        }, line_area);
        y += 1;
    }

    if (state.audit_line_count == 0) {
        frame.render(zithril.Text{
            .content = "Press 'r' to run audit...",
            .style = zithril.Style.init().fg(.white).italic(),
            .alignment = .center,
        }, findings_area);
    }

    if (y < findings_area.height and state.audit_line_count > 0) {
        const rate_area = zithril.Rect.init(findings_area.x, findings_area.y + y + 1, findings_area.width, 1);
        frame.render(zithril.Text{
            .content = rate_str,
            .style = zithril.Style.init().fg(.white).bold(),
        }, rate_area);
    }
}

fn runBufferAudit(state: *State, frame: *FrameType) void {
    state.audit_line_count = 0;
    state.audit_pass = 0;
    state.audit_warn = 0;
    state.audit_fail = 0;

    const buf = frame.buffer;
    const width = buf.width;
    const height = buf.height;

    var sample_row: u16 = 0;
    while (sample_row < height and state.audit_line_count < 14) : (sample_row += 3) {
        var col: u16 = 0;
        while (col < width) {
            const cell = buf.get(col, sample_row);
            const fg_color = cell.style.getForeground() orelse zithril.Color.white;
            const bg_color = cell.style.getBackground() orelse zithril.Color.black;

            var end_col = col + 1;
            while (end_col < width) : (end_col += 1) {
                const next_cell = buf.get(end_col, sample_row);
                const next_fg = next_cell.style.getForeground() orelse zithril.Color.white;
                const next_bg = next_cell.style.getBackground() orelse zithril.Color.black;
                if (!fg_color.eql(next_fg) or !bg_color.eql(next_bg)) break;
            }

            if (end_col - col >= 2 and !isDefaultPair(fg_color, bg_color)) {
                const fg_triplet = colorToTriplet(fg_color);
                const bg_triplet = colorToTriplet(bg_color);
                const ratio = fg_triplet.contrastRatio(bg_triplet);
                const level = fg_triplet.wcagLevel(bg_triplet);

                switch (level) {
                    .aaa, .aa => state.audit_pass += 1,
                    .aa_large => state.audit_warn += 1,
                    .fail => state.audit_fail += 1,
                }

                const severity: []const u8 = switch (level) {
                    .aaa, .aa => "PASS",
                    .aa_large => "WARN",
                    .fail => "FAIL",
                };

                var line_buf: [80]u8 = undefined;
                const line = std.fmt.bufPrint(&line_buf, "({d},{d})-({d},{d}): {d:.1}:1  {s}  {s}", .{
                    col,
                    sample_row,
                    end_col,
                    sample_row,
                    ratio,
                    wcagLevelStr(level),
                    severity,
                }) catch "?";
                state.setAuditLine(line);
            }

            col = end_col;
        }
    }
}

fn isDefaultPair(fg: zithril.Color, bg: zithril.Color) bool {
    return fg.eql(zithril.Color.white) and bg.eql(zithril.Color.black);
}

fn colorToTriplet(color: zithril.Color) ColorTriplet {
    if (color.getTriplet()) |t| return t;
    const num = color.number orelse return ColorTriplet{ .r = 229, .g = 229, .b = 229 };
    const standard_triplets = [16]ColorTriplet{
        .{ .r = 0, .g = 0, .b = 0 },
        .{ .r = 205, .g = 0, .b = 0 },
        .{ .r = 0, .g = 205, .b = 0 },
        .{ .r = 205, .g = 205, .b = 0 },
        .{ .r = 0, .g = 0, .b = 238 },
        .{ .r = 205, .g = 0, .b = 205 },
        .{ .r = 0, .g = 205, .b = 205 },
        .{ .r = 229, .g = 229, .b = 229 },
        .{ .r = 127, .g = 127, .b = 127 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 92, .g = 92, .b = 255 },
        .{ .r = 255, .g = 0, .b = 255 },
        .{ .r = 0, .g = 255, .b = 255 },
        .{ .r = 255, .g = 255, .b = 255 },
    };
    if (num < 16) return standard_triplets[num];
    if (num >= 232) {
        const gray: u8 = @intCast(8 + @as(u16, num - 232) * 10);
        return .{ .r = gray, .g = gray, .b = gray };
    }
    const ci = num - 16;
    const ri: u8 = @intCast(ci / 36);
    const gi: u8 = @intCast((ci % 36) / 6);
    const bi: u8 = @intCast(ci % 6);
    return .{
        .r = if (ri == 0) 0 else @intCast(55 + @as(u16, ri) * 40),
        .g = if (gi == 0) 0 else @intCast(55 + @as(u16, gi) * 40),
        .b = if (bi == 0) 0 else @intCast(55 + @as(u16, bi) * 40),
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var state = State{};
    var app = zithril.App(State).init(.{
        .state = &state,
        .update = update,
        .view = view,
        .tick_rate_ms = 2000,
    });
    try app.run(gpa.allocator());
}

pub const panic = zithril.terminal_panic;

// ============================================================
// QA COMPANION TESTS
// ============================================================
// Demonstrate TestHarness, ScenarioRunner, Snapshot, and auditContrast
// using the Gallery app's own State/update/view functions.

const testing_alloc = std.testing.allocator;

test "gallery: initial render shows Basics tab" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    try harness.expectString(0, 0, "Basics");
    try std.testing.expectEqual(GalleryTab.basics, state.current_tab);
}

test "gallery: increment counter on Basics tab" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    harness.pressKey('+');
    try std.testing.expectEqual(@as(i32, 1), state.count);

    harness.pressKey('+');
    harness.pressKey('+');
    try std.testing.expectEqual(@as(i32, 3), state.count);

    harness.pressKey('-');
    try std.testing.expectEqual(@as(i32, 2), state.count);
}

test "gallery: tab switching via number keys" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    try std.testing.expectEqual(GalleryTab.basics, state.current_tab);

    harness.pressKey('2');
    try std.testing.expectEqual(GalleryTab.navigation, state.current_tab);

    harness.pressKey('3');
    try std.testing.expectEqual(GalleryTab.data_viz, state.current_tab);

    harness.pressKey('6');
    try std.testing.expectEqual(GalleryTab.qa_audit, state.current_tab);

    harness.pressKey('1');
    try std.testing.expectEqual(GalleryTab.basics, state.current_tab);
}

test "gallery: tab switching via arrow keys" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    harness.pressSpecial(.right);
    try std.testing.expectEqual(GalleryTab.navigation, state.current_tab);

    harness.pressSpecial(.left);
    try std.testing.expectEqual(GalleryTab.basics, state.current_tab);

    harness.pressSpecial(.left);
    try std.testing.expectEqual(GalleryTab.basics, state.current_tab);
}

test "gallery: quit via q key" {
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

test "gallery: tick advances counter" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 80,
        .height = 24,
    });
    defer harness.deinit();

    harness.tickN(5);
    try std.testing.expectEqual(@as(u32, 5), state.tick_count);
}

test "gallery: navigation tab list selection" {
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
    try std.testing.expectEqual(GalleryTab.navigation, state.current_tab);

    harness.pressKey('j');
    try std.testing.expectEqual(@as(usize, 1), state.nav_selected);

    harness.pressKey('j');
    try std.testing.expectEqual(@as(usize, 2), state.nav_selected);

    harness.pressKey('k');
    try std.testing.expectEqual(@as(usize, 1), state.nav_selected);
}

test "gallery: snapshot captures buffer text" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(testing_alloc, .{
        .state = &state,
        .update = update,
        .view = view,
        .width = 40,
        .height = 10,
    });
    defer harness.deinit();

    var snap = try harness.snapshot(testing_alloc);
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 40), snap.width);
    try std.testing.expectEqual(@as(u16, 10), snap.height);
    try std.testing.expect(std.mem.indexOf(u8, snap.text, "Basics") != null);
}

test "gallery: ScenarioRunner basic workflow" {
    var state = State{};
    var runner = zithril.ScenarioRunner(State).init(
        testing_alloc,
        &state,
        update,
        view,
    );

    const scenario =
        \\size 80 24
        \\# Increment counter using type directive
        \\type "+++"
        \\# Switch to Navigation
        \\key 2
        \\# Switch back to Basics
        \\key 1
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(i32, 3), state.count);
}

test "gallery: auditContrast on rendered buffer" {
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
    var audit_result = try zithril.auditContrast(testing_alloc, buf);
    defer audit_result.deinit();

    try std.testing.expectEqual(zithril.AuditCategory.contrast, audit_result.category);
}

test "gallery: AuditReport summary" {
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
    var report = zithril.AuditReport.init(testing_alloc);
    defer report.deinit();

    const contrast = try zithril.auditContrast(testing_alloc, buf);
    try report.addResult(contrast);

    const summary = try report.summary(testing_alloc);
    defer testing_alloc.free(summary);

    try std.testing.expect(std.mem.indexOf(u8, summary, "Audit Report") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "contrast") != null);
}
