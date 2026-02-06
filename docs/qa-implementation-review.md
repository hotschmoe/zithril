# QA Testing Framework - Implementation Review

An assessment of the four QA phases implemented in zithril v0.15.0-v0.16.0.
Each section covers usage, a rating, and noted shortcomings.

---

## Phase 1: TestHarness

**Files**: `src/testing.zig` (TestHarness struct, ~300 lines)
**Tests**: 35 in testing.zig
**Version**: v0.15.0

### What It Is

A generic struct `TestHarness(State)` that drives the full update/view/render
cycle without a real terminal. It wires together MockBackend, double-buffered
rendering, and event injection so users can test TUI apps with a few lines.

### How to Use

```zig
const zithril = @import("zithril");

const State = struct { count: i32 = 0 };

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| switch (key.code) {
            .char => |c| {
                if (c == '+') state.count += 1;
                if (c == 'q') return .quit;
            },
            else => {},
        },
        else => {},
    }
    return .none;
}

fn view(state: *State, frame: anytype) void {
    // render state to frame
}

test "counter increments" {
    var state = State{};
    var harness = try zithril.TestHarness(State).init(
        std.testing.allocator,
        .{ .state = &state, .update = update, .view = view },
    );
    defer harness.deinit();

    harness.pressKey('+');
    try harness.expectString(0, 0, "Count: 1");
}
```

### Event Injection API

| Method                        | What It Does                                    |
|-------------------------------|-------------------------------------------------|
| `pressKey(char)`              | Synthesize a character key press                |
| `pressKeyWith(code, mods)`    | Key with ctrl/alt/shift modifiers               |
| `pressSpecial(KeyCode)`       | Named key (enter, escape, tab, arrows, F1-F12)  |
| `click(x, y)`                 | Mouse down + up at position                     |
| `rightClick(x, y)`            | Right mouse button (ctrl modifier workaround)   |
| `mouseDown(x, y)`             | Mouse button press                              |
| `mouseUp(x, y)`               | Mouse button release                            |
| `drag(x1, y1, x2, y2)`       | Down at (x1,y1), drag to (x2,y2), up           |
| `hover(x, y)`                 | Mouse move without button                       |
| `scroll(x, y, direction)`     | Scroll wheel event                              |
| `resize(w, h)`                | Reallocate buffers and send resize event        |
| `tick()`                       | Advance one tick                                |
| `tickN(n)`                     | Advance n ticks                                 |
| `inject(Event)`               | Raw event injection                             |

### Assertion API

| Method                         | What It Checks                     |
|--------------------------------|------------------------------------|
| `expectCell(x, y, char)`      | Single character at position       |
| `expectString(x, y, text)`    | String at position (UTF-8 aware)   |
| `expectStyle(x, y, attr)`     | Style attribute (bold, italic...)  |
| `expectEmpty(x, y)`           | Cell is space with no styling      |
| `expectAction(Action)`        | Last update() return value         |
| `expectQuit()`                | Shorthand for expectAction(.quit)  |

### Buffer Access

| Method                  | Returns                           |
|-------------------------|-----------------------------------|
| `getCell(x, y)`         | Raw Cell struct                   |
| `getBuffer()`           | Const pointer to current buffer   |
| `getText(allocator)`    | Full buffer as allocated string   |
| `getRow(allocator, y)`  | Single row as allocated string    |

### Rating: 9/10

The TestHarness is clean, complete, and well-tested. It faithfully implements
the event-update-render loop, provides rich error messages on assertion failure
(including Unicode codepoints and positional context), and handles wide
characters correctly. The 35 tests cover all public methods including edge
cases (out-of-bounds row access, empty buffers, resize during test).

### Shortcomings

1. **`getRegion(rect)` not implemented.** The design doc specifies a method to
   extract a rectangular region of the buffer as text. Currently users must
   call `getRow()` multiple times or inspect cells directly. Minor gap -- most
   tests work fine without it.

2. **MockBackend allocated but unused.** The harness creates a MockBackend
   during init but never writes ANSI output to it. The design doc mentions
   "Diff is computed but output goes to MockBackend" but the implementation
   renders directly to in-memory buffers. This isn't wrong (it matches how
   Ratatui's TestBackend works), but the MockBackend allocation is wasted
   memory.

3. **rightClick() uses ctrl modifier hack.** There is no dedicated right-button
   field on MouseKind, so right-click is simulated via `ctrl + left click`.
   Works for apps that follow this convention, but is not a true right-click
   event. This is a limitation of the event model, not the harness itself.

4. **MaxWidgets hardcoded to 64.** Not configurable per-harness. Unlikely to
   be a problem in practice, but large UIs with many widgets per frame could
   hit this ceiling.

5. **No async/command support.** `Action.command` exists as a variant but the
   harness does not execute commands. By design for Phase 1, but means
   command-driven apps cannot be fully tested yet.

---

## Phase 2: Snapshot Diffs (Golden File Workflow)

**Files**: `src/testing.zig` (Snapshot struct + bufferToText, ~180 lines)
**Tests**: ~12 snapshot-specific tests in testing.zig
**Version**: v0.15.0

### What It Is

A golden file testing system. Captures the rendered buffer as plain text,
saves it to `.golden` files, and compares subsequent runs against the baseline.
Mismatches produce line-by-line diffs.

### How to Use

**Inline snapshot (no file I/O):**

```zig
harness.pressKey('+');
harness.pressKey('+');
harness.pressKey('+');

try harness.expectSnapshot(
    \\Count: 3
    \\
);
```

**Golden file workflow:**

```zig
// First run: create baseline
try harness.saveSnapshot("tests/golden/counter_initial.golden");

// Subsequent runs: compare against baseline
try harness.expectSnapshotFile("tests/golden/counter_initial.golden");
```

**Standalone Snapshot API:**

```zig
var snap = try Snapshot.fromBuffer(allocator, buffer);
defer snap.deinit();

// Compare two snapshots
var other = try Snapshot.fromBuffer(allocator, other_buffer);
defer other.deinit();

if (!snap.eql(other)) {
    const diff_text = try snap.diff(allocator, other);
    defer allocator.free(diff_text);
    std.debug.print("{s}\n", .{diff_text});
}

// File I/O
try snap.saveToFile("tests/golden/my_test.golden");
var loaded = try Snapshot.loadFromFile(allocator, "tests/golden/my_test.golden", 80, 24);
defer loaded.deinit();
```

### Diff Output on Failure

When a snapshot does not match, the test prints:

```
SNAPSHOT MISMATCH: tests/golden/counter_initial.golden

Dimension mismatch: 80x24 vs 120x40

Line 2:
  Expected: "|  Count: 0   |"
  Actual:   "|  Count: 1   |"

Line 5:
  Expected: "|  [Start]    |"
  Actual:   "|  [Stop]     |"
```

### Rating: 7/10

The core workflow is solid. File save/load, inline comparison, and diff output
all work correctly. The integration with TestHarness is seamless. However, this
is the thinnest of the four phases -- it does the basics well but lacks the
polish that would make it a standout feature.

### Shortcomings

1. **No `--update-snapshots` build option.** The design doc specifies
   `zig build test -Dupdate-snapshots=true` to auto-update golden files when
   the UI changes intentionally. This is NOT implemented. Users must manually
   call `saveSnapshot()` to update baselines. This is a significant workflow
   gap -- Rust's `insta` and Go's `teatest -update` both have this, and it's
   the biggest quality-of-life feature for snapshot testing.

2. **Annotated snapshots not implemented.** The design doc describes a
   `[row,col] char style_flags fg bg` format for style-aware golden files.
   `bufferToAnnotatedText()` exists but only produces a simple debug
   pretty-print with row numbers -- it does NOT capture style attributes per
   cell. Plain text snapshots cannot detect style regressions (e.g., a label
   losing its bold attribute).

3. **loadFromFile dimensions are caller-supplied.** Width and height are not
   stored in the golden file, so the caller must pass matching dimensions.
   If the test changes dimensions but uses the same golden file, comparison
   will silently produce incorrect diffs. Storing dimensions in a header line
   would make golden files self-describing.

4. **1MB file size cap.** `loadFromFile()` limits reads to 1MB. Very large
   terminal captures (e.g., 200x100 buffer with Unicode) could approach this.
   The limit is undocumented.

5. **Trailing whitespace preserved.** Golden files include trailing spaces to
   fill the terminal width. This makes files harder to read in editors that
   strip trailing whitespace and can cause spurious diffs. No option to trim.

6. **No directory auto-creation.** `saveToFile()` requires the parent directory
   to exist. First-time users must `mkdir -p tests/golden/` manually. A small
   friction point.

---

## Phase 3: Scenario DSL (Data-Driven Test Files)

**Files**: `src/scenario.zig` (1305 lines)
**Tests**: 15 in scenario.zig (68 parser tests + 13 runner tests from test analysis)
**Version**: v0.16.0

### What It Is

A declarative file format (`.scenario`) for describing test sequences as
inputs and expected outputs, without writing Zig code. A parser reads the
file and a runner executes each directive against a TestHarness.

### How to Use

**Write a scenario file** (`tests/scenarios/counter_basic.scenario`):

```
# Terminal setup
size 40 10

# Press + three times
key +
key +
key +

# Verify count
expect_string 0 0 "Count: 3"

# Type a sequence
type "hello"

# Mouse interaction
click 10 5
expect_style 10 5 bold

# Use repeat for bulk actions
repeat 5
key +
expect_string 0 0 "Count: 8"

# Tick for animations
tick 10

# Modifier keys
key ctrl+c
expect_quit

# Golden file comparison
snapshot counter_final
```

**Run it from a Zig test:**

```zig
test "scenario: counter basic" {
    var state = Counter{};
    var runner = try zithril.ScenarioRunner(Counter).init(
        std.testing.allocator,
        &state,
        Counter.update,
        Counter.view,
    );

    // From string
    const result = try runner.run(
        \\size 40 10
        \\key +
        \\expect_string 0 0 "Count: 1"
    );
    defer result.deinit();
    try std.testing.expect(result.passed);

    // From file
    const file_result = try runner.runFile("tests/scenarios/counter_basic.scenario");
    defer file_result.deinit();
    try std.testing.expect(file_result.passed);
}
```

**Inspect failures:**

```zig
if (!result.passed) {
    for (result.failures) |f| {
        std.debug.print("Line {d}: {s} - expected {s}, got {s}\n", .{
            f.line, f.directive_text, f.expected, f.actual,
        });
    }
}
```

### Directive Reference

```
# Terminal
size <width> <height>            Set terminal dimensions (first line only)

# Keyboard
key <char>                       Press character key
key <name>                       Special: enter, escape, tab, backtab,
                                 backspace, up, down, left, right, home,
                                 end, page_up, page_down, insert, delete,
                                 f1..f12
key ctrl+<char>                  With ctrl modifier
key alt+<char>                   With alt modifier
key shift+<char>                 With shift modifier
key ctrl+alt+<char>              Combined modifiers
type "hello world"               Type each character in sequence

# Mouse
click <x> <y>                   Left click (down + up)
right_click <x> <y>             Right click
mouse_down <x> <y>              Button press
mouse_up <x> <y>                Button release
hover <x> <y>                   Mouse move
drag <x1> <y1> <x2> <y2>       Drag sequence
scroll_up <x> <y>               Scroll wheel up
scroll_down <x> <y>             Scroll wheel down

# Timing
tick                             Advance one frame
tick <n>                         Advance n frames

# Assertions
expect_string <x> <y> "<text>"  String at position
expect_cell <x> <y> <char>      Single character
expect_empty <x> <y>            Cell is blank
expect_style <x> <y> <attr>     Style: bold, italic, underline, dim,
                                blink, reverse, strikethrough, overline
expect_action none               Last action was .none
expect_action quit               Last action was .quit
expect_quit                      Shorthand for expect_action quit
snapshot <name>                  Compare to tests/golden/<name>.golden

# Control
repeat <n>                       Repeat next directive n times
# comment                        Ignored
```

### Rating: 8/10

The Scenario DSL is well-structured and covers the vast majority of the design
doc's specification. The parser handles 22 directive types with clean error
reporting (line numbers, directive names, expected vs actual). The tagged union
approach for directives is idiomatic Zig. Test coverage is strong with both
parser-level and runner-level tests.

### Shortcomings

1. **`wait <ms>` directive not implemented.** Listed in the design doc for
   timed delays between events (useful for animation testing). The `tick`
   directive advances frame-by-frame but there is no wall-clock delay. This
   matters for apps with time-based animations.

2. **No escape sequences in strings.** `type "hello\"world"` will fail.
   Quoted strings are parsed by finding the next `"` character -- no support
   for `\"`, `\\`, `\n`, or other escape sequences. Users cannot type strings
   containing quote characters.

3. **`repeat` only affects the next single directive.** Cannot repeat a block
   of directives. To repeat a sequence (e.g., key + assertion), users must
   write it out manually or use multiple `repeat` lines. The design doc implies
   this limitation ("Repeat next directive n times") but a block form would be
   more useful.

4. **Snapshot path hardcoded to `tests/golden/{name}.golden`.** Not
   configurable on the ScenarioRunner. If a project uses a different directory
   structure, the scenario `snapshot` directive cannot accommodate it.

5. **`size` must be the first directive.** If `size` appears anywhere else in
   the file, it is silently treated as first (extracted before execution). The
   parser does not error on `size` appearing mid-file, but the behavior is
   unclear -- it always uses the first parsed `size` and ignores the rest.

6. **No coordinate bounds checking.** Directives like `click 999 999` on an
   80x24 buffer will execute without error. The TestHarness accesses cells at
   those coordinates, which may silently produce wrong results or index into
   invalid memory depending on buffer bounds checking.

7. **`addFailure()` silently drops OOM.** When recording a failure, if the
   allocator runs out of memory, the failure is silently lost. In testing
   contexts with `std.testing.allocator` this is unlikely, but it could mask
   issues with general-purpose allocators.

8. **No recording-to-scenario converter.** The design doc describes a workflow
   where TestRecorder sessions are exported as `.scenario` files. This
   `recorder.toScenario()` method is not implemented.

---

## Phase 4: QA Analysis (Accessibility Auditing)

**Files**: `src/audit.zig` (904 lines)
**Tests**: 10 tests covering all 3 audit functions
**Version**: v0.16.0

### What It Is

Automated analysis tools that inspect the rendered buffer and app behavior to
identify accessibility and usability issues. Three audits are implemented:
contrast checking, keyboard navigation, and focus visibility.

### How to Use

**Contrast audit (works on any Buffer):**

```zig
var buf = try Buffer.init(allocator, 80, 24);
defer buf.deinit();

// Render your UI into buf...
buf.setString(0, 0, "Warning", Style.init().fg(.{ .rgb = .{ 0x88, 0x88, 0x88 }})
                                            .bg(.{ .rgb = .{ 0x99, 0x99, 0x99 }}));

var result = try zithril.auditContrast(allocator, &buf);
defer result.deinit();

// Check results
if (result.failCount() > 0) {
    std.debug.print("{d} contrast failures\n", .{result.failCount()});
}
```

**Keyboard navigation audit (requires TestHarness):**

```zig
var state = MyState{};
var harness = try zithril.TestHarness(MyState).init(allocator, .{
    .state = &state, .update = update, .view = view,
    .width = 80, .height = 24,
});
defer harness.deinit();

var nav = try zithril.auditKeyboardNav(MyState, allocator, &harness, .{
    .max_tabs = 20,  // default: 20
});
defer nav.deinit();

// Expect at least one tab stop
try std.testing.expect(nav.passCount() > 0);
```

**Focus visibility audit (requires TestHarness):**

```zig
var focus = try zithril.auditFocusVisibility(MyState, allocator, &harness, .{
    .max_tabs = 20,
});
defer focus.deinit();

// All focused elements should be visually distinguishable
try std.testing.expect(focus.failCount() == 0);
```

**Aggregate report:**

```zig
var report = zithril.AuditReport.init(allocator);
defer report.deinit();

try report.addResult(contrast_result);
try report.addResult(nav_result);
try report.addResult(focus_result);

const summary = try report.summary(allocator);
defer allocator.free(summary);
std.debug.print("{s}\n", .{summary});
// Output:
//   QA AUDIT REPORT
//   ===============
//   contrast: 45 findings (2 fail, 3 warn, 40 pass)
//   keyboard_navigation: 5 findings (0 fail, 1 warn, 4 pass)
//   focus_visibility: 4 findings (1 fail, 0 warn, 3 pass)
//   Overall pass rate: 87.0%
```

### Severity Mapping

| WCAG Level    | Severity | Meaning                    |
|---------------|----------|----------------------------|
| AAA (7:1+)    | pass     | Excellent contrast         |
| AA  (4.5:1+)  | warn     | Acceptable, not ideal      |
| AA Large only  | fail     | Insufficient for body text |
| Below AA      | fail     | Fails accessibility check  |

### Rating: 6/10

This is the most ambitious phase and the most incomplete. The three implemented
audits work correctly and the type system (Finding, AuditResult, AuditReport)
is well-designed for aggregation and reporting. However, the heuristic-based
approach for keyboard and focus audits has fundamental limitations, and two of
the five planned audit types are missing entirely.

### Shortcomings

1. **Mouse target size audit not implemented.** Listed in the design doc and
   present as `AuditCategory.mouse_targets` in the enum, but no corresponding
   `auditMouseTargets()` function exists. The design describes checking that
   clickable regions are at least 3x1 cells, which would require HitTester
   integration.

2. **Screen reader hint audit not implemented.** Described in the design doc as
   "aspirational" and not expected for v0.16.0, but worth noting. No
   infrastructure for semantic labeling of widgets exists yet.

3. **Heuristic focus detection is fragile.** Both `auditKeyboardNav` and
   `auditFocusVisibility` detect focus changes by diffing the buffer before
   and after Tab presses. This approach:
   - Fails if the app changes content but not style on focus (e.g., prepending
     a `>` marker without changing cell style)
   - Produces false positives if non-focus content changes on Tab (e.g.,
     a counter that increments each frame)
   - Cannot distinguish "focus moved" from "something else changed"

4. **Contrast audit skips default colors.** Cells using the terminal's default
   foreground/background colors are silently skipped because there is no RGB
   triplet to calculate a ratio from. In practice, many TUI apps rely heavily
   on default colors. The audit only checks explicitly-set RGB colors, which
   may be a small fraction of the rendered content.

5. **No per-finding deduplication.** If the same color pair appears in 50
   different regions, 50 separate findings are generated. A "unique issues"
   count or grouping by color pair would make reports more actionable.

6. **`auditFocusVisibility` only checks style, not content.** If an app's
   focus indicator is a character change (e.g., `[ ]` becomes `[*]`), the
   focus visibility audit will report a false failure because it only calls
   `detectStyleChange()`, not a content diff.

7. **No programmatic finding access by region.** Findings have a `.region`
   field but there is no API to query "findings overlapping this Rect" or
   "findings for this widget." Users must iterate the findings array manually.

8. **Keyboard audit mutates harness state.** Both `auditKeyboardNav` and
   `auditFocusVisibility` inject Tab key events into the harness, permanently
   changing the app state. After running a keyboard audit, the harness state
   is wherever the Tab cycle left it. There is no save/restore mechanism. Users
   must re-init the harness (or manually reset state) to continue testing.

9. **AuditReport.summary() format is basic.** Counts findings per category but
   does not print individual findings. Users must iterate `.findings` manually
   to see details. A verbose summary mode showing each finding's message and
   region would be useful.

---

## Cross-Cutting Observations

### What Works Well Across All Phases

- **Consistent allocator discipline.** Every allocation is caller-owned,
  every struct has a matching `deinit()`, errdefer chains are correct.
- **Rich error messages.** All assertions print context: position, expected
  vs actual values, Unicode codepoints. Failures are debuggable without
  stepping through code.
- **UTF-8 correctness.** Wide characters, multi-byte sequences, and
  codepoint-level comparison are handled throughout.
- **Composability.** The phases layer cleanly: Scenarios use TestHarness,
  Audits use TestHarness, Snapshots work with both. No circular
  dependencies, no tight coupling.
- **Comprehensive test suites.** 60+ tests across the three source files.
  Tests cover sanity, behavior, and regression categories.

### What's Missing Across the Board

- **No example app with QA tests.** The framework has `examples/` and `demos/`
  directories but no example showing how to set up a full QA test suite with
  scenarios, golden files, and audits. A reference example would accelerate
  adoption.
- **No CI integration guide.** The design doc mentions artifact collection and
  `zig build test` integration, but there is no documentation on how to set up
  golden file management in CI (committing baselines, handling updates,
  reporting failures).
- **`screen_reader_hints` category unused.** Not in the enum, not planned for
  implementation. The design doc acknowledges this as aspirational.

### Overall Framework Rating: 8/10

The QA Testing Framework delivers on its core promise: a single entry point
(TestHarness) that wires together all testing primitives, with three layers
of progressively higher abstraction (assertions, snapshots, scenarios) and
automated accessibility analysis. The implementation is idiomatic Zig with
solid memory management and good test coverage.

The main areas for improvement are the snapshot workflow (needs auto-update),
the audit heuristics (inherently limited by buffer-level analysis), and the
two missing audit types. These are reasonable gaps for a v0.16.0 release and
represent clear next steps rather than fundamental design flaws.
