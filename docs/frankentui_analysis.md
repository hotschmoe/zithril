# FrankenTUI Analysis: Lessons for zithril

*Deep dive into the Rust TUI kernel and what we can adopt for our Zig framework.*

**Repository**: https://github.com/Dicklesworthstone/frankentui

---

## Executive Summary

FrankenTUI is a Rust TUI kernel that positions itself as a minimal, high-performance foundation rather than a full framework. It emphasizes **correctness over cleverness**, **deterministic output**, and **layered architecture**. While zithril shares many of these values, FrankenTUI offers several patterns worth considering for adoption.

**Key takeaways:**
1. Inline mode (preserve scrollback while rendering UI) - unique differentiator
2. Bayesian diff strategy selection - adaptive performance optimization
3. Frame abstraction (hit grid, cursor, degradation hints) - richer render context
4. RAII terminal cleanup with panic safety - robust lifecycle management
5. Command pattern for side effects - clean async integration
6. One-writer rule - prevents race conditions and flicker

---

## 1. Architecture Comparison

### FrankenTUI: 15-Crate Workspace

```
ftui              - Public facade + prelude
ftui-core         - Terminal lifecycle, events, capabilities, RAII guards
ftui-render       - Buffer, diff, ANSI presenter
ftui-style        - Style + theme system
ftui-text         - Spans, segments, rope editor
ftui-layout       - Flex + Grid constraint solvers
ftui-runtime      - Elm/Bubbletea-style runtime loop
ftui-widgets      - Core widget library
ftui-extras       - Feature-gated add-ons
...
```

### zithril: Monolithic Library

```
src/
  App.zig         - Event loop, terminal setup/teardown
  Frame.zig       - Layout methods, render dispatch
  Layout.zig      - Constraint solver
  Buffer.zig      - Cell grid with diff support
  widgets/        - Block, List, Table, Gauge, Text...
```

**Assessment**: Our monolithic structure is appropriate for a Zig library. The Rust workspace pattern exists partly to manage Cargo compilation boundaries. We should keep our single-module approach but ensure clear internal layering.

---

## 2. Event Loop Architecture

### FrankenTUI: Elm/Bubbletea Model

```
Event --> Model::update() --> Cmd<Message> --> Model::view() --> Render
  ^                                                                |
  |________________________________________________________________|
```

The Model trait requires four methods:
- `init()` - Initial setup, returns commands
- `update(msg)` - State transitions, returns commands
- `view(frame)` - Render current state
- `subscriptions()` - Declare continuous event sources

### zithril: Direct Callbacks

```
Event --> update(state, event) --> Action --> view(state, frame) --> Render
```

Our callbacks are simpler:
- `update(state, event) -> Action`
- `view(state, frame) -> void`

**Lessons to adopt:**

1. **Subscriptions pattern**: We could add optional subscription support for periodic events without requiring the user to manage timers manually.

2. **Cmd pattern for async**: Instead of just `.quit` and `.none` actions, we could add:
   - `.command(fn)` - Execute async operation
   - `.batch([actions])` - Multiple operations
   - `.sequence([actions])` - Ordered operations

**Proposed extension:**
```zig
const Action = union(enum) {
    none,
    quit,
    command: fn () Action,           // Deferred execution
    tick: u64,                       // Request tick in N ms
    log: []const u8,                 // Write to scrollback (inline mode)
};
```

---

## 3. Rendering Pipeline

### FrankenTUI: Multi-Stage Pipeline

```
view() --> Frame --> Buffer --> BufferDiff --> Presenter --> ANSI
```

Key innovations:
1. **Frame abstraction** - Not just a buffer wrapper
2. **Deterministic diff** - Computes exact cell changes
3. **Presenter with state tracking** - Minimizes ANSI escape codes
4. **Synchronized output** - DEC 2026 brackets prevent tearing

### zithril: Buffer-Direct Rendering

```
view() --> Frame --> Buffer --> diff --> Terminal
```

**Lessons to adopt:**

### 3.1 Frame as Rich Context

FrankenTUI's Frame provides:
```rust
frame.buffer         // Cell grid
frame.hit_grid       // Mouse hit testing
frame.cursor_position
frame.cursor_visible
frame.degradation    // Performance budget
```

Our Frame could expand from layout-only to include:
```zig
pub const Frame = struct {
    buffer: *Buffer,

    // New: interaction context
    hit_regions: HitGrid,
    cursor: ?struct { x: u16, y: u16, visible: bool },

    // New: performance hints
    degradation: DegradationLevel,

    // Existing
    pub fn layout(...) ...
    pub fn render(...) ...
};
```

### 3.2 Hit Grid for Mouse

```zig
const HitRegion = struct {
    rect: Rect,
    widget_id: u64,
    tag: enum { content, border, scrollbar },
    data: u64,  // Custom payload (e.g., list item index)
};

// During render:
frame.register_hit(rect, widget_id, .content, item_index);

// During event handling:
if (event == .mouse) {
    if (frame.hit_grid.get(event.mouse.x, event.mouse.y)) |hit| {
        // Route to appropriate widget
    }
}
```

### 3.3 Degradation Levels

Adaptive rendering under performance pressure:
```zig
const DegradationLevel = enum {
    full,           // All visual effects
    limited,        // Skip animations, reduce detail
    essential_only, // Only critical content
};

// Widget checks during render:
pub fn render(self: MyWidget, area: Rect, buf: *Buffer) void {
    if (buf.degradation.applyStyles()) {
        // Full visual fidelity
    } else {
        // Minimal rendering
    }
}
```

---

## 4. Diff Strategy Selection

### FrankenTUI: Bayesian Adaptive Selection

```
DiffStrategy enum:
  Full           - Full buffer comparison
  DirtyRows      - Skip clean rows (marked during mutations)
  FullRedraw     - Redraw entire screen
  FullWithReset  - Full diff + reset color state
```

A **Bayesian strategy selector**:
- Tracks historical change rates via Beta posterior
- Dynamically chooses cheapest strategy based on evidence
- Resets on terminal resize

### zithril: Static Diff

We currently do a simple cell-by-cell comparison.

**Lessons to adopt:**

### 4.1 Dirty Row Tracking

O(1) mutation marking, O(height) space overhead:
```zig
const Buffer = struct {
    cells: [][]Cell,
    dirty_rows: DynamicBitSet,  // Track which rows changed

    pub fn set(self: *Buffer, x: u16, y: u16, cell: Cell) void {
        if (!self.cells[y][x].eql(cell)) {
            self.cells[y][x] = cell;
            self.dirty_rows.set(y);
        }
    }
};
```

### 4.2 Change Rate Tracking

Simple heuristic without full Bayesian machinery:
```zig
const DiffConfig = struct {
    recent_change_rates: [8]f32,  // Rolling window
    rate_index: u8,

    pub fn recordFrame(self: *DiffConfig, changed: usize, total: usize) void {
        self.recent_change_rates[self.rate_index] = @as(f32, changed) / @as(f32, total);
        self.rate_index = (self.rate_index + 1) % 8;
    }

    pub fn selectStrategy(self: DiffConfig) DiffStrategy {
        const avg = average(self.recent_change_rates);
        if (avg > 0.5) return .full_redraw;
        if (avg < 0.1) return .dirty_rows;
        return .full_diff;
    }
};
```

---

## 5. Inline Mode

### FrankenTUI's Unique Feature

Preserves terminal scrollback while UI stays stable:
```
+------------------------------------------+
| $ previous command output                | <- Scrollable history
| $ another command                        |
| Some log messages...                     |
+==========================================+
| [Fixed UI Chrome]                        | <- Stays in place
| Status: Running                          |
+==========================================+
```

Implementation:
- Uses DEC cursor save/restore (ESC 7 / ESC 8)
- Scroll region management for log output
- Auto-height variant for dynamic UI sizing

Screen modes:
```rust
enum ScreenMode {
    AltScreen,                      // Traditional full-screen
    Inline { ui_height: u16 },      // Fixed height inline
    InlineAuto { min: u16, max: u16 }, // Dynamic height
}
```

**Assessment for zithril:**

Inline mode solves the "logs + UI" problem elegantly. This is valuable for:
- Build tools showing progress + scrolling logs
- Monitoring dashboards preserving history
- Interactive CLIs with persistent context

**Proposed implementation:**
```zig
const ScreenMode = union(enum) {
    alt_screen,
    inline_fixed: u16,           // Fixed UI height
    inline_auto: struct { min: u16, max: u16 },
};

const AppConfig = struct {
    state: *State,
    update: UpdateFn,
    view: ViewFn,
    screen_mode: ScreenMode = .alt_screen,  // New
};
```

---

## 6. Terminal Lifecycle (RAII)

### FrankenTUI: Guaranteed Cleanup

```rust
pub struct TerminalSession {
    alt_screen: bool,
    mouse_enabled: bool,
    bracketed_paste: bool,
    focus_events: bool,
    // Drop impl guarantees cleanup in reverse order
}
```

Features:
- Cleanup during panic unwinding
- Signal handling (SIGINT, SIGTERM, SIGWINCH)
- Features disabled in reverse order of enablement
- Stdout flushes immediately after raw mode exit

### zithril: Manual Cleanup

We use `defer` blocks in the App run method.

**Lessons to adopt:**

### 6.1 Panic-Safe Cleanup

Zig's `errdefer` and `defer` can achieve similar guarantees:
```zig
pub fn run(self: *App, allocator: Allocator) !void {
    const terminal = try Terminal.init();
    errdefer terminal.deinit();  // Cleanup on error
    defer terminal.deinit();     // Cleanup on success

    // Event loop...
}
```

### 6.2 Feature Tracking

```zig
const TerminalFeatures = struct {
    raw_mode: bool = false,
    alt_screen: bool = false,
    mouse: bool = false,
    bracketed_paste: bool = false,

    pub fn deinit(self: *TerminalFeatures) void {
        // Disable in reverse order
        if (self.bracketed_paste) disableBracketedPaste();
        if (self.mouse) disableMouse();
        if (self.alt_screen) leaveAltScreen();
        if (self.raw_mode) leaveRawMode();
    }
};
```

---

## 7. Widget System Comparison

### FrankenTUI: Borrowed Widgets

```rust
pub trait Widget {
    fn render(&self, area: Rect, frame: &mut Frame);
    fn is_essential(&self) -> bool { false }
}
```

Widgets are **borrowed** (`&self`), not consumed.

### zithril: Value Widgets

```zig
pub fn render(self: MyWidget, area: Rect, buf: *Buffer) void {
    // ...
}
```

Widgets are passed by value (or pointer for large structs).

**Assessment**: Our approach is fine for Zig. The Rust pattern exists because ownership semantics make consumed widgets inconvenient. Zig's explicit value vs pointer semantics work well.

### 7.1 Widget Categories

FrankenTUI categorizes widgets by capability:
1. **Buffer-only**: Simple rendering (Block, Paragraph)
2. **Interactive**: Hit registration (List, Table)
3. **Input**: Cursor control (TextInput)
4. **Adaptive**: Degradation-aware (ProgressBar)

**Lesson**: Document which widgets support which features. Consider:
```zig
pub const WidgetCapabilities = struct {
    supports_focus: bool = false,
    supports_mouse: bool = false,
    supports_degradation: bool = false,
};
```

---

## 8. Layout System Comparison

### FrankenTUI: 9 Constraint Types

```rust
enum Constraint {
    Fixed(u16),
    Percentage(f32),
    Min(u16),
    Max(u16),
    Ratio(u32, u32),
    Fill,
    FitContent,
    FitContentBounded { min, max },
    FitMin,
}
```

Additional features:
- Grid layout with cell spanning
- Gap and margin support
- Intrinsic sizing via measurer callbacks
- RTL support

### zithril: 5 Constraint Types

```zig
const Constraint = union(enum) {
    length: u16,     // Exactly N
    min: u16,        // At least N
    max: u16,        // At most N
    flex: u16,       // Proportional (flex-grow)
    ratio: struct { a: u16, b: u16 },
};
```

**Lessons to adopt:**

### 8.1 Content-Based Sizing

FrankenTUI's `FitContent` allows widgets to declare preferred sizes:
```rust
flex.split_with_measurer(area, |idx, available| {
    LayoutSizeHint { min: 5, preferred: 20, max: Some(50) }
})
```

**Proposed addition:**
```zig
const Constraint = union(enum) {
    // Existing
    length: u16,
    min: u16,
    max: u16,
    flex: u16,
    ratio: struct { a: u16, b: u16 },

    // New
    fit_content,                          // Size to widget preference
    fit_bounded: struct { min: u16, max: u16 },
};

const SizeHint = struct {
    min: u16,
    preferred: u16,
    max: ?u16,
};

// Layout with measurer
pub fn layoutWithMeasurer(
    frame: *Frame,
    area: Rect,
    direction: Direction,
    constraints: []const Constraint,
    measurer: fn (index: usize, available: u16) SizeHint,
) []Rect {
    // ...
}
```

### 8.2 Grid Layout

Two-dimensional layout with spanning:
```zig
const GridLayout = struct {
    rows: []const Constraint,
    cols: []const Constraint,
    row_gap: u16 = 0,
    col_gap: u16 = 0,

    pub fn cell(self: GridLayout, row: usize, col: usize) Rect { ... }
    pub fn span(self: GridLayout, row: usize, col: usize, rowspan: usize, colspan: usize) Rect { ... }
};
```

---

## 9. Styling and Theming

### FrankenTUI: Sophisticated System

- **AdaptiveColor**: Light/dark mode switching
- **WCAG compliance**: Contrast ratio calculation
- **StyleSheet**: Named styles via StyleId
- **ThemeBuilder**: Semantic color slots

### zithril: Basic Styling

We use rich_zig's Style and Color types directly.

**Lessons to adopt:**

### 9.1 Theme System

```zig
const Theme = struct {
    primary: Color,
    secondary: Color,
    background: Color,
    foreground: Color,
    border: Color,
    highlight: Color,
    error_color: Color,
    warning: Color,
    success: Color,
};

const default_theme = Theme{
    .primary = .cyan,
    .secondary = .magenta,
    .background = .black,
    .foreground = .white,
    // ...
};
```

### 9.2 Semantic Styles

```zig
const SemanticStyle = enum {
    normal,
    highlighted,
    selected,
    disabled,
    error_style,
    warning,
    success,

    pub fn resolve(self: SemanticStyle, theme: Theme) Style {
        return switch (self) {
            .highlighted => Style{ .fg = theme.highlight, .bold = true },
            .error_style => Style{ .fg = theme.error_color },
            // ...
        };
    }
};
```

---

## 10. Performance Optimizations

### FrankenTUI Techniques

1. **16-byte cells** - 4 cells per cache line (SIMD-friendly)
2. **Dirty row tracking** - Skip unchanged rows
3. **Grapheme pooling** - String interning
4. **Presenter cost model** - DP for cursor positioning
5. **Allocation budget** - Triggers degradation if exceeded
6. **Double buffering** - Pointer swap, not reallocation

### Applicable to zithril

**Already implemented:**
- Cell-based buffer with diff

**Consider adopting:**

### 10.1 Cell Size Alignment

```zig
const Cell = extern struct {
    char: [4]u8,    // UTF-8 grapheme (or index for complex)
    fg: u8,         // Color index
    bg: u8,
    flags: u8,      // Bold, italic, etc.
    _pad: u8,       // Align to 8 bytes
};
// 8 cells per 64-byte cache line
```

### 10.2 Allocation Budget

```zig
const RenderBudget = struct {
    max_allocations: usize,
    current_allocations: usize,

    pub fn exceeded(self: RenderBudget) bool {
        return self.current_allocations > self.max_allocations;
    }
};
```

---

## 11. One-Writer Rule

### FrankenTUI's Pattern

All terminal output goes through a single `TerminalWriter`:
- Serializes UI renders and log writes
- Enforces atomicity per operation
- 64KB internal buffer for batching

**Why this matters:**
- Prevents race conditions between update and render
- Eliminates partial frame display
- Enables synchronized output (DEC 2026)

**Lesson for zithril:**

Ensure all terminal output goes through a single path:
```zig
const TerminalWriter = struct {
    buffer: [64 * 1024]u8,
    pos: usize = 0,

    pub fn write(self: *TerminalWriter, bytes: []const u8) void {
        // Buffer writes, flush when full or on commit
    }

    pub fn commit(self: *TerminalWriter) !void {
        // Atomic flush to stdout
        try std.io.getStdOut().writeAll(self.buffer[0..self.pos]);
        self.pos = 0;
    }
};
```

---

## 12. Testing Infrastructure

### FrankenTUI Features

- **ProgramSimulator**: Deterministic replay-based testing
- **Snapshot testing**: Expected buffer outputs
- **Evidence logs**: JSON diagnostics for diff decisions
- **No mocks policy**: Real terminal backends

### Lessons for zithril

```zig
const TestFrame = struct {
    buffer: Buffer,
    events: []Event,

    pub fn sendKey(self: *TestFrame, key: KeyCode) void {
        self.events.append(.{ .key = key });
    }

    pub fn expectCell(self: TestFrame, x: u16, y: u16, char: u21) !void {
        try std.testing.expectEqual(char, self.buffer.get(x, y).char);
    }

    pub fn snapshot(self: TestFrame) []const u8 {
        // Render buffer to string for snapshot comparison
    }
};
```

---

## 13. Recommended Adoption Priority

### High Priority (Significant Value)

1. **Hit Grid for Mouse** - Essential for proper mouse support
2. **Dirty Row Tracking** - Low-cost performance win
3. **Frame Context Expansion** - Richer render environment
4. **Theme System** - Better styling abstraction

### Medium Priority (Nice to Have)

5. **Inline Mode** - Unique capability, specific use cases
6. **Degradation Levels** - Adaptive rendering
7. **Content-Based Sizing** - FitContent constraint
8. **One-Writer Rule** - Robustness

### Low Priority (Consider Later)

9. **Grid Layout** - More complex, less common
10. **Subscription Pattern** - Adds complexity
11. **Bayesian Diff Selection** - Over-engineering for now
12. **State Persistence** - Application concern

---

## 14. Implementation Roadmap

### Phase 1: Frame Enhancement

```zig
// Expand Frame with hit testing and cursor control
pub const Frame = struct {
    buffer: *Buffer,
    hit_regions: std.ArrayList(HitRegion),
    cursor: ?CursorState,

    pub fn registerHit(self: *Frame, rect: Rect, widget_id: u64, data: u64) void;
    pub fn setCursor(self: *Frame, x: u16, y: u16, visible: bool) void;
};
```

### Phase 2: Dirty Row Optimization

```zig
// Add dirty tracking to Buffer
pub const Buffer = struct {
    cells: [][]Cell,
    dirty: DynamicBitSet,

    pub fn set(self: *Buffer, x: u16, y: u16, cell: Cell) void;
    pub fn clearDirty(self: *Buffer) void;
    pub fn isDirty(self: *Buffer, row: u16) bool;
};
```

### Phase 3: Theme System

```zig
// Add theming to rich_zig or zithril
pub const Theme = struct { ... };
pub const SemanticStyle = enum { ... };
```

### Phase 4: Inline Mode (Optional)

```zig
// Add screen mode configuration
pub const ScreenMode = union(enum) { ... };
```

---

## 15. Conclusion

FrankenTUI offers several patterns worth adopting for zithril:

**Definitely adopt:**
- Hit grid for mouse interaction
- Dirty row tracking for performance
- Expanded Frame context
- Theme/semantic styling system

**Consider for roadmap:**
- Inline mode (unique differentiator)
- Content-based layout sizing
- Degradation levels

**Skip for now:**
- Full Elm architecture (our simpler model is fine)
- Bayesian strategy selection (premature optimization)
- 15-crate workspace (Zig doesn't need this)

The key insight is that FrankenTUI solves problems we haven't encountered yet (inline mode, complex async, statistical optimization) while also having elegant solutions for problems we will encounter (mouse interaction, theming, performance).

---

*Analysis based on FrankenTUI repository exploration, February 2026.*
