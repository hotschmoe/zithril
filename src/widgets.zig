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

test "widgets module" {
    _ = block;
    _ = text;
    _ = list;
}
