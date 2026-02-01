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

    // Demonstrate zithril Style wrapper
    const style = zithril.Style.init().bold().fg(.green);
    const segments = [_]rich_zig.Segment{
        rich_zig.Segment.styled("Style wrapper works: ", rich_zig.Style.empty),
        rich_zig.Segment.styled("green bold", style.toRichStyle()),
    };
    try console.printSegments(&segments);
    try console.print("");

    // Demonstrate geometry types
    const rect = zithril.Rect.init(0, 0, 80, 24);
    const inner_rect = rect.inner(2);
    const rect_str = try std.fmt.allocPrint(
        allocator,
        "Rect: {d}x{d} at ({d},{d}), inner(2): {d}x{d} at ({d},{d})",
        .{ rect.width, rect.height, rect.x, rect.y, inner_rect.width, inner_rect.height, inner_rect.x, inner_rect.y },
    );
    defer allocator.free(rect_str);
    try console.print(rect_str);
    try console.print("");
}

test "main module imports" {
    _ = zithril.Style;
    _ = zithril.Rect;
    _ = zithril.Position;
    _ = rich_zig.Style;
}
