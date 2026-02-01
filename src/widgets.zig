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

pub const table = @import("widgets/table.zig");
pub const Table = table.Table;

pub const tabs = @import("widgets/tabs.zig");
pub const Tabs = tabs.Tabs;

pub const scrollbar = @import("widgets/scrollbar.zig");
pub const Scrollbar = scrollbar.Scrollbar;
pub const Orientation = scrollbar.Orientation;

pub const clear = @import("widgets/clear.zig");
pub const Clear = clear.Clear;

test "widgets module" {
    _ = block;
    _ = text;
    _ = list;
    _ = gauge;
    _ = paragraph;
    _ = table;
    _ = tabs;
    _ = scrollbar;
    _ = clear;
}
