//! Custom widgets for the Rung game.
//! Uses box-drawing characters, gradients, and color-coded elements
//! to create a polished ladder logic editing experience.

const std = @import("std");
const zithril = @import("zithril");

const game = @import("game.zig");
const levels = @import("levels.zig");

const LadderCell = game.Cell;
const Diagram = game.Diagram;
const Position = game.Position;
const ComponentType = game.ComponentType;
const Mode = game.Mode;
const Level = levels.Level;

const Buffer = zithril.Buffer;
const Rect = zithril.Rect;
const Style = zithril.Style;
const Color = zithril.Color;

/// Simple buffer writer for building strings without allocation.
const BufWriter = struct {
    buf: []u8,
    pos: usize = 0,

    fn init(buf: []u8) BufWriter {
        return .{ .buf = buf };
    }

    fn write(self: *BufWriter, str: []const u8) void {
        if (self.pos + str.len <= self.buf.len) {
            @memcpy(self.buf[self.pos..][0..str.len], str);
            self.pos += str.len;
        }
    }

    fn writeChar(self: *BufWriter, c: u8) void {
        if (self.pos < self.buf.len) {
            self.buf[self.pos] = c;
            self.pos += 1;
        }
    }

    fn slice(self: *const BufWriter) []const u8 {
        return self.buf[0..self.pos];
    }
};

// -- Color Theme --
// A cohesive palette using 256-color for broad terminal support.
const C = struct {
    const rail = Style.init().fg(Color.from256(33)).bold();
    const wire = Style.init().fg(Color.from256(252));
    const junction = Style.init().fg(Color.from256(214)).bold();

    const contact_no = Style.init().fg(Color.from256(82));
    const contact_nc = Style.init().fg(Color.from256(220)).bold();
    const coil = Style.init().fg(Color.from256(196));
    const coil_latch = Style.init().fg(Color.from256(135));
    const coil_unlatch = Style.init().fg(Color.from256(44));

    const cursor = Style.init().fg(Color.from256(0)).bg(Color.from256(51)).bold();

    const pass = Style.init().fg(Color.from256(46)).bold();
    const fail = Style.init().fg(Color.from256(196)).bold();
    const untested = Style.init().fg(Color.from256(240));

    const header = Style.init().fg(Color.from256(51)).bold();
    const header_accent = Style.init().fg(Color.from256(214)).bold();
    const title = Style.init().fg(Color.from256(255)).bold();
    const hint = Style.init().fg(Color.from256(245));
    const dim = Style.init().fg(Color.from256(238));
    const highlight = Style.init().fg(Color.from256(226)).bold();
    const story = Style.init().fg(Color.from256(183));

    const overlay_bg = Style.init().bg(Color.from256(235));
    const overlay_border = Style.init().fg(Color.from256(51)).bold();

    const diff_beginner = Style.init().fg(Color.from256(82));
    const diff_intermediate = Style.init().fg(Color.from256(220));
    const diff_advanced = Style.init().fg(Color.from256(208));
    const diff_expert = Style.init().fg(Color.from256(196));

    const toast_bg = Style.init().fg(Color.from256(255)).bg(Color.from256(24));
};

/// Draw a centered overlay box. Returns the inner rect, or null if area is too small.
fn drawOverlayBox(buf: *Buffer, area: Rect, box_width: u16, box_height: u16, title_text: []const u8) ?Rect {
    if (area.width < box_width or area.height < box_height) return null;

    const box_x = area.x + (area.width - box_width) / 2;
    const box_y = area.y + (area.height - box_height) / 2;
    const box = Rect{ .x = box_x, .y = box_y, .width = box_width, .height = box_height };

    // Fill background
    for (0..box_height) |dy| {
        for (0..box_width) |dx| {
            buf.setString(
                box_x + @as(u16, @intCast(dx)),
                box_y + @as(u16, @intCast(dy)),
                " ",
                C.overlay_bg,
            );
        }
    }

    // Draw border with title
    const block = zithril.Block{
        .title = title_text,
        .border = .rounded,
        .border_style = C.overlay_border,
    };
    block.render(box, buf);

    return block.inner(box);
}

/// Header widget showing level info, mode, and description
pub const HeaderWidget = struct {
    level: usize,
    title: []const u8,
    mode: Mode,

    pub fn render(self: HeaderWidget, area: Rect, buf: *Buffer) void {
        const block = zithril.Block{
            .title = "RUNG",
            .border = .rounded,
            .border_style = C.header,
        };
        block.render(area, buf);

        const inner = block.inner(area);
        if (inner.height == 0 or inner.width < 20) return;

        // Level info with difficulty indicator
        var level_buf: [80]u8 = undefined;
        const level_str = std.fmt.bufPrint(&level_buf, "Level {d}/{d}: {s}", .{
            self.level,
            levels.count(),
            self.title,
        }) catch "Level ?";
        buf.setString(inner.x + 1, inner.y, level_str, C.title);

        // Mode indicator on the right
        const mode_str: []const u8 = switch (self.mode) {
            .editing => "[EDITING]",
            .simulating => "[TESTING]",
            .solved => "[SOLVED!]",
        };
        const mode_style = switch (self.mode) {
            .editing => Style.init().fg(Color.from256(220)).bold(),
            .simulating => Style.init().fg(Color.from256(51)).bold(),
            .solved => C.pass,
        };
        if (inner.width > mode_str.len + 2) {
            buf.setString(
                inner.x + inner.width - @as(u16, @intCast(mode_str.len)) - 1,
                inner.y,
                mode_str,
                mode_style,
            );
        }
    }
};

/// Diagram editor widget with box-drawing characters and power visualization
pub const DiagramWidget = struct {
    diagram: *const Diagram,
    cursor: Position,
    editing: bool,
    input_names: []const []const u8,
    output_names: []const []const u8,

    pub fn render(self: DiagramWidget, area: Rect, buf: *Buffer) void {
        const block = zithril.Block{
            .title = "Ladder Diagram",
            .border = .rounded,
            .border_style = Style.init().fg(Color.from256(252)),
        };
        block.render(area, buf);

        const inner = block.inner(area);
        if (inner.height == 0 or inner.width == 0) return;

        const cell_width: u16 = 5;

        // Draw each cell
        for (0..self.diagram.height) |y| {
            if (y >= inner.height) break;

            for (0..self.diagram.width) |x| {
                const screen_x = inner.x + @as(u16, @intCast(x)) * cell_width;
                const screen_y = inner.y + @as(u16, @intCast(y));

                if (screen_x + cell_width > inner.x + inner.width) break;

                const cell = self.diagram.get(x, y);
                const is_cursor = self.editing and x == self.cursor.x and y == self.cursor.y;

                self.renderLadderCell(buf, screen_x, screen_y, cell, is_cursor, cell_width);
            }
        }

        // Description area below diagram
        const desc_y = inner.y + @as(u16, @intCast(self.diagram.height)) + 1;
        if (desc_y < inner.y + inner.height) {
            buf.setString(inner.x + 1, desc_y, "Arrows:Move  Space:Place  Tab:Cycle  Enter:Sim", C.hint);
        }
        if (desc_y + 1 < inner.y + inner.height) {
            buf.setString(inner.x + 1, desc_y + 1, "?:Help  L:Levels  D:Description  Ctrl+Z:Undo", C.dim);
        }
    }

    fn renderLadderCell(self: DiagramWidget, buf: *Buffer, x: u16, y: u16, cell: LadderCell, is_cursor: bool, width: u16) void {
        // Build the cell visual representation
        var str_buf: [5]u8 = undefined;
        const display: struct { str: []const u8, style: Style } = switch (cell) {
            .empty => .{
                .str = fillBuf(&str_buf, '.', width),
                .style = C.dim,
            },
            .wire_h => .{
                .str = fillBuf(&str_buf, '-', width),
                .style = C.wire,
            },
            .wire_v => blk: {
                const mid = width / 2;
                @memset(&str_buf, ' ');
                if (mid < str_buf.len) str_buf[mid] = '|';
                break :blk .{ .str = str_buf[0..width], .style = C.wire };
            },
            .junction => blk: {
                @memset(&str_buf, '-');
                const mid = width / 2;
                if (mid < str_buf.len) str_buf[mid] = '+';
                break :blk .{ .str = str_buf[0..width], .style = C.junction };
            },
            .rail_left => blk: {
                @memset(str_buf[0..width], ' ');
                str_buf[width - 1] = '|';
                if (width > 1) str_buf[width - 2] = '|';
                break :blk .{ .str = str_buf[0..width], .style = C.rail };
            },
            .rail_right => blk: {
                @memset(str_buf[0..width], ' ');
                str_buf[0] = '|';
                if (width > 1) str_buf[1] = '|';
                break :blk .{ .str = str_buf[0..width], .style = C.rail };
            },
            .contact_no => |idx| blk: {
                str_buf = .{ '-', '[', self.getInputLabel(idx), ']', '-' };
                break :blk .{ .str = str_buf[0..width], .style = C.contact_no };
            },
            .contact_nc => blk: {
                str_buf = .{ '-', '[', '/', ']', '-' };
                break :blk .{ .str = str_buf[0..width], .style = C.contact_nc };
            },
            .coil, .coil_latch, .coil_unlatch => blk: {
                const idx = switch (cell) {
                    .coil => |i| i,
                    .coil_latch => |i| i,
                    .coil_unlatch => |i| i,
                    else => unreachable,
                };
                const style = switch (cell) {
                    .coil => C.coil,
                    .coil_latch => C.coil_latch,
                    .coil_unlatch => C.coil_unlatch,
                    else => unreachable,
                };
                str_buf = .{ '-', '(', self.getOutputLabel(idx), ')', '-' };
                break :blk .{ .str = str_buf[0..width], .style = style };
            },
        };

        const final_style = if (is_cursor) C.cursor else display.style;
        buf.setString(x, y, display.str, final_style);
    }

    fn fillBuf(buf: *[5]u8, char: u8, width: u16) []const u8 {
        const w = @min(width, 5);
        @memset(buf[0..w], char);
        return buf[0..w];
    }

    fn getInputLabel(self: DiagramWidget, idx: u8) u8 {
        if (idx < self.input_names.len and self.input_names[idx].len > 0) {
            return self.input_names[idx][0];
        }
        return if (idx < 26) 'A' + idx else '?';
    }

    fn getOutputLabel(self: DiagramWidget, idx: u8) u8 {
        if (idx < self.output_names.len and self.output_names[idx].len > 0) {
            return self.output_names[idx][0];
        }
        return if (idx < 2) 'Y' + idx else '?';
    }
};

/// Truth table widget with color-coded results
pub const TruthTableWidget = struct {
    level: Level,
    results: []const bool,

    pub fn render(self: TruthTableWidget, area: Rect, buf: *Buffer) void {
        const block = zithril.Block{
            .title = "Truth Table",
            .border = .rounded,
            .border_style = Style.init().fg(Color.from256(252)),
        };
        block.render(area, buf);

        const inner = block.inner(area);
        if (inner.height == 0 or inner.width == 0) return;

        var y_offset: u16 = 0;

        // Column header
        var header_buf: [80]u8 = undefined;
        var writer = BufWriter.init(&header_buf);

        writer.write("  ");
        for (self.level.input_names) |name| {
            writer.write(name);
            writer.writeChar(' ');
        }
        writer.write("| ");
        for (self.level.output_names) |name| {
            writer.write(name);
            writer.writeChar(' ');
        }
        writer.write("| OK");

        buf.setString(inner.x, inner.y + y_offset, writer.slice(), C.header);
        y_offset += 1;

        // Separator
        if (y_offset < inner.height) {
            var sep_buf: [80]u8 = undefined;
            @memset(&sep_buf, '-');
            const sep_w: u16 = @intCast(@min(writer.pos, inner.width));
            const sep = sep_buf[0..sep_w];
            // Put a nice separator char at the pipe positions
            buf.setString(inner.x, inner.y + y_offset, sep, C.dim);
            y_offset += 1;
        }

        // Data rows
        for (self.level.truth_table, 0..) |row, i| {
            if (y_offset >= inner.height) break;

            var row_buf: [80]u8 = undefined;
            var row_writer = BufWriter.init(&row_buf);

            // Row number
            var num_buf: [4]u8 = undefined;
            const num_str = std.fmt.bufPrint(&num_buf, "{d} ", .{i + 1}) catch "? ";
            row_writer.write(num_str);

            // Inputs
            for (self.level.input_names, 0..) |_, j| {
                row_writer.writeChar(if (row.inputs[j]) '1' else '0');
                row_writer.writeChar(' ');
            }
            row_writer.write("| ");

            // Outputs
            for (self.level.output_names, 0..) |_, j| {
                row_writer.writeChar(if (row.outputs[j]) '1' else '0');
                row_writer.writeChar(' ');
            }
            row_writer.write("| ");

            // Result indicator
            const tested = i < self.results.len;
            if (tested) {
                if (self.results[i]) {
                    row_writer.writeChar('P');
                } else {
                    row_writer.writeChar('F');
                }
            } else {
                row_writer.writeChar('-');
            }

            const row_style = if (tested)
                (if (self.results[i]) C.pass else C.fail)
            else
                C.untested;

            buf.setString(inner.x, inner.y + y_offset, row_writer.slice(), row_style);
            y_offset += 1;
        }

        // Summary
        if (y_offset + 1 < inner.height) {
            y_offset += 1; // blank line

            var pass_count: usize = 0;
            var tested_count: usize = 0;
            for (self.results) |r| {
                tested_count += 1;
                if (r) pass_count += 1;
            }

            if (tested_count > 0) {
                var sum_buf: [32]u8 = undefined;
                const sum_str = std.fmt.bufPrint(&sum_buf, "{d}/{d} passing", .{
                    pass_count,
                    self.level.truth_table.len,
                }) catch "";

                const sum_style = if (pass_count == self.level.truth_table.len) C.pass else C.fail;
                buf.setString(inner.x + 1, inner.y + y_offset, sum_str, sum_style);
            }
        }

        // Story text at bottom
        if (y_offset + 2 < inner.height) {
            y_offset += 2;
            // Wrap story text to fit
            const story = self.level.story_text;
            const max_w = inner.width -| 2;
            if (story.len > 0 and max_w > 10) {
                const line1_len = @min(story.len, max_w);
                buf.setString(inner.x + 1, inner.y + y_offset, story[0..line1_len], C.story);
                if (story.len > max_w and y_offset + 1 < inner.height) {
                    const line2_len = @min(story.len - max_w, max_w);
                    buf.setString(inner.x + 1, inner.y + y_offset + 1, story[max_w..][0..line2_len], C.story);
                }
            }
        }
    }
};

/// Component palette widget (footer) with clickable items
pub const PaletteWidget = struct {
    selected: ComponentType,
    selected_index: u8,
    input_names: []const []const u8,
    output_names: []const []const u8,

    pub fn render(self: PaletteWidget, area: Rect, buf: *Buffer) void {
        const block = zithril.Block{
            .title = "Palette",
            .border = .rounded,
            .border_style = Style.init().fg(Color.from256(252)),
        };
        block.render(area, buf);

        const inner = block.inner(area);
        if (inner.height == 0 or inner.width == 0) return;

        const components = [_]struct { t: ComponentType, label: []const u8, sym: []const u8 }{
            .{ .t = .wire_horizontal, .label = "---", .sym = "Wire" },
            .{ .t = .wire_vertical, .label = " | ", .sym = "VWire" },
            .{ .t = .contact_no, .label = "[ ]", .sym = "NO" },
            .{ .t = .contact_nc, .label = "[/]", .sym = "NC" },
            .{ .t = .coil, .label = "( )", .sym = "Coil" },
            .{ .t = .coil_latch, .label = "(L)", .sym = "Latch" },
            .{ .t = .coil_unlatch, .label = "(U)", .sym = "Unlatch" },
            .{ .t = .junction, .label = "-+-", .sym = "Junc" },
            .{ .t = .empty, .label = " x ", .sym = "Del" },
        };

        var x_offset: u16 = 0;
        for (components) |comp| {
            if (x_offset + 5 > inner.width) break;

            const is_selected = comp.t == self.selected;
            const style = if (is_selected)
                Style.init().fg(Color.from256(0)).bg(Color.from256(51)).bold()
            else
                Style.init().fg(Color.from256(252));

            buf.setString(inner.x + x_offset, inner.y, comp.label, style);
            x_offset += 4;
        }

        // Show selected component info and index
        if (x_offset + 16 <= inner.width) {
            const label = self.getCurrentLabel();
            var idx_buf: [20]u8 = undefined;
            const idx_str = std.fmt.bufPrint(&idx_buf, " Idx:{d}={c}", .{
                self.selected_index,
                label,
            }) catch " Idx:?";
            buf.setString(inner.x + x_offset, inner.y, idx_str, C.highlight);
        }

        // Controls hint on second line
        if (inner.height > 1) {
            const controls = "R:Reset  N/P:Nav  Q:Quit  Enter:Sim  Scroll:Cycle  Click:Place";
            buf.setString(inner.x, inner.y + 1, controls, C.hint);
        }
    }

    fn getCurrentLabel(self: PaletteWidget) u8 {
        const is_coil = self.selected == .coil or
            self.selected == .coil_latch or
            self.selected == .coil_unlatch;

        if (is_coil) {
            if (self.selected_index < self.output_names.len and self.output_names[self.selected_index].len > 0) {
                return self.output_names[self.selected_index][0];
            }
            return if (self.selected_index < 2) 'Y' + self.selected_index else '?';
        } else {
            if (self.selected_index < self.input_names.len and self.input_names[self.selected_index].len > 0) {
                return self.input_names[self.selected_index][0];
            }
            return if (self.selected_index < 26) 'A' + self.selected_index else '?';
        }
    }
};

/// Victory overlay with celebration styling
pub const VictoryOverlay = struct {
    level: usize,
    has_next: bool,

    pub fn render(self: VictoryOverlay, area: Rect, buf: *Buffer) void {
        const inner = drawOverlayBox(buf, area, 40, 11, "SOLVED!") orelse return;

        // Decorative top border
        const deco = "* * * * * * * * * * * * * * * * * * *";
        const deco_len: u16 = @intCast(@min(deco.len, inner.width));
        const deco_x = inner.x + (inner.width -| deco_len) / 2;
        buf.setString(deco_x, inner.y, deco[0..deco_len], C.highlight);

        // Victory message
        var msg_buf: [40]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Level {d} Complete!", .{self.level}) catch "Complete!";
        const msg_x = inner.x + (inner.width -| @as(u16, @intCast(msg.len))) / 2;
        buf.setString(msg_x, inner.y + 2, msg, C.pass);

        // Stars
        const stars = "* * * * *";
        const stars_x = inner.x + (inner.width -| @as(u16, @intCast(stars.len))) / 2;
        buf.setString(stars_x, inner.y + 4, stars, C.header_accent);

        // Next level prompt
        const hint = if (self.has_next) "Press N for next level" else "All levels complete!";
        const hint_x = inner.x + (inner.width -| @as(u16, @intCast(hint.len))) / 2;
        buf.setString(hint_x, inner.y + 6, hint, C.hint);

        // Decorative bottom border
        if (inner.height > 8) {
            buf.setString(deco_x, inner.y + 8, deco[0..deco_len], C.highlight);
        }
    }
};

/// Help overlay showing all controls (keyboard + mouse)
pub const HelpOverlay = struct {
    pub fn render(_: HelpOverlay, area: Rect, buf: *Buffer) void {
        const inner = drawOverlayBox(buf, area, 52, 20, "Help") orelse return;

        const Pair = struct { key: []const u8, desc: []const u8 };

        const keys = [_]Pair{
            .{ .key = "KEYBOARD", .desc = "" },
            .{ .key = "--------", .desc = "--------------------" },
            .{ .key = "Arrows", .desc = "Move cursor" },
            .{ .key = "Space", .desc = "Place component at cursor" },
            .{ .key = "Tab", .desc = "Cycle component type" },
            .{ .key = "0-9", .desc = "Set input/output index" },
            .{ .key = "Enter", .desc = "Run simulation" },
            .{ .key = "Ctrl+Z/Y", .desc = "Undo / Redo" },
            .{ .key = "R", .desc = "Reset level" },
            .{ .key = "N / P", .desc = "Next / Previous level" },
            .{ .key = "L", .desc = "Level select" },
            .{ .key = "D", .desc = "Toggle description" },
            .{ .key = "Q", .desc = "Quit" },
            .{ .key = "", .desc = "" },
            .{ .key = "MOUSE", .desc = "" },
            .{ .key = "-----", .desc = "--------------------" },
            .{ .key = "Click", .desc = "Place / select" },
            .{ .key = "Scroll", .desc = "Cycle components" },
        };

        for (keys, 0..) |pair, y| {
            if (y >= inner.height) break;
            const row_y = inner.y + @as(u16, @intCast(y));

            if (pair.key.len == 0) continue;

            const is_header = pair.desc.len == 0;
            const key_style = if (is_header) C.header else C.highlight;
            const desc_style = if (is_header) C.header else C.hint;

            buf.setString(inner.x + 1, row_y, pair.key, key_style);
            if (pair.desc.len > 0) {
                buf.setString(inner.x + 14, row_y, pair.desc, desc_style);
            }
        }
    }
};

/// Level selection overlay
pub const LevelSelectOverlay = struct {
    current_level: usize,
    total_levels: usize,

    pub fn render(self: LevelSelectOverlay, area: Rect, buf: *Buffer) void {
        const box_height: u16 = @as(u16, @intCast(self.total_levels)) + 6;
        const inner = drawOverlayBox(buf, area, 48, box_height, "Select Level") orelse return;

        for (0..self.total_levels) |i| {
            if (i >= inner.height) break;

            const level = levels.get(i);
            const is_current = i == self.current_level;

            var line_buf: [44]u8 = undefined;
            const key: u8 = if (i < 9) '1' + @as(u8, @intCast(i)) else '0';
            const line = std.fmt.bufPrint(&line_buf, " {c}. {s}", .{ key, level.name }) catch "?";

            const diff_style = switch (level.difficulty) {
                .beginner => C.diff_beginner,
                .intermediate => C.diff_intermediate,
                .advanced => C.diff_advanced,
                .expert => C.diff_expert,
            };

            const name_style = if (is_current) C.highlight else Style.init().fg(Color.from256(252));
            buf.setString(inner.x, inner.y + @as(u16, @intCast(i)), line, name_style);

            // Difficulty tag on the right
            const diff_str = switch (level.difficulty) {
                .beginner => " [B]",
                .intermediate => " [I]",
                .advanced => " [A]",
                .expert => " [E]",
            };
            const tag_x = inner.x + inner.width -| 5;
            buf.setString(tag_x, inner.y + @as(u16, @intCast(i)), diff_str, diff_style);
        }

        // Footer
        const hint_str = "Press 1-9/0 to select, Esc to close";
        const hint_y = inner.y + inner.height - 1;
        buf.setString(inner.x + 1, hint_y, hint_str, C.hint);
    }
};

/// Description panel overlay showing level story and hint
pub const DescriptionOverlay = struct {
    level: Level,

    pub fn render(self: DescriptionOverlay, area: Rect, buf: *Buffer) void {
        const inner = drawOverlayBox(buf, area, 50, 12, "Level Info") orelse return;

        var y: u16 = 0;

        // Description
        buf.setString(inner.x + 1, inner.y + y, "Objective:", C.header);
        y += 1;
        if (y < inner.height) {
            const desc_w: usize = @min(self.level.description.len, inner.width -| 3);
            buf.setString(inner.x + 2, inner.y + y, self.level.description[0..desc_w], C.title);
            y += 1;
        }

        y += 1; // blank line

        // Hint
        if (y < inner.height) {
            buf.setString(inner.x + 1, inner.y + y, "Hint:", C.header_accent);
            y += 1;
        }
        if (y < inner.height) {
            const hint_w: usize = @min(self.level.hint.len, inner.width -| 3);
            buf.setString(inner.x + 2, inner.y + y, self.level.hint[0..hint_w], C.highlight);
            y += 1;
        }

        y += 1;

        // Story
        if (y < inner.height) {
            buf.setString(inner.x + 1, inner.y + y, "Scenario:", C.header);
            y += 1;
        }
        if (y < inner.height) {
            const story_w: usize = @min(self.level.story_text.len, inner.width -| 3);
            buf.setString(inner.x + 2, inner.y + y, self.level.story_text[0..story_w], C.story);
        }

        // Close hint at bottom
        const close_str = "Press D or Esc to close";
        const close_y = inner.y + inner.height - 1;
        buf.setString(inner.x + 1, close_y, close_str, C.dim);
    }
};

/// Toast message widget (rendered at bottom center)
pub const ToastWidget = struct {
    message: []const u8,
    timer: u32,
    max_timer: u32,

    pub fn render(self: ToastWidget, area: Rect, buf: *Buffer) void {
        if (self.message.len == 0) return;

        const msg_len: u16 = @intCast(@min(self.message.len, area.width -| 4));
        const box_w = msg_len + 4;
        const box_x = area.x + (area.width -| box_w) / 2;
        const box_y = if (area.height > 2) area.y + area.height - 2 else area.y;

        const style = C.toast_bg;

        // Draw background
        for (0..box_w) |dx| {
            buf.setString(box_x + @as(u16, @intCast(dx)), box_y, " ", style);
        }

        // Draw message centered
        const msg_x = box_x + 2;
        buf.setString(msg_x, box_y, self.message[0..msg_len], style);
    }
};
