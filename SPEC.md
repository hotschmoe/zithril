# zithril Specification

Version: 0.1.0 (Draft)

---

## 1. Overview

zithril is a Zig TUI framework for building terminal user interfaces. It follows an immediate-mode rendering paradigm where the entire UI is described every frame, with no retained widget tree or hidden state.

### 1.1 Design Principles

| Principle | Implementation |
|-----------|----------------|
| Explicit over implicit | User owns all state; framework never allocates behind your back |
| Immediate mode | Describe entire UI every frame; no widget tree, no retained state |
| Composition over inheritance | Widgets are structs with `render` functions, not class hierarchies |
| Built for Zig | Comptime layouts, error unions, no hidden control flow |

### 1.2 Architecture Layers

```
+------------------------------------------------------------------+
|                       USER APPLICATION                            |
|                                                                   |
|   State struct        - You define and own all application state |
|   update(Event)       - You handle events, return Actions        |
|   view(Frame)         - You describe UI by calling frame.render  |
+------------------------------------------------------------------+
                                |
                                v
+------------------------------------------------------------------+
|                          zithril                                  |
|                                                                   |
|   App(State)          - Generic runtime parameterized by State   |
|   Frame               - Layout methods, render dispatch          |
|   Layout              - Constraint solver (ratatui-style)        |
|   Buffer              - Cell grid with diff support              |
|   Widgets             - Block, List, Table, Gauge, Text, etc.    |
+------------------------------------------------------------------+
                                |
                                v
+------------------------------------------------------------------+
|                         rich_zig                                  |
|                                                                   |
|   Style               - Colors, bold, italic, underline, etc.    |
|   Color               - Named, indexed (256), RGB (true color)   |
|   Text spans          - Styled text segments                     |
|   ANSI rendering      - Escape sequence generation               |
+------------------------------------------------------------------+
                                |
                                v
+------------------------------------------------------------------+
|                     Terminal Backend                              |
|                                                                   |
|   Raw mode            - Disable line buffering, echo             |
|   Alternate screen    - Preserve original terminal content       |
|   Input parsing       - ANSI escape sequence decoding            |
|   Output              - Write buffer to terminal                 |
+------------------------------------------------------------------+
```

---

## 2. Core Types

### 2.1 Geometry

#### Rect

Represents a rectangular region in terminal coordinates.

```zig
pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    /// Returns a new Rect inset by `margin` on all sides.
    /// Uses saturating subtraction to prevent underflow.
    pub fn inner(self: Rect, margin: u16) Rect;

    /// Returns area (width * height)
    pub fn area(self: Rect) u32;

    /// Returns true if rect has zero area
    pub fn is_empty(self: Rect) bool;

    /// Clamp a point to be within this rect
    pub fn clamp(self: Rect, x: u16, y: u16) struct { x: u16, y: u16 };
};
```

#### Position

Simple x,y coordinate pair.

```zig
pub const Position = struct {
    x: u16,
    y: u16,
};
```

### 2.2 Layout System

#### Constraint

Constraints describe how space should be allocated among layout children.

```zig
pub const Constraint = union(enum) {
    /// Exactly n cells
    length: u16,

    /// At least n cells
    min: u16,

    /// At most n cells
    max: u16,

    /// Fraction of available space (numerator, denominator)
    ratio: struct { num: u16, den: u16 },

    /// Proportional share (like CSS flex-grow)
    /// flex(1) and flex(1) = 50/50 split
    /// flex(1) and flex(2) = 33/67 split
    flex: u16,
};
```

#### Direction

```zig
pub const Direction = enum {
    horizontal,
    vertical,
};
```

#### Layout Algorithm

The constraint solver allocates space in this order:

1. **Fixed constraints** (`length`): Allocate exact requested size
2. **Minimum constraints** (`min`): Allocate at least requested size
3. **Maximum constraints** (`max`): Allocate at most requested size
4. **Ratio constraints** (`ratio`): Allocate fraction of total space
5. **Flex constraints** (`flex`): Distribute remaining space proportionally

When space is insufficient:
- Fixed/min constraints take priority
- Flex items shrink to zero before fixed items shrink
- No negative sizes (saturating arithmetic)

### 2.3 Events

```zig
pub const Event = union(enum) {
    key: Key,
    mouse: Mouse,
    resize: Size,
    tick: void,

    pub const Key = struct {
        code: KeyCode,
        modifiers: Modifiers,
    };

    pub const KeyCode = union(enum) {
        char: u21,          // Unicode codepoint
        enter: void,
        tab: void,
        backtab: void,      // Shift+Tab
        backspace: void,
        escape: void,
        up: void,
        down: void,
        left: void,
        right: void,
        home: void,
        end: void,
        page_up: void,
        page_down: void,
        insert: void,
        delete: void,
        f: u8,              // F1-F12 (1-12)
    };

    pub const Modifiers = packed struct {
        ctrl: bool = false,
        alt: bool = false,
        shift: bool = false,
    };

    pub const Mouse = struct {
        x: u16,
        y: u16,
        kind: MouseKind,
        modifiers: Modifiers,
    };

    pub const MouseKind = enum {
        down,
        up,
        drag,
        move,
        scroll_up,
        scroll_down,
    };

    pub const Size = struct {
        width: u16,
        height: u16,
    };
};
```

### 2.4 Actions

Actions are returned by the update function to control the application.

```zig
pub const Action = union(enum) {
    /// Continue running, no special action
    none: void,

    /// Exit the application
    quit: void,

    /// Execute an async command (future)
    command: Command,
};
```

### 2.5 Style

```zig
pub const Style = struct {
    fg: Color = .default,
    bg: Color = .default,
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    dim: bool = false,
    blink: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,

    /// Merge another style on top of this one.
    /// Non-default values in `other` override values in `self`.
    pub fn patch(self: Style, other: Style) Style;
};

pub const Color = union(enum) {
    default: void,

    // Basic 8 colors
    black: void,
    red: void,
    green: void,
    yellow: void,
    blue: void,
    magenta: void,
    cyan: void,
    white: void,

    // Bright variants
    bright_black: void,
    bright_red: void,
    bright_green: void,
    bright_yellow: void,
    bright_blue: void,
    bright_magenta: void,
    bright_cyan: void,
    bright_white: void,

    // 256-color palette
    indexed: u8,

    // True color (24-bit RGB)
    rgb: struct { r: u8, g: u8, b: u8 },
};
```

---

## 3. Buffer

The Buffer is a 2D grid of Cells that widgets render into.

### 3.1 Cell

```zig
pub const Cell = struct {
    char: u21 = ' ',        // Unicode codepoint
    style: Style = .{},
    width: u8 = 1,          // Display width (1 for most chars, 2 for wide)
};
```

### 3.2 Buffer

```zig
pub const Buffer = struct {
    width: u16,
    height: u16,
    cells: []Cell,          // Row-major: cells[y * width + x]

    /// Set a single cell
    pub fn set(self: *Buffer, x: u16, y: u16, cell: Cell) void;

    /// Get a cell (returns default if out of bounds)
    pub fn get(self: Buffer, x: u16, y: u16) Cell;

    /// Write a string starting at (x, y) with given style
    /// Handles wide characters, clips at buffer bounds
    pub fn set_string(self: *Buffer, x: u16, y: u16, str: []const u8, style: Style) void;

    /// Fill a rectangular region with a cell
    pub fn fill(self: *Buffer, area: Rect, cell: Cell) void;

    /// Fill a rectangular region with a style (preserves characters)
    pub fn set_style(self: *Buffer, area: Rect, style: Style) void;

    /// Compute diff between two buffers, return list of changed cells
    pub fn diff(self: Buffer, other: Buffer) []CellUpdate;
};
```

---

## 4. Frame

The Frame is passed to the view function and provides layout and rendering methods.

```zig
pub fn Frame(comptime max_widgets: usize) type {
    return struct {
        buffer: *Buffer,
        size_: Rect,

        /// Returns the full terminal area
        pub fn size(self: *@This()) Rect;

        /// Split an area according to constraints
        /// Returns array of Rects (up to constraints.len)
        pub fn layout(
            self: *@This(),
            area: Rect,
            direction: Direction,
            constraints: []const Constraint,
        ) []Rect;

        /// Render a widget into an area
        /// Widget must have: pub fn render(self: T, area: Rect, buf: *Buffer) void
        pub fn render(self: *@This(), widget: anytype, area: Rect) void;
    };
}
```

---

## 5. App Runtime

### 5.1 App

```zig
pub fn App(comptime State: type) type {
    return struct {
        state: State,
        update_fn: *const fn (*State, Event) Action,
        view_fn: *const fn (*State, *Frame) void,

        // Configuration
        tick_rate_ms: u32 = 0,          // 0 = disabled
        mouse_capture: bool = false,
        paste_bracket: bool = false,
        alternate_screen: bool = true,

        pub fn init(config: Config) @This();

        /// Run the main loop until Action.quit is returned
        pub fn run(self: *@This()) !void;
    };
}
```

### 5.2 Main Loop

```
+-----------------------------------------------------------+
|                                                           |
|   +-------+     +--------+     +------+     +--------+   |
|   | Event | --> | Update | --> | View | --> | Render |   |
|   +-------+     +--------+     +------+     +--------+   |
|       ^                                          |        |
|       |                                          |        |
|       +------------------------------------------+        |
|                                                           |
+-----------------------------------------------------------+
```

1. **Poll Event**: Wait for input (key, mouse, resize) or tick timeout
2. **Update**: Call user's `update(state, event)` function
3. **Check Action**: If `.quit`, exit loop
4. **View**: Call user's `view(state, frame)` function
5. **Render**: Diff buffer, write changes to terminal
6. **Repeat**

---

## 6. Built-in Widgets

All widgets implement the same interface:

```zig
pub fn render(self: @This(), area: Rect, buf: *Buffer) void
```

### 6.1 Block

Draws borders and optional title.

```zig
pub const Block = struct {
    title: ?[]const u8 = null,
    title_alignment: Alignment = .left,
    border: BorderType = .none,
    border_style: Style = .{},
    style: Style = .{},             // Background style

    pub const BorderType = enum {
        none,
        plain,      // ASCII: +-|
        rounded,    // Unicode: rounded corners
        double,     // Unicode: double lines
        thick,      // Unicode: thick lines
    };

    pub const Alignment = enum { left, center, right };
};
```

### 6.2 Text

Single-line styled text.

```zig
pub const Text = struct {
    content: []const u8,
    style: Style = .{},
    alignment: Alignment = .left,
};
```

### 6.3 Paragraph

Multi-line text with optional wrapping.

```zig
pub const Paragraph = struct {
    text: []const u8,
    style: Style = .{},
    wrap: Wrap = .none,
    alignment: Alignment = .left,

    pub const Wrap = enum {
        none,       // Clip at boundary
        char,       // Wrap at any character
        word,       // Wrap at word boundaries
    };
};
```

### 6.4 List

Navigable list with selection.

```zig
pub const List = struct {
    items: []const []const u8,
    selected: ?usize = null,
    style: Style = .{},
    highlight_style: Style = .{ .bg = .blue },
    highlight_symbol: []const u8 = "> ",
};
```

### 6.5 Table

Rows and columns with optional header.

```zig
pub const Table = struct {
    header: ?[]const []const u8 = null,
    rows: []const []const []const u8,
    widths: []const Constraint,
    selected: ?usize = null,
    style: Style = .{},
    header_style: Style = .{ .bold = true },
    highlight_style: Style = .{ .bg = .blue },
};
```

### 6.6 Gauge

Progress bar.

```zig
pub const Gauge = struct {
    ratio: f32,                     // 0.0 to 1.0
    label: ?[]const u8 = null,
    style: Style = .{},
    gauge_style: Style = .{ .bg = .green },
};
```

### 6.7 Tabs

Tab headers.

```zig
pub const Tabs = struct {
    titles: []const []const u8,
    selected: usize = 0,
    style: Style = .{},
    highlight_style: Style = .{ .bold = true, .fg = .yellow },
    divider: []const u8 = " | ",
};
```

### 6.8 Scrollbar

Scroll position indicator.

```zig
pub const Scrollbar = struct {
    total: usize,           // Total items
    position: usize,        // Current position
    viewport: u16,          // Visible items
    style: Style = .{},
    orientation: Orientation = .vertical,

    pub const Orientation = enum { vertical, horizontal };
};
```

### 6.9 Clear

Fills area with default style (useful before popups).

```zig
pub const Clear = struct {
    style: Style = .{},
};
```

---

## 7. Terminal Backend

### 7.1 Capabilities

| Capability | Description |
|------------|-------------|
| Raw mode | Disable line buffering and echo |
| Alternate screen | Switch to alternate buffer, restore on exit |
| Mouse capture | Enable mouse event reporting |
| Bracketed paste | Distinguish pasted text from typed text |
| Cursor control | Hide, show, position cursor |
| Color support | Detect 16/256/true color support |

### 7.2 Input Parsing

The backend parses ANSI escape sequences into Event values:

| Sequence | Event |
|----------|-------|
| `\x1b[A` | Key.up |
| `\x1b[B` | Key.down |
| `\x1b[C` | Key.right |
| `\x1b[D` | Key.left |
| `\x1b[1;5A` | Key.up + Ctrl |
| `\x1b[M...` | Mouse (X10 mode) |
| `\x1b[<...` | Mouse (SGR mode) |

### 7.3 Output

Rendering uses ANSI escape sequences:

| Sequence | Purpose |
|----------|---------|
| `\x1b[H` | Move cursor to home |
| `\x1b[y;xH` | Move cursor to position |
| `\x1b[2J` | Clear screen |
| `\x1b[?1049h` | Enter alternate screen |
| `\x1b[?1049l` | Leave alternate screen |
| `\x1b[38;5;Nm` | Set foreground (256 color) |
| `\x1b[48;2;R;G;Bm` | Set background (true color) |

---

## 8. Error Handling

### 8.1 Error Types

```zig
pub const Error = error{
    TerminalInitFailed,
    TerminalQueryFailed,
    BufferOverflow,
    InvalidUtf8,
    IoError,
    OutOfMemory,
};
```

### 8.2 Philosophy

- All errors are explicit and must be handled
- No panics in library code (only in user code via `.?`)
- Use `catch unreachable` only when mathematically impossible to fail
- Prefer returning errors over assertions

---

## 9. Memory Model

### 9.1 Allocations

| Component | Allocation Strategy |
|-----------|---------------------|
| Buffer | User provides allocator, single allocation for cell grid |
| Widgets | Stack-allocated (no heap) |
| Strings | User-provided slices (no copies) |
| Layout results | Comptime-sized arrays or user-provided slice |

### 9.2 No Hidden State

The framework maintains no global state. All state is:

1. Passed explicitly via parameters
2. Owned by the user's State struct
3. Scoped to the current frame (transient)

---

## 10. Platform Support

### 10.1 Target Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| Linux | Primary | Full support |
| macOS | Primary | Full support |
| Windows | Secondary | Via Windows Console API or ConPTY |
| BSD | Best-effort | Should work, not actively tested |

### 10.2 Terminal Compatibility

| Terminal | Color | Mouse | Unicode |
|----------|-------|-------|---------|
| xterm | Full | Full | Full |
| gnome-terminal | Full | Full | Full |
| iTerm2 | Full | Full | Full |
| Windows Terminal | Full | Full | Full |
| cmd.exe | 16 | Limited | Limited |
| alacritty | Full | Full | Full |
| kitty | Full | Full | Full |

---

## 11. Future Considerations

### 11.1 Command Pattern (Async)

```zig
pub const Command = union(enum) {
    none: void,
    batch: []const Command,
    custom: struct {
        id: u32,
        data: *anyopaque,
    },
};

// Commands are returned from update, executed by runtime
// Results come back as events
```

### 11.2 Animation Support

```zig
pub const Animation = struct {
    duration_ms: u32,
    easing: Easing,
    on_frame: *const fn (progress: f32) void,
};
```

### 11.3 Image Support

- Sixel graphics
- Kitty graphics protocol
- iTerm2 inline images

---

## Appendix A: Comparison with Prior Art

### A.1 vs ratatui (Rust)

| Aspect | zithril | ratatui |
|--------|---------|---------|
| Language | Zig | Rust |
| Mode | Immediate | Immediate |
| State ownership | User | User |
| Backend | Built-in | crossterm/termion/termwiz |
| Allocation | Explicit | Explicit |

**What we take**: Constraint-based layout, widget trait pattern, buffer diffing.

### A.2 vs bubbletea (Go)

| Aspect | zithril | bubbletea |
|--------|---------|-----------|
| Language | Zig | Go |
| Mode | Immediate | Elm architecture |
| State ownership | User | Model |
| Async | Commands | Commands |
| Allocation | Explicit | GC |

**What we take**: Command pattern for async operations, clean Update/View separation.

### A.3 vs OpenTUI (TypeScript)

| Aspect | zithril | OpenTUI |
|--------|---------|---------|
| Language | Zig | TypeScript |
| Mode | Immediate | Component/OOP |
| State ownership | User | Widgets |
| Widget model | Structs | Classes |

**What we avoid**: OOP inheritance hierarchies, hidden widget state, event bubbling complexity.
