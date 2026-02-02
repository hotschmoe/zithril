//! Custom widgets for the Rung game.

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
        if (self.pos + str.len < self.buf.len) {
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

// Colors for the game
const Colors = struct {
    const rail = Style.init().fg(.blue);
    const wire = Style.init().fg(.white);
    const contact_no = Style.init().fg(.green);
    const contact_nc = Style.init().fg(.yellow);
    const coil = Style.init().fg(.red);
    const cursor = Style.init().fg(.black).bg(.cyan);
    const powered = Style.init().fg(.green).bold();
    const pass = Style.init().fg(.green);
    const fail = Style.init().fg(.red);
    const header = Style.init().fg(.cyan).bold();
    const hint = Style.init().fg(Color.from256(245)); // gray
};

/// Header widget showing level info and mode
pub const HeaderWidget = struct {
    level: usize,
    title: []const u8,
    mode: Mode,

    pub fn render(self: HeaderWidget, area: Rect, buf: *Buffer) void {
        // Draw border
        const block = zithril.Block{
            .title = "RUNG",
            .border = .rounded,
            .border_style = Colors.header,
        };
        block.render(area, buf);

        const inner = block.inner(area);
        if (inner.height == 0) return;

        // Level info
        var level_buf: [64]u8 = undefined;
        const level_str = std.fmt.bufPrint(&level_buf, "Level {d}: {s}", .{
            self.level,
            self.title,
        }) catch "Level ?";
        buf.setString(inner.x, inner.y, level_str, Colors.header);

        // Mode indicator on the right
        const mode_str = switch (self.mode) {
            .editing => "[EDITING]",
            .simulating => "[TESTING]",
            .solved => "[SOLVED!]",
        };
        const mode_style = switch (self.mode) {
            .editing => Style.init().fg(.yellow),
            .simulating => Style.init().fg(.cyan),
            .solved => Style.init().fg(.green).bold(),
        };
        if (inner.width > mode_str.len) {
            buf.setString(
                inner.x + inner.width - @as(u16, @intCast(mode_str.len)),
                inner.y,
                mode_str,
                mode_style,
            );
        }
    }
};

/// Diagram editor widget
pub const DiagramWidget = struct {
    diagram: *const Diagram,
    cursor: Position,
    editing: bool,

    pub fn render(self: DiagramWidget, area: Rect, buf: *Buffer) void {
        // Draw border
        const block = zithril.Block{
            .title = "Ladder Diagram",
            .border = .rounded,
            .border_style = Style.init().fg(.white),
        };
        block.render(area, buf);

        const inner = block.inner(area);
        if (inner.height == 0 or inner.width == 0) return;

        // Each cell is 3 characters wide for visibility
        const cell_width: u16 = 3;

        for (0..self.diagram.height) |y| {
            if (y >= inner.height) break;

            for (0..self.diagram.width) |x| {
                const screen_x = inner.x + @as(u16, @intCast(x)) * cell_width;
                const screen_y = inner.y + @as(u16, @intCast(y));

                if (screen_x + cell_width > inner.x + inner.width) break;

                const cell = self.diagram.get(x, y);
                const is_cursor = self.editing and x == self.cursor.x and y == self.cursor.y;

                renderLadderCell(buf, screen_x, screen_y, cell, is_cursor);
            }
        }

        // Help text at bottom
        if (inner.height > self.diagram.height + 1) {
            const help_y = inner.y + @as(u16, @intCast(self.diagram.height)) + 1;
            buf.setString(inner.x, help_y, "Arrows:Move  Space:Place  Tab:Component  Enter:Test", Colors.hint);
        }
    }

    fn renderLadderCell(buf: *Buffer, x: u16, y: u16, cell: LadderCell, is_cursor: bool) void {
        const str: []const u8 = switch (cell) {
            .empty => "   ",
            .wire_h => "---",
            .wire_v => " | ",
            .junction => "-+-",
            .rail_left => "|  ",
            .rail_right => "  |",
            .contact_no => "[ ]",
            .contact_nc => "[/]",
            .coil => "( )",
            .coil_latch => "(L)",
            .coil_unlatch => "(U)",
        };

        const style: Style = if (is_cursor)
            Colors.cursor
        else switch (cell) {
            .rail_left, .rail_right => Colors.rail,
            .wire_h, .wire_v, .junction => Colors.wire,
            .contact_no => Colors.contact_no,
            .contact_nc => Colors.contact_nc,
            .coil, .coil_latch, .coil_unlatch => Colors.coil,
            .empty => Style.empty,
        };

        buf.setString(x, y, str, style);
    }
};

/// Truth table widget
pub const TruthTableWidget = struct {
    level: Level,
    results: []const bool,

    pub fn render(self: TruthTableWidget, area: Rect, buf: *Buffer) void {
        const block = zithril.Block{
            .title = "Truth Table",
            .border = .rounded,
            .border_style = Style.init().fg(.white),
        };
        block.render(area, buf);

        const inner = block.inner(area);
        if (inner.height == 0 or inner.width == 0) return;

        var y_offset: u16 = 0;

        // Header row
        var header_buf: [64]u8 = undefined;
        var writer = BufWriter.init(&header_buf);

        for (self.level.input_names) |name| {
            writer.write(name);
            writer.writeChar(' ');
        }
        writer.write("| ");
        for (self.level.output_names) |name| {
            writer.write(name);
            writer.writeChar(' ');
        }
        writer.write("| ?");

        buf.setString(inner.x, inner.y + y_offset, writer.slice(), Colors.header);
        y_offset += 1;

        // Separator line
        if (y_offset < inner.height) {
            var sep_buf: [64]u8 = undefined;
            @memset(&sep_buf, '-');
            const sep_len = @min(writer.pos, inner.width);
            buf.setString(inner.x, inner.y + y_offset, sep_buf[0..sep_len], Style.empty);
            y_offset += 1;
        }

        // Data rows
        for (self.level.truth_table, 0..) |row, i| {
            if (y_offset >= inner.height) break;

            var row_buf: [64]u8 = undefined;
            var row_writer = BufWriter.init(&row_buf);

            for (self.level.input_names, 0..) |_, j| {
                row_writer.writeChar(if (row.inputs[j]) '1' else '0');
                row_writer.writeChar(' ');
            }
            row_writer.write("| ");
            for (self.level.output_names, 0..) |_, j| {
                row_writer.writeChar(if (row.outputs[j]) '1' else '0');
                row_writer.writeChar(' ');
            }
            row_writer.write("| ");

            const result_char: u8 = if (i < self.results.len)
                (if (self.results[i]) 'P' else 'F')
            else
                '-';
            row_writer.writeChar(result_char);

            const row_style = if (i < self.results.len)
                (if (self.results[i]) Colors.pass else Colors.fail)
            else
                Style.empty;

            buf.setString(inner.x, inner.y + y_offset, row_writer.slice(), row_style);
            y_offset += 1;
        }
    }
};

/// Component palette widget (footer)
pub const PaletteWidget = struct {
    selected: ComponentType,

    pub fn render(self: PaletteWidget, area: Rect, buf: *Buffer) void {
        // Draw border
        const block = zithril.Block{
            .title = "Components",
            .border = .rounded,
            .border_style = Style.init().fg(.white),
        };
        block.render(area, buf);

        const inner = block.inner(area);
        if (inner.height == 0 or inner.width == 0) return;

        const components = [_]struct { t: ComponentType, label: []const u8 }{
            .{ .t = .wire_horizontal, .label = "---" },
            .{ .t = .wire_vertical, .label = " | " },
            .{ .t = .contact_no, .label = "[ ]" },
            .{ .t = .contact_nc, .label = "[/]" },
            .{ .t = .coil, .label = "( )" },
            .{ .t = .coil_latch, .label = "(L)" },
            .{ .t = .coil_unlatch, .label = "(U)" },
            .{ .t = .junction, .label = "-+-" },
            .{ .t = .empty, .label = "DEL" },
        };

        var x_offset: u16 = 0;
        for (components) |comp| {
            if (x_offset + 5 > inner.width) break;

            const style = if (comp.t == self.selected)
                Style.init().fg(.black).bg(.white).bold()
            else
                Style.init().fg(.white);

            buf.setString(inner.x + x_offset, inner.y, comp.label, style);
            x_offset += 4; // 3 chars + 1 space
        }

        // Controls hint
        if (inner.height > 1) {
            buf.setString(inner.x, inner.y + 1, "R:Reset  N:Next  Q:Quit", Colors.hint);
        }
    }
};

/// Status widget (unused for now, but available for expansion)
pub const StatusWidget = struct {
    message: []const u8 = "",

    pub fn render(self: StatusWidget, area: Rect, buf: *Buffer) void {
        if (self.message.len > 0) {
            buf.setString(area.x, area.y, self.message, Style.empty);
        }
    }
};
