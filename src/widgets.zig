// Widgets module for zithril TUI framework
// Re-exports all built-in widgets

pub const block = @import("widgets/block.zig");
pub const Block = block.Block;
pub const BorderType = block.BorderType;
pub const BorderChars = block.BorderChars;
pub const Alignment = block.Alignment;

test "widgets module" {
    _ = block;
}
