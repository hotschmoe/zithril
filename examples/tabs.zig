// Tabs example for zithril TUI framework
//
// Demonstrates:
// - Tab navigation with active index state
// - Key handling (1-4=direct select, left/right/h/l=navigate, q=quit)
// - Different content rendered per tab
// - Tabs widget integration with Block

const std = @import("std");
const zithril = @import("zithril");

// Tab identifiers
const Tab = enum(usize) {
    overview = 0,
    details = 1,
    settings = 2,
    help = 3,
};

// Application state: current tab selection
const State = struct {
    current_tab: Tab = .overview,
    item_count: u32 = 42,
    enabled: bool = true,

    fn nextTab(self: *State) void {
        const idx = @intFromEnum(self.current_tab);
        if (idx < 3) {
            self.current_tab = @enumFromInt(idx + 1);
        }
    }

    fn prevTab(self: *State) void {
        const idx = @intFromEnum(self.current_tab);
        if (idx > 0) {
            self.current_tab = @enumFromInt(idx - 1);
        }
    }

    fn selectTab(self: *State, tab: Tab) void {
        self.current_tab = tab;
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
                        'h', 'H' => state.prevTab(),
                        'l', 'L' => state.nextTab(),
                        '1' => state.selectTab(.overview),
                        '2' => state.selectTab(.details),
                        '3' => state.selectTab(.settings),
                        '4' => state.selectTab(.help),
                        else => {},
                    },
                    .left => state.prevTab(),
                    .right => state.nextTab(),
                    .tab => state.nextTab(),
                    .backtab => state.prevTab(),
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

    // Main outer block
    const block = zithril.Block{
        .title = "Tabs Example (1-4 or arrows, q to quit)",
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(block, area);

    const inner = block.inner(area);
    if (inner.isEmpty()) return;

    // Split: tabs header (1 row) and content (rest)
    const chunks = zithril.layout(inner, .vertical, &.{
        zithril.Constraint.len(1),
        zithril.Constraint.flexible(1),
    });

    // Render tabs header
    const tab_titles = [_][]const u8{ "Overview", "Details", "Settings", "Help" };
    const tabs = zithril.Tabs{
        .titles = &tab_titles,
        .selected = @intFromEnum(state.current_tab),
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bold().fg(.yellow).bg(.blue),
        .divider = " | ",
    };
    frame.render(tabs, chunks.get(0));

    // Render content based on selected tab
    const content_area = chunks.get(1);
    if (content_area.isEmpty()) return;

    switch (state.current_tab) {
        .overview => renderOverview(frame, content_area, state),
        .details => renderDetails(frame, content_area, state),
        .settings => renderSettings(frame, content_area, state),
        .help => renderHelp(frame, content_area),
    }
}

fn renderOverview(frame: *zithril.Frame(zithril.App(State).DefaultMaxWidgets), area: zithril.Rect, state: *State) void {
    const content_block = zithril.Block{
        .title = "Overview",
        .border = .plain,
        .border_style = zithril.Style.init().fg(.green),
    };
    frame.render(content_block, area);

    const content_inner = content_block.inner(area);
    if (content_inner.isEmpty()) return;

    var buf: [128]u8 = undefined;
    const overview_text = std.fmt.bufPrint(&buf, "Welcome to the zithril tabs demo!\n\nCurrent items: {d}\nStatus: {s}", .{
        state.item_count,
        if (state.enabled) "Active" else "Inactive",
    }) catch "Overview content";

    const para = zithril.Paragraph{
        .text = overview_text,
        .style = zithril.Style.init().fg(.white),
        .wrap = .word,
    };
    frame.render(para, content_inner);
}

fn renderDetails(frame: *zithril.Frame(zithril.App(State).DefaultMaxWidgets), area: zithril.Rect, state: *State) void {
    const content_block = zithril.Block{
        .title = "Details",
        .border = .plain,
        .border_style = zithril.Style.init().fg(.yellow),
    };
    frame.render(content_block, area);

    const content_inner = content_block.inner(area);
    if (content_inner.isEmpty()) return;

    var buf: [256]u8 = undefined;
    const details_text = std.fmt.bufPrint(&buf,
        \\Item Details
        \\------------
        \\Count:    {d}
        \\Enabled:  {s}
        \\Type:     Standard
        \\Priority: Normal
    , .{
        state.item_count,
        if (state.enabled) "Yes" else "No",
    }) catch "Details content";

    const para = zithril.Paragraph{
        .text = details_text,
        .style = zithril.Style.init().fg(.white),
        .wrap = .none,
    };
    frame.render(para, content_inner);
}

fn renderSettings(frame: *zithril.Frame(zithril.App(State).DefaultMaxWidgets), area: zithril.Rect, state: *State) void {
    _ = state;
    const content_block = zithril.Block{
        .title = "Settings",
        .border = .plain,
        .border_style = zithril.Style.init().fg(.magenta),
    };
    frame.render(content_block, area);

    const content_inner = content_block.inner(area);
    if (content_inner.isEmpty()) return;

    const items = [_][]const u8{
        "[ ] Enable notifications",
        "[x] Show status bar",
        "[ ] Auto-refresh",
        "[x] Dark mode",
        "[ ] Compact view",
    };

    const list = zithril.List{
        .items = &items,
        .selected = null,
        .style = zithril.Style.init().fg(.white),
    };
    frame.render(list, content_inner);
}

fn renderHelp(frame: *zithril.Frame(zithril.App(State).DefaultMaxWidgets), area: zithril.Rect) void {
    const content_block = zithril.Block{
        .title = "Help",
        .border = .plain,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    frame.render(content_block, area);

    const content_inner = content_block.inner(area);
    if (content_inner.isEmpty()) return;

    const help_text =
        \\Keyboard Shortcuts
        \\------------------
        \\1-4       Select tab directly
        \\Left/h    Previous tab
        \\Right/l   Next tab
        \\Tab       Next tab
        \\Shift+Tab Previous tab
        \\q         Quit
    ;

    const para = zithril.Paragraph{
        .text = help_text,
        .style = zithril.Style.init().fg(.white),
        .wrap = .none,
    };
    frame.render(para, content_inner);
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
