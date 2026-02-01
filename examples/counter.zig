// Minimal counter example - placeholder for full zithril implementation
const std = @import("std");
const zithril = @import("zithril");
const rich_zig = @import("rich_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var console = rich_zig.Console.init(allocator);
    defer console.deinit();

    const style = zithril.Style.empty.bold().fg(.green);
    const segments = [_]rich_zig.Segment{
        rich_zig.Segment.styled("Counter Example", style),
    };
    try console.printSegments(&segments);
    try console.print("(Full TUI implementation coming soon)");
}
