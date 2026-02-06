const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);

const State = struct {
    tick_count: u32 = 0,

    fn phase(self: *const State) u32 {
        return self.tick_count % 4;
    }
};

const five_rows = [_]zithril.Constraint{
    zithril.Constraint.len(1),
    zithril.Constraint.len(1),
    zithril.Constraint.len(1),
    zithril.Constraint.len(1),
    zithril.Constraint.len(1),
};

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
    return zithril.layout(inner, .vertical, &five_rows);
}

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            switch (key.code) {
                .char => |c| {
                    if (c == 'q') return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;
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
    const rows = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(4),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(1),
    });

    frame.render(zithril.BigText{
        .text = "SHOWCASE",
        .style = zithril.Style.init().fg(.cyan).bold(),
        .pixel_size = .half,
    }, rows.get(0));

    const mid = rows.get(1);
    const panel_rows = zithril.layout(mid, .vertical, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    const top_cols = zithril.layout(panel_rows.get(0), .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    const bot_cols = zithril.layout(panel_rows.get(1), .horizontal, &.{
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
        zithril.Constraint.flexible(1),
    });

    renderThemePanel(state, frame, top_cols.get(0));
    renderAnsiPanel(state, frame, top_cols.get(1));
    renderHighlighterPanel(state, frame, top_cols.get(2));
    renderPrettyPanel(state, frame, bot_cols.get(0));
    renderNewStylesPanel(state, frame, bot_cols.get(1));
    renderMeasurementPanel(state, frame, bot_cols.get(2));

    var status_buf: [80]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, " q:quit | Phase: {d}/4 | Tick: {d}", .{ state.phase() + 1, state.tick_count }) catch " q:quit";
    frame.render(zithril.Text{
        .content = status,
        .style = zithril.Style.init().bg(.blue).fg(.white),
    }, rows.get(2));
}

fn renderThemePanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Theme", .cyan) orelse return;
    const p = state.phase();

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

fn renderAnsiPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "ANSI Parser", .green) orelse return;
    const p = state.phase();

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

fn renderHighlighterPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Highlighter", .yellow) orelse return;
    const p = state.phase();

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

fn renderPrettyPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Pretty Print", .magenta) orelse return;
    const p = state.phase();

    if (p == 0 or p == 1) {
        frame.render(zithril.Text{ .content = "struct {", .style = zithril.Style.init().fg(.white) }, lines.get(0));
        frame.render(zithril.Text{ .content = "  .name = \"zithril\"", .style = zithril.Style.init().fg(.yellow) }, lines.get(1));
        frame.render(zithril.Text{ .content = "  .version = 9", .style = zithril.Style.init().fg(.cyan).bold() }, lines.get(2));
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

fn renderNewStylesPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "New Styles", .red) orelse return;
    const p = state.phase();

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

fn renderMeasurementPanel(state: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Measurement", .blue) orelse return;
    const p = state.phase();

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
