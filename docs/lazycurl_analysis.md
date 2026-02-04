# Analysis: lazycurl TUI Architecture

A study of [BowTiedCrocodile/lazycurl](https://github.com/BowTiedCrocodile/lazycurl), a Zig TUI for curl built on libvaxis.

---

## Overview

lazycurl is a pre-alpha terminal UI that provides visual command building for curl. It uses libvaxis (rockorager/libvaxis) for terminal rendering - a different approach from our rich_zig foundation.

Key differentiator: lazycurl shows the underlying curl command at all times, maintaining transparency unlike tools like Postman that abstract the HTTP mechanics.

---

## Architecture Comparison

### lazycurl's Layer Stack

```
+--------------------------------------------------+
|              lazycurl Application                 |
|  App (state) --> Runtime (execution)             |
|  UiState (presentation) --> Components (render)  |
+--------------------------------------------------+
                      |
                      v
+--------------------------------------------------+
|                  libvaxis                         |
|  Terminal abstraction, input events, rendering   |
|  Kitty keyboard protocol, mouse, clipboard       |
+--------------------------------------------------+
```

### zithril's Layer Stack

```
+--------------------------------------------------+
|              YOUR APPLICATION                     |
|  State --> update(Event) --> Action              |
|  State --> view(Frame) --> (renders widgets)     |
+--------------------------------------------------+
                      |
                      v
+--------------------------------------------------+
|                  zithril                          |
|  App, Frame, Layout, Buffer, Widgets             |
+--------------------------------------------------+
                      |
                      v
+--------------------------------------------------+
|                  rich_zig                         |
|  Style, Color, Text spans, ANSI rendering        |
+--------------------------------------------------+
```

**Key difference**: lazycurl has a thicker application layer with more structure (separate UiState, Runtime). zithril is more minimal - you own all state.

---

## Patterns Worth Adopting

### 1. Separated Presentation State (UiState)

lazycurl explicitly separates:
- **App state**: Domain data (commands, templates, history)
- **UiState**: Presentation concerns (scroll positions, active tab, cursor blink)

```zig
// lazycurl pattern
const UiState = struct {
    active_tab: Tab,
    scroll_positions: ScrollMap,
    text_inputs: InputMap,
    copy_indicator_active: bool,
};
```

**Recommendation for zithril**: Document this as a best practice. While zithril doesn't enforce separation, users building complex apps should split their state similarly.

### 2. Semantic Theme System

lazycurl centralizes all styles in a Theme struct with semantic names:

```zig
const Theme = struct {
    border: vaxis.Style = .{ .fg = .{ .index = 244 } },
    title: vaxis.Style = .{ .fg = .{ .index = 111 }, .bold = true },
    text: vaxis.Style = .{},
    muted: vaxis.Style = .{ .fg = .{ .index = 244 } },
    accent: vaxis.Style = .{ .fg = .{ .index = 81 } },
    error_style: vaxis.Style = .{ .fg = .{ .index = 196 } },
    success: vaxis.Style = .{ .fg = .{ .index = 82 } },
    warning: vaxis.Style = .{ .fg = .{ .index = 214 } },
};
```

**Recommendation for zithril**: Consider adding a Theme example/pattern. We use rich_zig's Style directly, but a semantic layer helps consistency.

### 3. Component-per-Panel Organization

lazycurl organizes UI into focused component files:

```
ui/components/
  command_builder.zig
  command_display.zig
  environment_panel.zig
  history_panel.zig
  options_panel.zig
  output_panel.zig
  shortcuts_panel.zig
  status_bar.zig
  templates_panel.zig
  url_container.zig
```

Each component is a focused module with its own render function. This maps well to zithril's widget pattern.

**Recommendation for zithril**: Add an example showing multi-file component organization for larger apps.

### 4. Frame-Locked Rendering with Arena Allocator

lazycurl uses a 33ms tick rate (~30 FPS) and clears an arena allocator each frame:

```zig
// Per-frame arena pattern
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const frame_alloc = arena.allocator();
// ... render using frame_alloc ...
// arena auto-clears on next frame
```

**Recommendation for zithril**: Document this pattern. zithril's Frame could expose a per-frame arena for temporary allocations during view().

### 5. Modal State Machine

lazycurl uses an explicit state machine for modes:

```zig
const AppState = enum {
    normal,
    editing,
    method_dropdown,
    importing,
    // ...
};
```

Event handlers dispatch based on current mode. This prevents invalid state combinations.

**Recommendation for zithril**: Document the modal pattern. Our focus example shows manual focus, but modes are a higher-level pattern worth demonstrating.

---

## Patterns to Consider Carefully

### 1. Direct vaxis Rendering

lazycurl renders directly to vaxis primitives (Segment, print()). No intermediate representation.

**Trade-off**: Faster, but couples components to the rendering backend.

**zithril approach**: We already have an intermediate Buffer that handles diffing. This is better for our goals (diffing, testability).

### 2. Runtime as Separate Concern

lazycurl has a Runtime struct for async command execution:

```zig
const Runtime = struct {
    active_job: ?Job,
    poll_result: ?Result,

    fn tick(self: *Runtime) void {
        // Poll for completion
    }
};
```

**Observation**: This is curl-specific but the pattern of separating async operations is valuable.

**Recommendation for zithril**: Our planned Command/Action pattern could learn from this. The Runtime cleanly separates "what's running" from "what's on screen."

### 3. Undo via Full Object Preservation

lazycurl stores complete deleted objects for undo, not deltas:

```zig
const UndoEntry = struct {
    deleted_template: ?Template,
    deleted_environment: ?Environment,
    // Full objects, not patches
};
```

**Trade-off**: Uses more memory but restoration is trivial.

**Observation**: Good for apps with discrete deletable objects. Not relevant for zithril core, but useful pattern for apps.

---

## What zithril Does Better

### 1. Constraint-Based Layout

zithril's layout system is more expressive:

```zig
// zithril
const chunks = frame.layout(area, .vertical, &.{
    .length(3),     // Exact
    .flex(1),       // Proportional
    .ratio(1, 3),   // Fractional
    .min(5),        // Minimum
});
```

lazycurl appears to use more manual positioning.

### 2. Widget Protocol

zithril has a clear widget interface:

```zig
pub fn render(self: Widget, area: Rect, buf: *Buffer) void
```

This enables composition and reuse. lazycurl's components are more ad-hoc.

### 3. Framework vs Application

zithril is a reusable framework. lazycurl is an application. We provide primitives; they solve a specific problem.

---

## Action Items

### Documentation Additions

1. **State separation guide**: Show UiState pattern for complex apps
2. **Theme/styling guide**: Semantic style naming conventions
3. **Multi-file organization**: Example project structure for larger apps
4. **Per-frame arena pattern**: Memory management in view()
5. **Modal state machines**: Pattern for mode-based UIs

### Potential Features

1. **Theme struct example**: Optional semantic style wrapper
2. **Frame.arena()**: Expose per-frame allocator for temporary allocations
3. **InputField widget**: lazycurl's TextInput is well-designed - study for our text input widget

### Examples to Create

1. **Panel-based layout**: Multi-panel app like lazycurl structure
2. **Async operations**: Command pattern with polling (when we implement Commands)

---

## libvaxis Comparison

lazycurl uses libvaxis directly. Some capabilities they get:

- Kitty keyboard protocol (granular key events)
- System clipboard integration
- Bracketed paste
- Mouse input (clicks, drag, scroll)

**Gap analysis for zithril**:
- Mouse support: On our roadmap
- Clipboard: Could be useful, requires terminal support detection
- Kitty protocol: Advanced, nice-to-have

---

## Summary

lazycurl demonstrates solid patterns for building a real-world TUI application in Zig:

| Pattern | lazycurl | zithril | Action |
|---------|----------|---------|--------|
| State separation | UiState struct | User's choice | Document pattern |
| Theming | Centralized Theme | Direct Style | Add example |
| Components | File-per-panel | Widget structs | Add example |
| Frame allocation | Arena per frame | User manages | Consider Frame.arena() |
| Modes | Enum state machine | Manual | Document pattern |
| Async | Runtime struct | Planned Command | Learn from approach |

The biggest takeaway: as zithril matures, we should provide more guidance on how to structure larger applications. The core framework is minimal by design, but users need patterns for scaling up.
