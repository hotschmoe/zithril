// Ralph - zithril reference application
// A demonstration of multiple widgets working together
const std = @import("std");
const zithril = @import("zithril");
const rich_zig = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich_zig.Console.init(allocator);
    defer console.deinit();

    const title_style = zithril.Style.init().bold().fg(.magenta);
    const subtitle_style = zithril.Style.init().italic().fg(.white);

    const segments = [_]rich_zig.Segment{
        rich_zig.Segment.styled("Ralph", title_style.toRichStyle()),
        rich_zig.Segment.plain(" - "),
        rich_zig.Segment.styled("zithril Reference Application", subtitle_style.toRichStyle()),
    };
    try console.printSegments(&segments);
    try console.print("(Full TUI reference implementation coming soon)");
}
