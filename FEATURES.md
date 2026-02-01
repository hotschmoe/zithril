# zithril Features

Itemized feature list for implementation. Each item represents a discrete, implementable unit.

---

## 1. Core Types

### 1.1 Geometry

- [ ] **Rect struct**: x, y, width, height (all u16)
- [ ] **Rect.inner(margin)**: Return new Rect inset by margin on all sides, saturating subtraction
- [ ] **Rect.area()**: Return width * height as u32
- [ ] **Rect.is_empty()**: Return true if area is zero
- [ ] **Rect.clamp(x, y)**: Clamp a point to be within the rect bounds
- [ ] **Position struct**: Simple x, y coordinate pair (u16, u16)

### 1.2 Style

- [ ] **Style struct**: fg, bg, bold, italic, underline, dim, blink, reverse, strikethrough
- [ ] **Style.patch(other)**: Merge another style on top, non-default values override
- [ ] **Style defaults**: All attributes default to false/default color

### 1.3 Color

- [ ] **Color.default**: Terminal default color
- [ ] **Color basic 8**: black, red, green, yellow, blue, magenta, cyan, white
- [ ] **Color bright variants**: bright_black through bright_white (8 colors)
- [ ] **Color.indexed(u8)**: 256-color palette support
- [ ] **Color.rgb(r, g, b)**: True color (24-bit) support

---

## 2. Layout System

### 2.1 Constraint Types

- [ ] **Constraint.length(n)**: Exactly n cells
- [ ] **Constraint.min(n)**: At least n cells
- [ ] **Constraint.max(n)**: At most n cells
- [ ] **Constraint.ratio(num, den)**: Fraction of available space
- [ ] **Constraint.flex(n)**: Proportional share (like CSS flex-grow)

### 2.2 Direction

- [ ] **Direction.horizontal**: Split left-to-right
- [ ] **Direction.vertical**: Split top-to-bottom

### 2.3 Layout Solver

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

### 3.1 Event Union

- [ ] **Event.key**: Key press with modifiers
- [ ] **Event.mouse**: Mouse action with position and modifiers
- [ ] **Event.resize**: Terminal size change
- [ ] **Event.tick**: Timer tick for animations/polling

### 3.2 Key Events

- [ ] **Key.code**: The key that was pressed
- [ ] **Key.modifiers**: Ctrl, Alt, Shift flags
- [ ] **KeyCode.char(u21)**: Unicode codepoint for printable characters
- [ ] **KeyCode navigation**: enter, tab, backtab, backspace, escape
- [ ] **KeyCode arrows**: up, down, left, right
- [ ] **KeyCode extended**: home, end, page_up, page_down, insert, delete
- [ ] **KeyCode function keys**: f(1-12)

### 3.3 Mouse Events

- [ ] **Mouse.x, Mouse.y**: Position in terminal coordinates
- [ ] **Mouse.kind**: down, up, drag, move, scroll_up, scroll_down
- [ ] **Mouse.modifiers**: Ctrl, Alt, Shift flags

### 3.4 Modifiers

- [ ] **Modifiers packed struct**: ctrl, alt, shift as bools

### 3.5 Size Event

- [ ] **Size.width, Size.height**: New terminal dimensions

---

## 4. Action System

### 4.1 Action Union

- [ ] **Action.none**: Continue running, no special action
- [ ] **Action.quit**: Exit the application
- [ ] **Action.command**: Execute async command (future feature)

### 4.2 Command Pattern (Future)

- [ ] **Command union type**: User-defined commands
- [ ] **Command execution by runtime**: Results return as events
- [ ] **Command.batch**: Execute multiple commands

---

## 5. Buffer System

### 5.1 Cell

- [ ] **Cell struct**: char (u21), style (Style), width (u8)
- [ ] **Cell defaults**: Space character, default style, width 1
- [ ] **Cell wide character support**: Width 2 for CJK/emoji

### 5.2 Buffer

- [ ] **Buffer struct**: width, height, cells array (row-major)
- [ ] **Buffer.set(x, y, cell)**: Set a single cell
- [ ] **Buffer.get(x, y)**: Get cell, return default if out of bounds
- [ ] **Buffer.set_string(x, y, str, style)**: Write string with style
- [ ] **Buffer.set_string wide char handling**: Proper width tracking
- [ ] **Buffer.set_string clipping**: Stop at buffer bounds
- [ ] **Buffer.fill(area, cell)**: Fill rectangular region
- [ ] **Buffer.set_style(area, style)**: Apply style to region, preserve chars
- [ ] **Buffer.diff(other)**: Compute changed cells between buffers

### 5.3 Buffer Diff

- [ ] **CellUpdate struct**: x, y, cell for each changed position
- [ ] **Diff algorithm**: Compare cell-by-cell, collect changes
- [ ] **Diff optimization**: Skip unchanged cells for minimal output

---

## 6. Frame System

### 6.1 Frame Struct

- [ ] **Frame generic over max_widgets**: Comptime-sized layout cache
- [ ] **Frame.buffer**: Reference to render buffer
- [ ] **Frame.size_**: Full terminal area as Rect

### 6.2 Frame Methods

- [ ] **Frame.size()**: Return full terminal area
- [ ] **Frame.layout(area, direction, constraints)**: Split area, return Rects
- [ ] **Frame.render(widget, area)**: Render any widget to buffer

### 6.3 Widget Interface

- [ ] **Widget render signature**: fn render(self, area: Rect, buf: *Buffer) void
- [ ] **Frame.render duck typing**: Accept any type with render method
- [ ] **No widget base class**: Composition via functions

---

## 7. App Runtime

### 7.1 App Generic Struct

- [ ] **App(State) type**: Generic over user state type
- [ ] **App.state**: User's state instance
- [ ] **App.update_fn**: Pointer to update function
- [ ] **App.view_fn**: Pointer to view function

### 7.2 App Configuration

- [ ] **tick_rate_ms**: Tick event interval (0 = disabled)
- [ ] **mouse_capture**: Enable mouse event reporting
- [ ] **paste_bracket**: Enable bracketed paste detection
- [ ] **alternate_screen**: Use alternate screen buffer

### 7.3 App Methods

- [ ] **App.init(config)**: Create app with config
- [ ] **App.run()**: Run main loop until quit

### 7.4 Main Loop

- [ ] **Poll event**: Wait for input or tick timeout
- [ ] **Call update**: User's update(state, event) -> Action
- [ ] **Check action**: Exit on .quit, handle .command
- [ ] **Call view**: User's view(state, frame)
- [ ] **Render**: Diff buffer, write changes to terminal
- [ ] **Loop**: Repeat until quit

---

## 8. Terminal Backend

### 8.1 Terminal Initialization

- [ ] **Raw mode enable**: Disable line buffering and echo
- [ ] **Alternate screen enter**: Preserve original terminal content
- [ ] **Cursor hide**: Hide cursor during rendering
- [ ] **Mouse enable**: Enable mouse event reporting (optional)
- [ ] **Bracketed paste enable**: Distinguish pasted text (optional)

### 8.2 Terminal Cleanup

- [ ] **Raw mode disable**: Restore normal input mode
- [ ] **Alternate screen leave**: Restore original content
- [ ] **Cursor show**: Restore cursor visibility
- [ ] **Mouse disable**: Stop mouse reporting
- [ ] **Bracketed paste disable**: Stop paste detection
- [ ] **Cleanup on panic**: Register handler for clean exit

### 8.3 Terminal Queries

- [ ] **Get terminal size**: Query current width/height
- [ ] **Detect color support**: 16/256/true color detection

### 8.4 Input Parsing

- [ ] **Read raw bytes**: Non-blocking read from stdin
- [ ] **Parse ANSI escape sequences**: Decode to Event
- [ ] **Arrow key parsing**: ESC [ A/B/C/D
- [ ] **Function key parsing**: ESC [ 1-24 ~
- [ ] **Modifier parsing**: ESC [ 1;5 A (Ctrl+Up)
- [ ] **Mouse X10 parsing**: ESC [ M ...
- [ ] **Mouse SGR parsing**: ESC [ < ...
- [ ] **UTF-8 character parsing**: Multi-byte sequences
- [ ] **Paste detection**: Bracketed paste sequences

### 8.5 Output

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

### 9.1 Block

- [ ] **Block.title**: Optional title string
- [ ] **Block.title_alignment**: left, center, right
- [ ] **Block.border**: none, plain, rounded, double, thick
- [ ] **Block.border_style**: Style for border characters
- [ ] **Block.style**: Background style for interior
- [ ] **Block.render**: Draw border and title to buffer

### 9.2 Text

- [ ] **Text.content**: String to display
- [ ] **Text.style**: Style for text
- [ ] **Text.alignment**: left, center, right
- [ ] **Text.render**: Draw single line of styled text

### 9.3 Paragraph

- [ ] **Paragraph.text**: Multi-line text content
- [ ] **Paragraph.style**: Style for text
- [ ] **Paragraph.wrap**: none (clip), char, word
- [ ] **Paragraph.alignment**: left, center, right
- [ ] **Paragraph.render**: Draw wrapped text

### 9.4 List

- [ ] **List.items**: Slice of strings
- [ ] **List.selected**: Optional selected index
- [ ] **List.style**: Style for unselected items
- [ ] **List.highlight_style**: Style for selected item
- [ ] **List.highlight_symbol**: Prefix for selected item (e.g., "> ")
- [ ] **List.render**: Draw navigable list

### 9.5 Table

- [ ] **Table.header**: Optional header row
- [ ] **Table.rows**: Slice of row data
- [ ] **Table.widths**: Constraint slice for column widths
- [ ] **Table.selected**: Optional selected row index
- [ ] **Table.style**: Style for cells
- [ ] **Table.header_style**: Style for header row
- [ ] **Table.highlight_style**: Style for selected row
- [ ] **Table.render**: Draw table with columns

### 9.6 Gauge

- [ ] **Gauge.ratio**: Progress 0.0 to 1.0
- [ ] **Gauge.label**: Optional label text
- [ ] **Gauge.style**: Style for unfilled portion
- [ ] **Gauge.gauge_style**: Style for filled portion
- [ ] **Gauge.render**: Draw progress bar

### 9.7 Tabs

- [ ] **Tabs.titles**: Slice of tab title strings
- [ ] **Tabs.selected**: Currently selected tab index
- [ ] **Tabs.style**: Style for unselected tabs
- [ ] **Tabs.highlight_style**: Style for selected tab
- [ ] **Tabs.divider**: String between tabs (e.g., " | ")
- [ ] **Tabs.render**: Draw tab bar

### 9.8 Scrollbar

- [ ] **Scrollbar.total**: Total item count
- [ ] **Scrollbar.position**: Current scroll position
- [ ] **Scrollbar.viewport**: Visible item count
- [ ] **Scrollbar.style**: Style for scrollbar
- [ ] **Scrollbar.orientation**: vertical, horizontal
- [ ] **Scrollbar.render**: Draw scroll indicator

### 9.9 Clear

- [ ] **Clear.style**: Style to fill with (default: empty)
- [ ] **Clear.render**: Fill area with style (for popups)

---

## 10. Error Handling

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

### 11.1 Primary Platforms

- [ ] **Linux support**: Full feature support
- [ ] **macOS support**: Full feature support

### 11.2 Secondary Platforms

- [ ] **Windows support**: Via Windows Console API or ConPTY
- [ ] **Windows Terminal detection**: Modern terminal vs legacy cmd
- [ ] **BSD support**: Best-effort, not actively tested

### 11.3 Terminal Compatibility

- [ ] **xterm compatibility**: Reference terminal
- [ ] **GNOME Terminal compatibility**: Common Linux terminal
- [ ] **iTerm2 compatibility**: Common macOS terminal
- [ ] **Windows Terminal compatibility**: Modern Windows
- [ ] **Alacritty compatibility**: Cross-platform GPU terminal
- [ ] **Kitty compatibility**: Feature-rich terminal

---

## 12. Integration

### 12.1 rich_zig Integration

- [ ] **Use rich_zig Style**: Import or re-export Style type
- [ ] **Use rich_zig Color**: Import or re-export Color type
- [ ] **Use rich_zig text spans**: For styled text segments
- [ ] **ANSI rendering via rich_zig**: Escape sequence generation

### 12.2 Build System

- [ ] **build.zig module export**: Export zithril module
- [ ] **build.zig.zon dependencies**: Declare rich_zig dependency
- [ ] **Example executables**: Counter, list, tabs, ralph examples

---

## 13. Examples

### 13.1 Counter Example

- [ ] **Minimal state**: Single counter value
- [ ] **Key handling**: q to quit, up/down to increment/decrement
- [ ] **Simple view**: Block with counter display

### 13.2 List Example

- [ ] **List state**: Items and selected index
- [ ] **Navigation**: j/k or arrows to move selection
- [ ] **Selection highlight**: Visual feedback

### 13.3 Tabs Example

- [ ] **Tab state**: Tab titles and active index
- [ ] **Tab switching**: Number keys or arrow keys
- [ ] **Content per tab**: Different view per tab

### 13.4 Ralph Example (Reference App)

- [ ] **Agent list**: Multiple agents with status
- [ ] **Agent detail panel**: Selected agent info
- [ ] **Log panel**: Scrollable log output
- [ ] **Status bar**: Help text
- [ ] **Progress gauges**: Per-agent progress
- [ ] **Focus management**: Switch between panels

---

## 14. Future Features (Not in Initial Release)

### 14.1 Mouse Support

- [ ] Clickable regions
- [ ] Drag selection
- [ ] Scroll wheel handling
- [ ] Hover detection

### 14.2 Scrollable Containers

- [ ] Virtual scrolling for large lists
- [ ] Scroll state management
- [ ] Scrollbar integration

### 14.3 Text Input Widget

- [ ] Single-line input
- [ ] Cursor movement
- [ ] Selection
- [ ] Clipboard integration

### 14.4 Command/Async Pattern

- [ ] Command type definition
- [ ] Runtime command execution
- [ ] Result events
- [ ] Batch commands

### 14.5 Animation Helpers

- [ ] Easing functions
- [ ] Duration tracking
- [ ] Frame interpolation

### 14.6 Image Support

- [ ] Sixel graphics detection and rendering
- [ ] Kitty graphics protocol
- [ ] iTerm2 inline images

### 14.7 Testing

- [ ] Recording/playback for tests
- [ ] Headless terminal mock
- [ ] Snapshot testing

---

## Implementation Priority

**Phase 1 - Core (Must Have)**
1. Geometry types (Rect, Position)
2. Style and Color
3. Buffer and Cell
4. Terminal backend (raw mode, alternate screen, basic input)
5. Frame and basic layout
6. App runtime with main loop

**Phase 2 - Widgets (Must Have)**
1. Block (borders)
2. Text (single line)
3. List (with selection)
4. Gauge (progress bar)

**Phase 3 - Layout (Must Have)**
1. Full constraint solver
2. Nested layouts

**Phase 4 - Polish (Should Have)**
1. Paragraph (wrapping)
2. Table
3. Tabs
4. Scrollbar
5. Clear

**Phase 5 - Advanced (Nice to Have)**
1. Mouse support
2. Text input
3. Async commands
4. Scrollable containers
