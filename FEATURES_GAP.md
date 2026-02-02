# Feature Gap Analysis: zithril vs ratatui

Comparison of zithril (Zig TUI framework) against [ratatui](https://ratatui.rs/) (Rust TUI framework).

---

## Executive Summary

zithril has strong parity with ratatui's core functionality. The main gaps are in **data visualization widgets** (charts, sparklines, canvas) and **layout flexibility** (margins, padding, Flex alignment modes). The third-party ecosystem is the largest gap but is expected for a newer project.

| Category | zithril | ratatui | Gap |
|----------|---------|---------|-----|
| Core Widgets | 11 | 14+ | Minor |
| Data Visualization | 1 (Gauge) | 5 | **Major** |
| Layout Constraints | 5 | 6 | Minor |
| Layout Flex/Alignment | None | 7 modes | **Moderate** |
| Styling | Full | Full | Parity |
| Events | Full | Full | Parity |
| Graphics Protocols | 3 | 3 | Parity |
| Third-Party Ecosystem | None | 20+ widgets | **Major** |

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

| Widget | Priority | Description | Effort |
|--------|----------|-------------|--------|
| **BarChart** | High | Grouped bar charts for data visualization | Medium |
| **Chart** | High | Line graphs and scatter plots with axes | High |
| **Sparkline** | High | Compact inline data visualization | Low |
| **Canvas** | Medium | Arbitrary shape drawing (lines, circles, maps) | High |
| **LineGauge** | Low | Thin-line progress indicator | Low |
| **Calendar** | Low | Monthly calendar widget | Medium |

### Missing Canvas Shapes (if Canvas implemented)

| Shape | Description |
|-------|-------------|
| Circle | Center, radius, color |
| Line | Two-point line |
| Rectangle | Basic rectangle |
| Points | Scatter plot points |
| Map | World map with resolution control |
| Label | Text on canvas |
| Custom shapes | User-defined via Shape trait |

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
| Percentage | -- | `Percentage(n)` |

**Gap**: zithril lacks `Percentage` constraint. Can be approximated with `ratio(n, 100)` but less convenient.

### Flex Alignment (Excess Space Distribution)

ratatui's `Flex` enum controls how excess space is distributed:

| Mode | Description | zithril |
|------|-------------|---------|
| Start | Content at start, space at end | -- |
| End | Content at end, space at start | -- |
| Center | Content centered, space on sides | -- |
| SpaceBetween | Space between items, none at edges | -- |
| SpaceAround | Equal space around each item | -- |
| SpaceEvenly | Equal gaps including edges | -- |
| Legacy | Excess in final element | Default behavior |

**Gap**: zithril only supports Legacy-style distribution. Adding Flex alignment would improve layout flexibility.

### Margins and Padding

| Feature | zithril | ratatui |
|---------|---------|---------|
| Rect.inner(margin) | Yes | Yes |
| Block padding | Via style | `Padding` struct |
| Asymmetric margins | Manual Rect math | `Margin` struct |
| Inter-element spacing | -- | `Spacing` |

**Gap**: No built-in `Padding`, `Margin`, or `Spacing` types. Users must calculate manually.

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
| Hidden | -- | Yes |
| Rapid Blink | -- | Yes |
| Crossed Out | Yes (via strikethrough) | Yes |

**Gap**: Minor. Missing `Hidden` and `RapidBlink` (rarely used).

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

## 9. Prioritized Recommendations

### P0 - High Impact, Reasonable Effort

| Feature | Bead ID | Description |
|---------|---------|-------------|
| Sparkline widget | `bd-2ke` | Compact data visualization, low effort |
| Percentage constraint | `bd-d42` | Convenience for common layouts |
| Flex alignment modes | `bd-mlx` | Start, Center, End, SpaceBetween, SpaceAround, SpaceEvenly |

### P1 - High Impact, Higher Effort

| Feature | Bead ID | Description |
|---------|---------|-------------|
| BarChart widget | `bd-2zv` | Data visualization for dashboards |
| Chart widget | `bd-24d` | Line graphs with axes (epic) |
| - Axis rendering | `bd-128` | X/Y axes, ticks, labels, auto-scaling |
| - Line dataset | `bd-1qm` | Connect data points with lines |
| - Scatter dataset | `bd-ad4` | Individual point markers |
| Padding/Margin types | `bd-ms6` | Layout convenience structs |

### P2 - Medium Impact

| Feature | Bead ID | Description |
|---------|---------|-------------|
| LineGauge widget | `bd-2it` | Thin progress variant |
| Canvas widget | `bd-2us` | Arbitrary drawing (epic) |
| - Circle shape | `bd-2os` | Bresenham circle algorithm |
| - Line shape | `bd-2nk` | Bresenham line algorithm |
| - Rectangle shape | `bd-1zo` | Fill or outline mode |
| - Points shape | `bd-1jl` | Scatter plot points |
| - Shape trait | `bd-lsj` | Custom shape extensibility |
| Tree widget | `bd-197` | Hierarchical data display |
| Menu widget | `bd-oaf` | Nested navigation |

### P3 - Low Priority

| Feature | Bead ID | Description |
|---------|---------|-------------|
| Calendar widget | `bd-5s1` | Monthly calendar display |
| Hidden text attribute | `bd-207` | Invisible text rendering |
| BigText widget | `bd-tbm` | Decorative large text |
| CodeEditor widget | `bd-446` | Syntax highlighting (P4 backlog) |

---

## 11. Summary

**Strengths of zithril vs ratatui**:
- Built-in TextInput and ScrollView (ratatui needs third-party)
- Built-in animation system
- Built-in mouse interaction utilities
- Native Zig with zero hidden allocations
- Comptime-sized layouts

**Gaps to address**:
1. Data visualization widgets (Sparkline, BarChart, Chart)
2. Layout Flex alignment modes
3. Convenience types (Percentage, Padding, Margin)
4. Canvas for arbitrary drawing

The core architecture is solid. Focus on data visualization widgets for the highest impact.

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
