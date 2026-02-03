# zithril Usage Guide

This document covers usage patterns, state management, and common patterns when building applications with zithril.

---

## Table of Contents

1. [State Ownership Model](#state-ownership-model)
2. [Widget Patterns](#widget-patterns)
3. [Layout Patterns](#layout-patterns)
4. [Focus Management](#focus-management)

---

## State Ownership Model

zithril uses **pointer semantics** for state. You own your state, and the App borrows a pointer to it:

```zig
var state = MyState{ .count = 0 };
var app = zithril.App(MyState).init(.{
    .state = &state,  // App borrows pointer to your state
    .update = update,
    .view = view,
});
```

After `App.init()`:
- `app.state` is a pointer to **your** `state` variable
- All mutations happen directly to `state`
- You are responsible for cleanup (if any)

### The Ownership Rule

**You own the state. The App borrows it.**

```
                   state <--------> [your data]
                     ^
                     |
    app.state -------+  (pointer to your state)
```

### Cleanup Pattern

For state that needs cleanup:

```zig
pub fn main() !void {
    var state = MyState.init(allocator);
    defer state.deinit();  // You own it, you clean it up

    var app = zithril.App(MyState).init(.{
        .state = &state,
        .update = update,
        .view = view,
    });

    try app.run(allocator);
}
```

### Checking State After Run

After `run()` returns, your state reflects any mutations made by `update()`:

```zig
pub fn main() !void {
    var state = MyState{ .submitted = false };

    var app = zithril.App(MyState).init(.{ .state = &state, ... });
    try app.run(allocator);

    // state.submitted reflects whatever update() set
    if (state.submitted) {
        // Process submission
    }
}
```

---

## Widget Patterns

### Stateless Widgets

Most widgets should be stateless - just data to render:

```zig
const InfoPanel = struct {
    title: []const u8,
    lines: []const []const u8,
    style: Style = .{},

    pub fn render(self: InfoPanel, area: Rect, buf: *Buffer) void {
        // Render title
        buf.setString(area.x, area.y, self.title, self.style);

        // Render lines
        for (self.lines, 0..) |line, i| {
            if (area.y + 1 + i >= area.bottom()) break;
            buf.setString(area.x, area.y + 1 + @intCast(i), line, .{});
        }
    }
};
```

### Widgets with External State

For widgets needing persistent state (scroll position, selection), keep state in your App state:

```zig
const State = struct {
    list_selected: usize = 0,
    list_scroll: usize = 0,
    items: []const []const u8,
};

fn view(state: *State, frame: *Frame) void {
    frame.render(List{
        .items = state.items,
        .selected = state.list_selected,
        .scroll_offset = state.list_scroll,
    }, frame.size());
}

fn update(state: *State, event: Event) Action {
    switch (event) {
        .key => |key| switch (key.code) {
            .down => state.list_selected +|= 1,
            .up => state.list_selected -|= 1,
            else => {},
        },
        else => {},
    }
    return .none;
}
```

---

## Layout Patterns

### Fixed + Flexible

```zig
const chunks = frame.layout(area, .vertical, &.{
    .length(3),   // Fixed header
    .flex(1),     // Flexible content
    .length(1),   // Fixed footer
});
```

### Proportional Split

```zig
const chunks = frame.layout(area, .horizontal, &.{
    .ratio(1, 3),  // 1/3 for sidebar
    .flex(1),      // Rest for main
});
```

### Minimum with Flex

```zig
const chunks = frame.layout(area, .horizontal, &.{
    .min(20),   // At least 20, but can grow
    .flex(2),   // Gets 2x the flex space
    .flex(1),   // Gets 1x the flex space
});
```

---

## Focus Management

zithril does not manage focus - you implement it:

```zig
const Focus = enum { sidebar, main, dialog };

const State = struct {
    focus: Focus = .sidebar,
    show_dialog: bool = false,
};

fn update(state: *State, event: Event) Action {
    // Tab cycles focus (unless dialog is open)
    if (event == .key and event.key.code == .tab and !state.show_dialog) {
        state.focus = switch (state.focus) {
            .sidebar => .main,
            .main => .sidebar,
            .dialog => .dialog,
        };
        return .none;
    }

    // Dispatch to focused component
    if (state.show_dialog) {
        return updateDialog(state, event);
    }
    return switch (state.focus) {
        .sidebar => updateSidebar(state, event),
        .main => updateMain(state, event),
        .dialog => unreachable,
    };
}

fn view(state: *State, frame: *Frame) void {
    const chunks = frame.layout(frame.size(), .horizontal, &.{
        .length(30),
        .flex(1),
    });

    // Highlight focused panel
    const sidebar_style = if (state.focus == .sidebar)
        Style{ .fg = .cyan }
    else
        Style{};

    frame.render(Block{
        .title = "Sidebar",
        .border_style = sidebar_style,
    }, chunks[0]);

    // Dialog overlays everything
    if (state.show_dialog) {
        const dialog_area = centerRect(frame.size(), 40, 10);
        frame.render(Dialog{ .message = "Confirm?" }, dialog_area);
    }
}
```

---

*See also: [README.md](README.md) for quick start and API overview.*
