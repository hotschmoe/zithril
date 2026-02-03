# zithril Testing Philosophy

---

## Core Principle

**Tests are diagnostic tools, not success criteria.**

A passing test suite does not mean the code is good.
A failing test does not mean the code is wrong.

Tests tell you *what happened*, not *what should happen*.

---

## The Three Questions

When a test fails, ask these questions **in order**:

```
    +-------------------------------------------+
    | 1. Is the test itself correct and         |
    |    valuable?                              |
    |                                           |
    |    - Does it test real behavior?          |
    |    - Is the assertion actually correct?   |
    |    - Is this test worth maintaining?      |
    +-------------------------------------------+
                        |
                       YES
                        |
                        v
    +-------------------------------------------+
    | 2. Does the test align with our current   |
    |    design vision?                         |
    |                                           |
    |    - Has the API intentionally changed?   |
    |    - Are we testing deprecated behavior?  |
    |    - Does this test encode old decisions? |
    +-------------------------------------------+
                        |
                       YES
                        |
                        v
    +-------------------------------------------+
    | 3. Is the code actually broken?           |
    |                                           |
    |    - Does the failure indicate a bug?     |
    |    - Is there a regression?               |
    |    - Did we break a contract?             |
    +-------------------------------------------+
                        |
                       YES
                        |
                        v
                  FIX THE CODE
```

If any answer is "no", you likely need to fix or remove the test, not the code.

---

## What Tests Are Good For

### 1. Regression Detection

Did a refactor break something that used to work?

```zig
test "layout solver respects minimum constraints" {
    const result = layout(
        Rect{ .x = 0, .y = 0, .width = 100, .height = 10 },
        .horizontal,
        &.{ .min(30), .flex(1) },
    );
    // First chunk must be at least 30, even if flex wants more space
    try std.testing.expect(result[0].width >= 30);
}
```

This test catches regressions in the constraint solver. If it fails after a refactor, something broke.

### 2. Sanity Checks

Does the basic happy path work?

```zig
test "Buffer can set and get cells" {
    var buf = Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    buf.set(5, 5, .{ .char = 'X', .style = .{ .fg = .red } });
    const cell = buf.get(5, 5);

    try std.testing.expectEqual('X', cell.char);
    try std.testing.expectEqual(Color.red, cell.style.fg);
}
```

If this fails, something is fundamentally broken. Investigate immediately.

### 3. Behavior Documentation

Tests show what the code currently does.

```zig
test "Rect.inner with margin larger than dimensions returns zero-size rect" {
    const r = Rect{ .x = 10, .y = 10, .width = 5, .height = 5 };
    const inner = r.inner(10); // margin > width/height

    // Documents current behavior: saturating subtraction, not panic
    try std.testing.expectEqual(0, inner.width);
    try std.testing.expectEqual(0, inner.height);
}
```

This test documents an edge case. It doesn't say this behavior is *correct*, just that it's *current*.

---

## What Tests Are NOT

### Not a Definition of Correctness

```zig
// BAD: This test defines correctness, locking in arbitrary behavior
test "progress bar at 50% renders exactly this string" {
    const gauge = Gauge{ .ratio = 0.5, .width = 20 };
    try std.testing.expectEqualStrings(
        "[##########          ]",  // Arbitrary rendering decision
        gauge.render_to_string(),
    );
}
```

This test is brittle. Any visual change (spacing, characters, formatting) breaks it, even if the change is an improvement.

### Not a Measure of Code Quality

100% test coverage means nothing if the tests are:
- Testing implementation details instead of behavior
- Copy-pasted boilerplate with no thought
- Assertions that can never fail
- Tests of trivial getters/setters

### Not Something to "Make Pass" at All Costs

```zig
// BAD: Test "passes" but hides the real problem
test "event parsing handles escape sequences" {
    const result = parse_event("\x1b[A");
    // Original: try std.testing.expect(result == .key_up);
    // "Fixed" to pass:
    try std.testing.expect(result != null);  // Weakened assertion!
}
```

If you weaken an assertion to make a test pass, you've hidden a bug.

---

## Testing for Agentic Development

When AI agents run tests, they need clear signals. Our testing approach optimizes for this.

### Principle 1: Tests Emit Diagnostic Information

Tests should explain *why* they failed, not just *that* they failed.

```zig
test "layout distributes flex space proportionally" {
    const result = layout(
        Rect{ .x = 0, .y = 0, .width = 100, .height = 10 },
        .horizontal,
        &.{ .flex(1), .flex(2) },
    );

    const expected_first = 33;  // 1/3 of 100
    const expected_second = 67; // 2/3 of 100

    if (result[0].width != expected_first or result[1].width != expected_second) {
        std.debug.print(
            \\LAYOUT DIAGNOSTIC:
            \\  Total width: 100
            \\  Constraints: flex(1), flex(2)
            \\  Expected: [{d}, {d}]
            \\  Got:      [{d}, {d}]
            \\  Ratio:    {d:.2}:{d:.2} (expected 1:2)
            \\
        , .{
            expected_first, expected_second,
            result[0].width, result[1].width,
            @as(f32, @floatFromInt(result[0].width)) / 100.0,
            @as(f32, @floatFromInt(result[1].width)) / 100.0,
        });
    }

    try std.testing.expectEqual(expected_first, result[0].width);
    try std.testing.expectEqual(expected_second, result[1].width);
}
```

An agent can parse this output and understand:
- What was being tested
- What the expected behavior was
- What actually happened
- How far off the result was

### Principle 2: Tests Are Categorized by Purpose

```zig
// ============================================================
// SANITY TESTS - If these fail, something is fundamentally broken
// ============================================================

test "sanity: Buffer initializes with correct dimensions" { ... }
test "sanity: Event loop starts and stops cleanly" { ... }
test "sanity: Terminal enters and exits raw mode" { ... }

// ============================================================
// REGRESSION TESTS - Guard against breaking existing behavior
// ============================================================

test "regression: #42 - layout handles zero-width constraints" { ... }
test "regression: #57 - wide characters don't overflow buffer" { ... }

// ============================================================
// BEHAVIOR TESTS - Document current behavior (may change)
// ============================================================

test "behavior: Gauge rounds progress to nearest percent" { ... }
test "behavior: List wraps selection at boundaries" { ... }
```

An agent encountering a failing `sanity:` test knows to investigate deeply. A failing `behavior:` test might just need the test updated.

### Principle 3: Tests Run Fast and Frequently

```
    Target: Full test suite < 2 seconds
    Reasoning: Agents run tests after every change
```

Slow tests discourage iteration. If tests take 30 seconds, agents (and humans) skip them.

```zig
// BAD: Slow test that waits for real time
test "tick events fire at correct interval" {
    var app = App.init(...);
    app.tick_rate_ms = 100;
    std.time.sleep(500 * std.time.ns_per_ms);  // Blocks for 500ms!
    try std.testing.expect(tick_count >= 4);
}

// GOOD: Mock time or test the math directly
test "tick calculation produces correct intervals" {
    const tick_rate_ms: u32 = 100;
    const elapsed_ms: u64 = 500;
    const expected_ticks = elapsed_ms / tick_rate_ms;
    try std.testing.expectEqual(5, expected_ticks);
}
```

### Principle 4: Test Output Is Machine-Parseable

Structure test names and output for programmatic analysis:

```
    [PASS] sanity: Buffer initializes with correct dimensions
    [PASS] sanity: Event loop starts and stops cleanly
    [FAIL] regression: #42 - layout handles zero-width constraints
           EXPECTED: width = 0
           ACTUAL:   width = 4294967295 (likely underflow)
           LOCATION: src/layout.zig:142
    [PASS] behavior: Gauge rounds progress to nearest percent
```

An agent can parse this and:
1. See that a regression test failed
2. Understand it's an underflow bug
3. Navigate to the exact location
4. Know that `#42` has context (an issue number)

---

## The Closed-Loop Testing Workflow

```
    +-------------------+
    | Agent makes       |
    | a code change     |
    +-------------------+
             |
             v
    +-------------------+
    | Run: zig build    |
    | test              |
    +-------------------+
             |
             v
    +-------------------+
    | Parse test output |
    +-------------------+
             |
      +------+------+
      |             |
    PASS          FAIL
      |             |
      v             v
    +--------+  +------------------+
    | Done   |  | Analyze failure: |
    +--------+  | 1. Is test valid?|
                | 2. Is code wrong?|
                +------------------+
                         |
              +----------+----------+
              |                     |
         Test invalid          Code is wrong
              |                     |
              v                     v
        +-----------+        +-------------+
        | Update or |        | Fix the bug |
        | remove    |        +-------------+
        | the test  |               |
        +-----------+               |
              |                     |
              +----------+----------+
                         |
                         v
                 +---------------+
                 | Run tests     |
                 | again         |
                 +---------------+
```

### Example: Agent Workflow

1. **Agent receives task**: "Add mouse support to List widget"

2. **Agent reads existing tests**:
   ```
   test "List renders items" - PASS
   test "List highlights selected item" - PASS
   test "List handles empty items" - PASS
   ```

3. **Agent writes implementation** and adds:
   ```zig
   test "List handles mouse click to select" {
       var list = List{ .items = &.{ "a", "b", "c" }, .selected = 0 };
       list.handle_mouse(.{ .kind = .down, .x = 0, .y = 1 });
       try std.testing.expectEqual(1, list.selected);
   }
   ```

4. **Test fails** - List doesn't have `handle_mouse` yet

5. **Agent implements** `handle_mouse`:
   ```zig
   pub fn handle_mouse(self: *List, mouse: Event.Mouse) void {
       if (mouse.kind == .down) {
           self.selected = mouse.y;  // BUG: doesn't account for scroll offset
       }
   }
   ```

6. **Tests pass** (basic test didn't catch the scroll offset bug)

7. **Agent adds edge case test**:
   ```zig
   test "List mouse click respects scroll offset" {
       var list = List{
           .items = &.{ "a", "b", "c", "d", "e" },
           .selected = 0,
           .scroll_offset = 2,  // Items "c", "d", "e" visible
       };
       list.handle_mouse(.{ .kind = .down, .x = 0, .y = 0 }); // Click first visible
       try std.testing.expectEqual(2, list.selected); // Should select "c" (index 2)
   }
   ```

8. **Test fails** - Diagnostic output shows:
   ```
   EXPECTED: selected = 2
   ACTUAL:   selected = 0
   NOTE: mouse.y=0, scroll_offset=2, should select index 2
   ```

9. **Agent fixes bug**:
   ```zig
   self.selected = mouse.y + self.scroll_offset;
   ```

10. **All tests pass** - Agent marks task complete

---

## Test Categories for zithril

### Unit Tests (src/*.zig)

Test individual functions in isolation.

```zig
// src/layout.zig
test "solve_constraints handles all-flex" { ... }
test "solve_constraints handles all-fixed" { ... }
test "solve_constraints handles mixed" { ... }
test "solve_constraints handles overflow" { ... }
```

### Integration Tests (test/*.zig)

Test components working together.

```zig
// test/app_integration.zig
test "App runs view function each frame" { ... }
test "App passes events to update function" { ... }
test "App exits on Action.quit" { ... }
```

### Visual Tests (test/visual/*.zig)

Test rendering output matches expected patterns.

```zig
// test/visual/block_test.zig
test "Block with rounded border renders correctly" {
    var buf = Buffer.init(test_allocator, 10, 5);
    defer buf.deinit();

    Block{ .border = .rounded }.render(
        Rect{ .x = 0, .y = 0, .width = 10, .height = 5 },
        &buf,
    );

    // Check corners
    try std.testing.expectEqual(@as(u21, 0x256D), buf.get(0, 0).char); // top-left
    try std.testing.expectEqual(@as(u21, 0x256E), buf.get(9, 0).char); // top-right
}
```

### Property Tests (test/property/*.zig)

Test invariants across many inputs.

```zig
// test/property/layout_properties.zig
test "layout total width equals input width" {
    var prng = std.rand.DefaultPrng.init(12345);
    for (0..1000) |_| {
        const width = prng.random().intRangeAtMost(u16, 1, 1000);
        const constraints = generate_random_constraints(&prng);

        const result = layout(
            Rect{ .x = 0, .y = 0, .width = width, .height = 10 },
            .horizontal,
            constraints,
        );

        var total: u16 = 0;
        for (result) |r| total += r.width;

        try std.testing.expectEqual(width, total);
    }
}
```

---

## Running Tests

```bash
# Run all tests
zig build test

# Run with optimization (catches different bugs)
zig build test -Doptimize=ReleaseSafe

# Run specific test file
zig test src/layout.zig

# Run with verbose output (for diagnostics)
zig build test -- --verbose
```

---

## Summary

```
    +------------------------------------------+
    |  Tests are DIAGNOSTIC TOOLS              |
    |                                          |
    |  They tell you WHAT HAPPENED             |
    |  Not WHAT SHOULD HAPPEN                  |
    |                                          |
    |  When a test fails:                      |
    |  1. Question the test first              |
    |  2. Question the design second           |
    |  3. Fix the code last                    |
    |                                          |
    |  For agentic development:                |
    |  - Emit diagnostic information           |
    |  - Categorize tests by purpose           |
    |  - Keep tests fast                       |
    |  - Make output machine-parseable         |
    +------------------------------------------+
```

The goal is not green checkmarks. The goal is code that furthers the project vision.
