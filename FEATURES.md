# zithril Features

Itemized feature list for implementation. Each item represents a discrete, implementable unit.
Bead IDs are shown in brackets for task tracking via `br show <id>`.

---

## 1. Core Types

### 1.1 Geometry [bd-2ad]

- [x] **Rect struct**: x, y, width, height (all u16)
- [x] **Rect.inner(margin)**: Return new Rect inset by margin on all sides, saturating subtraction
- [x] **Rect.area()**: Return width * height as u32
- [x] **Rect.isEmpty()**: Return true if area is zero
- [x] **Rect.clamp(x, y)**: Clamp a point to be within the rect bounds
- [x] **Rect.contains(x, y)**: Check if point is within rect
- [x] **Rect.right(), Rect.bottom()**: Edge coordinates
- [x] **Position struct**: Simple x, y coordinate pair (u16, u16)

### 1.2 Style [bd-1gb]

- [x] **Style struct**: fg, bg, bold, italic, underline, dim, blink, reverse, strikethrough
- [x] **Style.patch(other)**: Merge another style on top, non-default values override
- [x] **Style defaults**: All attributes default to false/default color
- [x] **Style.renderAnsi()**: Render to ANSI escape sequences via rich_zig
- [x] **Method chaining**: .bold().fg(.red).bg(.blue) syntax

### 1.3 Color [bd-dx8]

- [x] **Color.default**: Terminal default color
- [x] **Color basic 8**: black, red, green, yellow, blue, magenta, cyan, white
- [x] **Color bright variants**: bright_black through bright_white (8 colors)
- [x] **Color.from256(u8)**: 256-color palette support
- [x] **Color.fromRgb(r, g, b)**: True color (24-bit) support

---

## 2. Layout System

### 2.1 Constraint Types [bd-1p0]

- [x] **Constraint.len(n)**: Exactly n cells
- [x] **Constraint.minSize(n)**: At least n cells
- [x] **Constraint.maxSize(n)**: At most n cells
- [x] **Constraint.fractional(num, den)**: Fraction of available space
- [x] **Constraint.flexible(n)**: Proportional share (like CSS flex-grow)

### 2.2 Direction [bd-2zl]

- [x] **Direction.horizontal**: Split left-to-right
- [x] **Direction.vertical**: Split top-to-bottom

### 2.3 Layout Solver [bd-2vo]

- [x] **layout(area, direction, constraints)**: Split a Rect into child Rects
- [x] **Fixed constraint allocation**: Allocate exact requested size first
- [x] **Minimum constraint allocation**: Allocate at least requested size
- [x] **Maximum constraint allocation**: Allocate at most requested size
- [x] **Ratio constraint allocation**: Allocate fraction of total space
- [x] **Flex constraint allocation**: Distribute remaining space proportionally
- [x] **Insufficient space handling**: Flex shrinks first, then fixed; never negative
- [x] **BoundedRects return type**: Array of Rects matching constraint count

---

## 3. Event System

### 3.1 Event Union and Key Events [bd-14k]

- [x] **Event.key**: Key press with modifiers
- [x] **Event.mouse**: Mouse action with position and modifiers
- [x] **Event.resize**: Terminal size change
- [x] **Event.tick**: Timer tick for animations/polling
- [x] **Event.command_result**: Result from async command
- [x] **Key.code**: The key that was pressed
- [x] **Key.modifiers**: Ctrl, Alt, Shift flags
- [x] **KeyCode.char(u21)**: Unicode codepoint for printable characters
- [x] **KeyCode navigation**: enter, tab, backtab, backspace, escape
- [x] **KeyCode arrows**: up, down, left, right
- [x] **KeyCode extended**: home, end, page_up, page_down, insert, delete
- [x] **KeyCode function keys**: f(1-12)

### 3.2 Mouse Events [bd-15o]

- [x] **Mouse.x, Mouse.y**: Position in terminal coordinates
- [x] **Mouse.kind**: down, up, drag, move, scroll_up, scroll_down
- [x] **Mouse.modifiers**: Ctrl, Alt, Shift flags

### 3.3 Modifiers and Size [bd-1b7]

- [x] **Modifiers packed struct**: ctrl, alt, shift as bools
- [x] **Size.width, Size.height**: New terminal dimensions
- [x] **Size.area()**: Calculate total cells

---

## 4. Action System

### 4.1 Action Union [bd-1ku]

- [x] **Action.none**: Continue running, no special action
- [x] **Action.quit**: Exit the application
- [x] **Action.command**: Execute async command

### 4.2 Command Pattern [bd-2xr]

- [x] **Command union type**: none, batch, custom, delay_tick
- [x] **Command.batch**: Execute multiple commands
- [x] **Command.custom**: User-defined with ID and data pointer
- [x] **Command.delay_tick**: One-shot delayed tick
- [x] **CommandResult**: Success/failed/cancelled status with ID matching

---

## 5. Buffer System

### 5.1 Cell [bd-3gl]

- [x] **Cell struct**: char (u21), style (Style), width (u8)
- [x] **Cell defaults**: Space character, default style, width 1
- [x] **Cell wide character support**: Width 2 for CJK/emoji
- [x] **Cell.isWide()**: Check if cell is double-width
- [x] **Cell.isDefault()**: Check if cell is default

### 5.2 Buffer [bd-35j]

- [x] **Buffer struct**: width, height, cells array (row-major)
- [x] **Buffer.set(x, y, cell)**: Set a single cell
- [x] **Buffer.get(x, y)**: Get cell, return default if out of bounds
- [x] **Buffer.setString(x, y, str, style)**: Write string with style
- [x] **Buffer.setString wide char handling**: Proper width tracking
- [x] **Buffer.setString clipping**: Stop at buffer bounds
- [x] **Buffer.fill(area, cell)**: Fill rectangular region
- [x] **Buffer.setStyleArea(area, style)**: Apply style to region, preserve chars
- [x] **Buffer.clear()**: Reset all cells to default
- [x] **Buffer.resize()**: Change dimensions

### 5.3 Buffer Diff [bd-1cm]

- [x] **CellUpdate struct**: x, y, cell for each changed position
- [x] **Diff algorithm**: Compare cell-by-cell, collect changes
- [x] **Diff optimization**: Skip unchanged cells for minimal output
- [x] **Buffer.diff(other)**: Compute changed cells between buffers
- [x] **Buffer.diffCount(other)**: Count changes without allocating

---

## 6. Frame System

### 6.1 Frame Struct and Methods [bd-fmp]

- [x] **Frame generic over max_widgets**: Comptime-sized layout cache
- [x] **Frame.buffer**: Reference to render buffer
- [x] **Frame.size()**: Return full terminal area as Rect
- [x] **Frame.layout(area, direction, constraints)**: Split area, return BoundedRects
- [x] **Frame.render(widget, area)**: Render any widget to buffer

### 6.2 Widget Interface [bd-3lt]

- [x] **Widget render signature**: fn render(self, area: Rect, buf: *Buffer) void
- [x] **Frame.render duck typing**: Accept any type with render method
- [x] **No widget base class**: Composition via functions

---

## 7. App Runtime

### 7.1 App Generic Struct [bd-3go]

- [x] **App(State) type**: Generic over user state type
- [x] **App.state**: User's state instance
- [x] **App.update_fn**: Pointer to update function
- [x] **App.view_fn**: Pointer to view function

### 7.2 App Configuration [bd-git]

- [x] **tick_rate_ms**: Tick event interval (0 = disabled)
- [x] **mouse_capture**: Enable mouse event reporting
- [x] **bracketed_paste**: Enable bracketed paste detection
- [x] **alternate_screen**: Use alternate screen buffer
- [x] **hide_cursor**: Hide cursor during operation

### 7.3 Main Loop [bd-1aw]

- [x] **App.init(config)**: Create app with config
- [x] **App.run()**: Run main loop until quit
- [x] **Poll event**: Wait for input or tick timeout
- [x] **Call update**: User's update(state, event) -> Action
- [x] **Check action**: Exit on .quit, handle .command
- [x] **Call view**: User's view(state, frame)
- [x] **Render**: Diff buffer, write changes to terminal
- [x] **Loop**: Repeat until quit

---

## 8. Terminal Backend

### 8.1 Terminal Initialization [bd-sr5]

- [x] **Raw mode enable**: Disable line buffering and echo
- [x] **Alternate screen enter**: Preserve original terminal content
- [x] **Cursor hide**: Hide cursor during rendering
- [x] **Mouse enable**: Enable mouse event reporting (optional)
- [x] **Bracketed paste enable**: Distinguish pasted text (optional)

### 8.2 Terminal Cleanup [bd-2gz]

- [x] **Raw mode disable**: Restore normal input mode
- [x] **Alternate screen leave**: Restore original content
- [x] **Cursor show**: Restore cursor visibility
- [x] **Mouse disable**: Stop mouse reporting
- [x] **Bracketed paste disable**: Stop paste detection
- [x] **Cleanup on panic**: Register handler for clean exit

### 8.3 Terminal Queries [bd-198]

- [x] **Get terminal size**: Query current width/height
- [x] **Detect color support**: 16/256/true color detection
- [x] **Detect terminal type**: Identify specific terminals (kitty, iterm2, etc.)
- [x] **TerminalCapabilities**: Comprehensive feature detection

### 8.4 Input Parsing [bd-3bl]

- [x] **Read raw bytes**: Non-blocking read from stdin
- [x] **Parse ANSI escape sequences**: Decode to Event
- [x] **Arrow key parsing**: ESC [ A/B/C/D
- [x] **Function key parsing**: ESC [ 1-24 ~
- [x] **Modifier parsing**: ESC [ 1;5 A (Ctrl+Up)
- [x] **Mouse X10 parsing**: ESC [ M ...
- [x] **Mouse SGR parsing**: ESC [ < ...
- [x] **UTF-8 character parsing**: Multi-byte sequences
- [x] **Paste detection**: Bracketed paste sequences

### 8.5 Output [bd-1k0]

- [x] **Cursor positioning**: ESC [ y;x H
- [x] **Clear screen**: ESC [ 2J
- [x] **Set foreground 16**: ESC [ 30-37 m, ESC [ 90-97 m
- [x] **Set background 16**: ESC [ 40-47 m, ESC [ 100-107 m
- [x] **Set foreground 256**: ESC [ 38;5;N m
- [x] **Set background 256**: ESC [ 48;5;N m
- [x] **Set foreground RGB**: ESC [ 38;2;R;G;B m
- [x] **Set background RGB**: ESC [ 48;2;R;G;B m
- [x] **Set attributes**: Bold, italic, underline, etc.
- [x] **Reset attributes**: ESC [ 0 m
- [x] **Buffered output**: Batch writes for efficiency (Output type)
- [x] **Flush output**: Write buffered content to terminal

---

## 9. Built-in Widgets

### 9.1 Block [bd-1nq]

- [x] **Block.title**: Optional title string
- [x] **Block.title_alignment**: left, center, right
- [x] **Block.border**: none, plain, rounded, double, thick
- [x] **Block.border_style**: Style for border characters
- [x] **Block.style**: Background style for interior
- [x] **Block.render**: Draw border and title to buffer
- [x] **Block.inner(area)**: Calculate interior area

### 9.2 Text [bd-2lq]

- [x] **Text.content**: String to display
- [x] **Text.style**: Style for text
- [x] **Text.alignment**: left, center, right
- [x] **Text.render**: Draw single line of styled text

### 9.3 Paragraph [bd-2hs]

- [x] **Paragraph.text**: Multi-line text content
- [x] **Paragraph.style**: Style for text
- [x] **Paragraph.wrap**: none (clip), char, word
- [x] **Paragraph.alignment**: left, center, right
- [x] **Paragraph.render**: Draw wrapped text

### 9.4 List [bd-2x7]

- [x] **List.items**: Slice of strings
- [x] **List.selected**: Optional selected index
- [x] **List.style**: Style for unselected items
- [x] **List.highlight_style**: Style for selected item
- [x] **List.highlight_symbol**: Prefix for selected item (e.g., "> ")
- [x] **List.render**: Draw navigable list

### 9.5 Table [bd-17u]

- [x] **Table.header**: Optional header row
- [x] **Table.rows**: Slice of row data
- [x] **Table.widths**: Constraint slice for column widths
- [x] **Table.selected**: Optional selected row index
- [x] **Table.style**: Style for cells
- [x] **Table.header_style**: Style for header row
- [x] **Table.highlight_style**: Style for selected row
- [x] **Table.render**: Draw table with columns

### 9.6 Gauge [bd-dmx]

- [x] **Gauge.ratio**: Progress 0.0 to 1.0
- [x] **Gauge.label**: Optional label text
- [x] **Gauge.style**: Style for unfilled portion
- [x] **Gauge.gauge_style**: Style for filled portion
- [x] **Gauge.render**: Draw progress bar

### 9.7 Tabs [bd-zjw]

- [x] **Tabs.titles**: Slice of tab title strings
- [x] **Tabs.selected**: Currently selected tab index
- [x] **Tabs.style**: Style for unselected tabs
- [x] **Tabs.highlight_style**: Style for selected tab
- [x] **Tabs.divider**: String between tabs (e.g., " | ")
- [x] **Tabs.render**: Draw tab bar

### 9.8 Scrollbar [bd-1h6]

- [x] **Scrollbar.total**: Total item count
- [x] **Scrollbar.position**: Current scroll position
- [x] **Scrollbar.viewport**: Visible item count
- [x] **Scrollbar.style**: Style for scrollbar
- [x] **Scrollbar.orientation**: vertical, horizontal
- [x] **Scrollbar.render**: Draw scroll indicator

### 9.9 Clear [bd-2v0]

- [x] **Clear.style**: Style to fill with (default: empty)
- [x] **Clear.render**: Fill area with style (for popups)

### 9.10 ScrollView [bd-33j]

- [x] **ScrollView**: Virtual scrolling container
- [x] **ScrollState**: Scroll position management
- [x] **ScrollableList**: List with built-in scrolling

### 9.11 TextInput [bd-t6z]

- [x] **TextInput**: Single-line text input widget
- [x] **TextInputState**: Cursor position, text content
- [x] **Cursor movement**: Left, right, home, end
- [x] **Text editing**: Insert, delete, backspace

---

## 10. Error Handling [bd-2jl]

### 10.1 Error Types

- [x] **Error.NotATty**: Stdout is not a terminal
- [x] **Error.TerminalQueryFailed**: Could not query terminal state
- [x] **Error.TerminalSetFailed**: Could not set terminal state
- [x] **Error.IoError**: IO operation failed
- [x] **Error.OutOfMemory**: Allocation failed (via Zig error)

### 10.2 Error Philosophy

- [x] **All errors explicit**: No panics in library code
- [x] **Error unions throughout**: Functions return errors when fallible
- [x] **catch unreachable justified**: Only when mathematically impossible

---

## 11. Platform Support

### 11.1 Primary Platforms [bd-1q1]

- [x] **Linux support**: Full feature support
- [x] **macOS support**: Full feature support

### 11.2 Secondary Platforms [bd-3nt]

- [x] **Windows support**: Via Windows Console API with VT sequences
- [x] **Windows Terminal detection**: Modern terminal vs legacy cmd
- [x] **BSD support**: Best-effort via POSIX backend

### 11.3 Terminal Compatibility [bd-2xj]

- [x] **xterm compatibility**: Reference terminal
- [x] **GNOME Terminal compatibility**: VTE-based detection
- [x] **iTerm2 compatibility**: macOS terminal with image support
- [x] **Windows Terminal compatibility**: Modern Windows
- [x] **Alacritty compatibility**: Cross-platform GPU terminal
- [x] **Kitty compatibility**: Feature-rich terminal with graphics
- [x] **WezTerm compatibility**: Cross-platform with graphics
- [x] **Konsole compatibility**: KDE terminal
- [x] **tmux/screen compatibility**: Terminal multiplexers

---

## 12. Integration

### 12.1 rich_zig Integration [bd-1af]

- [x] **Use rich_zig Style**: Wrapper with zithril-specific conveniences
- [x] **Use rich_zig Color**: Import and re-export Color type
- [x] **Use rich_zig text spans**: Segment type for styled text
- [x] **ANSI rendering via rich_zig**: Escape sequence generation
- [x] **ControlCode support**: Terminal control sequences

### 12.2 Build System [bd-2oi]

- [x] **build.zig module export**: Export zithril module
- [x] **build.zig.zon dependencies**: Declare rich_zig dependency
- [x] **Example executables**: Counter, list, tabs, ralph examples

---

## 13. Examples

### 13.1 Counter Example [bd-dif]

- [x] **Minimal state**: Single counter value
- [x] **Key handling**: q to quit, up/down to increment/decrement
- [x] **Simple view**: Block with counter display

### 13.2 List Example [bd-1rz]

- [x] **List state**: Items and selected index
- [x] **Navigation**: j/k or arrows to move selection
- [x] **Selection highlight**: Visual feedback

### 13.3 Tabs Example [bd-2m5]

- [x] **Tab state**: Tab titles and active index
- [x] **Tab switching**: Number keys or arrow keys
- [x] **Content per tab**: Different view per tab

### 13.4 Ralph Example (Reference App) [bd-8pk]

- [x] **Agent list**: Multiple agents with status
- [x] **Agent detail panel**: Selected agent info
- [x] **Log panel**: Scrollable log output
- [x] **Status bar**: Help text
- [x] **Progress gauges**: Per-agent progress
- [x] **Focus management**: Switch between panels

---

## 14. Advanced Features

### 14.1 Mouse Utilities [bd-3kk]

- [x] **HitRegion**: Clickable region with identifier
- [x] **HitTester**: Collection of hit regions for testing
- [x] **HoverState**: Track mouse enter/leave transitions
- [x] **DragState**: Track drag operations with selection rect
- [x] **ScrollAccumulator**: Handle scroll wheel events

### 14.2 Animation Helpers [bd-4m6]

- [x] **Easing functions**: linear, ease_in/out, quad, cubic, elastic, back, bounce
- [x] **Animation struct**: Duration tracking with progress
- [x] **Keyframe**: Multi-point animation support
- [x] **KeyframeAnimation**: Sequence of keyframes
- [x] **Duration**: Time representation (ms, seconds)
- [x] **FrameTimer**: FPS-based timing
- [x] **Interpolation helpers**: lerp, inverseLerp, remap, smoothstep

### 14.3 Image Support [bd-2je]

- [x] **GraphicsProtocol**: Sixel, Kitty, iTerm2 detection
- [x] **GraphicsCapabilities**: Runtime capability detection
- [x] **SixelEncoder**: Sixel graphics encoding
- [x] **KittyEncoder**: Kitty graphics protocol encoding
- [x] **ITerm2Encoder**: iTerm2 inline image encoding

### 14.4 Testing Utilities [bd-2gy]

- [x] **TestRecorder**: Record events with timestamps
- [x] **TestPlayer**: Playback recorded events
- [x] **MockBackend**: Headless terminal mock
- [x] **Snapshot**: Buffer snapshot for comparison
- [x] **bufferToAnnotatedText**: Debug output helper
- [x] **expectCell, expectString**: Test assertions

---

## Implementation Status

All planned features have been implemented:

- **Phase 1 - Core**: Complete
- **Phase 2 - Widgets**: Complete
- **Phase 3 - Layout**: Complete
- **Phase 4 - Polish**: Complete
- **Phase 5 - Advanced**: Complete

---

## Quick Reference: All Beads

| Section | Bead ID | Description | Status |
|---------|---------|-------------|--------|
| Core Types | bd-2ad | Geometry (Rect, Position) | Complete |
| Core Types | bd-1gb | Style | Complete |
| Core Types | bd-dx8 | Color | Complete |
| Layout | bd-1p0 | Constraint Types | Complete |
| Layout | bd-2zl | Direction | Complete |
| Layout | bd-2vo | Layout Solver | Complete |
| Events | bd-14k | Event Union and Key Events | Complete |
| Events | bd-15o | Mouse Events | Complete |
| Events | bd-1b7 | Modifiers and Size | Complete |
| Actions | bd-1ku | Action Union | Complete |
| Actions | bd-2xr | Command Pattern | Complete |
| Buffer | bd-3gl | Cell | Complete |
| Buffer | bd-35j | Buffer | Complete |
| Buffer | bd-1cm | Buffer Diff | Complete |
| Frame | bd-fmp | Frame Struct and Methods | Complete |
| Frame | bd-3lt | Widget Interface | Complete |
| App | bd-3go | App Generic Struct | Complete |
| App | bd-git | App Configuration | Complete |
| App | bd-1aw | Main Loop | Complete |
| Terminal | bd-sr5 | Initialization | Complete |
| Terminal | bd-2gz | Cleanup | Complete |
| Terminal | bd-198 | Queries | Complete |
| Terminal | bd-3bl | Input Parsing | Complete |
| Terminal | bd-1k0 | Output | Complete |
| Widgets | bd-1nq | Block | Complete |
| Widgets | bd-2lq | Text | Complete |
| Widgets | bd-2hs | Paragraph | Complete |
| Widgets | bd-2x7 | List | Complete |
| Widgets | bd-17u | Table | Complete |
| Widgets | bd-dmx | Gauge | Complete |
| Widgets | bd-zjw | Tabs | Complete |
| Widgets | bd-1h6 | Scrollbar | Complete |
| Widgets | bd-2v0 | Clear | Complete |
| Widgets | bd-33j | ScrollView | Complete |
| Widgets | bd-t6z | TextInput | Complete |
| Errors | bd-2jl | Error Types | Complete |
| Platform | bd-1q1 | Linux and macOS | Complete |
| Platform | bd-3nt | Windows | Complete |
| Platform | bd-2xj | Terminal Compatibility | Complete |
| Integration | bd-1af | rich_zig | Complete |
| Integration | bd-2oi | Build System | Complete |
| Examples | bd-dif | Counter | Complete |
| Examples | bd-1rz | List | Complete |
| Examples | bd-2m5 | Tabs | Complete |
| Examples | bd-8pk | Ralph (Reference App) | Complete |
| Advanced | bd-3kk | Mouse Utilities | Complete |
| Advanced | bd-4m6 | Animation Helpers | Complete |
| Advanced | bd-2je | Image Support | Complete |
| Advanced | bd-2gy | Testing Utilities | Complete |
