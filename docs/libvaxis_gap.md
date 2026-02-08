# Libvaxis Feature Gap Analysis

Comparison of zithril (v0.18.0) against [libvaxis](https://github.com/rockorager/libvaxis) (Zig 0.15.1).
Both are Zig TUI libraries with immediate-mode rendering and double-buffered cell diffing.
This document catalogs every notable libvaxis feature, whether we have it, and recommendations
for closing gaps.

---

## Full Feature Matrix

### Terminal Capability Detection

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| Terminal type detection | Direct terminal queries (no terminfo) | Env var sniffing (14 terminal types) | YES |
| Color support detection | Query-based | Env var + COLORTERM heuristics | YES |
| Unicode width mode (Mode 2027) | Negotiated with terminal | Static tables from rich_zig | YES |
| Color mode updates (Mode 2031) | Supported | No | YES |
| In-band resize (Mode 2048) | Supported | ioctl / Windows API | Minor |
| Sync output (Mode 2026) | Supported | Supported | -- |
| Kitty keyboard protocol | Supported | Supported | -- |
| Bracketed paste | Supported | Supported | -- |

### Cell Model

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| Character storage | `[]const u8` grapheme cluster | `u21` single codepoint | YES |
| Width tracking | Per-grapheme, deferred measurement | Per-codepoint, static table | YES |
| Style fields | fg, bg, underline color, bools | fg, bg, full SGR attribute set | -- |
| Hyperlink (OSC 8) | Cell-level `link` field | No | YES |
| Image placement | Cell-level `image` field | No | YES |
| Superscript/subscript scaling | `scale` field | No | Minor |

### Rendering & Windowing

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| Double-buffered diffing | Yes | Yes | -- |
| Sync output wrapping | Yes | Yes | -- |
| Window hierarchy (nested clipping) | Window struct with parent offsets | Flat buffer (Frame renders widgets directly) | Design choice |
| Surface z-indexing | Yes (vxfw SubSurface) | No (widgets render in call order) | Design choice |
| Cursor shape control | setCursorShape() on Window | No API (raw escape only) | Minor |
| Mouse shape (OSC 22) | Supported | No | Minor |

### Input Handling

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| Keyboard (standard) | Yes | Yes | -- |
| Kitty keyboard (CSI u) | Yes | Yes | -- |
| Mouse (SGR + X10) | Yes | Yes | -- |
| Bracketed paste | Yes | Yes | -- |
| Custom event union (comptime) | Yes (exhaustive switching) | Fixed Event union | Design choice |
| Multithreaded event loop | Built-in option | Single-threaded only | YES |

### Framework Layer

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| High-level framework | vxfw (Flutter-inspired retained mode) | Single immediate-mode API | Design choice |
| Event bubbling/capture phases | Yes (vxfw EventContext) | Flat dispatch to update() | Design choice |
| Focus management | Built into vxfw | Manual (user manages focus state) | Design choice |
| Arena-per-frame allocation | Yes (vxfw DrawContext) | Zero allocation (no allocator in view) | Tradeoff |
| Async command queue | vxfw command system | Action enum (command variant stubbed) | Partial |

### Widgets (Low-Level)

| Widget | libvaxis | zithril |
|--------|----------|---------|
| Text / Paragraph | TextView | Text, Paragraph (4 wrap modes) |
| Text input | TextInput | TextInput |
| Table | Table | Table |
| Scrollbar | Scrollbar | Scrollbar |
| ScrollView | ScrollView | ScrollView, ScrollableList |
| Code viewer | CodeView | CodeEditor (syntax highlighting) |
| Line numbers | LineNumbers | No (CodeEditor handles internally) |
| Terminal emulator | Terminal | **No** |
| Alignment | alignment module | Flex alignment modes on layout |
| View container | View | Block |

### Widgets (vxfw)

| Widget | libvaxis vxfw | zithril equivalent |
|--------|---------------|-------------------|
| Button | Yes | No (trivial to build) |
| Text | Yes | Text |
| TextField | Yes | TextInput |
| RichText | Yes | Paragraph + ANSI parsing |
| Border | Yes | Block (borders built in) |
| Center | Yes | Flex alignment .center |
| FlexColumn / FlexRow | Yes | layout() with .vertical / .horizontal |
| Padding | Yes | Padding type + Block inner area |
| SizedBox | Yes | Constraint .length() |
| SplitView | Yes | layout() with two constraints |
| ListView | Yes | List, ScrollableList |
| ScrollView / ScrollBars | Yes | ScrollView, Scrollbar |
| Spinner | Yes | No |

### Widgets zithril Has, libvaxis Does Not

| Widget | Purpose |
|--------|---------|
| Sparkline | Inline trend graph (8-height) |
| BarChart | Grouped vertical/horizontal bars |
| Chart | XY line and scatter plots with axes |
| Canvas | Arbitrary shape drawing (points, lines, circles, rects) |
| LineGauge | Compact single-line progress bar |
| Gauge | Full progress bar with label |
| Tree | Hierarchical expand/collapse navigation |
| Menu | Nested dropdown menu |
| Calendar | Monthly calendar picker |
| BigText | Large 8x8 bitmap text (4 font sizes) |
| Tabs | Tab header bar |
| Clear | Fill area with style |

### Image / Graphics

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| Kitty graphics protocol | Full pipeline (transmit, display, scale, z-index) | Encoder only (no buffer integration) | YES |
| Sixel | No | Encoder only (no buffer integration) | Partial |
| iTerm2 inline images | No | Encoder only (no buffer integration) | Partial |
| Image scaling modes | none / fill / fit / contain | No | YES |
| Cell-level image placement | Yes (Image.Placement in Cell) | No | YES |
| Image in widget tree | Natural (cell contains placement) | Not wired | YES |

### Terminal Features (OSC / DEC Modes)

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| Hyperlinks (OSC 8) | Yes | No | YES |
| System clipboard (OSC 52) | Yes | No | YES |
| Notifications (OSC 9/777) | Yes | No | Minor |
| Fancy underlines (undercurl, dotted, dashed) | Yes | underline + underline2 (SGR 21) only | Partial |
| Underline color | Yes (Style.ul) | No separate underline color | YES |

### Color & Theming

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| RGB colors | Yes | Yes | -- |
| 256 colors | Yes | Yes | -- |
| 16 standard colors | Yes | Yes | -- |
| AdaptiveColor (auto-downgrade) | No | Yes (via rich_zig) | They lack |
| HSL color space | No | Yes (via rich_zig) | They lack |
| Gradients | No | Yes (via rich_zig) | They lack |
| WCAG contrast ratio | No | Yes (via rich_zig) | They lack |
| Named theme registry | No | Yes (via rich_zig) | They lack |
| Underline color (separate) | Yes | No | YES |

### Testing & QA

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| Event recording/playback | No | TestRecorder/Player | They lack |
| Mock backend (headless) | No | MockBackend | They lack |
| Snapshot testing | No | Snapshot (annotated text) | They lack |
| Scenario DSL | No | ScenarioParser/Runner | They lack |
| Accessibility audits | No | auditContrast, auditKeyboardNav | They lack |

### Other

| Feature | libvaxis | zithril | Gap? |
|---------|----------|---------|------|
| Animation / easing | No | Full module (12 easing functions, keyframes) | They lack |
| Pattern highlighting | No | Highlighter (numbers, bools, URLs, custom) | They lack |
| Pretty printing | No | Comptime Zig value formatter | They lack |
| ANSI parsing | No (raw cells) | fromAnsi, stripAnsi, parseAnsiToSegments | They lack |
| Grapheme cache | GraphemeCache module | No (single codepoint per cell) | Related to cell gap |
| Threading | Multi-threaded event loop | Single-threaded | YES |

---

## Recommendations

### R1: Grapheme Cluster Cells

**Priority**: High
**Target**: zithril (`src/cell.zig`, `src/buffer.zig`)
**Why**: Our Cell stores a single `u21` codepoint. This means multi-codepoint grapheme
clusters (flag emoji, ZWJ family sequences, accented characters composed of base + combining
mark) cannot be represented correctly. This is a correctness issue for any application
rendering internationalized or emoji-heavy text.

**What changes**:
- Cell.char changes from `u21` to a type that can hold a grapheme cluster.
  Options: (a) small inline buffer (e.g. `[8]u8` covers >99% of clusters) with overflow
  to a side table, (b) `[]const u8` slice into a per-frame arena. Option (a) keeps
  cells value-typed and avoids allocation; option (b) matches libvaxis but requires
  a frame-scoped allocator.
- Buffer.setString() already iterates UTF-8; it would need to segment by grapheme
  boundary instead of by codepoint. rich_zig's cell width function already handles
  individual codepoints but would need a grapheme-cluster-aware wrapper.
- Width calculation: when the cluster width is ambiguous, consider deferring to
  terminal measurement (query-based width, like libvaxis) as a future enhancement.

**What stays in rich_zig**: Grapheme segmentation and cluster width calculation
should live in rich_zig since they are terminal-primitive concerns. File an upstream
issue for a grapheme iterator and cluster width function.

**Impact**: Touches Cell, Buffer, and every widget that writes characters. This is the
single largest change on this list and should be designed carefully before implementation.

---

### R2: Terminal Query-Based Capability Detection

**Priority**: High
**Target**: zithril (`src/backend.zig`) and rich_zig (`src/terminal.zig`)
**Why**: Our current detection enumerates 14 known terminal types via env vars
(TERM, TERM_PROGRAM, COLORTERM, etc.) and maps each to a capabilities struct.
This is fragile -- any new terminal, custom build, or unusual configuration
falls through to conservative defaults. libvaxis queries the terminal directly
using standard escape sequences and parses the responses, which works with any
terminal that supports the query, regardless of its name.

**Key queries to implement**:
- **DA1** (Device Attributes, `ESC [ c`): identifies terminal class
- **XTVERSION** (`ESC [ > 0 q`): returns terminal name + version string
- **DECRQM** (Request Mode, `ESC [ ? <mode> $ p`): checks if a specific mode
  (2026 sync output, 2027 unicode, 2048 in-band resize) is supported
- **DSR** (Device Status Report, `ESC [ 6 n`): cursor position
- **Color query** (`ESC ] 11 ; ? BEL`): background color for light/dark detection
- **Kitty keyboard query** (`ESC [ ? u`): kitty keyboard support

**What goes where**:
- **rich_zig**: Low-level query/response primitives. Functions that write a query
  sequence and parse the response bytes. These are terminal I/O primitives.
- **zithril**: Orchestration during `Backend.init()`. Send queries, wait briefly
  for responses (with timeout), parse results into TerminalCapabilities. Fall back
  to env var heuristics when queries time out (e.g. piped output, screen, old terminals).

**Complexity**: Medium-high. The main challenge is timing -- queries are async (write
query, read response from stdin), and responses can intermix with user input. libvaxis
solves this with a dedicated parser state machine in its event loop. We would need
similar logic in our input parser, or a dedicated init-time query phase before the
event loop starts.

---

### R3: Image Rendering Pipeline

**Priority**: Medium
**Target**: zithril (`src/graphics.zig`, `src/cell.zig`, `src/buffer.zig`)
**Why**: We already have protocol encoders for Sixel, Kitty, and iTerm2, and
we detect graphics capabilities at runtime. But the encoders are not wired into
the rendering pipeline -- there is no way to place an image into the buffer and
have it appear on screen. libvaxis has a complete pipeline: Cell contains an
optional Image.Placement, the screen writer emits the appropriate protocol
sequences, and images participate in z-ordering and clipping.

**What changes**:
- Add an optional image placement field to Cell (or a parallel image layer on Buffer)
- Define scaling modes: none, fill, fit, contain
- Wire Buffer/Frame to emit image sequences during renderBuffer()
- The existing encoders (SixelEncoder, KittyEncoder, ITerm2Encoder) already generate
  the correct escape sequences; this work is about plumbing them into the render path

**What goes where**:
- **zithril**: All image rendering pipeline work. Image placement, scaling logic,
  buffer integration, and render-time sequence emission are TUI framework concerns.
- **rich_zig**: No changes needed. The protocol sequences are terminal-level but
  our encoders already handle them.

**Design consideration**: Images in cells vs. an overlay layer. Cell-level placement
(libvaxis approach) is simpler but makes cells larger. An overlay layer keeps cells
lean but adds a second rendering pass. Recommend starting with cell-level placement
for simplicity.

---

### R4: Hyperlinks (OSC 8)

**Priority**: Medium
**Target**: zithril (`src/cell.zig`, `src/backend.zig`)
**Why**: OSC 8 hyperlinks (`ESC ] 8 ; params ; uri ST`) let terminal text be
clickable. This is widely supported (iTerm2, WezTerm, Kitty, Windows Terminal,
GNOME Terminal, Konsole, foot) and cheap to implement. libvaxis stores a hyperlink
per cell; we have no support.

**What changes**:
- Add an optional hyperlink field to Cell or Style. A hyperlink is a URI string
  plus an optional ID (for grouping cells into one link).
- During renderBuffer(), when a cell has a hyperlink different from the previous
  cell, emit OSC 8 open/close sequences.
- Provide a convenience method on Buffer or Frame for writing a linked string.

**What goes where**:
- **zithril**: Hyperlink field on Cell, render-time OSC 8 emission, convenience API.
- **rich_zig**: OSC 8 sequence constants (open/close format strings). These are
  terminal primitives like sync output sequences.

**Complexity**: Low. This is a straightforward addition with no architectural changes.

---

### R5: Underline Color and Extended Underline Styles

**Priority**: Medium
**Target**: rich_zig (`src/style.zig`) and zithril (`src/style.zig`)
**Why**: libvaxis supports a separate underline color (`Style.ul`) and multiple
underline styles (curly/dotted/dashed via SGR 4:3, 4:4, 4:5). We support
underline (SGR 4) and double underline (SGR 21) but no underline color or
curly/dotted/dashed variants. Fancy underlines are used for spell-check
indicators, error squiggles, and decorative text -- valuable for code editors
and rich text display.

**What changes**:
- Add underline color field to Style (separate from fg/bg)
- Add underline style enum: none, single, double, curly, dotted, dashed
- Emit SGR 58;2;r;g;b for underline color, SGR 4:N for underline style
- Emit SGR 59 to reset underline color

**What goes where**:
- **rich_zig**: Underline color field and underline style enum on Style, SGR
  rendering for both. These are SGR primitives.
- **zithril**: Update Style wrapper to expose the new fields via method chaining
  (e.g. `.underlineColor(.red)`, `.underlineCurly()`).

---

### R6: System Clipboard (OSC 52)

**Priority**: Low
**Target**: zithril (`src/backend.zig`)
**Why**: OSC 52 lets applications read from and write to the system clipboard via
escape sequences. This is useful for copy/paste in TUI apps without requiring
external tools (xclip, pbcopy). Supported by most modern terminals.

**What changes**:
- Add clipboard read/write functions to Backend
- Write: `ESC ] 52 ; c ; <base64-data> ST`
- Read: `ESC ] 52 ; c ; ? ST` (response comes via input as OSC 52 reply)
- Parse clipboard response in input.zig

**What goes where**:
- **zithril**: Clipboard API on Backend or as standalone functions. The
  read path requires input parser changes to handle OSC 52 responses.
- **rich_zig**: OSC 52 sequence format constants.

---

### R7: Threading / Multi-Threaded Event Loop

**Priority**: Medium
**Target**: zithril (`src/app.zig`)
**Why**: Our event loop is single-threaded: poll for input, call update, call view,
render, repeat. This means long-running update() or view() calls block input
processing. libvaxis offers a multi-threaded event loop where input parsing runs
on a separate thread and events are delivered via a thread-safe queue. This is
important for applications that do background work (network requests, file I/O,
process monitoring) and need responsive input handling.

**What changes**:
- Add a threaded event loop option alongside the current single-threaded one.
  The user selects which mode at App init time.
- Threaded mode: spawn a reader thread that polls stdin and pushes events into
  a thread-safe queue. The main thread drains the queue, calls update/view, and
  renders. This keeps the current API shape (update/view are always called from
  the main thread) while unblocking input.
- Also enables: background command execution for the existing Action.command
  variant, which is currently stubbed.

**What goes where**:
- **zithril**: All threading work. Thread-safe event queue, reader thread
  lifecycle, App config option. rich_zig has no threading concerns.

**Design consideration**: Zig's standard library provides `std.Thread` and
`std.Thread.Mutex`. The queue can be a bounded ring buffer protected by a mutex,
or a lock-free MPSC queue. Start with mutex-based for simplicity.

**Complexity**: Medium. The main challenge is clean shutdown (signaling the reader
thread to exit) and ensuring the reader thread does not interfere with terminal
restore on panic/exit.

---

### R8: Terminal Emulator Widget

**Priority**: Low
**Target**: zithril (`src/widgets/`)
**Why**: libvaxis ships a Terminal widget -- a VT parser embedded in a widget that
can render the output of a child process. This enables split-pane terminal
multiplexing, embedded shells, and process output viewers within a TUI app.
It is a complex but high-value widget for power-user applications.

**What changes**:
- Implement a VT100/VT220 parser that processes escape sequences and maintains
  a virtual screen buffer (rows x cols of cells).
- Widget renders the virtual screen buffer into the parent buffer.
- Requires: PTY management (forkpty/openpty on POSIX, ConPTY on Windows),
  non-blocking reads from child process, and a subset of terminal emulation
  (cursor movement, scrolling, SGR styling, alternate screen).
- This is the most complex single widget possible in a TUI framework.

**What goes where**:
- **zithril**: The widget, PTY management, VT parser. This is a TUI-framework
  feature, not a terminal primitive. rich_zig should not be involved.

**Complexity**: High. A minimal implementation (VT100 subset: cursor movement,
SGR, scroll, clear) is feasible. Full VT220/xterm compatibility is a major
project on its own. Recommend starting with a minimal "process output viewer"
that handles the most common sequences, then iterating.

**Prerequisite**: R7 (threading) would make this significantly easier, since
the child process output needs to be read without blocking the event loop.

---

## Priority Summary

| # | Feature | Priority | Target | Complexity | Prerequisite |
|---|---------|----------|--------|------------|-------------|
| R1 | Grapheme cluster cells | High | zithril + rich_zig | High | -- |
| R2 | Terminal query detection | High | zithril + rich_zig | Medium-High | -- |
| R3 | Image rendering pipeline | Medium | zithril | Medium | -- |
| R4 | Hyperlinks (OSC 8) | Medium | zithril + rich_zig | Low | -- |
| R5 | Underline color + styles | Medium | rich_zig + zithril | Low | -- |
| R6 | System clipboard (OSC 52) | Low | zithril + rich_zig | Low | -- |
| R7 | Threaded event loop | Medium | zithril | Medium | -- |
| R8 | Terminal emulator widget | Low | zithril | High | R7 |

### Suggested Implementation Order

```
Phase 1 (foundations):
  R4  Hyperlinks         -- low complexity, high user value, unblocks nothing
  R5  Underline styles   -- low complexity, improves style parity

Phase 2 (correctness):
  R1  Grapheme clusters  -- correctness fix, largest single change
  R2  Terminal queries   -- reliability improvement, replaces fragile heuristics

Phase 3 (capabilities):
  R7  Threading          -- enables async commands and R8
  R3  Image pipeline     -- wires existing encoders into render path
  R6  Clipboard          -- convenience feature

Phase 4 (advanced):
  R8  Terminal widget    -- requires R7, complex standalone project
```

---

## What We Do Better (No Action Needed)

These are areas where zithril has clear advantages over libvaxis. No gap to close;
maintain and extend these strengths:

- **Widget breadth**: 22 widgets vs ~10+10, especially data visualization (Sparkline,
  BarChart, Chart, Canvas) and navigation (Tree, Menu, Calendar)
- **Layout flexibility**: 6 constraint types + 7 flex alignment modes
- **Zero-allocation views**: View functions take no allocator, hard guarantee
- **Animation system**: 12 easing functions, keyframe animations, interpolation utilities
- **QA framework**: TestRecorder, MockBackend, Snapshot, ScenarioParser, accessibility audits
- **Color science**: HSL, gradients, WCAG contrast, AdaptiveColor (via rich_zig)
- **Rich text pipeline**: ANSI parsing, pattern highlighting, comptime pretty printing
- **Mouse utilities**: HitTester, HoverState, DragState, ScrollAccumulator
- **Multiple graphics protocols**: Sixel + Kitty + iTerm2 detection (vs Kitty only)
- **Showcases as QA**: 3 runnable showcases that double as integration test suites
