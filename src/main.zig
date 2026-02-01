const std = @import("std");
const zithril = @import("zithril");
const rich_zig = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich_zig.Console.init(allocator);
    defer console.deinit();

    try console.print("");
    try console.printRenderable(rich_zig.Rule.init().withTitle("zithril").withCharacters("="));
    try console.print("");

    try console.print("[bold cyan]zithril[/] - Zig TUI Framework");
    try console.print("Built on [bold]rich_zig[/] for terminal rendering");
    try console.print("");

    // Demonstrate zithril re-exports
    const style = zithril.Style.empty.bold().fg(.green);
    const segments = [_]rich_zig.Segment{
        rich_zig.Segment.styled("Style re-export works: ", rich_zig.Style.empty),
        rich_zig.Segment.styled("green bold", style),
    };
    try console.printSegments(&segments);
    try console.print("");
}

test "main module imports" {
    _ = zithril.Style;
    _ = rich_zig.Style;
}
