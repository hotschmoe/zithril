# QA Testing Framework Design

A plan for turning zithril's existing testing primitives into a complete QA
framework that users can opt into for automated TUI testing.

---

## Current State

`src/testing.zig` already provides:

| Primitive       | What it does                                        |
|-----------------|-----------------------------------------------------|
| `TestRecorder`  | Records events with timestamps (comptime capacity)  |
| `TestPlayer`    | Replays events sequentially or timed                |
| `MockBackend`   | Headless terminal (configurable size, 256KB capture) |
| `Snapshot`      | Buffer-to-text, diff, golden file comparison        |
| Helper fns      | `keyEvent()`, `mouseEvent()`, `expectCell()`, etc.  |

The architecture is inherently testable. `update()` and `view()` are pure
functions. `Input.parse()` is pure. Buffer is in-memory. The Backend abstracts
all terminal I/O. What is missing is a **single entry point** that wires these
together at the App level so users can write QA tests without stitching the
pieces manually.

---

## Priority 1: TestHarness

**Goal**: A single struct that drives the full update/view/render cycle without
a real terminal, exposing a high-level API for injecting events and asserting
output.

### Why

Today, testing an app requires manually creating a Buffer, Frame, calling
`update()`, calling `view()`, and inspecting cells. The TestHarness eliminates
that boilerplate:

```zig
// BEFORE (manual wiring)
var buf = try Buffer.init(allocator, 80, 24);
defer buf.deinit();
var frame = Frame(64).init(&buf);
var state = MyState{};
const action = update(&state, keyEvent('j'));
view(&state, &frame);
try expectString(buf, 0, 0, "Selected: item_1");

// AFTER (TestHarness)
var harness = try TestHarness(MyState).init(allocator, .{
    .state = &state,
    .update = update,
    .view = view,
});
defer harness.deinit();

harness.pressKey('j');
try harness.expectString(0, 0, "Selected: item_1");
```

### Architecture

```
TestHarness(State)
  |
  |-- current_buf: Buffer      (in-memory cell grid)
  |-- previous_buf: Buffer     (for diffing)
  |-- mock: MockBackend         (captures ANSI output)
  |-- state: *State             (user's app state)
  |-- update_fn                 (user's update function)
  |-- view_fn                   (user's view function)
  |-- frame_count: u64          (frames rendered so far)
  |
  +-- Event injection -----------+
  |   pressKey(char)             |  Synthesizes key Event, calls update(),
  |   pressKeyWith(code, mods)   |  then re-renders (calls view() + diff).
  |   pressSpecial(KeyCode)      |
  |   click(x, y)               |
  |   rightClick(x, y)          |
  |   mouseDown(x, y)           |
  |   mouseUp(x, y)             |
  |   drag(from_x, from_y,      |
  |        to_x, to_y)          |
  |   hover(x, y)               |
  |   scroll(x, y, direction)   |
  |   resize(w, h)              |
  |   tick()                    |
  |   tickN(n)                  |
  |   inject(Event)             |  Raw event injection
  +------------------------------+
  |
  +-- Assertions -----------------+
  |   expectCell(x, y, char)      |  Cell content
  |   expectString(x, y, text)    |  String at position
  |   expectStyle(x, y, attr)     |  Style attribute
  |   expectEmpty(x, y)           |  Cell is space/default
  |   expectAction(Action)        |  Last update() returned this
  |   expectQuit()                |  Last update() returned .quit
  +-------------------------------+
  |
  +-- Buffer access ---------------+
  |   getCell(x, y) -> Cell        |
  |   getBuffer() -> *const Buffer |
  |   getText() -> []const u8      |  Full buffer as text
  |   getRow(y) -> []const u8      |  Single row as text
  |   getRegion(rect) -> []const u8|  Rectangular region
  +--------------------------------+
  |
  +-- Snapshot --------------------+
  |   snapshot() -> Snapshot       |  Current buffer state
  |   expectSnapshot(expected)     |  Compare to golden text
  +--------------------------------+
```

### Key design decisions

**Re-render after every event.** Each event injection method calls `update()`
then `view()` automatically, keeping the buffer in sync. This matches the real
App loop behavior: event -> update -> view -> render.

**Track the last Action.** Store the return value of each `update()` call so
tests can assert on it (`expectAction(.quit)`, `expectAction(.none)`).

**No allocator in view.** Consistent with the real framework. View functions
receive `*State` and `*Frame` only.

**Resize reallocates buffers.** Just like `App.run()`, calling
`harness.resize()` resizes both buffers and re-renders.

**MockBackend captures raw ANSI.** For tests that need to verify escape
sequences (e.g., sync output, cursor positioning), the MockBackend's output
buffer remains accessible.

### Implementation sketch

```zig
pub fn TestHarness(comptime State: type) type {
    return struct {
        const Self = @This();
        const MaxWidgets = 64;

        allocator: std.mem.Allocator,
        state: *State,
        update_fn: *const fn (*State, Event) Action,
        view_fn: *const fn (*State, *Frame(MaxWidgets)) void,
        current_buf: Buffer,
        previous_buf: Buffer,
        mock: MockBackend,
        last_action: Action,
        frame_count: u64,

        pub fn init(allocator: std.mem.Allocator, config: Config) !Self { ... }
        pub fn deinit(self: *Self) void { ... }

        // -- Core loop --

        fn step(self: *Self, event: Event) void {
            self.last_action = self.update_fn(self.state, event);
            self.render();
        }

        fn render(self: *Self) void {
            self.current_buf.clear();
            var frame = Frame(MaxWidgets).init(&self.current_buf);
            self.view_fn(self.state, &frame);
            // Diff is computed but output goes to MockBackend
            @memcpy(self.previous_buf.cells, self.current_buf.cells);
            self.frame_count += 1;
        }

        // -- Event injection (each calls step()) --

        pub fn pressKey(self: *Self, char: u21) void {
            self.step(testing.keyEvent(char));
        }

        pub fn click(self: *Self, x: u16, y: u16) void {
            self.step(testing.mouseEvent(x, y, .down));
            self.step(testing.mouseEvent(x, y, .up));
        }

        // ... etc
    };
}
```

### What it replaces from other frameworks

| Framework         | Their primitive      | Our equivalent            |
|-------------------|----------------------|---------------------------|
| Ratatui           | `TestBackend`        | `MockBackend` + Harness   |
| Bubbletea/teatest | `NewTestModel()`     | `TestHarness.init()`      |
| Textual           | `Pilot`              | `TestHarness` (event API) |

---

## Priority 2: Snapshot Diffs (Golden File Workflow)

**Goal**: Let users save buffer snapshots to files and compare against them in
subsequent test runs, catching unintended visual regressions.

### Why

Manual cell-by-cell assertions are brittle and tedious for full-screen layouts.
Snapshot testing captures the entire rendered state and compares it against a
known-good baseline. When the UI changes intentionally, users update the
baseline. When it changes unintentionally, the test fails with a readable diff.

### How it works

```
1. Test runs, renders buffer
2. bufferToText() converts cells to plain text
3. Compare against .golden file on disk
4. Match -> pass
5. Mismatch -> fail with line-by-line diff
6. No .golden file -> create one (first run)
```

### File layout

```
tests/
  golden/
    counter_initial.golden       # plain text, one line per row
    counter_after_increment.golden
    dashboard_80x24.golden
    dashboard_120x40.golden      # different terminal sizes
```

### API surface

```zig
// Save a snapshot (first run or update mode)
try harness.saveSnapshot("tests/golden/counter_initial.golden");

// Assert snapshot matches golden file
try harness.expectSnapshotFile("tests/golden/counter_initial.golden");

// Inline comparison (no file I/O, for small widgets)
try harness.expectSnapshot(
    \\+--------+
    \\| Count  |
    \\|   42   |
    \\+--------+
);
```

### Annotated snapshots (optional)

For style-aware golden files, an extended format captures both content and
attributes:

```
# counter_styled.golden.annotated
# Format: [row,col] char style_flags fg bg
[0,0] '+' none default default
[0,1] '-' none default default
[1,0] '|' none default default
[1,2] 'C' bold green default
[1,3] 'o' bold green default
...
```

This is already supported by `bufferToAnnotatedText()` in testing.zig. The
annotated format captures style regressions that plain text misses (e.g., a
label losing its bold attribute).

### Diff output on failure

When a snapshot does not match, the test prints:

```
SNAPSHOT MISMATCH: tests/golden/counter_initial.golden

Line 2:
  Expected: "|  Count: 0   |"
  Actual:   "|  Count: 1   |"

Line 5:
  Expected: "|  [Start]    |"
  Actual:   "|  [Stop]     |"

To update: zig build test -- --update-snapshots
```

### Update workflow

A build option controls whether mismatches overwrite the golden file:

```bash
# Normal test run (mismatches fail)
zig build test

# Update golden files to match current output
zig build test -Dupdate-snapshots=true
```

This follows the patterns established by Rust's `insta` and Go's
`teatest -update`.

### Design decisions

**Plain text by default.** Annotated snapshots are opt-in. Most tests only
care about character content.

**Deterministic dimensions.** Tests must specify terminal size. A snapshot
taken at 80x24 is not comparable to one at 120x40. The TestHarness enforces
this by requiring dimensions at init.

**No ANSI in golden files.** Raw escape sequences make golden files unreadable.
The plain text format strips all ANSI. The annotated format provides structured
style information instead.

**One snapshot per file.** Each `.golden` file represents one buffer state.
Tests that check multiple states use multiple files (e.g.,
`counter_step1.golden`, `counter_step2.golden`).

---

## Priority 3: Scenario DSL (Data-Driven Test Files)

**Goal**: A declarative file format for describing test scenarios as sequences
of inputs and expected outputs, without writing Zig code.

### Why

Scenario files separate test logic from test infrastructure. They are:
- Readable by non-programmers (QA teams, designers)
- Easy to generate from recorded sessions
- Diffable in code review
- Runnable without recompilation (parsed at runtime or comptime)

### File format

```
# counter_test.scenario
# Lines starting with # are comments.

# -- Setup --
size 80 24

# -- Actions --
key j
key j
key j

# -- Assertions --
expect_string 5 0 "Count: 3"

# -- More actions --
key k

# -- More assertions --
expect_string 5 0 "Count: 2"
snapshot counter_at_2

# Mouse interactions
click 10 5
expect_style 10 5 bold

# Modifier keys
key ctrl+c
expect_quit

# Timing (for animations)
tick 10
expect_string 0 0 "Frame: 10"
```

### Directive reference

```
# Terminal setup
size <width> <height>              Set terminal dimensions

# Keyboard input
key <char>                         Press a character key
key <name>                         Press a special key (enter, escape,
                                   tab, up, down, left, right, home,
                                   end, page_up, page_down, f1..f12)
key ctrl+<char>                    Press with ctrl modifier
key alt+<char>                     Press with alt modifier
key shift+<char>                   Press with shift modifier
key ctrl+alt+<char>                Combined modifiers
type "hello world"                 Press each character in sequence

# Mouse input
click <x> <y>                     Mouse down + up at position
right_click <x> <y>               Right mouse button
mouse_down <x> <y>                Mouse button down
mouse_up <x> <y>                  Mouse button up
hover <x> <y>                     Mouse move to position
drag <x1> <y1> <x2> <y2>         Mouse down, move, up sequence
scroll_up <x> <y>                 Scroll wheel up at position
scroll_down <x> <y>               Scroll wheel down at position

# Time
tick                               Advance one tick
tick <n>                           Advance n ticks
wait <ms>                          Timed delay between events

# Assertions
expect_string <x> <y> "<text>"    String at position
expect_cell <x> <y> <char>        Single character at position
expect_empty <x> <y>              Cell is blank
expect_style <x> <y> <attr>       Style attribute (bold, italic, etc.)
expect_action none                 Last action was .none
expect_action quit                 Last action was .quit
expect_quit                        Shorthand for expect_action quit
snapshot <name>                    Compare to golden file
                                   (tests/golden/<name>.golden)

# Control flow
repeat <n>                         Repeat next directive n times
```

### Runner architecture

```
ScenarioRunner
  |-- parser: ScenarioParser        Reads .scenario file
  |-- harness: TestHarness(State)   Drives the app
  |-- golden_dir: []const u8        Path to golden files
  |
  |-- run(path) -> TestResult
  |   1. Parse file into directive list
  |   2. Execute directives sequentially
  |   3. Assertions check harness state
  |   4. Return pass/fail with details
  |
  +-- TestResult
      |-- passed: bool
      |-- failures: []Failure
      |-- Failure: { line, directive, expected, actual }
```

### Integration with zig build test

Scenario files live alongside test code and are discovered by a test runner:

```
tests/
  scenarios/
    counter_basic.scenario
    counter_mouse.scenario
    dashboard_resize.scenario
  golden/
    counter_basic_final.golden
    dashboard_resize_80x24.golden
```

A Zig test block loads and runs scenarios:

```zig
test "scenario: counter basic" {
    var state = Counter{};
    var runner = try ScenarioRunner(Counter).init(
        std.testing.allocator,
        &state,
        update,
        view,
    );
    defer runner.deinit();

    const result = try runner.run("tests/scenarios/counter_basic.scenario");
    try std.testing.expect(result.passed);
}
```

### Recording scenarios

The TestRecorder already captures events with timestamps. A recorder-to-scenario
converter could dump recorded sessions as `.scenario` files:

```zig
var recorder = TestRecorder(1024).init();
recorder.start(getTimeMs());

// ... user interaction happens ...

// Export to scenario format
const scenario_text = try recorder.toScenario(allocator);
try std.fs.cwd().writeFile("recorded.scenario", scenario_text);
```

This enables a workflow where QA:
1. Runs the app with recording enabled
2. Performs their test manually
3. Exports the recording as a `.scenario` file
4. Adds assertions manually
5. The scenario runs automatically in CI from that point forward

---

## Priority 4: QA Analysis (Accessibility Auditing)

**Goal**: Automated analysis tools that inspect the rendered buffer and app
behavior to identify accessibility, usability, and design issues.

### Why

No TUI framework currently offers automated accessibility analysis. This is
an opportunity to go beyond what Ratatui, Bubbletea, and Textual provide.
The building blocks already exist in zithril: WCAG contrast ratios in
`color.zig`, style introspection in `buffer.zig`, and the TestHarness for
driving interactions programmatically.

### Analysis categories

#### 1. Color Contrast Audit

Check that all foreground/background color combinations meet WCAG contrast
requirements.

```
CONTRAST AUDIT
==============
FAIL  [row 3, col 0-15] "Status: OK"
      fg=#888888 bg=#999999  ratio=1.3:1  (needs 4.5:1 for AA)

PASS  [row 0, col 0-10] "Dashboard"
      fg=#FFFFFF bg=#000000  ratio=21:1   (AAA)

WARN  [row 5, col 0-20] "Help: press ? for commands"
      fg=#AAAAAA bg=#000000  ratio=7.4:1  (AA, not AAA)

Summary: 45 regions checked, 2 failures, 3 warnings
```

Uses `ColorTriplet.contrastRatio()` and `ColorTriplet.wcagLevel()` from
`src/color.zig`. Walks every cell in the buffer, groups contiguous cells with
the same style, and evaluates each group.

#### 2. Keyboard Navigation Audit

Verify that all interactive elements are reachable via keyboard.

```zig
var audit = KeyboardAudit(MyState).init(allocator, .{
    .state = &state,
    .update = update,
    .view = view,
    .size = .{ .width = 80, .height = 24 },
});
defer audit.deinit();

const result = try audit.run();
```

The audit:
1. Renders the initial frame
2. Simulates Tab presses up to N times
3. After each Tab, diffs the buffer to detect focus changes
4. Records which regions changed (assumed focus indicators)
5. Reports regions that never received focus

```
KEYBOARD NAVIGATION AUDIT
==========================
Tab cycle: 4 stops detected

  Tab 1: [row 2, col 5-15]  style changed to bold+underline
  Tab 2: [row 4, col 5-15]  style changed to bold+underline
  Tab 3: [row 6, col 5-15]  style changed to bold+underline
  Tab 4: [row 2, col 5-15]  cycle complete (returned to start)

Potential issues:
  WARN  [row 8, col 0-20] "Delete Account" has button-like styling
        but was never focused during Tab cycle.
```

This is heuristic-based (detecting focus by style changes), not perfect, but
useful as a signal.

#### 3. Focus Visibility Audit

Ensure focused elements are visually distinguishable from unfocused ones.

```
FOCUS VISIBILITY AUDIT
======================
FAIL  Tab stop 2: [row 4, col 5-15]
      Focused style:   fg=white, bold
      Unfocused style: fg=white, bold
      No visible difference detected.

PASS  Tab stop 1: [row 2, col 5-15]
      Focused style:   fg=yellow, bold, underline
      Unfocused style: fg=white, none
      Clear visual distinction.
```

Compares the style of each element before and after it receives focus. If the
styles are identical (or differ only in ways that may not be visible), it flags
a warning.

#### 4. Mouse Target Size Audit

Check that clickable regions are large enough to be usable.

```
MOUSE TARGET AUDIT
==================
WARN  [row 3, col 40] "X" (1x1 cell)
      Clickable area is only 1 cell wide.
      Recommended minimum: 3x1 for single-line targets.

PASS  [row 5, col 2-20] "[  Submit  ]" (18x1 cells)
      Adequate target size.
```

This requires the app to use the HitTester pattern (from `mouse_demo.zig`).
The audit walks registered hit regions and checks their dimensions.

#### 5. Screen Reader Hint Audit (future)

TUI apps have no DOM or ARIA, but we can check for structural hints:
- Do bordered regions have titles?
- Are interactive elements labeled?
- Is there a consistent reading order (left-to-right, top-to-bottom)?

This is aspirational and depends on conventions that would need to be
established in the widget system.

### QA Report Format

All audits produce a structured report:

```zig
pub const AuditResult = struct {
    category: AuditCategory,
    findings: []Finding,

    pub const Finding = struct {
        severity: Severity,     // pass, warn, fail
        region: Rect,           // buffer area
        message: []const u8,    // human-readable description
        details: ?[]const u8,   // additional context
    };
};

pub const AuditCategory = enum {
    contrast,
    keyboard_navigation,
    focus_visibility,
    mouse_targets,
    screen_reader_hints,
};
```

Reports can be:
- Printed to stderr during test runs
- Written to a file for CI artifact collection
- Asserted on programmatically (e.g., `try expect(report.passRate() >= 0.95)`)

### Integration with TestHarness

The QA audit tools layer on top of the TestHarness:

```zig
var harness = try TestHarness(MyState).init(allocator, .{
    .state = &state,
    .update = update,
    .view = view,
    .size = .{ .width = 80, .height = 24 },
});
defer harness.deinit();

// Render initial state
harness.tick();

// Run specific audits
const contrast = try auditContrast(harness.getBuffer());
const keyboard = try auditKeyboardNav(&harness, .{ .max_tabs = 20 });
const focus = try auditFocusVisibility(&harness, .{ .max_tabs = 20 });

// Check results
try std.testing.expect(contrast.failCount() == 0);
try std.testing.expect(keyboard.findings.len > 0);  // at least one tab stop
```

### What makes this different from other frameworks

No TUI framework offers this. The closest is:
- **Textual**: SVG snapshots catch visual regressions but do not analyze them
- **Ratatui**: Cell assertions verify content but not accessibility
- **Web frameworks**: Lighthouse, axe-core audit HTML accessibility

zithril would be the first TUI framework with built-in QA analysis tooling.

---

## Implementation Order

```
Phase 1: TestHarness                    [DONE - v0.15.0]
  |-- Wire MockBackend + Buffer + update/view into one struct
  |-- Event injection methods
  |-- Cell/string/style assertions
  |-- Inline snapshot comparison
  |
  v
Phase 2: Snapshot Diffs                 [DONE - v0.15.0]
  |-- File I/O for golden files
  |-- Snapshot.saveToFile / loadFromFile / expectMatchesFile
  |-- TestHarness.saveSnapshot / expectSnapshotFile
  |-- Diff output formatting
  |
  v
Phase 3: Scenario DSL
  |-- Parser for .scenario format
  |-- ScenarioRunner wiring to TestHarness
  |-- Recorder-to-scenario export
  |-- zig build test integration
  |
  v
Phase 4: QA Analysis
  |-- Contrast audit (uses existing color.zig)
  |-- Keyboard navigation audit
  |-- Focus visibility audit
  |-- Mouse target audit
  |-- Report format and output
```

Each phase builds on the previous one. Phase 1 is the foundation that
everything else depends on. Phases 2 and 3 are independent of each other
but both require Phase 1. Phase 4 requires Phase 1 and benefits from
Phase 3 (scenario-driven audits).

---

## References

### Existing art

- **Ratatui TestBackend**: In-memory terminal, cell assertions, `insta` snapshots
- **ratatui-testlib**: PTY-based E2E testing with terminal emulation
- **Bubbletea teatest**: Golden file testing with `RequireEqualOutput()`
- **Bubbletea catwalk**: Data-driven test files with directives
- **Textual Pilot**: Headless mode, `press()`/`click()`, SVG snapshots
- **Microsoft tui-test**: PTY-based TUI testing framework

### zithril modules involved

- `src/testing.zig` - TestRecorder, TestPlayer, MockBackend, Snapshot, TestHarness, helpers
- `src/app.zig` - App struct, update/view loop, Config
- `src/buffer.zig` - Cell grid, diff, setString
- `src/event.zig` - Event, Key, Mouse, KeyCode, Modifiers
- `src/color.zig` - WcagLevel, contrastRatio, ColorTriplet
- `src/style.zig` - Style, StyleAttribute
- `src/frame.zig` - Frame, layout, render dispatch
