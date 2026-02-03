# zithril

*Light as a feather, hard as dragon scales.*

A Zig TUI framework for building terminal user interfaces. Immediate mode rendering, zero hidden state, built on [rich_zig](https://github.com/hotschmoe/rich_zig).

```
┌─────────────────────────────────────────────────────────────────────┐
│  🤖 Ralph Orchestrator                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ▶ claude-1    laminae      ████████████░░░░░░░░  65%  page tables │
│  ▶ codex-1     rich_zig     ██████░░░░░░░░░░░░░░  30%  port tables │
│  ⏸ gemini-1    tmux_zig     ░░░░░░░░░░░░░░░░░░░░   0%  idle       │
│  ✓ claude-2    beads_zig    ████████████████████ 100%  done       │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│  q: quit │ j/k: navigate │ enter: details │ r: restart             │
└─────────────────────────────────────────────────────────────────────┘
```

## Philosophy

**Explicit over implicit.** You own all state. The framework never allocates behind your back.

**Immediate mode.** Describe your entire UI every frame. No widget tree, no retained state, no lifecycle hooks to remember. Just functions that take state and return visuals.

**Composition over inheritance.** Widgets are structs with a `render` function. Combine them however you want.

**Built for Zig.** Comptime layouts, error unions, no hidden control flow. If you know Zig, you know zithril.

## Quick Start

```zig
const std = @import("std");
const zithril = @import("zithril");

const State = struct {
    count: i32 = 0,
};

pub fn main() !void {
    var state = State{};
    var app = zithril.App(State).init(.{
        .state = &state,
        .update = update,
        .view = view,
    });
    try app.run(std.heap.page_allocator);
}

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| switch (key.code) {
            .char => |c| if (c == 'q') return .quit,
            .up => state.count += 1,
            .down => state.count -= 1,
            else => {},
        },
        else => {},
    }
    return .none;
}

fn view(state: *State, frame: *zithril.Frame) void {
    const area = frame.size();
    
    frame.render(zithril.Block{
        .title = "Counter",
        .border = .rounded,
    }, area);
    
    frame.render(zithril.Text{
        .content = std.fmt.comptimePrint("Count: {d}", .{state.count}),
        .style = .{ .bold = true },
    }, area.inner(1));
}
```

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .zithril = .{
        .url = "https://github.com/your-username/zithril/archive/refs/heads/main.tar.gz",
        .hash = "...",
    },
},
```

Then in `build.zig`:

```zig
const zithril = b.dependency("zithril", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zithril", zithril.module("zithril"));
```

## Core Concepts

### The App Loop

zithril uses a simple loop: **Event → Update → View → Render**.

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐ │
│   │  Event  │ ──▶ │ Update  │ ──▶ │  View   │ ──▶ │ Render  │ │
│   │  (key)  │     │  (you)  │     │  (you)  │     │ (zithril)│ │
│   └─────────┘     └─────────┘     └─────────┘     └─────────┘ │
│        ▲                                               │       │
│        └───────────────────────────────────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

- **Event**: Keyboard, mouse, resize, or tick
- **Update**: Your function. Modify state, return an action (`.none`, `.quit`, or `.command`)
- **View**: Your function. Call `frame.render()` to describe the UI
- **Render**: zithril diffs and draws only what changed

### Layout

Layouts split a `Rect` into smaller regions using constraints:

```zig
fn view(state: *State, frame: *zithril.Frame) void {
    const chunks = frame.layout(frame.size(), .vertical, &.{
        .length(3),     // Header: exactly 3 rows
        .flex(1),       // Content: fill remaining space
        .length(1),     // Footer: exactly 1 row
    });
    
    frame.render(Header{}, chunks[0]);
    frame.render(Content{ .items = state.items }, chunks[1]);
    frame.render(StatusBar{ .message = state.status }, chunks[2]);
}
```

**Constraint types:**

| Constraint | Description |
|------------|-------------|
| `.length(n)` | Exactly `n` cells |
| `.min(n)` | At least `n` cells |
| `.max(n)` | At most `n` cells |
| `.flex(n)` | Proportional share (like CSS flex-grow) |
| `.ratio(a, b)` | Fraction `a/b` of available space |

### Widgets

Widgets are just structs that implement `render`:

```zig
const MyWidget = struct {
    title: []const u8,
    highlighted: bool = false,
    
    pub fn render(self: MyWidget, area: zithril.Rect, buf: *zithril.Buffer) void {
        const style = if (self.highlighted) 
            zithril.Style{ .fg = .yellow, .bold = true }
        else
            zithril.Style{};
        
        buf.set_string(area.x, area.y, self.title, style);
    }
};
```

### Events

```zig
fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            // key.code: .char, .enter, .tab, .backspace, .escape,
            //           .up, .down, .left, .right, .home, .end, etc.
            // key.modifiers: .ctrl, .alt, .shift
        },
        .mouse => |mouse| {
            // mouse.kind: .down, .up, .drag, .scroll_up, .scroll_down
            // mouse.x, mouse.y: position
            // mouse.modifiers: .ctrl, .alt, .shift
        },
        .resize => |size| {
            // size.width, size.height
        },
        .tick => {
            // Called at configured tick rate (for animations, polling)
        },
    }
    return .none;
}
```

### Actions and Commands

Return `.quit` to exit, or `.command` for async operations:

```zig
fn update(state: *State, event: zithril.Event) zithril.Action {
    if (event == .key and event.key.code == .char and event.key.code.char == 'r') {
        return .{ .command = Command.refresh_data };
    }
    return .none;
}

// Commands are executed by the runtime, results come back as events
const Command = enum {
    refresh_data,
    save_file,
};
```

## Built-in Widgets

### Text & Paragraph

```zig
// Simple text
frame.render(zithril.Text{
    .content = "Hello, world!",
    .style = .{ .fg = .green },
}, area);

// Multi-line with wrapping
frame.render(zithril.Paragraph{
    .text = long_text,
    .wrap = .word,
    .alignment = .center,
}, area);
```

### Block (borders & titles)

```zig
frame.render(zithril.Block{
    .title = " My Panel ",
    .title_alignment = .center,
    .border = .rounded,  // .none, .plain, .rounded, .double, .thick
    .border_style = .{ .fg = .blue },
}, area);
```

### List

```zig
frame.render(zithril.List{
    .items = &.{ "Item 1", "Item 2", "Item 3" },
    .selected = state.selected,
    .highlight_style = .{ .bg = .blue, .bold = true },
    .highlight_symbol = "▶ ",
}, area);
```

### Table

```zig
frame.render(zithril.Table{
    .header = &.{ "Name", "Status", "Progress" },
    .rows = state.rows,
    .widths = &.{ .flex(1), .length(10), .length(20) },
    .selected = state.selected_row,
}, area);
```

### Gauge (progress bar)

```zig
frame.render(zithril.Gauge{
    .ratio = 0.65,
    .label = "65%",
    .style = .{ .fg = .green },
}, area);
```

### Tabs

```zig
frame.render(zithril.Tabs{
    .titles = &.{ "Overview", "Logs", "Settings" },
    .selected = state.active_tab,
}, area);
```

### Scrollbar

```zig
frame.render(zithril.Scrollbar{
    .total = state.items.len,
    .position = state.scroll_offset,
    .viewport = area.height,
}, area);
```

## Styling

Styles can be applied to any widget:

```zig
const style = zithril.Style{
    .fg = .red,              // Foreground color
    .bg = .black,            // Background color
    .bold = true,
    .italic = false,
    .underline = false,
    .dim = false,
    .blink = false,
    .reverse = false,
    .strikethrough = false,
};
```

**Colors:**

```zig
// Named colors
.fg = .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white, .default

// Bright variants
.fg = .bright_red, .bright_green, // ...

// 256-color palette
.fg = .{ .indexed = 208 },

// RGB (true color)
.fg = .{ .rgb = .{ 255, 128, 0 } },
```

## Advanced Patterns

### Sub-views

Break complex UIs into functions:

```zig
fn view(state: *State, frame: *zithril.Frame) void {
    const chunks = frame.layout(frame.size(), .horizontal, &.{
        .ratio(1, 3),
        .flex(1),
    });
    
    render_sidebar(state, frame, chunks[0]);
    render_main(state, frame, chunks[1]);
}

fn render_sidebar(state: *State, frame: *zithril.Frame, area: zithril.Rect) void {
    frame.render(zithril.Block{ .title = "Sidebar", .border = .rounded }, area);
    frame.render(zithril.List{ .items = state.menu_items }, area.inner(1));
}

fn render_main(state: *State, frame: *zithril.Frame, area: zithril.Rect) void {
    // ...
}
```

### Nested layouts

```zig
fn view(state: *State, frame: *zithril.Frame) void {
    const outer = frame.layout(frame.size(), .vertical, &.{
        .length(3),
        .flex(1),
    });
    
    // Header
    frame.render(Header{}, outer[0]);
    
    // Main area split horizontally
    const inner = frame.layout(outer[1], .horizontal, &.{
        .length(30),
        .flex(1),
    });
    
    frame.render(Sidebar{}, inner[0]);
    frame.render(Content{}, inner[1]);
}
```

### Conditional rendering

```zig
fn view(state: *State, frame: *zithril.Frame) void {
    if (state.show_popup) {
        // Render popup over everything
        const popup_area = center(frame.size(), 40, 10);
        frame.render(zithril.Clear{}, popup_area);  // Clear the area first
        frame.render(Popup{ .message = state.popup_message }, popup_area);
    }
}

fn center(area: zithril.Rect, width: u16, height: u16) zithril.Rect {
    return .{
        .x = area.x + (area.width -| width) / 2,
        .y = area.y + (area.height -| height) / 2,
        .width = @min(width, area.width),
        .height = @min(height, area.height),
    };
}
```

### Focus management

zithril doesn't manage focus for you—you do:

```zig
const Focus = enum { sidebar, main, popup };

const State = struct {
    focus: Focus = .sidebar,
    // ...
};

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            if (key.code == .tab) {
                state.focus = switch (state.focus) {
                    .sidebar => .main,
                    .main => .sidebar,
                    .popup => .popup,
                };
                return .none;
            }
            
            // Dispatch to focused component
            switch (state.focus) {
                .sidebar => return update_sidebar(state, event),
                .main => return update_main(state, event),
                .popup => return update_popup(state, event),
            }
        },
        else => {},
    }
    return .none;
}
```

## Configuration

```zig
var state = State{};
var app = zithril.App(State).init(.{
    .state = &state,
    .update = update,
    .view = view,

    // Optional configuration
    .tick_rate_ms = 250,           // Tick event interval (0 = disabled)
    .mouse_capture = true,          // Enable mouse events
    .paste_bracket = true,          // Enable bracketed paste
    .alternate_screen = true,       // Use alternate screen buffer
});
```

## Examples

See the `/examples` directory:

- **counter** — Minimal example
- **list** — Navigable list with selection
- **tabs** — Multi-tab interface
- **async** — Commands and async operations
- **ralph** — Full agent orchestrator TUI (the reference app)

Run an example:

```bash
zig build run-example-counter
zig build run-example-ralph
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         YOUR APPLICATION                            │
│                                                                     │
│   State ──▶ update(Event) ──▶ Action                               │
│   State ──▶ view(Frame) ──▶ (renders widgets)                      │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           zithril                                   │
│                                                                     │
│   App        Event loop, terminal setup/teardown                   │
│   Frame      Layout methods, render dispatch                        │
│   Layout     Constraint solver                                      │
│   Buffer     Cell grid with diff support                           │
│   Widgets    Block, List, Table, Gauge, Text, Paragraph, ...       │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           rich_zig                                  │
│                                                                     │
│   Style, Color, Text spans, ANSI rendering                         │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Terminal Backend                            │
│                                                                     │
│   Raw mode, alternate screen, ANSI parsing, input events           │
└─────────────────────────────────────────────────────────────────────┘
```

## Comparison

| Feature | zithril | ratatui (Rust) | bubbletea (Go) |
|---------|---------|----------------|----------------|
| Rendering | Immediate | Immediate | Elm-style |
| State | You own it | You own it | Model/Update/View |
| Allocation | Explicit | Explicit | GC |
| Async | Commands | — | Commands |
| Widgets | Structs | Traits | Interfaces |

**Why zithril over ratatui?** You're writing Zig, not Rust.

**Why zithril over bubbletea?** No GC, no interface{} soup, comptime layout.

## Roadmap

- [x] Core rendering loop
- [x] Basic widgets (Block, Text, List, Table, Gauge)
- [x] Constraint-based layout
- [x] Keyboard input
- [ ] Mouse support
- [ ] Scrollable containers
- [ ] Text input widget
- [ ] Command/async pattern
- [ ] Animation helpers
- [ ] Sixel/Kitty image support
- [ ] Recording/playback for tests

## Contributing to rich_zig

zithril is built on [rich_zig](https://github.com/hotschmoe/rich_zig). If you encounter issues or need features in the rendering layer, file issues upstream:

```bash
# Report a bug
gh issue create --repo hotschmoe/rich_zig --title "Bug: ..." --body "..."

# Request a feature
gh issue create --repo hotschmoe/rich_zig --title "Feature: ..." --body "..."

# Update dependency after upstream fix
zig fetch --save git+https://github.com/hotschmoe/rich_zig
```

## Credits

Inspired by:
- [ratatui](https://github.com/ratatui-org/ratatui) (Rust) — Immediate mode design
- [bubbletea](https://github.com/charmbracelet/bubbletea) (Go) — Elm architecture, command pattern
- [OpenTUI](https://github.com/anomalyco/opentui) (TypeScript) — Modern TUI patterns

Built on:
- [rich_zig](https://github.com/hotschmoe/rich_zig) — Terminal rendering primitives

## License

MIT

---

*"Light as a feather, hard as dragon scales."*
