# TUI Framework: Architecture Comparison

## First: Rich vs TUI Framework

```
    WHAT YOU HAVE (rich_zig)              WHAT YOU NEED (TUI framework)
    ════════════════════════              ════════════════════════════
    
    ┌─────────────────────────┐          ┌─────────────────────────────┐
    │  Rich = Rendering       │          │  TUI = Application          │
    │                         │          │                             │
    │  • Styled text          │          │  • Event loop               │
    │  • Colors/formatting    │          │  • Input handling           │
    │  • Tables               │          │  • State management         │
    │  • Panels/boxes         │          │  • Layout system            │
    │  • Markdown             │          │  • Widget composition       │
    │  • Progress bars        │          │  • Focus management         │
    │                         │          │  • Reactive updates         │
    └─────────────────────────┘          └─────────────────────────────┘
              │                                       │
              │                                       │
              └───────────────┬───────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  rich_zig can   │
                    │  be the BACKEND │
                    │  for your TUI   │
                    └─────────────────┘
    
    
    Python analogy:
    
    Rich     ──▶  Textual
    (render)      (TUI framework built on Rich)
    
    Your path:
    
    rich_zig ──▶  tui_zig (what you'll build)
```

---

## The Three Architectures

### 1. Ratatui (Rust) - Immediate Mode

```
    IMMEDIATE MODE: "Describe the UI every frame"
    ═════════════════════════════════════════════
    
    ┌──────────────────────────────────────────────────────────────────┐
    │                                                                  │
    │   loop {                                                         │
    │       // 1. Handle events                                        │
    │       if let Event::Key(key) = read_event() {                   │
    │           match key {                                            │
    │               'q' => break,                                      │
    │               'j' => state.selected += 1,                       │
    │               ...                                                │
    │           }                                                      │
    │       }                                                          │
    │                                                                  │
    │       // 2. Draw ENTIRE UI (every frame)                        │
    │       terminal.draw(|frame| {                                   │
    │           let chunks = Layout::default()                        │
    │               .direction(Vertical)                              │
    │               .constraints([Length(3), Min(0), Length(1)])      │
    │               .split(frame.size());                             │
    │                                                                  │
    │           frame.render_widget(header, chunks[0]);               │
    │           frame.render_widget(list, chunks[1]);                 │
    │           frame.render_widget(status, chunks[2]);               │
    │       });                                                        │
    │   }                                                              │
    │                                                                  │
    └──────────────────────────────────────────────────────────────────┘
    
    
    Data flow:
    
    ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
    │  Event  │ ──▶ │  State  │ ──▶ │  View   │ ──▶ │ Screen  │
    │  (key)  │     │ (yours) │     │  (fn)   │     │ (draw)  │
    └─────────┘     └─────────┘     └─────────┘     └─────────┘
                         ▲                              
                         │                              
                         └──────────────────────────────
                              You own all state
    
    
    Pros:
    ✓ Dead simple mental model
    ✓ You own all state (Zig-friendly)
    ✓ No framework magic
    ✓ Easy to debug (just print state)
    ✓ Naturally handles resize/redraw
    
    Cons:
    ✗ Redraws everything every frame (can optimize with damage tracking)
    ✗ Widget state (scroll position, cursor) is your problem
    ✗ Can get verbose for complex UIs
```

### 2. Bubbletea (Go) - Elm Architecture

```
    ELM ARCHITECTURE: "Messages drive state changes"
    ════════════════════════════════════════════════
    
    ┌──────────────────────────────────────────────────────────────────┐
    │                                                                  │
    │   type Model struct {                                            │
    │       items    []string                                          │
    │       selected int                                               │
    │   }                                                              │
    │                                                                  │
    │   func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {     │
    │       switch msg := msg.(type) {                                │
    │       case tea.KeyMsg:                                          │
    │           switch msg.String() {                                 │
    │           case "q":                                              │
    │               return m, tea.Quit                                │
    │           case "j":                                              │
    │               m.selected++                                       │
    │               return m, nil                                      │
    │           }                                                      │
    │       }                                                          │
    │       return m, nil                                              │
    │   }                                                              │
    │                                                                  │
    │   func (m Model) View() string {                                │
    │       // Return the UI as a string                              │
    │       return renderList(m.items, m.selected)                    │
    │   }                                                              │
    │                                                                  │
    └──────────────────────────────────────────────────────────────────┘
    
    
    Data flow:
    
         ┌─────────────────────────────────────────────────┐
         │                                                 │
         ▼                                                 │
    ┌─────────┐     ┌─────────┐     ┌─────────┐          │
    │   Msg   │ ──▶ │ Update  │ ──▶ │  Model  │ ─────────┘
    │  (any)  │     │  (fn)   │     │ (state) │
    └─────────┘     └─────────┘     └────┬────┘
                                         │
                                         ▼
                                    ┌─────────┐
                                    │  View   │ ──▶ Screen
                                    │  (fn)   │
                                    └─────────┘
    
    
    Messages include:
    • Key presses
    • Mouse events  
    • Window resize
    • Timer ticks
    • Async results (HTTP, file IO)
    • Custom messages between components
    
    
    Pros:
    ✓ Very clean state management
    ✓ Easy to test (pure functions)
    ✓ Commands for side effects (async)
    ✓ Composable sub-models
    
    Cons:
    ✗ Message boilerplate explosion
    ✗ Go's interface{} becomes Zig union hell
    ✗ Indirection can be confusing
    ✗ "Where does this message come from?"
```

### 3. OpenTUI (TS) - Component/OOP Style

```
    COMPONENT TREE: "Widgets are objects with lifecycle"
    ════════════════════════════════════════════════════
    
    ┌──────────────────────────────────────────────────────────────────┐
    │                                                                  │
    │   class ListView extends Widget {                                │
    │       items: string[]                                            │
    │       selected: number                                           │
    │                                                                  │
    │       onKey(key: Key) {                                         │
    │           if (key === 'j') this.selected++                      │
    │           this.markDirty()  // request redraw                   │
    │       }                                                          │
    │                                                                  │
    │       render(ctx: Context) {                                    │
    │           for (let i = 0; i < this.items.length; i++) {        │
    │               ctx.print(this.items[i], i === this.selected)    │
    │           }                                                      │
    │       }                                                          │
    │   }                                                              │
    │                                                                  │
    │   // Composition                                                 │
    │   app.add(new Header("My App"))                                 │
    │   app.add(new ListView(items))                                  │
    │   app.add(new StatusBar())                                      │
    │                                                                  │
    └──────────────────────────────────────────────────────────────────┘
    
    
    Widget tree:
    
                        App
                         │
           ┌─────────────┼─────────────┐
           │             │             │
        Header       ListView      StatusBar
                         │
                   ┌─────┴─────┐
                   │           │
               ListItem    ListItem
    
    
    Pros:
    ✓ Familiar to OOP developers
    ✓ Widgets encapsulate their state
    ✓ Natural composition model
    
    Cons:
    ✗ Inheritance hierarchies get messy
    ✗ Hidden state in widget tree
    ✗ Event bubbling complexity
    ✗ Not Zig-idiomatic AT ALL
```

---

## My Recommendation: Immediate Mode (ratatui-inspired)

```
    WHY IMMEDIATE MODE FOR ZIG
    ══════════════════════════
    
    Zig Philosophy                    Immediate Mode
    ══════════════                    ══════════════
    
    Explicit over implicit      ──▶   You control all state
    No hidden allocations       ──▶   Render to provided buffer
    Comptime power              ──▶   Widget layout at comptime
    No OOP inheritance          ──▶   Composition via functions
    Error handling explicit     ──▶   Draw functions return errors
    
    
    WHAT TO STEAL FROM EACH
    ═══════════════════════
    
    From ratatui:
    ✓ Immediate mode rendering
    ✓ Constraint-based layout (Length, Min, Max, Ratio)
    ✓ Widget trait → Zig interface pattern
    ✓ Buffer abstraction (cell grid)
    
    From bubbletea:
    ✓ Command pattern for async (Cmd returns, runtime executes)
    ✓ Clean separation of Update and View
    ✓ Sub-model composition idea (but simpler)
    
    From neither:
    ✗ OOP widget inheritance
    ✗ Complex message routing
    ✗ Hidden framework state
```

---

## Proposed Architecture: tui_zig

```
    LAYER CAKE
    ══════════
    
    ┌─────────────────────────────────────────────────────────────────┐
    │                      YOUR APPLICATION                           │
    │                                                                 │
    │   fn view(state: *State, frame: *Frame) void {                 │
    │       const layout = frame.layout(.vertical, .{                │
    │           .length(3),    // header                              │
    │           .flex(1),      // content                             │
    │           .length(1),    // status                              │
    │       });                                                       │
    │       frame.render(Header{ .title = "Ralph" }, layout[0]);     │
    │       frame.render(AgentList{ .agents = state.agents }, layout[1]);│
    │       frame.render(StatusBar{ .msg = state.status }, layout[2]);│
    │   }                                                             │
    └─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
    ┌─────────────────────────────────────────────────────────────────┐
    │                        tui_zig CORE                             │
    │                                                                 │
    │   • Frame (current render target with layout methods)          │
    │   • Layout (constraint solver)                                  │
    │   • Widget (interface: fn render(*Self, Rect, *Buffer))        │
    │   • Event (key, mouse, resize, custom)                         │
    │   • Runtime (event loop, terminal setup/teardown)              │
    └─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
    ┌─────────────────────────────────────────────────────────────────┐
    │                         rich_zig                                │
    │                                                                 │
    │   • Style (colors, bold, etc.)                                 │
    │   • Text (styled spans)                                        │
    │   • Table, Panel, etc. (become widgets)                        │
    │   • Cell, Buffer (low-level terminal grid)                     │
    └─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
    ┌─────────────────────────────────────────────────────────────────┐
    │                     Terminal Backend                            │
    │                                                                 │
    │   • ANSI escape sequences                                       │
    │   • Raw mode                                                    │
    │   • Alternate screen                                            │
    └─────────────────────────────────────────────────────────────────┘
```

---

## Core Types (Minimal)

```zig
// ═══════════════════════════════════════════════════════════════
// tui.zig - Core types
// ═══════════════════════════════════════════════════════════════

const std = @import("std");
const rich = @import("rich_zig");

// ─────────────────────────────────────────────────────────────────
// Geometry
// ─────────────────────────────────────────────────────────────────

pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    
    pub fn inner(self: Rect, margin: u16) Rect {
        return .{
            .x = self.x + margin,
            .y = self.y + margin,
            .width = self.width -| (margin * 2),
            .height = self.height -| (margin * 2),
        };
    }
};

// ─────────────────────────────────────────────────────────────────
// Layout constraints (ratatui-style)
// ─────────────────────────────────────────────────────────────────

pub const Constraint = union(enum) {
    length: u16,      // Exact size
    min: u16,         // At least this
    max: u16,         // At most this
    ratio: [2]u16,    // Fraction (num, denom)
    flex: u16,        // Flex weight (like CSS flex-grow)
};

pub fn layout(
    area: Rect,
    direction: enum { horizontal, vertical },
    constraints: []const Constraint,
) []Rect {
    // Constraint solver here
    // Returns array of Rects
}

// ─────────────────────────────────────────────────────────────────
// Widget interface
// ─────────────────────────────────────────────────────────────────

pub fn Widget(comptime T: type) type {
    return struct {
        pub fn render(self: T, area: Rect, buf: *Buffer) void {
            self.renderImpl(area, buf);
        }
    };
}

// Usage: widgets just implement renderImpl
// 
// const MyWidget = struct {
//     data: []const u8,
//     
//     pub fn renderImpl(self: MyWidget, area: Rect, buf: *Buffer) void {
//         buf.set_string(area.x, area.y, self.data, .{});
//     }
// };

// ─────────────────────────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────────────────────────

pub const Event = union(enum) {
    key: Key,
    mouse: Mouse,
    resize: struct { w: u16, h: u16 },
    tick,  // For animations/polling
    
    pub const Key = struct {
        code: KeyCode,
        modifiers: Modifiers,
    };
    
    pub const KeyCode = union(enum) {
        char: u21,
        enter,
        tab,
        backspace,
        escape,
        up, down, left, right,
        // ...
    };
};

// ─────────────────────────────────────────────────────────────────
// Application runtime
// ─────────────────────────────────────────────────────────────────

pub fn App(comptime State: type) type {
    return struct {
        state: State,
        
        // User provides these
        update: *const fn (*State, Event) Action,
        view: *const fn (*State, *Frame) void,
        
        pub const Action = union(enum) {
            none,
            quit,
            // Could add: spawn_task, send_message, etc.
        };
        
        pub fn run(self: *@This()) !void {
            var terminal = try Terminal.init();
            defer terminal.deinit();
            
            while (true) {
                // Render
                var frame = terminal.begin_frame();
                self.view(&self.state, &frame);
                try terminal.end_frame(&frame);
                
                // Handle input
                if (try terminal.poll_event()) |event| {
                    switch (self.update(&self.state, event)) {
                        .quit => break,
                        .none => {},
                    }
                }
            }
        }
    };
}
```

---

## Example: Your Ralph TUI

```zig
const std = @import("std");
const tui = @import("tui_zig");
const rich = @import("rich_zig");

// ═══════════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════════

const State = struct {
    agents: []Agent,
    selected: usize,
    logs: RingBuffer(LogEntry, 100),
    
    const Agent = struct {
        name: []const u8,
        project: []const u8,
        status: enum { idle, working, blocked, done },
        current_task: ?[]const u8,
        progress: f32,
    };
};

// ═══════════════════════════════════════════════════════════════
// Update
// ═══════════════════════════════════════════════════════════════

fn update(state: *State, event: tui.Event) tui.App(State).Action {
    switch (event) {
        .key => |key| {
            if (key.code == .char and key.code.char == 'q') {
                return .quit;
            }
            switch (key.code) {
                .up, .char => |c| if (c == 'k') {
                    state.selected -|= 1;
                },
                .down, .char => |c| if (c == 'j') {
                    state.selected = @min(state.selected + 1, state.agents.len - 1);
                },
                else => {},
            }
        },
        else => {},
    }
    return .none;
}

// ═══════════════════════════════════════════════════════════════
// View
// ═══════════════════════════════════════════════════════════════

fn view(state: *State, frame: *tui.Frame) void {
    const areas = frame.layout(.vertical, &.{
        .length(3),   // Header
        .flex(1),     // Main content
        .length(10),  // Logs
        .length(1),   // Status bar
    });
    
    // Header
    frame.render(Header{ .title = "🤖 Ralph Orchestrator" }, areas[0]);
    
    // Main: split horizontal
    const main_areas = frame.split(areas[1], .horizontal, &.{
        .ratio(1, 2),  // Agent list
        .ratio(1, 2),  // Agent detail
    });
    
    frame.render(AgentList{
        .agents = state.agents,
        .selected = state.selected,
    }, main_areas[0]);
    
    frame.render(AgentDetail{
        .agent = &state.agents[state.selected],
    }, main_areas[1]);
    
    // Logs
    frame.render(LogPanel{ .logs = &state.logs }, areas[2]);
    
    // Status bar
    frame.render(StatusBar{
        .text = "q: quit | j/k: navigate | enter: details",
    }, areas[3]);
}

// ═══════════════════════════════════════════════════════════════
// Widgets (use rich_zig for rendering)
// ═══════════════════════════════════════════════════════════════

const AgentList = struct {
    agents: []const State.Agent,
    selected: usize,
    
    pub fn renderImpl(self: AgentList, area: tui.Rect, buf: *tui.Buffer) void {
        // Border
        buf.draw_box(area, .rounded);
        const inner = area.inner(1);
        
        for (self.agents, 0..) |agent, i| {
            const y = inner.y + @intCast(u16, i);
            if (y >= inner.y + inner.height) break;
            
            const style = if (i == self.selected)
                rich.Style{ .bg = .blue, .bold = true }
            else
                rich.Style{};
            
            const status_icon = switch (agent.status) {
                .idle => "⏸",
                .working => "▶",
                .blocked => "⚠",
                .done => "✓",
            };
            
            buf.set_string(inner.x, y, status_icon, style);
            buf.set_string(inner.x + 2, y, agent.name, style);
            buf.set_string(inner.x + 15, y, agent.project, style);
            
            // Progress bar
            if (agent.status == .working) {
                buf.draw_gauge(
                    .{ .x = inner.x + 30, .y = y, .width = 20, .height = 1 },
                    agent.progress,
                );
            }
        }
    }
};

// ═══════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════

pub fn main() !void {
    var app = tui.App(State){
        .state = .{
            .agents = &.{
                .{ .name = "claude-1", .project = "laminae", .status = .working, .current_task = "page tables", .progress = 0.65 },
                .{ .name = "codex-1", .project = "rich_zig", .status = .working, .current_task = "port tables", .progress = 0.30 },
                .{ .name = "gemini-1", .project = "tmux_zig", .status = .idle, .current_task = null, .progress = 0 },
            },
            .selected = 0,
            .logs = .{},
        },
        .update = update,
        .view = view,
    };
    
    try app.run();
}
```

---

## What Rich_zig Already Gives You

```
    RICH_ZIG FEATURES                    TUI FRAMEWORK NEEDS
    ════════════════                     ═══════════════════
    
    ✓ Style (colors, bold, etc.)    ──▶  Widget styling
    ✓ Text (styled spans)           ──▶  Text rendering
    ✓ Table                         ──▶  Table widget
    ✓ Panel                         ──▶  Box/border widget
    ✓ Progress bar                  ──▶  Gauge widget
    ✓ Columns                       ──▶  Layout primitive
    ✓ Syntax highlighting           ──▶  Code viewer widget
    
    YOU NEED TO ADD:
    
    ✗ Event loop / raw mode
    ✗ Input parsing (ANSI escape sequences)
    ✗ Constraint-based layout solver
    ✗ Frame/Buffer abstraction
    ✗ Widget composition
    ✗ Focus management (which widget gets input)
```

---

## Implementation Order

```
    WEEK 1: Core
    ════════════
    
    □ Terminal backend (raw mode, alternate screen)
    □ Buffer (cell grid that rich_zig renders into)
    □ Event parsing (keyboard, mouse, resize)
    □ Basic event loop
    
    Milestone: Can clear screen, print colored text, read keys
    
    
    WEEK 2: Layout
    ══════════════
    
    □ Rect type
    □ Constraint solver (steal ratatui's algorithm)
    □ Frame abstraction
    □ Horizontal/Vertical layout
    
    Milestone: Can split screen into regions
    
    
    WEEK 3: Widgets
    ═══════════════
    
    □ Widget interface
    □ Port rich_zig Panel → Box widget
    □ Port rich_zig Table → Table widget
    □ List widget (with selection)
    □ Text/Paragraph widget
    
    Milestone: Can render your Ralph TUI mockup
    
    
    WEEK 4: Polish
    ══════════════
    
    □ Focus management
    □ Scrolling
    □ Mouse support
    □ Async commands (for agent status updates)
    
    Milestone: Fully functional Ralph TUI
```

---

## Summary

```
    DECISION
    ════════
    
    Base on:     ratatui (immediate mode)
    Steal from:  bubbletea (Command pattern for async)
    Avoid:       OOP widget trees
    
    rich_zig:    Rendering backend (keep it)
    tui_zig:     New crate for app framework
    
    
    WHY THIS APPROACH
    ═════════════════
    
    • Zig-idiomatic (explicit state, no hidden magic)
    • Builds on your existing 22k LOC investment
    • Simple enough to understand completely
    • Powerful enough for Ralph orchestrator
    • Foundation for future projects (enercalc UI, etc.)
    
    
    ESTIMATED EFFORT
    ════════════════
    
    Core framework:     ~2-3k LOC
    Widget library:     ~2-3k LOC (reusing rich_zig)
    Ralph TUI app:      ~1-2k LOC
    
    Total:              ~4-6 weeks part-time
                        or ~2 weeks with agent assistance
```

Want me to sketch out the terminal backend or the constraint solver in more detail? Those are the two non-trivial pieces that don't exist in rich_zig yet.