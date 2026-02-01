# zithril Features

Itemized feature list for implementation. Each item represents a discrete, implementable unit.
Bead IDs are shown in brackets for task tracking via `br show <id>`.

---

## 1. Core Types

### 1.1 Geometry [bd-2ad]

- [ ] **Rect struct**: x, y, width, height (all u16)
- [ ] **Rect.inner(margin)**: Return new Rect inset by margin on all sides, saturating subtraction
- [ ] **Rect.area()**: Return width * height as u32
- [ ] **Rect.is_empty()**: Return true if area is zero
- [ ] **Rect.clamp(x, y)**: Clamp a point to be within the rect bounds
- [ ] **Position struct**: Simple x, y coordinate pair (u16, u16)

### 1.2 Style [bd-1gb]

- [ ] **Style struct**: fg, bg, bold, italic, underline, dim, blink, reverse, strikethrough
- [ ] **Style.patch(other)**: Merge another style on top, non-default values override
- [ ] **Style defaults**: All attributes default to false/default color

### 1.3 Color [bd-dx8]

- [ ] **Color.default**: Terminal default color
- [ ] **Color basic 8**: black, red, green, yellow, blue, magenta, cyan, white
- [ ] **Color bright variants**: bright_black through bright_white (8 colors)
- [ ] **Color.indexed(u8)**: 256-color palette support
- [ ] **Color.rgb(r, g, b)**: True color (24-bit) support

---

## 2. Layout System

### 2.1 Constraint Types [bd-1p0]

- [ ] **Constraint.length(n)**: Exactly n cells
- [ ] **Constraint.min(n)**: At least n cells
- [ ] **Constraint.max(n)**: At most n cells
- [ ] **Constraint.ratio(num, den)**: Fraction of available space
- [ ] **Constraint.flex(n)**: Proportional share (like CSS flex-grow)

### 2.2 Direction [bd-2zl]

- [ ] **Direction.horizontal**: Split left-to-right
- [ ] **Direction.vertical**: Split top-to-bottom

### 2.3 Layout Solver [bd-2vo]

- [ ] **layout(area, direction, constraints)**: Split a Rect into child Rects
- [ ] **Fixed constraint allocation**: Allocate exact requested size first
- [ ] **Minimum constraint allocation**: Allocate at least requested size
- [ ] **Maximum constraint allocation**: Allocate at most requested size
- [ ] **Ratio constraint allocation**: Allocate fraction of total space
- [ ] **Flex constraint allocation**: Distribute remaining space proportionally
- [ ] **Insufficient space handling**: Flex shrinks first, then fixed; never negative
- [ ] **Constraint solver returns slice**: Array of Rects matching constraint count

---

## 3. Event System

### 3.1 Event Union and Key Events [bd-14k]

- [ ] **Event.key**: Key press with modifiers
- [ ] **Event.mouse**: Mouse action with position and modifiers
- [ ] **Event.resize**: Terminal size change
- [ ] **Event.tick**: Timer tick for animations/polling
- [ ] **Key.code**: The key that was pressed
- [ ] **Key.modifiers**: Ctrl, Alt, Shift flags
- [ ] **KeyCode.char(u21)**: Unicode codepoint for printable characters
- [ ] **KeyCode navigation**: enter, tab, backtab, backspace, escape
- [ ] **KeyCode arrows**: up, down, left, right
- [ ] **KeyCode extended**: home, end, page_up, page_down, insert, delete
- [ ] **KeyCode function keys**: f(1-12)

### 3.2 Mouse Events [bd-15o]

- [ ] **Mouse.x, Mouse.y**: Position in terminal coordinates
- [ ] **Mouse.kind**: down, up, drag, move, scroll_up, scroll_down
- [ ] **Mouse.modifiers**: Ctrl, Alt, Shift flags

### 3.3 Modifiers and Size [bd-1b7]

- [ ] **Modifiers packed struct**: ctrl, alt, shift as bools
- [ ] **Size.width, Size.height**: New terminal dimensions

---

## 4. Action System

### 4.1 Action Union [bd-1ku]

- [ ] **Action.none**: Continue running, no special action
- [ ] **Action.quit**: Exit the application
- [ ] **Action.command**: Execute async command (future feature)

### 4.2 Command Pattern (Future) [bd-2xr]

- [ ] **Command union type**: User-defined commands
- [ ] **Command execution by runtime**: Results return as events
- [ ] **Command.batch**: Execute multiple commands

---

## 5. Buffer System

### 5.1 Cell [bd-3gl]

- [ ] **Cell struct**: char (u21), style (Style), width (u8)
- [ ] **Cell defaults**: Space character, default style, width 1
- [ ] **Cell wide character support**: Width 2 for CJK/emoji

### 5.2 Buffer [bd-35j]

- [ ] **Buffer struct**: width, height, cells array (row-major)
- [ ] **Buffer.set(x, y, cell)**: Set a single cell
- [ ] **Buffer.get(x, y)**: Get cell, return default if out of bounds
- [ ] **Buffer.set_string(x, y, str, style)**: Write string with style
- [ ] **Buffer.set_string wide char handling**: Proper width tracking
- [ ] **Buffer.set_string clipping**: Stop at buffer bounds
- [ ] **Buffer.fill(area, cell)**: Fill rectangular region
- [ ] **Buffer.set_style(area, style)**: Apply style to region, preserve chars

### 5.3 Buffer Diff [bd-1cm]

- [ ] **CellUpdate struct**: x, y, cell for each changed position
- [ ] **Diff algorithm**: Compare cell-by-cell, collect changes
- [ ] **Diff optimization**: Skip unchanged cells for minimal output
- [ ] **Buffer.diff(other)**: Compute changed cells between buffers

---

## 6. Frame System

### 6.1 Frame Struct and Methods [bd-fmp]

- [ ] **Frame generic over max_widgets**: Comptime-sized layout cache
- [ ] **Frame.buffer**: Reference to render buffer
- [ ] **Frame.size_**: Full terminal area as Rect
- [ ] **Frame.size()**: Return full terminal area
- [ ] **Frame.layout(area, direction, constraints)**: Split area, return Rects
- [ ] **Frame.render(widget, area)**: Render any widget to buffer

### 6.2 Widget Interface [bd-3lt]

- [ ] **Widget render signature**: fn render(self, area: Rect, buf: *Buffer) void
- [ ] **Frame.render duck typing**: Accept any type with render method
- [ ] **No widget base class**: Composition via functions

---

## 7. App Runtime

### 7.1 App Generic Struct [bd-3go]

- [ ] **App(State) type**: Generic over user state type
- [ ] **App.state**: User's state instance
- [ ] **App.update_fn**: Pointer to update function
- [ ] **App.view_fn**: Pointer to view function

### 7.2 App Configuration [bd-git]

- [ ] **tick_rate_ms**: Tick event interval (0 = disabled)
- [ ] **mouse_capture**: Enable mouse event reporting
- [ ] **paste_bracket**: Enable bracketed paste detection
- [ ] **alternate_screen**: Use alternate screen buffer

### 7.3 Main Loop [bd-1aw]

- [ ] **App.init(config)**: Create app with config
- [ ] **App.run()**: Run main loop until quit
- [ ] **Poll event**: Wait for input or tick timeout
- [ ] **Call update**: User's update(state, event) -> Action
- [ ] **Check action**: Exit on .quit, handle .command
- [ ] **Call view**: User's view(state, frame)
- [ ] **Render**: Diff buffer, write changes to terminal
- [ ] **Loop**: Repeat until quit

---

## 8. Terminal Backend

### 8.1 Terminal Initialization [bd-sr5]

- [ ] **Raw mode enable**: Disable line buffering and echo
- [ ] **Alternate screen enter**: Preserve original terminal content
- [ ] **Cursor hide**: Hide cursor during rendering
- [ ] **Mouse enable**: Enable mouse event reporting (optional)
- [ ] **Bracketed paste enable**: Distinguish pasted text (optional)

### 8.2 Terminal Cleanup [bd-2gz]

- [ ] **Raw mode disable**: Restore normal input mode
- [ ] **Alternate screen leave**: Restore original content
- [ ] **Cursor show**: Restore cursor visibility
- [ ] **Mouse disable**: Stop mouse reporting
- [ ] **Bracketed paste disable**: Stop paste detection
- [ ] **Cleanup on panic**: Register handler for clean exit

### 8.3 Terminal Queries [bd-198]

- [ ] **Get terminal size**: Query current width/height
- [ ] **Detect color support**: 16/256/true color detection

### 8.4 Input Parsing [bd-3bl]

- [ ] **Read raw bytes**: Non-blocking read from stdin
- [ ] **Parse ANSI escape sequences**: Decode to Event
- [ ] **Arrow key parsing**: ESC [ A/B/C/D
- [ ] **Function key parsing**: ESC [ 1-24 ~
- [ ] **Modifier parsing**: ESC [ 1;5 A (Ctrl+Up)
- [ ] **Mouse X10 parsing**: ESC [ M ...
- [ ] **Mouse SGR parsing**: ESC [ < ...
- [ ] **UTF-8 character parsing**: Multi-byte sequences
- [ ] **Paste detection**: Bracketed paste sequences

### 8.5 Output [bd-1k0]

- [ ] **Cursor positioning**: ESC [ y;x H
- [ ] **Clear screen**: ESC [ 2J
- [ ] **Set foreground 16**: ESC [ 30-37 m, ESC [ 90-97 m
- [ ] **Set background 16**: ESC [ 40-47 m, ESC [ 100-107 m
- [ ] **Set foreground 256**: ESC [ 38;5;N m
- [ ] **Set background 256**: ESC [ 48;5;N m
- [ ] **Set foreground RGB**: ESC [ 38;2;R;G;B m
- [ ] **Set background RGB**: ESC [ 48;2;R;G;B m
- [ ] **Set attributes**: Bold, italic, underline, etc.
- [ ] **Reset attributes**: ESC [ 0 m
- [ ] **Buffered output**: Batch writes for efficiency
- [ ] **Flush output**: Write buffered content to terminal

---

## 9. Built-in Widgets

### 9.1 Block [bd-1nq]

- [ ] **Block.title**: Optional title string
- [ ] **Block.title_alignment**: left, center, right
- [ ] **Block.border**: none, plain, rounded, double, thick
- [ ] **Block.border_style**: Style for border characters
- [ ] **Block.style**: Background style for interior
- [ ] **Block.render**: Draw border and title to buffer

### 9.2 Text [bd-2lq]

- [ ] **Text.content**: String to display
- [ ] **Text.style**: Style for text
- [ ] **Text.alignment**: left, center, right
- [ ] **Text.render**: Draw single line of styled text

### 9.3 Paragraph [bd-2hs]

- [ ] **Paragraph.text**: Multi-line text content
- [ ] **Paragraph.style**: Style for text
- [ ] **Paragraph.wrap**: none (clip), char, word
- [ ] **Paragraph.alignment**: left, center, right
- [ ] **Paragraph.render**: Draw wrapped text

### 9.4 List [bd-2x7]

- [ ] **List.items**: Slice of strings
- [ ] **List.selected**: Optional selected index
- [ ] **List.style**: Style for unselected items
- [ ] **List.highlight_style**: Style for selected item
- [ ] **List.highlight_symbol**: Prefix for selected item (e.g., "> ")
- [ ] **List.render**: Draw navigable list

### 9.5 Table [bd-17u]

- [ ] **Table.header**: Optional header row
- [ ] **Table.rows**: Slice of row data
- [ ] **Table.widths**: Constraint slice for column widths
- [ ] **Table.selected**: Optional selected row index
- [ ] **Table.style**: Style for cells
- [ ] **Table.header_style**: Style for header row
- [ ] **Table.highlight_style**: Style for selected row
- [ ] **Table.render**: Draw table with columns

### 9.6 Gauge [bd-dmx]

- [ ] **Gauge.ratio**: Progress 0.0 to 1.0
- [ ] **Gauge.label**: Optional label text
- [ ] **Gauge.style**: Style for unfilled portion
- [ ] **Gauge.gauge_style**: Style for filled portion
- [ ] **Gauge.render**: Draw progress bar

### 9.7 Tabs [bd-zjw]

- [ ] **Tabs.titles**: Slice of tab title strings
- [ ] **Tabs.selected**: Currently selected tab index
- [ ] **Tabs.style**: Style for unselected tabs
- [ ] **Tabs.highlight_style**: Style for selected tab
- [ ] **Tabs.divider**: String between tabs (e.g., " | ")
- [ ] **Tabs.render**: Draw tab bar

### 9.8 Scrollbar [bd-1h6]

- [ ] **Scrollbar.total**: Total item count
- [ ] **Scrollbar.position**: Current scroll position
- [ ] **Scrollbar.viewport**: Visible item count
- [ ] **Scrollbar.style**: Style for scrollbar
- [ ] **Scrollbar.orientation**: vertical, horizontal
- [ ] **Scrollbar.render**: Draw scroll indicator

### 9.9 Clear [bd-2v0]

- [ ] **Clear.style**: Style to fill with (default: empty)
- [ ] **Clear.render**: Fill area with style (for popups)

---

## 10. Error Handling [bd-2jl]

### 10.1 Error Types

- [ ] **Error.TerminalInitFailed**: Could not initialize terminal
- [ ] **Error.TerminalQueryFailed**: Could not query terminal state
- [ ] **Error.BufferOverflow**: Buffer operation exceeded bounds
- [ ] **Error.InvalidUtf8**: Invalid UTF-8 in input
- [ ] **Error.IoError**: IO operation failed
- [ ] **Error.OutOfMemory**: Allocation failed

### 10.2 Error Philosophy

- [ ] **All errors explicit**: No panics in library code
- [ ] **Error unions throughout**: Functions return errors when fallible
- [ ] **catch unreachable justified**: Only when mathematically impossible

---

## 11. Platform Support

### 11.1 Primary Platforms [bd-1q1]

- [ ] **Linux support**: Full feature support
- [ ] **macOS support**: Full feature support

### 11.2 Secondary Platforms [bd-3nt]

- [ ] **Windows support**: Via Windows Console API or ConPTY
- [ ] **Windows Terminal detection**: Modern terminal vs legacy cmd
- [ ] **BSD support**: Best-effort, not actively tested

### 11.3 Terminal Compatibility [bd-2xj]

- [ ] **xterm compatibility**: Reference terminal
- [ ] **GNOME Terminal compatibility**: Common Linux terminal
- [ ] **iTerm2 compatibility**: Common macOS terminal
- [ ] **Windows Terminal compatibility**: Modern Windows
- [ ] **Alacritty compatibility**: Cross-platform GPU terminal
- [ ] **Kitty compatibility**: Feature-rich terminal

---

## 12. Integration

### 12.1 rich_zig Integration [bd-1af]

- [ ] **Use rich_zig Style**: Import or re-export Style type
- [ ] **Use rich_zig Color**: Import or re-export Color type
- [ ] **Use rich_zig text spans**: For styled text segments
- [ ] **ANSI rendering via rich_zig**: Escape sequence generation

### 12.2 Build System [bd-2oi]

- [ ] **build.zig module export**: Export zithril module
- [ ] **build.zig.zon dependencies**: Declare rich_zig dependency
- [ ] **Example executables**: Counter, list, tabs, ralph examples

---

## 13. Examples

### 13.1 Counter Example [bd-dif]

- [ ] **Minimal state**: Single counter value
- [ ] **Key handling**: q to quit, up/down to increment/decrement
- [ ] **Simple view**: Block with counter display

### 13.2 List Example [bd-1rz]

- [ ] **List state**: Items and selected index
- [ ] **Navigation**: j/k or arrows to move selection
- [ ] **Selection highlight**: Visual feedback

### 13.3 Tabs Example [bd-2m5]

- [ ] **Tab state**: Tab titles and active index
- [ ] **Tab switching**: Number keys or arrow keys
- [ ] **Content per tab**: Different view per tab

### 13.4 Ralph Example (Reference App) [bd-8pk]

- [ ] **Agent list**: Multiple agents with status
- [ ] **Agent detail panel**: Selected agent info
- [ ] **Log panel**: Scrollable log output
- [ ] **Status bar**: Help text
- [ ] **Progress gauges**: Per-agent progress
- [ ] **Focus management**: Switch between panels

---

## 14. Future Features (Not in Initial Release)

### 14.1 Mouse Support [bd-3kk]

- [ ] Clickable regions
- [ ] Drag selection
- [ ] Scroll wheel handling
- [ ] Hover detection

### 14.2 Scrollable Containers [bd-33j]

- [ ] Virtual scrolling for large lists
- [ ] Scroll state management
- [ ] Scrollbar integration

### 14.3 Text Input Widget [bd-t6z]

- [ ] Single-line input
- [ ] Cursor movement
- [ ] Selection
- [ ] Clipboard integration

### 14.4 Command/Async Pattern [bd-2xr]

- [ ] Command type definition
- [ ] Runtime command execution
- [ ] Result events
- [ ] Batch commands

### 14.5 Animation Helpers [bd-4m6]

- [ ] Easing functions
- [ ] Duration tracking
- [ ] Frame interpolation

### 14.6 Image Support [bd-2je]

- [ ] Sixel graphics detection and rendering
- [ ] Kitty graphics protocol
- [ ] iTerm2 inline images

### 14.7 Testing Utilities [bd-2gy]

- [ ] Recording/playback for tests
- [ ] Headless terminal mock
- [ ] Snapshot testing

---

## Implementation Priority

**Phase 1 - Core (Must Have)** - P1 beads
1. Geometry types (Rect, Position) [bd-2ad]
2. Style and Color [bd-1gb, bd-dx8]
3. Buffer and Cell [bd-3gl, bd-35j]
4. Terminal backend (raw mode, alternate screen, basic input) [bd-sr5, bd-2gz, bd-198, bd-3bl, bd-1k0]
5. Frame and basic layout [bd-fmp, bd-3lt, bd-1p0, bd-2zl, bd-2vo]
6. App runtime with main loop [bd-3go, bd-git, bd-1aw]
7. Integration [bd-1af, bd-2oi]

**Phase 2 - Widgets (Must Have)** - P2 beads
1. Block (borders) [bd-1nq]
2. Text (single line) [bd-2lq]
3. List (with selection) [bd-2x7]
4. Gauge (progress bar) [bd-dmx]

**Phase 3 - Layout (Must Have)** - P2 beads
1. Full constraint solver [bd-2vo]
2. Nested layouts

**Phase 4 - Polish (Should Have)** - P3 beads
1. Paragraph (wrapping) [bd-2hs]
2. Table [bd-17u]
3. Tabs [bd-zjw]
4. Scrollbar [bd-1h6]
5. Clear [bd-2v0]

**Phase 5 - Advanced (Nice to Have)** - P4 beads
1. Mouse support [bd-3kk]
2. Text input [bd-t6z]
3. Async commands [bd-2xr]
4. Scrollable containers [bd-33j]

---

## Quick Reference: All Beads

| Section | Bead ID | Description |
|---------|---------|-------------|
| Core Types | bd-2ad | Geometry (Rect, Position) |
| Core Types | bd-1gb | Style |
| Core Types | bd-dx8 | Color |
| Layout | bd-1p0 | Constraint Types |
| Layout | bd-2zl | Direction |
| Layout | bd-2vo | Layout Solver |
| Events | bd-14k | Event Union and Key Events |
| Events | bd-15o | Mouse Events |
| Events | bd-1b7 | Modifiers and Size |
| Actions | bd-1ku | Action Union |
| Actions | bd-2xr | Command Pattern (Future) |
| Buffer | bd-3gl | Cell |
| Buffer | bd-35j | Buffer |
| Buffer | bd-1cm | Buffer Diff |
| Frame | bd-fmp | Frame Struct and Methods |
| Frame | bd-3lt | Widget Interface |
| App | bd-3go | App Generic Struct |
| App | bd-git | App Configuration |
| App | bd-1aw | Main Loop |
| Terminal | bd-sr5 | Initialization |
| Terminal | bd-2gz | Cleanup |
| Terminal | bd-198 | Queries |
| Terminal | bd-3bl | Input Parsing |
| Terminal | bd-1k0 | Output |
| Widgets | bd-1nq | Block |
| Widgets | bd-2lq | Text |
| Widgets | bd-2hs | Paragraph |
| Widgets | bd-2x7 | List |
| Widgets | bd-17u | Table |
| Widgets | bd-dmx | Gauge |
| Widgets | bd-zjw | Tabs |
| Widgets | bd-1h6 | Scrollbar |
| Widgets | bd-2v0 | Clear |
| Errors | bd-2jl | Error Types |
| Platform | bd-1q1 | Linux and macOS |
| Platform | bd-3nt | Windows |
| Platform | bd-2xj | Terminal Compatibility |
| Integration | bd-1af | rich_zig |
| Integration | bd-2oi | Build System |
| Examples | bd-dif | Counter |
| Examples | bd-1rz | List |
| Examples | bd-2m5 | Tabs |
| Examples | bd-8pk | Ralph (Reference App) |
| Future | bd-3kk | Mouse Support |
| Future | bd-33j | Scrollable Containers |
| Future | bd-t6z | Text Input Widget |
| Future | bd-4m6 | Animation Helpers |
| Future | bd-2je | Image Support |
| Future | bd-2gy | Testing Utilities |
