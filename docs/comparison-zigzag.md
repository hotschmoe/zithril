# zithril vs zigzag -- TUI Framework Comparison

Detailed technical comparison of **zithril** (our framework) against **[zigzag](https://github.com/meszmate/zigzag)** (by meszmate, MIT licensed, created Jan 2026).

---

## Executive Summary

zithril and zigzag are both Zig TUI frameworks but take fundamentally different architectural approaches. zithril uses a **cell-grid immediate-mode** model (inspired by ratatui), while zigzag uses a **string-composition Elm architecture** (inspired by Go's Bubble Tea + Lipgloss). These differences ripple through every layer: rendering, layout, state management, and performance characteristics.

Neither is strictly "better" -- they optimize for different trade-offs. This document maps out where each has advantages and where zithril can learn from zigzag's design.

---

## 1. Architecture

```
ZITHRIL                              ZIGZAG
------                              ------
Event --> update(State) --> Action   Event --> Msg --> update(Model,Msg) --> Cmd
          view(State, Frame)                  view(Model) --> string
          frame.render(widget, area)          Program.render(hash-diff)
          buffer.diff(prev, curr)
          output(changed cells)               output(entire string if changed)
```

| Aspect | zithril | zigzag |
|--------|---------|--------|
| Pattern | Immediate mode | Elm Architecture (TEA) |
| View returns | void (renders into buffer) | `[]const u8` (styled string) |
| Rendering unit | Cell grid (char + style per cell) | ANSI-embedded strings |
| Side effects | Action enum (.none, .quit, .command) | Cmd union (quit, tick, batch, sequence, perform, terminal control) |
| State ownership | User owns state, passes pointer | User defines Model with required interface |

**Analysis**: zithril's immediate-mode approach is simpler to reason about for widget rendering -- you call `frame.render(widget, area)` and the widget writes cells. zigzag's TEA pattern introduces more ceremony (Model/Msg/Cmd types) but provides a richer side-effect vocabulary via `Cmd`. The `Cmd` system supports batching, sequencing, timers, and async operations that zithril's `Action` enum currently lacks.

**Takeaway**: zithril's `Action` type could benefit from richer command support (timers, batching, async operations) without abandoning the immediate-mode rendering model.

---

## 2. Rendering Pipeline

### zithril: Cell-Level Diffing

```
view() --> widgets write to Buffer (cell grid)
       --> diff(current_buf, previous_buf)
       --> emit ANSI for only changed cells
       --> cursor movement optimized for consecutive cells
```

- **Buffer**: Contiguous `[]Cell` array, row-major, `y * width + x` indexing
- **Cell**: `{ char: u21, style: Style, width: u8 }`
- **Diff**: O(W*H) scan, O(changes) output
- **Cursor optimization**: Skips cursor-move sequences for adjacent cells on the same row
- **Output**: Buffered via rich_zig's `DefaultOutput`, flushed once per frame

### zigzag: Hash-Based String Comparison

```
view() --> returns complete ANSI string
       --> hash(new_output) != hash(prev_output)?
       --> if changed: write entire output
       --> ANSI compression reduces escape sequence overhead
       --> synchronized output (DEC mode 2026) prevents tearing
```

- **Screen module**: Has a cell-based `renderDiff()`, but the primary `Program` path uses hash comparison
- **ANSI compression**: `StyleState` tracks current terminal state, emits only deltas
- **Sync output**: Wraps writes in `sync_start`/`sync_end` to batch terminal updates

### Performance Comparison

```
Scenario: 80x24 terminal (1920 cells), 10 cells change per frame

zithril:
  - Scan: 1920 cell comparisons
  - Output: ~10 cursor moves + ~10 style sets + ~10 chars
  - Bytes written: ~200-400 bytes

zigzag:
  - Hash: 1 hash comparison
  - Output: entire screen content re-rendered
  - Bytes written: ~2000-5000 bytes (compressed ANSI)

Scenario: Nothing changed

zithril:
  - Scan: 1920 cell comparisons
  - Output: 0 bytes (no diff)

zigzag:
  - Hash: 1 comparison, match
  - Output: 0 bytes (hash match)

Scenario: Full screen repaint (resize, theme change)

zithril:
  - Scan: 1920 cell comparisons
  - Output: ~1920 cells worth of ANSI
  - Bytes written: ~5000-10000 bytes

zigzag:
  - Hash: 1 comparison, mismatch
  - Output: entire screen string
  - Bytes written: ~2000-5000 bytes (compressed)
```

**Analysis**: zithril has a clear advantage for partial updates (the common case in interactive TUIs). zigzag has lower overhead for full repaints thanks to ANSI compression. For the no-change case, both are efficient.

**Takeaway**: zithril's cell-level diffing is the right architectural choice for TUI performance. However, we should consider adding synchronized output (DEC mode 2026) to prevent tearing on fast updates.

---

## 3. Layout System

### zithril: Constraint-Based Layout Solver

```zig
const chunks = frame.layout(area, .vertical, &.{
    Constraint.len(3),        // Fixed 3 rows
    Constraint.flexible(1),   // Fill remaining
    Constraint.len(1),        // Fixed 1 row
});
```

Constraint types: `length`, `min`, `max`, `flex`, `ratio`, `percentage`

Flex alignment: `.start`, `.end_`, `.center`, `.space_between`, `.space_around`, `.space_evenly`, `.legacy`

Features:
- Returns `BoundedRects` array matching constraint count
- Layout cache within frame (comptime-sized)
- Supports vertical and horizontal direction
- Flex alignment modes for distributing excess space

### zigzag: String Joining + Placement

```zig
// Horizontal composition
const row = zz.joinHorizontal(.top, &.{ left_panel, right_panel });

// Vertical stacking
const page = zz.joinVertical(.left, &.{ header, body, footer });

// Absolute placement
const output = zz.place(80, 24, .center, .middle, content);

// Float-based positioning
const placed = zz.placeFloat(80, 24, 0.5, 0.5, dialog);

// Overlay compositing
const composited = zz.overlay(background, foreground);
```

No constraints, no solver. Layout is manual string manipulation:
- `joinHorizontal()` / `joinVertical()` -- concatenate rendered blocks
- `place()` / `placeFloat()` / `placeAt()` -- position in a box
- `overlay()` -- composite with transparency (spaces)
- ANSI-aware `width()` / `height()` measurement

### Comparison

| Feature | zithril | zigzag |
|---------|---------|--------|
| Constraint solver | Yes (6 constraint types) | No |
| Flex distribution | Yes (7 alignment modes) | No |
| Composition model | Rect subdivision | String joining |
| Nested layouts | Yes (recursive) | Yes (nested joins) |
| Absolute positioning | Via geometry | `placeAt()`, `placeFloat()` |
| Overlay/compositing | Not built-in | `overlay()` function |
| Width measurement | Via rich_zig | Built-in ANSI-aware |
| Caching | Yes (frame-level) | No (strings are transient) |

**Analysis**: zithril's constraint system is significantly more powerful for complex layouts. Flex modes, ratio constraints, and percentages enable responsive UIs without manual calculation. zigzag's approach is simpler and more flexible for ad-hoc layouts but requires manual sizing for anything complex.

zigzag's `overlay()` and `placeFloat()` are interesting capabilities we lack. Overlay compositing in particular is useful for dialogs and popups.

**Takeaway**: zithril's layout system is a strength. Consider adding overlay/compositing support for popup/dialog use cases.

---

## 4. Styling

### zithril

Style wraps rich_zig's Style type. Applied per-cell in the buffer.

```zig
const style = Style{ .fg = .yellow, .bold = true };
buf.set_string(area.x, area.y, text, style);
```

Color support determined by rich_zig's terminal detection.

### zigzag

Fluent builder pattern with extensive properties:

```zig
const style = zz.Style{}
    .bold(true)
    .fg(zz.Color.cyan())
    .paddingAll(1)
    .marginAll(2)
    .marginBackground(zz.Color.gray(3))
    .borderAll(zz.Border.rounded)
    .width(40)
    .alignH(.center);

const output = try style.render(allocator, "Hello");
```

**Key difference**: zigzag's Style handles layout (padding, margin, borders, sizing, alignment) in addition to visual attributes. In zithril, these responsibilities are split between Style (visual), Block (borders), Spacing (padding/margin), and the layout system (sizing).

| Feature | zithril | zigzag |
|---------|---------|--------|
| Text attributes | bold, dim, italic, underline, blink, reverse, strikethrough | Same set |
| Colors | 16 ANSI, 256, RGB (via rich_zig) | Same + adaptive colors, hex parsing, contrast ratio |
| Borders in style | No (Block widget) | Yes (14 border styles, per-side control) |
| Padding in style | No (Spacing type) | Yes (per-side) |
| Margin in style | No (Spacing type) | Yes (per-side with background color) |
| Sizing in style | No (layout constraints) | Yes (width, height, max_width, max_height) |
| Alignment in style | No (per-widget) | Yes (horizontal + vertical) |
| Range styling | No | `renderWithRanges()`, `renderWithHighlights()` |
| Style inheritance | No | `inherit()` fills unset values from parent |
| Adaptive colors | No | Yes (auto-degrade by terminal capability) |
| Contrast ratio | No | WCAG-compliant `contrastRatio()` |
| Color interpolation | No | `interpolateColor()` for gradients |

**Analysis**: zigzag's Style-as-layout approach is convenient for the string-composition model but conflates concerns. zithril's separation of style/layout/borders is cleaner architecturally but requires more types to accomplish the same visual result.

zigzag's color utilities (adaptive colors, contrast ratio, hex parsing, interpolation) are genuinely useful features we lack.

**Takeaway**: Consider adding to rich_zig: adaptive colors, hex color parsing, contrast ratio calculation, and color interpolation. These are terminal-primitive features that belong in the rendering layer.

---

## 5. Widget / Component Comparison

### Widget Count

| Category | zithril | zigzag |
|----------|---------|--------|
| Container/Border | Block | (via Style borders) |
| Text display | Text, Paragraph, BigText | (via styled strings) |
| Lists | List, ScrollableList | List (generic, fuzzy filter) |
| Tables | Table | Table (compile-time + dynamic) |
| Input | TextInput | TextInput, TextArea |
| Navigation | Tabs, Menu | Paginator, Help, KeyBinding |
| Progress | Gauge, LineGauge | Progress (gradient presets) |
| Animation | (animation module) | Spinner (15+ styles) |
| Data viz | Sparkline, BarChart, Chart | Sparkline |
| Scrolling | Scrollbar, ScrollView | Viewport |
| Tree | Tree | Tree (generic) |
| Calendar | Calendar | -- |
| Canvas | Canvas | -- |
| Code | CodeEditor | -- |
| Notifications | -- | Notification (toast system) |
| Dialogs | -- | Confirm (yes/no) |
| File system | -- | FilePicker |
| Timer | -- | Timer (countdown/stopwatch) |
| Styled lists | -- | StyledList (bullet/numbered/roman) |
| **Total** | **22** | **17** |

### Widget Design Philosophy

**zithril widgets**: Stateless render functions. Widget is a struct with config + `render(area, buf)`. All state is external.

```zig
// zithril: widget has no state, renders into buffer
const list = List{
    .items = state.items,
    .selected = state.selected,
    .highlight_style = Style{ .fg = .yellow },
};
frame.render(list, area);
```

**zigzag components**: Stateful structs with `init/handleKey/view/deinit`. Each component manages its own internal state (cursor position, scroll offset, filter text, etc.).

```zig
// zigzag: component owns state, returns string
var list = zz.List(MyItem).init(allocator);
list.setItems(items);
// In update:
if (list.handleKey(key)) |selected| { ... }
// In view:
const rendered = list.view(allocator);
```

**Analysis**: zithril's stateless widgets are simpler and more composable -- you can render them anywhere without lifecycle management. zigzag's stateful components are more self-contained and handle their own input, reducing boilerplate in the Model's update function.

Neither approach is strictly better. Stateless widgets give more control; stateful components give more convenience. Many TUI frameworks offer both patterns.

### Notable zigzag Components We Lack

1. **TextArea** -- Multi-line editor with line numbers, word wrap, viewport scrolling. We have CodeEditor but not a general-purpose multi-line input.
2. **FilePicker** -- Directory traversal with filtering, sorting, hidden file toggle. Useful for file-selection UIs.
3. **Spinner** -- 15+ animation styles (dots, braille, globe, moon, etc.). Our animation module has easing functions but no spinner widget.
4. **Notification** -- Toast notifications with severity, auto-dismiss. Useful for status feedback.
5. **Confirm** -- Simple yes/no dialog. Trivial to build but useful as a standard component.
6. **Timer** -- Countdown/stopwatch with threshold-based color changes.

**Takeaway**: The component gaps are more about convenience than capability. Our immediate-mode architecture can implement any of these. Priority candidates: Spinner (common need) and FilePicker (complex to build from scratch).

---

## 6. Event & Input Handling

| Feature | zithril | zigzag |
|---------|---------|--------|
| Keyboard parsing | CSI, SS3, Alt, UTF-8, control chars | Same + Kitty keyboard protocol |
| Mouse parsing | X10 + SGR | SGR only |
| Mouse events | down, up, drag, move, scroll_up, scroll_down | press, release, drag, move, scroll (4-way), extended buttons 8-11 |
| Modifiers | ctrl, alt, shift (packed struct) | shift, alt, ctrl, super (Kitty) |
| Bracketed paste | Parsed (flag in Input) | Parsed + delivered to Model.Msg.paste field |
| Key release events | No | Yes (Kitty protocol) |
| Message filtering | No | `setFilter()` for global event interception |
| Focus events | No | Yes (terminal focus in/out) |
| Suspend/resume | No | Yes (SIGSTOP + terminal re-init) |
| Input batching | Single event per poll | `parseAll()` for batch processing |

**Analysis**: zigzag has broader input protocol support. Kitty keyboard protocol enables key release detection and the super modifier, which are valuable for complex keybinding schemes. Focus events and suspend/resume improve the application lifecycle story.

**Takeaway**: Consider adding Kitty keyboard protocol support and suspend/resume handling. These are meaningful capability gaps.

---

## 7. Command / Side-Effect System

### zithril

```zig
pub const Action = enum {
    none,
    quit,
    command,  // Defined but not implemented in runtime
};
```

Minimal. Quit or continue. Command is reserved but unimplemented.

### zigzag

```zig
Cmd(Msg) = union {
    none, quit,
    tick: u64,                    // One-shot delay
    every: u64,                   // Repeating interval
    batch: []const Cmd(Msg),      // Concurrent execution
    sequence: []const Cmd(Msg),   // Sequential execution
    msg: Msg,                     // Dispatch message
    perform: *const fn() ?Msg,    // Execute function
    enable_mouse, disable_mouse,
    show_cursor, hide_cursor,
    enter_alt_screen, exit_alt_screen,
    suspend_process,
    set_title: []const u8,
    println: []const u8,          // Print above TUI output
};
```

Rich vocabulary for scheduling, batching, and terminal control.

**Analysis**: This is zigzag's biggest architectural advantage. The `Cmd` system allows:
- **Timer-based updates** without manual tick management
- **Batched/sequenced commands** for complex workflows
- **Terminal control** from update logic (toggle mouse, cursor, alt screen)
- **Side-effect isolation** -- update functions remain pure, side effects are declarative

zithril's tick system requires configuration at app init. zigzag allows dynamic timer creation from any update call.

**Takeaway**: This is a clear gap. Expanding `Action` (or introducing a `Command` type) to support timers, batching, and terminal control would significantly improve zithril's flexibility. This aligns with our roadmap item "Command/async pattern."

---

## 8. Memory Management

| Aspect | zithril | zigzag |
|--------|---------|--------|
| Allocator model | Single allocator passed to `app.run()` | Dual: arena (per-frame) + persistent |
| Per-frame allocations | None (widgets are stateless, buffer pre-allocated) | Many (view returns allocated strings) |
| Deallocation | Explicit (buffer resize/cleanup) | Arena reset per frame (bulk free) |
| Buffer memory | `W * H * sizeof(Cell)` fixed | String-based (variable, depends on content) |
| Widget allocations | Zero | Component init allocates internal state |
| Worst case per frame | O(1) -- no allocations | O(content) -- all view strings allocated |

### Memory Footprint Estimate (80x24 terminal)

```
zithril:
  2 buffers * 1920 cells * ~16 bytes/cell  = ~61 KB
  1 update array * 1920 * ~8 bytes          = ~15 KB
  Total baseline: ~76 KB

zigzag:
  Arena allocator overhead                  = ~4 KB
  Per-frame string allocations (typical)    = ~10-50 KB
  Component state (varies)                  = ~1-10 KB
  Total baseline: ~15-64 KB (varies per frame)
```

**Analysis**: zithril has predictable, fixed memory usage. zigzag's arena approach trades predictability for convenience -- view functions can freely allocate without tracking lifetimes, but memory usage varies per frame.

zithril's zero-allocation widget rendering is a genuine advantage for embedded or constrained environments. zigzag's arena pattern is more ergonomic for string-heavy composition.

**Takeaway**: zithril's memory model is a strength. The fixed-allocation, zero-per-frame-allocation approach is better suited for long-running TUI applications.

---

## 9. Platform Support

| Feature | zithril | zigzag |
|---------|---------|--------|
| Linux | Yes | Yes |
| macOS | Yes (POSIX) | Yes (POSIX) |
| Windows | Partial (via rich_zig) | Yes (Console API + VT sequences) |
| Terminal detection | Via rich_zig | Built-in (13 terminal types) |
| Color profile detection | Via rich_zig | Built-in (env vars: NO_COLOR, COLORTERM, TERM) |
| Dark/light detection | No | `hasDarkBackground()` |
| Synchronized output | No | Yes (DEC mode 2026) |
| Panic cleanup | Yes (terminal_panic handler) | Yes (similar) |
| Dependencies | rich_zig | None (zero dependencies) |

**Analysis**: zigzag's zero-dependency approach means all terminal handling is self-contained. zithril delegates to rich_zig, which is fine since we own that dependency, but means terminal capability improvements require upstream changes.

zigzag's terminal type detection (13 known terminals with per-terminal capability flags) is more granular than our approach.

**Takeaway**: Consider adding synchronized output support. Dark/light background detection would be useful for adaptive theming.

---

## 10. Expected Performance Comparison

### Frame Rendering (the hot path)

| Metric | zithril | zigzag |
|--------|---------|--------|
| View cost | Widget renders into buffer cells | String allocation + concatenation + ANSI embedding |
| Diff cost | O(W*H) cell comparison | O(1) hash comparison |
| Output cost (partial update) | O(changed_cells) | O(total_screen) |
| Output cost (no change) | O(W*H) scan, 0 bytes out | O(1) hash, 0 bytes out |
| Output cost (full repaint) | O(W*H) cells | O(total_screen) compressed |
| Memory churn per frame | Zero allocations | Arena allocations + bulk reset |
| I/O efficiency | Minimal bytes (only diffs) | ANSI compression reduces redundancy |

### Scaling Behavior

```
Terminal size: 200x50 (10,000 cells), 50 cells change

zithril:
  Diff scan: 10,000 comparisons (~fast, cache-friendly contiguous array)
  Output: ~50 updates, ~1-2 KB written

zigzag:
  Hash: 1 comparison
  Output: ~10,000 cells of content, ~10-25 KB written (compressed)
  Ratio: ~10-25x more I/O than zithril for small changes
```

For large terminals with small per-frame changes (the typical interactive TUI case), zithril's cell-level diffing produces dramatically less terminal I/O. This matters for:
- **SSH sessions** with limited bandwidth
- **Slow terminals** (serial, embedded)
- **High refresh rates** where minimizing output reduces latency

For applications that repaint the entire screen every frame (dashboards, animations), the gap narrows and zigzag's ANSI compression may partially compensate.

### CPU Overhead

zithril's cell comparison loop is branch-heavy but data-local (contiguous array scan). zigzag's string composition involves more pointer chasing and allocator interaction, but the arena reset is O(1).

**Expected winner**: zithril for interactive TUIs with localized updates. zigzag for full-screen refresh scenarios where hash-skip is the dominant optimization.

---

## 11. Feature Gap Summary

### Features zigzag Has That zithril Lacks

| Feature | Priority | Effort | Notes |
|---------|----------|--------|-------|
| Rich command/side-effect system | **High** | Medium | Aligns with roadmap "Command/async pattern" |
| Synchronized output (DEC 2026) | **High** | Low | Prevents tearing, easy to add |
| Kitty keyboard protocol | Medium | Medium | Key release events, super modifier |
| Adaptive colors | Medium | Low | Upstream to rich_zig |
| Color hex parsing | Low | Low | Upstream to rich_zig |
| Color interpolation/gradients | Low | Low | Upstream to rich_zig |
| Spinner widget | Medium | Low | Simple animation widget |
| FilePicker component | Low | Medium | Useful but niche |
| Notification/toast system | Low | Low | Easy to build |
| Suspend/resume (SIGSTOP) | Medium | Low | Lifecycle improvement |
| Dark background detection | Low | Low | Useful for adaptive themes |
| Message filtering | Low | Low | Global event interception |
| Focus events | Low | Low | Terminal focus in/out |
| WCAG contrast ratio | Low | Low | Accessibility utility |

### Features zithril Has That zigzag Lacks

| Feature | Notes |
|---------|-------|
| Cell-level diffing | Fundamental architecture advantage |
| Constraint-based layout solver | 6 constraint types + 7 flex modes |
| Canvas widget | Generic drawing surface |
| Chart widget | Line/scatter plots |
| BarChart widget | Grouped bar charts |
| Calendar widget | Month display |
| BigText widget | Large pixel font rendering |
| CodeEditor widget | Syntax-highlighted editing |
| Graphics protocols | Sixel, Kitty, iTerm2 image support |
| Animation/easing framework | Easing functions + animation state |
| Testing framework | Record/replay + mock backend |
| Layout caching | Frame-level cache for layout results |

---

## 12. Architectural Lessons

### What We Can Learn from zigzag

1. **Command system**: The `Cmd` pattern for side effects is well-designed. We should expand our `Action` type to support timers, batching, and terminal control declaratively.

2. **Synchronized output**: Wrapping frame renders in DEC mode 2026 is a simple, high-value addition that prevents visual tearing.

3. **Color utilities**: Adaptive colors, hex parsing, contrast ratios, and interpolation belong in our rendering layer (rich_zig).

4. **Component convenience**: Some users want pre-built stateful components (text input with cursor management, list with filtering). We can offer these alongside our stateless widget model.

5. **Overlay compositing**: The `overlay()` function for layering content (dialogs, popups, floating panels) is a layout capability we should consider.

### Where zithril's Approach is Stronger

1. **Cell-level diffing**: Our rendering pipeline is fundamentally more efficient for the common TUI case (localized updates). This is the right architectural choice.

2. **Constraint-based layout**: Our layout solver is more powerful and easier to use for complex, responsive layouts than manual string joining.

3. **Zero-allocation rendering**: Stateless widgets that write directly to a buffer avoid per-frame memory churn entirely.

4. **Separation of concerns**: Style, layout, borders, and widgets are distinct concepts. zigzag's "style does everything" approach is convenient but conflates responsibilities.

5. **Data visualization**: Chart, BarChart, Canvas, and Sparkline give us stronger data visualization capabilities.

6. **Testing infrastructure**: Record/replay and mock backends enable automated TUI testing. zigzag has no testing framework.

---

## 13. Recommendations

### Immediate (Low Effort, High Value)

1. Add **synchronized output** (DEC mode 2026) to the rendering pipeline
2. File upstream issue on rich_zig for **adaptive colors** and **hex color parsing**

### Short Term (Aligns with Roadmap)

3. Design and implement a **Command/side-effect system** expanding `Action` to support timers, batching, terminal control
4. Add **suspend/resume** handling (SIGSTOP + terminal re-initialization)
5. Build a **Spinner widget** (animation + comptime style definitions)

### Medium Term

6. Add **Kitty keyboard protocol** support for key release events
7. Add **overlay/compositing** support in the layout system for popups/dialogs
8. Build a **FilePicker** component
9. Upstream **color interpolation** and **contrast ratio** to rich_zig

### Not Recommended

- Switching to string-based rendering (our cell-grid diffing is architecturally superior for TUI use cases)
- Adopting the full Elm architecture (our immediate-mode approach is simpler with equivalent capability)
- Adding layout-in-style (our separation of layout/style/widgets is cleaner)
