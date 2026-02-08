# QA Testing Framework - Implementation Review

An assessment of the four QA phases implemented in zithril v0.15.0-v0.16.0,
updated for v0.17.0 fixes (8 items resolved).

---

## Status Summary

| Phase | Rating | Fixed in v0.17.0 | Remaining |
|-------|--------|------------------|-----------|
| 1. TestHarness | 9/10 | 2 (getRegion, MockBackend) | 3 |
| 2. Snapshots | 8/10 | 3 (update-snapshots, dimensions, auto-mkdir) | 2 |
| 3. Scenario DSL | 9/10 | 2 (escape sequences, bounds checking) | 5 |
| 4. QA Analysis | 7/10 | 1 (state restore) | 7 |
| **Overall** | **8/10** | **8 fixed** | **17 remaining** |

### What Was Fixed in v0.17.0

| # | Fix | Phase | Impact |
|---|-----|-------|--------|
| 1 | Removed unused MockBackend from TestHarness | P1 | -256KB per harness |
| 2 | `getRegion(allocator, Rect)` implemented | P1 | Rectangular buffer extraction |
| 3 | `--update-snapshots` build option | P2 | `zig build test -Dupdate-snapshots=true` |
| 4 | Golden file dimension headers | P2 | Self-describing `# zithril-golden WxH` |
| 5 | Auto-create directories for snapshots | P2 | No manual mkdir needed |
| 6 | Escape sequences in scenario strings | P3 | `\"`, `\\`, `\n`, `\t` |
| 7 | Coordinate bounds checking in scenarios | P3 | Prevents UB on out-of-bounds |
| 8 | Save/restore harness state in audits | P4 | No more state corruption |

### What Remains (by priority for future work)

**Actionable improvements** (concrete, well-scoped):

| # | Item | Phase | Effort | Notes |
|---|------|-------|--------|-------|
| A | Annotated snapshots (style-aware golden files) | P2 | Medium | Detect style regressions. Need per-cell `[row,col] char style fg bg` format. |
| B | Mouse target size audit | P4 | Medium | `auditMouseTargets()` -- check clickable regions >= 3x1 cells. Requires HitTester. |
| C | Verbose AuditReport.summary() | P4 | Small | Print individual findings with message + region, not just counts. |
| D | Per-finding deduplication in audits | P4 | Small | Group by color pair or style, show unique count. |
| E | Recording-to-scenario converter | P3 | Medium | `recorder.toScenario()` for exporting test sessions as `.scenario` files. |
| F | Configurable snapshot path in scenarios | P3 | Small | Let ScenarioRunner configure the golden file directory. |

**Known limitations** (by design or fundamental):

| # | Item | Phase | Why it stays |
|---|------|-------|-------------|
| G | rightClick() uses ctrl modifier hack | P1 | Event model has no right-button field. Fix upstream in event.zig. |
| H | MaxWidgets hardcoded to 64 | P1 | Unlikely to hit in practice. Could make configurable if needed. |
| I | No async/command support | P1 | By design for Phase 1. Requires runtime command dispatch. |
| J | Heuristic focus detection is fragile | P4 | Buffer diffing can't distinguish focus from other changes. |
| K | Focus visibility only checks style, not content | P4 | Character-based indicators (e.g., `[*]`) not detected. |
| L | Contrast audit skips default colors | P4 | No RGB triplet for terminal defaults. Would need background detection. |
| M | `repeat` only affects next single directive | P3 | Documented behavior. Block form would require parser changes. |

**Low-priority / cosmetic**:

| # | Item | Phase | Notes |
|---|------|-------|-------|
| N | 1MB golden file size cap | P2 | Undocumented limit. Unlikely to hit. |
| O | Trailing whitespace in golden files | P2 | Cosmetic. Editors may strip. |
| P | `size` must be first directive | P3 | Works correctly, just no error on mid-file size. |
| Q | `addFailure()` silently drops OOM | P3 | Moot with std.testing.allocator. |
| R | `wait <ms>` directive not implemented | P3 | `tick` covers frame-by-frame. Wall-clock delay is niche. |
| S | No programmatic finding access by region | P4 | Convenience API. Users can iterate manually. |
| T | Screen reader hint audit | P4 | Aspirational. No semantic labeling infrastructure. |

---

## Phase 1: TestHarness

**Files**: `src/testing.zig` (TestHarness struct, ~300 lines)
**Tests**: 35+ in testing.zig
**Version**: v0.15.0, updated v0.17.0

### What It Is

A generic struct `TestHarness(State)` that drives the full update/view/render
cycle without a real terminal. Double-buffered rendering and event injection
let users test TUI apps with a few lines.

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

| Method                         | Returns                            |
|--------------------------------|------------------------------------|
| `getCell(x, y)`                | Raw Cell struct                    |
| `getBuffer()`                  | Const pointer to current buffer    |
| `getText(allocator)`           | Full buffer as allocated string    |
| `getRow(allocator, y)`         | Single row as allocated string     |
| `getRegion(allocator, Rect)`   | Rectangular region as text (v0.17) |

### Remaining Work

- [G] rightClick() uses ctrl modifier hack (event model limitation)
- [H] MaxWidgets hardcoded to 64 (configurable if needed)
- [I] No async/command support (future: runtime command dispatch)

---

## Phase 2: Snapshot Diffs (Golden File Workflow)

**Files**: `src/testing.zig` (Snapshot struct + bufferToText, ~200 lines)
**Tests**: ~14 snapshot-specific tests in testing.zig
**Version**: v0.15.0, updated v0.17.0

### What It Is

A golden file testing system. Captures the rendered buffer as plain text,
saves it to `.golden` files with dimension headers, and compares subsequent
runs against the baseline. Mismatches produce line-by-line diffs.

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
// First run: create baseline (auto-creates directories)
try harness.saveSnapshot("tests/golden/counter_initial.golden");

// Subsequent runs: compare against baseline
try harness.expectSnapshotFile("tests/golden/counter_initial.golden");

// Or auto-update on mismatch:
//   zig build test -Dupdate-snapshots=true
```

**Standalone Snapshot API:**

```zig
var snap = try Snapshot.fromBuffer(allocator, buffer);
defer snap.deinit();

// File I/O (header stores dimensions automatically)
try snap.saveToFile("tests/golden/my_test.golden");
var loaded = try Snapshot.loadFromFile(allocator, "tests/golden/my_test.golden");
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

### Remaining Work

- [A] Annotated snapshots -- style-aware golden files with per-cell attributes
- [N] 1MB file size cap (undocumented, unlikely to hit)
- [O] Trailing whitespace preserved (cosmetic, editor strip issues)

---

## Phase 3: Scenario DSL (Data-Driven Test Files)

**Files**: `src/scenario.zig` (~1500 lines)
**Tests**: ~45 in scenario.zig (parser tests + runner tests)
**Version**: v0.16.0, updated v0.17.0

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

# Type a sequence (supports escape sequences)
type "hello\tworld"

# Mouse interaction (bounds-checked)
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
    var runner = ScenarioRunner(Counter).init(
        std.testing.allocator,
        &state,
        Counter.update,
        Counter.view,
    );

    const result = try runner.run(
        \\size 40 10
        \\key +
        \\expect_string 0 0 "Count: 1"
    );
    defer result.deinit();
    try std.testing.expect(result.passed);
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
                                 Supports: \", \\, \n, \t

# Mouse (bounds-checked against buffer dimensions)
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

# Assertions (bounds-checked against buffer dimensions)
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

### Remaining Work

- [E] Recording-to-scenario converter (`recorder.toScenario()`)
- [F] Configurable snapshot path in ScenarioRunner
- [M] `repeat` for blocks of directives (currently single-directive only)
- [P] `size` mid-file should produce a parse error
- [Q] `addFailure()` should propagate OOM instead of silently dropping
- [R] `wait <ms>` directive for wall-clock delays

---

## Phase 4: QA Analysis (Accessibility Auditing)

**Files**: `src/audit.zig` (~830 lines)
**Tests**: 12+ tests covering all 3 audit functions
**Version**: v0.16.0, updated v0.17.0

### What It Is

Automated analysis tools that inspect the rendered buffer and app behavior to
identify accessibility and usability issues. Three audits are implemented:
contrast checking, keyboard navigation, and focus visibility. Audits now
save and restore harness state so they can be used mid-test without side effects.

### How to Use

**Contrast audit (works on any Buffer):**

```zig
var result = try zithril.auditContrast(allocator, &buf);
defer result.deinit();

if (result.failCount() > 0) {
    std.debug.print("{d} contrast failures\n", .{result.failCount()});
}
```

**Keyboard navigation audit (requires TestHarness, state-safe):**

```zig
var nav = try zithril.auditKeyboardNav(MyState, allocator, &harness, .{
    .max_tabs = 20,
});
defer nav.deinit();
// harness state is restored after audit
```

**Focus visibility audit (requires TestHarness, state-safe):**

```zig
var focus = try zithril.auditFocusVisibility(MyState, allocator, &harness, .{});
defer focus.deinit();
// harness state is restored after audit
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
```

### Severity Mapping

| WCAG Level    | Severity | Meaning                    |
|---------------|----------|----------------------------|
| AAA (7:1+)    | pass     | Excellent contrast         |
| AA  (4.5:1+)  | warn     | Acceptable, not ideal      |
| AA Large only  | fail     | Insufficient for body text |
| Below AA      | fail     | Fails accessibility check  |

### Remaining Work

- [B] Mouse target size audit (`auditMouseTargets()` -- requires HitTester)
- [C] Verbose AuditReport.summary() (print individual findings)
- [D] Per-finding deduplication (group by color pair or style)
- [J] Heuristic focus detection is fragile (fundamental limitation)
- [K] Focus visibility only checks style, not content changes
- [L] Contrast audit skips default/terminal colors (no RGB available)
- [S] Programmatic finding access by region (convenience API)
- [T] Screen reader hint audit (aspirational, no infrastructure)

---

## Cross-Cutting Observations

### What Works Well

- **Consistent allocator discipline.** Every allocation is caller-owned,
  every struct has a matching `deinit()`, errdefer chains are correct.
- **Rich error messages.** All assertions print context: position, expected
  vs actual values, Unicode codepoints.
- **UTF-8 correctness.** Wide characters, multi-byte sequences, and
  codepoint-level comparison are handled throughout.
- **Composability.** Scenarios use TestHarness, Audits use TestHarness,
  Snapshots work with both. No circular dependencies.
- **Comprehensive test suites.** 70+ tests across the three source files.

### Cross-Cutting Gaps

- **No example app with QA tests.** No example showing how to set up a
  full QA test suite with scenarios, golden files, and audits. Planned
  for the demo/showcase overhaul.
- **No CI integration guide.** No documentation on golden file management
  in CI (committing baselines, handling updates, reporting failures).
