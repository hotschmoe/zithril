// Widgets module for zithril TUI framework
// Re-exports all built-in widgets

pub const block = @import("widgets/block.zig");
pub const Block = block.Block;
pub const BorderType = block.BorderType;
pub const BorderChars = block.BorderChars;

pub const text = @import("widgets/text.zig");
pub const Text = text.Text;
pub const Alignment = text.Alignment;

pub const list = @import("widgets/list.zig");
pub const List = list.List;

pub const gauge = @import("widgets/gauge.zig");
pub const Gauge = gauge.Gauge;

pub const paragraph = @import("widgets/paragraph.zig");
pub const Paragraph = paragraph.Paragraph;
pub const Wrap = paragraph.Wrap;

test "widgets module" {
    _ = block;
    _ = text;
    _ = list;
    _ = gauge;
    _ = paragraph;
}
