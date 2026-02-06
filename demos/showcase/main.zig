const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);
const ColorTriplet = zithril.ColorTriplet;

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

    // Row 1: Original panels
    renderThemePanel(state, frame, row1_cols.get(0));
    renderNewStylesPanel(state, frame, row1_cols.get(1));
    renderHighlighterPanel(state, frame, row1_cols.get(2));

    // Row 2: v1.4.0 feature panels
    renderAdaptivePanel(state, frame, row2_cols.get(0));
    renderGradientPanel(state, frame, row2_cols.get(1));
    renderWcagPanel(state, frame, row2_cols.get(2));

    // Row 3: More panels
    renderAnsiPanel(state, frame, row3_cols.get(0));
    renderPrettyPanel(state, frame, row3_cols.get(1));
    renderMeasurementPanel(state, frame, row3_cols.get(2));

    var status_buf: [80]u8 = undefined;
    const status = std.fmt.bufPrint(&status_buf, " q:quit | Phase: {d}/4 | Tick: {d} | Sync Output: active", .{ state.phase() + 1, state.tick_count }) catch " q:quit";
    frame.render(zithril.Text{
        .content = status,
        .style = zithril.Style.init().bg(.blue).fg(.white),
    }, rows.get(2));
}

// -- v1.4.0 Feature Panels --

fn renderAdaptivePanel(_: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Adaptive Colors", zithril.Color.fromRgb(255, 165, 0)) orelse return;

    const ac = zithril.AdaptiveColor.init(
        zithril.Color.fromRgb(255, 100, 50),
        zithril.Color.from256(208),
        zithril.Color.red,
    );

    frame.render(zithril.Text{
        .content = "AdaptiveColor: RGB(255,100,50)",
        .style = zithril.Style.init().bold(),
    }, lines.get(0));

    const tc = ac.resolve(.truecolor);
    frame.render(zithril.Text{
        .content = "  truecolor -> RGB direct",
        .style = zithril.Style.init().fg(tc),
    }, lines.get(1));

    const e8 = ac.resolve(.eight_bit);
    frame.render(zithril.Text{
        .content = "  256-color -> index 208",
        .style = zithril.Style.init().fg(e8),
    }, lines.get(2));

    const std16 = ac.resolve(.standard);
    frame.render(zithril.Text{
        .content = "  16-color  -> red",
        .style = zithril.Style.init().fg(std16),
    }, lines.get(3));

    frame.render(zithril.Text{
        .content = "Auto-degrades per terminal",
        .style = zithril.Style.init().dim(),
    }, lines.get(4));
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

fn renderGradientPanel(_: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "Color Gradients", zithril.Color.fromRgb(128, 0, 255)) orelse return;

    // RGB gradient: red -> blue
    const rgb_stops = [_]ColorTriplet{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
    };
    var rgb_out: [5]ColorTriplet = undefined;
    zithril.gradient(&rgb_stops, &rgb_out, false);

    // HSL gradient: red -> green (goes through yellow)
    const hsl_stops = [_]ColorTriplet{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
    };
    var hsl_out: [5]ColorTriplet = undefined;
    zithril.gradient(&hsl_stops, &hsl_out, true);

    frame.render(zithril.Text{
        .content = "RGB red->blue:",
        .style = zithril.Style.init().bold(),
    }, lines.get(0));

    // Show RGB gradient: each hex value colored with its own gradient color
    renderGradientSamples(frame, lines.get(1), &rgb_out);

    frame.render(zithril.Text{
        .content = "HSL red->green:",
        .style = zithril.Style.init().bold(),
    }, lines.get(2));

    renderGradientSamples(frame, lines.get(3), &hsl_out);

    frame.render(zithril.Text{
        .content = "HSL avoids muddy midpoints",
        .style = zithril.Style.init().dim(),
    }, lines.get(4));
}

fn wcagLevelStr(level: zithril.WcagLevel) []const u8 {
    return switch (level) {
        .fail => "FAIL",
        .aa_large => "AA-lg",
        .aa => "AA",
        .aaa => "AAA",
    };
}

fn renderWcagPanel(_: *const State, frame: *FrameType, area: zithril.Rect) void {
    const lines = panelLines(frame, area, "WCAG Contrast", zithril.Color.fromRgb(0, 200, 100)) orelse return;

    const black = ColorTriplet{ .r = 0, .g = 0, .b = 0 };
    const white = ColorTriplet{ .r = 255, .g = 255, .b = 255 };
    const gray = ColorTriplet{ .r = 150, .g = 150, .b = 150 };

    var buf0: [40]u8 = undefined;
    var buf1: [40]u8 = undefined;
    var buf2: [40]u8 = undefined;

    const bw_ratio = black.contrastRatio(white);
    const s0 = std.fmt.bufPrint(&buf0, "Blk/Wht: {d:.1}:1 AAA", .{bw_ratio}) catch "?";
    frame.render(zithril.Text{
        .content = "WCAG 2.1 Contrast Ratios:",
        .style = zithril.Style.init().bold(),
    }, lines.get(0));
    frame.render(zithril.Text{
        .content = s0,
        .style = zithril.Style.init().fg(.green),
    }, lines.get(1));

    const gw_ratio = gray.contrastRatio(white);
    const gw_level = gray.wcagLevel(white);
    const s1 = std.fmt.bufPrint(&buf1, "Gry/Wht: {d:.1}:1 {s}", .{ gw_ratio, wcagLevelStr(gw_level) }) catch "?";
    frame.render(zithril.Text{
        .content = s1,
        .style = zithril.Style.init().fg(if (gw_level == .fail) zithril.Color.red else zithril.Color.yellow),
    }, lines.get(2));

    const gb_ratio = gray.contrastRatio(black);
    const gb_level = gray.wcagLevel(black);
    const s2 = std.fmt.bufPrint(&buf2, "Gry/Blk: {d:.1}:1 {s}", .{ gb_ratio, wcagLevelStr(gb_level) }) catch "?";
    frame.render(zithril.Text{
        .content = s2,
        .style = zithril.Style.init().fg(.cyan),
    }, lines.get(3));

    frame.render(zithril.Text{
        .content = "4.5:1=AA, 7:1=AAA",
        .style = zithril.Style.init().dim(),
    }, lines.get(4));
}

// -- Original Panels --

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
