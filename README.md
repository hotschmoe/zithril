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
| `.percentage(n)` | `n`% of available space (0-100) |

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

## Built-in Widgets (22)

### Core Display

| Widget | Purpose |
|--------|---------|
| `Block` | Borders (none/plain/rounded/double/thick) and titles |
| `Text` | Single-line styled text with alignment |
| `Paragraph` | Multi-line text with wrapping (none/char/word) |
| `Clear` | Fill area with style (for popups/overlays) |
| `BigText` | Large decorative text using 8x8 bitmap font |

### Navigation & Input

| Widget | Purpose |
|--------|---------|
| `List` | Navigable item list with selection highlight |
| `Table` | Rows/columns with headers and selection |
| `Tabs` | Horizontal tab bar with highlight |
| `Tree` | Hierarchical expand/collapse with selection |
| `Menu` | Nested dropdown menu with keyboard nav |
| `TextInput` | Single-line text input with cursor and selection |
| `Calendar` | Monthly calendar with date picking |

### Data Visualization

| Widget | Purpose |
|--------|---------|
| `Gauge` | Progress bar with label |
| `LineGauge` | Compact single-line progress indicator |
| `Sparkline` | Inline trend graph using Unicode blocks |
| `BarChart` | Grouped vertical/horizontal bar charts |
| `Chart` | XY line and scatter plots with axes |
| `Canvas` | Arbitrary shape drawing (circles, lines, rectangles) |

### Containers & Utilities

| Widget | Purpose |
|--------|---------|
| `Scrollbar` | Vertical/horizontal scroll indicator |
| `ScrollView` | Virtual scrolling container |
| `ScrollableList` | List with built-in scrolling |
| `CodeEditor` | Syntax-highlighted code viewer |

## Rich Text Features

Wrappers around rich_zig v1.3.0 for rich text processing:

| Module | Purpose |
|--------|---------|
| `Theme` | Named style registry -- define once, reference by name |
| `fromAnsi` / `stripAnsi` | Parse or strip ANSI escape sequences |
| `parseAnsiToSegments` | Convert ANSI text to styled Segments for buffer rendering |
| `Highlighter` | Pattern-based text highlighting (numbers, bools, strings, URLs) |
| `Pretty` | Comptime pretty printer for Zig values with configurable themes |
| `Measurement` | Min/max width measurement with constraint conversion |

```zig
// Theme: define styles once, look up by name
var theme = try zithril.Theme.defaultTheme(allocator);
defer theme.deinit();
const style = theme.get("error").?;  // bold red

// ANSI: parse escape sequences into styled text
const stripped = try zithril.stripAnsi(allocator, "\x1b[1mBold\x1b[0m");

// Measurement: convert constraints to min/max measurements
const m = zithril.fromConstraint(zithril.Constraint.len(30), 100);
// m.minimum == 30, m.maximum == 30
```

### Widget Examples

```zig
// Block with border
frame.render(zithril.Block{
    .title = " My Panel ",
    .title_alignment = .center,
    .border = .rounded,
    .border_style = zithril.Style.init().fg(.blue),
}, area);

// Navigable list
frame.render(zithril.List{
    .items = &.{ "Item 1", "Item 2", "Item 3" },
    .selected = state.selected,
    .highlight_style = zithril.Style.init().bg(.blue).bold(),
    .highlight_symbol = "> ",
}, area);

// Progress gauge
frame.render(zithril.Gauge{
    .ratio = 0.65,
    .label = "65%",
    .gauge_style = zithril.Style.init().bg(.green),
}, area);

// Sparkline trend
frame.render(zithril.Sparkline{
    .data = &.{ 10.0, 25.0, 40.0, 30.0, 55.0, 80.0 },
    .style = zithril.Style.init().fg(.cyan),
}, area);

// Bar chart
frame.render(zithril.BarChart{
    .groups = &.{
        .{ .label = "Q1", .bars = &.{
            .{ .value = 80.0, .label = "Sales", .style = zithril.Style.init().fg(.green) },
        }},
    },
    .bar_width = 3,
}, area);
```

## Styling

Styles can be applied to any widget:

```zig
const style = zithril.Style.init()
    .fg(.red)              // Foreground color
    .bg(.black)            // Background color
    .bold()                // Bold text
    .italic()              // Italic text
    .underline()           // Single underline
    .underline2()          // Double underline (SGR 21)
    .dim()                 // Dim/faint text
    .reverse()             // Reverse video
    .strikethrough()       // Strikethrough
    .overline()            // Overline (SGR 53)
    .frame()               // Frame (SGR 51)
    .encircle()            // Encircle (SGR 52)
    .hidden();             // Hidden/concealed text
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

## Examples & Demos

### Examples (`/examples`)

| Example | What it demonstrates |
|---------|---------------------|
| **counter** | Minimal app: state, update, view, Block + Text |
| **list** | Navigable list with j/k and selection highlight |
| **tabs** | Multi-tab interface with per-tab content |
| **ralph** | Full reference app: agent list, detail panel, logs, gauges, focus management |

```bash
zig build run-example-counter
zig build run-example-ralph
```

### Demos (`/demos`)

Larger applications that stress-test the framework:

| Demo | What it showcases |
|------|-------------------|
| **rung** | Ladder logic puzzle game -- grid editing, simulation, 10 levels |
| **dashboard** | System monitoring -- Sparkline, BarChart, Gauge, LineGauge, BigText, Table |
| **explorer** | File browser -- Tree, Menu, TextInput, CodeEditor, Tabs, focus management |
| **dataviz** | Visualization gallery -- Chart, Canvas, Calendar, BigText, 5 pages |
| **showcase** | Rich text features -- Theme, ANSI parsing, Highlighter, Pretty printer, new style attributes, Measurement |

```bash
zig build run-rung
zig build run-dashboard
zig build run-explorer
zig build run-dataviz
zig build run-showcase
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
│   Layout     Constraint solver + Measurement protocol              │
│   Buffer     Cell grid with diff support                           │
│   Widgets    Block, List, Table, Gauge, Text, Paragraph, ...       │
│   Theme      Named style registry for consistent theming           │
│   ANSI       Parse/strip ANSI escape sequences                     │
│   Highlight  Pattern-based text highlighting (repr, custom rules)  │
│   Pretty     Comptime pretty printer for Zig values                │
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
- [x] Basic widgets (Block, Text, List, Table, Gauge, Tabs, Scrollbar)
- [x] Constraint-based layout (length, min, max, flex, ratio, percentage)
- [x] Flex alignment modes (start, end, center, space_between, space_around, space_evenly)
- [x] Padding, Margin, Spacing types
- [x] Keyboard input
- [x] Mouse support (parsing, hit testing, hover, drag, scroll)
- [x] Scrollable containers (ScrollView, ScrollableList)
- [x] Text input widget (TextInput with cursor and selection)
- [x] Command/async pattern (Command, CommandResult)
- [x] Animation helpers (easing, keyframes, interpolation)
- [x] Graphics protocol detection (Sixel, Kitty, iTerm2)
- [x] Testing utilities (recorder, player, mock backend, snapshots)
- [x] Data visualization (Sparkline, BarChart, Chart, Canvas, LineGauge)
- [x] Navigation widgets (Tree, Menu, Calendar)
- [x] Specialty widgets (BigText, CodeEditor)
- [x] Theming system (named style registry)
- [x] ANSI parsing (fromAnsi, stripAnsi, parseAnsiToSegments)
- [x] Pattern highlighting (repr, custom rules)
- [x] Pretty printing (comptime Zig value formatter)
- [x] Measurement protocol (constraint-to-measurement conversion)
- [x] Extended style attributes (underline2, frame, encircle, overline)
- [ ] Mouse event wiring to app event loop
- [ ] Async command dispatch in runtime
- [ ] Image rendering via graphics protocols

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
