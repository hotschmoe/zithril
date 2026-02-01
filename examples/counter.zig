// Minimal counter example for zithril TUI framework
//
// Demonstrates:
// - Single counter value state
// - Key handling (q=quit, up/down=increment/decrement)
// - Simple view with Block and counter display

const std = @import("std");
const zithril = @import("zithril");

// Application state: a single counter value
const State = struct {
    count: i32 = 0,
};

// Handle events and return actions
fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            switch (key.code) {
                .char => |c| {
                    if (c == 'q' and !key.modifiers.any()) return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;
                },
                .up => if (!key.modifiers.any()) { state.count +|= 1; },
                .down => if (!key.modifiers.any()) { state.count -|= 1; },
                else => {},
            }
        },
        else => {},
    }
    return .none;
}

// Render the UI
fn view(state: *State, frame: *zithril.Frame(zithril.App(State).DefaultMaxWidgets)) void {
    const area = frame.size();

    // Draw a block with title
    const block = zithril.Block{
        .title = "Counter (up/down, q/Ctrl-C to quit)",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(block, area);

    // Get interior area for content
    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    // Format the counter value
    var buf: [64]u8 = undefined;
    const count_str = std.fmt.bufPrint(&buf, "Count: {d}", .{state.count}) catch "???";

    // Draw counter text centered in the block
    const text = zithril.Text{
        .content = count_str,
        .style = zithril.Style.init().bold().fg(.green),
        .alignment = .center,
    };
    frame.render(text, inner);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = zithril.App(State).init(.{
        .state = .{},
        .update = update,
        .view = view,
    });

    try app.run(allocator);
}

// Use zithril's panic handler to ensure terminal cleanup on abnormal exit
pub const panic = zithril.terminal_panic;
