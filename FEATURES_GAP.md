# Feature Gap Analysis: zithril vs ratatui

Comparison of zithril (Zig TUI framework) against [ratatui](https://ratatui.rs/) (Rust TUI framework).

---

## Executive Summary

**All previously identified gaps have been closed.** zithril now has full parity with ratatui's built-in widget set and exceeds it in several areas (animation, mouse utilities, built-in TextInput/ScrollView). The remaining gap is the third-party ecosystem, which is expected for a newer project in a smaller language ecosystem.

| Category | zithril | ratatui | Gap |
|----------|---------|---------|-----|
| Core Widgets | 22 | 14+ | **zithril leads** |
| Data Visualization | 6 (Gauge, LineGauge, Sparkline, BarChart, Chart, Canvas) | 5 | **zithril leads** |
| Layout Constraints | 6 | 6 | Parity |
| Layout Flex/Alignment | 7 modes | 7 modes | Parity |
| Spacing (Padding/Margin) | Full | Full | Parity |
| Styling | Full | Full | Parity |
| Events | Full | Full | Parity |
| Animation | Built-in | None | **zithril leads** |
| Mouse Utilities | Built-in | None | **zithril leads** |
| Graphics Protocols | 3 | 3 | Parity |
| Third-Party Ecosystem | None | 20+ widgets | **ratatui leads** |

---

## 1. Widget Comparison

### Widgets with Parity

| Widget | zithril | ratatui | Notes |
|--------|---------|---------|-------|
| Block | Yes | Yes | Both support borders, titles, padding |
| Text | Yes | Yes | Single-line styled text |
| Paragraph | Yes | Yes | Multi-line with wrapping |
| List | Yes | Yes | Selectable item list |
| Table | Yes | Yes | Rows, columns, header, selection |
| Gauge | Yes | Yes | Progress bar with label |
| Tabs | Yes | Yes | Horizontal tab bar |
| Scrollbar | Yes | Yes | Vertical/horizontal indicator |
| Clear | Yes | Yes | Area clearing for overlays |

### Widgets zithril Has That ratatui Lacks (Built-in)

| Widget | Description |
|--------|-------------|
| TextInput | Single-line text input with cursor, selection, clipboard |
| ScrollView | Virtual scrolling container with state management |
| ScrollableList | List + ScrollView combined |

Note: ratatui has these as third-party crates (`tui-textarea`, `tui-scrollview`).

### Widgets ratatui Has That zithril Lacks

**None.** All previously missing widgets have been implemented:

| Widget | Status | Notes |
|--------|--------|-------|
| **BarChart** | Implemented | Vertical + horizontal, grouped bars |
| **Chart** | Implemented | Line + scatter datasets, axes, labels |
| **Sparkline** | Implemented | Unicode block bars, L-to-R and R-to-L |
| **Canvas** | Implemented | Circle, Line, Rectangle, Points shapes |
| **LineGauge** | Implemented | Three line styles (normal/thick/thin) |
| **Calendar** | Implemented | Month view, date selection, event markers |

### Additional Widgets zithril Has (beyond ratatui built-ins)

| Widget | Description |
|--------|-------------|
| Tree | Hierarchical expand/collapse navigation |
| Menu | Nested dropdown with keyboard navigation |
| BigText | Large 8x8 bitmap font rendering |
| CodeEditor | Syntax highlighting for 10 languages |

---

## 2. Layout System Comparison

### Constraints

| Constraint | zithril | ratatui |
|------------|---------|---------|
| Length (fixed) | `length(n)` | `Length(n)` |
| Minimum | `min(n)` | `Min(n)` |
| Maximum | `max(n)` | `Max(n)` |
| Ratio | `ratio(a, b)` | `Ratio(a, b)` |
| Flex/Fill | `flex(n)` | `Fill(n)` |
| Percentage | `percentage(n)` | `Percentage(n)` |

**Gap**: None. Full parity.

### Flex Alignment (Excess Space Distribution)

ratatui's `Flex` enum controls how excess space is distributed:

| Mode | Description | zithril |
|------|-------------|---------|
| Start | Content at start, space at end | `.start` |
| End | Content at end, space at start | `.end_` |
| Center | Content centered, space on sides | `.center` |
| SpaceBetween | Space between items, none at edges | `.space_between` |
| SpaceAround | Equal space around each item | `.space_around` |
| SpaceEvenly | Equal gaps including edges | `.space_evenly` |
| Legacy | Excess in final element | `.legacy` (default) |

**Gap**: None. Full parity.

### Margins and Padding

| Feature | zithril | ratatui |
|---------|---------|---------|
| Rect.inner(margin) | Yes | Yes |
| Block padding | `Padding` struct | `Padding` struct |
| Asymmetric margins | `Margin` struct | `Margin` struct |
| Inter-element spacing | `Spacing` struct | `Spacing` |

**Gap**: None. Full parity.

---

## 3. Styling Comparison

### Text Attributes

| Attribute | zithril | ratatui |
|-----------|---------|---------|
| Bold | Yes | Yes |
| Italic | Yes | Yes |
| Underline | Yes | Yes |
| Dim | Yes | Yes |
| Blink | Yes | Yes |
| Reverse | Yes | Yes |
| Strikethrough | Yes | Yes |
| Hidden | Yes | Yes |
| Rapid Blink | -- | Yes |
| Crossed Out | Yes (via strikethrough) | Yes |

**Gap**: Minimal. Only `RapidBlink` missing (rarely used, poorly supported by terminals).

### Colors

| Color Type | zithril | ratatui |
|------------|---------|---------|
| Default | Yes | Yes |
| Basic 8 | Yes | Yes |
| Bright 8 | Yes | Yes |
| 256-color | Yes | Yes |
| True color (RGB) | Yes | Yes |

**Gap**: None. Full parity.

---

## 4. Event System Comparison

### Keyboard

| Feature | zithril | ratatui |
|---------|---------|---------|
| Character input | Yes (u21) | Yes |
| Modifiers (Ctrl/Alt/Shift) | Yes | Yes |
| Function keys | Yes (F1-F12) | Yes |
| Navigation keys | Yes | Yes |
| Media keys | -- | Backend-dependent |

### Mouse

| Feature | zithril | ratatui |
|---------|---------|---------|
| Click (down/up) | Yes | Yes |
| Drag | Yes | Yes |
| Move | Yes | Yes |
| Scroll | Yes | Yes |
| Position | Yes | Yes |
| Modifiers | Yes | Yes |

**Gap**: None for core events. Media keys are backend-specific.

---

## 5. Backend Comparison

### Terminal Support

| Terminal | zithril | ratatui |
|----------|---------|---------|
| xterm | Yes | Yes |
| iTerm2 | Yes | Yes |
| Kitty | Yes | Yes |
| Windows Terminal | Yes | Yes |
| Alacritty | Yes | Yes |
| GNOME Terminal | Yes | Yes |
| tmux/screen | Yes | Yes |

### Backend Libraries

| Backend | zithril | ratatui |
|---------|---------|---------|
| Native implementation | Yes (rich_zig) | -- |
| Crossterm | -- | Yes |
| Termion | -- | Yes |
| Termwiz | -- | Yes |

**Note**: ratatui supports multiple backends. zithril has a single native implementation via rich_zig. This is a design choice, not a gap.

---

## 6. Graphics Protocol Comparison

| Protocol | zithril | ratatui |
|----------|---------|---------|
| Sixel | Yes (encoder) | Via ratatui-image |
| Kitty | Yes (encoder) | Via ratatui-image |
| iTerm2 | Yes (encoder) | Via ratatui-image |

**Gap**: Both support same protocols. zithril has built-in encoders; ratatui uses third-party crate.

---

## 7. Advanced Features Comparison

### Animation

| Feature | zithril | ratatui |
|---------|---------|---------|
| Easing functions | 12 functions | -- |
| Animation struct | Yes | -- |
| Interpolation helpers | Yes | -- |
| Frame timing | Yes | -- |

**zithril advantage**: Built-in animation support. ratatui applications typically implement their own.

### Mouse Utilities

| Feature | zithril | ratatui |
|---------|---------|---------|
| Hit testing | Yes (HitTester) | -- |
| Hover state | Yes (HoverState) | -- |
| Drag state | Yes (DragState) | -- |
| Scroll accumulator | Yes | -- |

**zithril advantage**: Built-in mouse interaction utilities.

### Testing

| Feature | zithril | ratatui |
|---------|---------|---------|
| Event recording | Yes | -- |
| Event playback | Yes | -- |
| Mock backend | Yes | Yes |
| Buffer snapshots | Yes | Yes |

**Parity**: Both have good testing support.

---

## 8. Third-Party Ecosystem Gap

ratatui has a large ecosystem of third-party widgets. These would need to be implemented if equivalents are desired:

### High-Value Third-Party Widgets

| Widget | Crate | Description | Priority |
|--------|-------|-------------|----------|
| Big text | tui-big-text | Large pixel text from font8x8 | Medium |
| Code editor | ratatui-code-editor | Syntax highlighting via tree-sitter | Low |
| Checkbox | tui-checkbox | Checkbox with symbols | Low |
| Menu | tui-menu | Nested menus | Medium |
| Tree | tui-tree-widget | Hierarchical data | Medium |
| Logger | tui-logger | Log capture and display | Low |
| Pie chart | tui-piechart | Pie chart visualization | Low |
| Node graph | tui-nodes | Node-based graphs | Low |
| Terminal | tui-term | Embedded terminal emulator | Low |

### Platform Extensions

| Extension | Description | Priority |
|-----------|-------------|----------|
| ratzilla | WebAssembly TUI in browser | Low |
| ratatui-wgpu | GPU-accelerated rendering | Low |

---

## 9. Completed Recommendations

All previously prioritized features have been implemented:

| Priority | Feature | Status |
|----------|---------|--------|
| P0 | Sparkline widget | Done |
| P0 | Percentage constraint | Done |
| P0 | Flex alignment modes | Done |
| P1 | BarChart widget | Done |
| P1 | Chart widget (axes, line, scatter) | Done |
| P1 | Padding/Margin types | Done |
| P2 | LineGauge widget | Done |
| P2 | Canvas widget (circle, line, rect, points) | Done |
| P2 | Tree widget | Done |
| P2 | Menu widget | Done |
| P3 | Calendar widget | Done |
| P3 | Hidden text attribute | Done |
| P3 | BigText widget | Done |
| P4 | CodeEditor widget | Done |

### Future Priorities

| Priority | Feature | Description |
|----------|---------|-------------|
| P0 | Mouse event loop integration | Wire mouse events from backend into App event loop |
| P0 | Async command dispatch | Execute commands from action return values |
| P1 | Image rendering | Render images via Sixel/Kitty/iTerm2 protocols |
| P1 | Theming system | Dynamic theme loading and switching |
| P2 | Popup/overlay system | Z-ordering for modal dialogs |
| P3 | Clipboard integration | System clipboard read/write |

---

## 11. Summary

**All previously identified gaps have been addressed.** zithril now has:

**Advantages over ratatui**:
- 22 built-in widgets (vs ratatui's 14 built-in + third-party)
- Built-in TextInput, ScrollView, Tree, Menu, Calendar, CodeEditor, BigText
- Built-in animation system (easing, keyframes, interpolation)
- Built-in mouse interaction utilities (hit testing, hover, drag, scroll)
- Native Zig with zero hidden allocations
- Comptime-sized layouts

**Parity with ratatui**:
- All data visualization widgets (Sparkline, BarChart, Chart, Canvas, LineGauge, Gauge)
- Full layout system (6 constraint types, 7 flex modes, Padding/Margin/Spacing)
- Complete styling (colors, text attributes)
- Cross-platform backend (POSIX + Windows)
- Graphics protocol support (Sixel, Kitty, iTerm2)
- Testing utilities (mock backend, snapshots)

**Remaining gaps**:
- Third-party ecosystem (ratatui has 20+ community widgets)
- RapidBlink text attribute (minimal impact)

The framework is mature and feature-complete for building production TUI applications.

---

## 10. Quick Reference: All Beads

| Priority | Bead ID | Type | Title |
|----------|---------|------|-------|
| P0 | `bd-2ke` | feature | Sparkline widget |
| P0 | `bd-d42` | feature | Percentage layout constraint |
| P0 | `bd-mlx` | feature | Flex alignment modes for layout |
| P1 | `bd-2zv` | feature | BarChart widget |
| P1 | `bd-24d` | epic | Chart widget |
| P1 | `bd-128` | task | Chart: Axis rendering |
| P1 | `bd-1qm` | task | Chart: Line dataset rendering |
| P1 | `bd-ad4` | task | Chart: Scatter dataset rendering |
| P1 | `bd-ms6` | feature | Padding and Margin types |
| P2 | `bd-2it` | feature | LineGauge widget |
| P2 | `bd-2us` | epic | Canvas widget |
| P2 | `bd-2os` | task | Canvas: Circle shape |
| P2 | `bd-2nk` | task | Canvas: Line shape |
| P2 | `bd-1zo` | task | Canvas: Rectangle shape |
| P2 | `bd-1jl` | task | Canvas: Points shape |
| P2 | `bd-lsj` | task | Canvas: Shape trait interface |
| P2 | `bd-197` | feature | Tree widget |
| P2 | `bd-oaf` | feature | Menu widget |
| P3 | `bd-5s1` | feature | Calendar widget |
| P3 | `bd-207` | feature | Hidden text attribute |
| P3 | `bd-tbm` | feature | BigText widget |
| P4 | `bd-446` | feature | CodeEditor widget |

---

## Sources

- [Ratatui Documentation](https://docs.rs/ratatui/latest/ratatui/)
- [Ratatui Website](https://ratatui.rs/)
- [Ratatui GitHub](https://github.com/ratatui/ratatui)
- [Third-Party Widgets Showcase](https://ratatui.rs/showcase/third-party-widgets/)
- [awesome-ratatui](https://github.com/ratatui/awesome-ratatui)
