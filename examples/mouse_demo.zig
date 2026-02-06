// Mouse interaction demo for zithril TUI framework
//
// Demonstrates:
// - Mouse position and button state tracking
// - Hit testing with colored regions
// - Hover detection with enter/exit transitions
// - Drag selection as a rectangle overlay
// - Scroll event logging
//
// Controls:
// - Mouse: interact with colored regions
// - Scroll: generates scroll events in the log
// - q / Ctrl-C: quit

const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);

const RegionId = enum(u8) {
    red = 0,
    green = 1,
    blue = 2,
    yellow = 3,
};

const region_count = 4;

const region_colors = [region_count]zithril.Color{
    .red,
    .green,
    .blue,
    .yellow,
};

const region_labels = [region_count][]const u8{
    "Red",
    "Green",
    "Blue",
    "Yellow",
};

const max_log_entries = 32;

const State = struct {
    mouse_x: u16 = 0,
    mouse_y: u16 = 0,
    mouse_kind: ?zithril.MouseKind = null,

    hit_tester: zithril.HitTester(RegionId, region_count) = zithril.HitTester(RegionId, region_count).init(),
    hover_states: [region_count]zithril.HoverState = [_]zithril.HoverState{.{}} ** region_count,
    active_region: ?RegionId = null,

    drag: zithril.DragState = .{},
    scroll: zithril.ScrollAccumulator = .{},

    log_buf: [max_log_entries][80]u8 = undefined,
    log_lens: [max_log_entries]u8 = [_]u8{0} ** max_log_entries,
    log_count: usize = 0,
    scroll_total: i32 = 0,
    click_count: u32 = 0,

    fn addLog(self: *State, msg: []const u8) void {
        if (self.log_count >= max_log_entries) {
            // Shift entries up
            var i: usize = 0;
            while (i < max_log_entries - 1) : (i += 1) {
                self.log_buf[i] = self.log_buf[i + 1];
                self.log_lens[i] = self.log_lens[i + 1];
            }
            self.log_count = max_log_entries - 1;
        }
        const idx = self.log_count;
        const len = @min(msg.len, 80);
        @memcpy(self.log_buf[idx][0..len], msg[0..len]);
        self.log_lens[idx] = @intCast(len);
        self.log_count += 1;
    }

    fn getLog(self: *const State, idx: usize) []const u8 {
        return self.log_buf[idx][0..self.log_lens[idx]];
    }
};

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            switch (key.code) {
                .char => |c| {
                    if (c == 'q' and !key.modifiers.any()) return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;
                },
                else => {},
            }
        },
        .mouse => |mouse| {
            state.mouse_x = mouse.x;
            state.mouse_y = mouse.y;
            state.mouse_kind = mouse.kind;

            // Hit test
            state.active_region = state.hit_tester.hitTest(mouse);

            // Hover transitions
            for (0..region_count) |i| {
                const region_idx: u8 = @intCast(i);
                if (region_idx < state.hit_tester.count) {
                    const rect = state.hit_tester.regions[i].rect;
                    const transition = state.hover_states[i].update(rect, mouse);
                    if (transition == .entered) {
                        var buf: [80]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "Hover entered: {s}", .{region_labels[i]}) catch "hover enter";
                        state.addLog(msg);
                    } else if (transition == .exited) {
                        var buf: [80]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "Hover exited: {s}", .{region_labels[i]}) catch "hover exit";
                        state.addLog(msg);
                    }
                }
            }

            // Drag tracking
            if (state.drag.handleMouse(mouse)) {
                if (mouse.kind == .down) {
                    var buf: [80]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "Drag start: ({d},{d})", .{ mouse.x, mouse.y }) catch "drag start";
                    state.addLog(msg);
                } else if (mouse.kind == .up and state.drag.hasMoved()) {
                    const d = state.drag.delta();
                    var buf: [80]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "Drag end: delta=({d},{d})", .{ d.dx, d.dy }) catch "drag end";
                    state.addLog(msg);
                }
            }

            // Click counting
            if (mouse.kind == .down) {
                state.click_count += 1;
            }

            // Scroll accumulation
            if (state.scroll.handleMouse(mouse)) |delta| {
                state.scroll_total += delta;
                var buf: [80]u8 = undefined;
                const dir: []const u8 = if (delta < 0) "up" else "down";
                const msg = std.fmt.bufPrint(&buf, "Scroll {s} (total: {d})", .{ dir, state.scroll_total }) catch "scroll";
                state.addLog(msg);
            }
        },
        else => {},
    }
    return .none;
}

fn view(state: *State, frame: *FrameType) void {
    const area = frame.size();

    // Main layout: header(3) | content(flex) | status(1)
    const main_chunks = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    renderHeader(state, frame, main_chunks.get(0));
    renderContent(state, frame, main_chunks.get(1));
    renderStatusBar(state, frame, main_chunks.get(2));
}

fn renderHeader(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Mouse Demo",
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

    const text = zithril.Text{
        .content = info,
        .style = zithril.Style.init().fg(.white),
        .alignment = .left,
    };
    frame.render(text, inner);
}

fn renderContent(state: *State, frame: *FrameType, area: zithril.Rect) void {
    // Split: regions panel (left) | event log (right)
    const h_chunks = zithril.layout(area, .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    renderRegions(state, frame, h_chunks.get(0));
    renderEventLog(state, frame, h_chunks.get(1));
}

fn renderRegions(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Hover Regions",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.white),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    // Lay out 4 regions in a 2x2 grid
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

    // Register hit regions for next frame
    state.hit_tester.clear();
    for (0..region_count) |i| {
        _ = state.hit_tester.register(@enumFromInt(i), regions[i]);
    }

    // Render each region
    for (0..region_count) |i| {
        const hovered = state.hover_states[i].isHovering();
        const color = region_colors[i];
        const border_style = if (hovered)
            zithril.Style.init().fg(color).bold()
        else
            zithril.Style.init().fg(color);

        const region_block = zithril.Block{
            .title = region_labels[i],
            .border = if (hovered) .double else .rounded,
            .border_style = border_style,
        };
        frame.render(region_block, regions[i]);

        const region_inner = region_block.inner(regions[i]);
        if (!region_inner.isEmpty()) {
            const fill_style = if (hovered)
                zithril.Style.init().bg(color)
            else
                zithril.Style.init();
            const clear = zithril.Clear{ .style = fill_style };
            frame.render(clear, region_inner);

            if (hovered) {
                const status_text = zithril.Text{
                    .content = "[HOVER]",
                    .style = zithril.Style.init().fg(.white).bold(),
                    .alignment = .center,
                };
                frame.render(status_text, region_inner);
            }
        }
    }

    // Render drag selection overlay
    if (state.drag.active) {
        if (state.drag.selectionRect()) |sel| {
            const drag_block = zithril.Block{
                .border = .plain,
                .border_style = zithril.Style.init().fg(.magenta).bold(),
            };
            frame.render(drag_block, sel);
        }
    }
}

fn renderEventLog(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .title = "Event Log",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.white),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    // Render log entries from bottom up (newest at bottom)
    const visible: usize = inner.height;
    const start = if (state.log_count > visible)
        state.log_count - visible
    else
        0;
    const end = state.log_count;

    var y: u16 = 0;
    for (start..end) |i| {
        if (y >= inner.height) break;
        const line_area = zithril.Rect.init(inner.x, inner.y + y, inner.width, 1);
        const text = zithril.Text{
            .content = state.getLog(i),
            .style = zithril.Style.init().fg(.cyan),
            .alignment = .left,
        };
        frame.render(text, line_area);
        y += 1;
    }

    // Show empty state hint
    if (state.log_count == 0) {
        const hint = zithril.Text{
            .content = "Move, click, or scroll...",
            .style = zithril.Style.init().fg(.white).italic(),
            .alignment = .center,
        };
        frame.render(hint, inner);
    }
}

fn renderStatusBar(state: *State, frame: *FrameType, area: zithril.Rect) void {
    _ = state;
    const clear = zithril.Clear{
        .style = zithril.Style.init().bg(.blue),
    };
    frame.render(clear, area);

    const text = zithril.Text{
        .content = "Mouse Demo | q/Ctrl-C: Quit | Hover, click, drag, scroll to interact",
        .style = zithril.Style.init().fg(.white).bg(.blue).bold(),
        .alignment = .left,
    };
    frame.render(text, area);
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
        .mouse_capture = true,
    });

    try app.run(allocator);
}

pub const panic = zithril.terminal_panic;
