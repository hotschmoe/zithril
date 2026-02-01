// List example for zithril TUI framework
//
// Demonstrates:
// - Navigable list with items and selected index state
// - Key handling (q=quit, j/down=next, k/up=previous)
// - Selection highlight with visual feedback

const std = @import("std");
const zithril = @import("zithril");

// Application state: list items and selection index
const State = struct {
    items: []const []const u8,
    selected: usize = 0,

    fn selectNext(self: *State) void {
        if (self.items.len == 0) return;
        if (self.selected < self.items.len - 1) {
            self.selected += 1;
        }
    }

    fn selectPrev(self: *State) void {
        if (self.selected > 0) {
            self.selected -= 1;
        }
    }

    fn selectFirst(self: *State) void {
        self.selected = 0;
    }

    fn selectLast(self: *State) void {
        if (self.items.len > 0) {
            self.selected = self.items.len - 1;
        }
    }
};

// Handle events and return actions
fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            if (!key.modifiers.any()) {
                switch (key.code) {
                    .char => |c| switch (c) {
                        'q' => return .quit,
                        'j' => state.selectNext(),
                        'k' => state.selectPrev(),
                        'g' => state.selectFirst(),
                        'G' => state.selectLast(),
                        else => {},
                    },
                    .up => state.selectPrev(),
                    .down => state.selectNext(),
                    .home => state.selectFirst(),
                    .end => state.selectLast(),
                    else => {},
                }
            }
        },
        else => {},
    }
    return .none;
}

// Render the UI
fn view(state: *State, frame: *zithril.Frame(zithril.App(State).DefaultMaxWidgets)) void {
    const area = frame.size();

    // Outer block with title
    const block = zithril.Block{
        .title = "List Navigation (j/k or arrows, q to quit)",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(block, area);

    // Get interior area for the list
    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    // Render the list widget
    const list = zithril.List{
        .items = state.items,
        .selected = state.selected,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white).bold(),
        .highlight_symbol = "> ",
    };
    frame.render(list, inner);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Sample items for the list
    const items = [_][]const u8{
        "Apple",
        "Banana",
        "Cherry",
        "Date",
        "Elderberry",
        "Fig",
        "Grape",
        "Honeydew",
        "Jackfruit",
        "Kiwi",
    };

    var app = zithril.App(State).init(.{
        .state = .{ .items = &items, .selected = 0 },
        .update = update,
        .view = view,
    });

    try app.run(allocator);
}

// Use zithril's panic handler to ensure terminal cleanup on abnormal exit
pub const panic = zithril.terminal_panic;
