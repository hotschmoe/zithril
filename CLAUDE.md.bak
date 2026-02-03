<!-- BEGIN:header -->
# CLAUDE.md

we love you, Claude! do your best today
<!-- END:header -->

<!-- BEGIN:rule-1-no-delete -->
## RULE 1 - NO DELETIONS (ARCHIVE INSTEAD)

You may NOT delete any file or directory. Instead, move deprecated files to `.archive/`.

**When you identify files that should be removed:**
1. Create `.archive/` directory if it doesn't exist
2. Move the file: `mv path/to/file .archive/`
3. Notify me: "Moved `path/to/file` to `.archive/` - deprecated because [reason]"

**Rules:**
- This applies to ALL files, including ones you just created (tests, tmp files, scripts, etc.)
- You do not get to decide that something is "safe" to delete
- The `.archive/` directory is gitignored - I will review and permanently delete when ready
- If `.archive/` doesn't exist and you can't create it, ask me before proceeding

**Only I can run actual delete commands** (`rm`, `git clean`, etc.) after reviewing `.archive/`.
<!-- END:rule-1-no-delete -->

<!-- BEGIN:irreversible-actions -->
### IRREVERSIBLE GIT & FILESYSTEM ACTIONS

Absolutely forbidden unless I give the **exact command and explicit approval** in the same message:

- `git reset --hard`
- `git clean -fd`
- `rm -rf`
- Any command that can delete or overwrite code/data

Rules:

1. If you are not 100% sure what a command will delete, do not propose or run it. Ask first.
2. Prefer safe tools: `git status`, `git diff`, `git stash`, copying to backups, etc.
3. After approval, restate the command verbatim, list what it will affect, and wait for confirmation.
4. When a destructive command is run, record in your response:
   - The exact user text authorizing it
   - The command run
   - When you ran it

If that audit trail is missing, then you must act as if the operation never happened.
<!-- END:irreversible-actions -->

<!-- BEGIN:code-discipline -->
### Code Editing Discipline

- Do **not** run scripts that bulk-modify code (codemods, invented one-off scripts, giant `sed`/regex refactors).
- Large mechanical changes: break into smaller, explicit edits and review diffs.
- Subtle/complex changes: edit by hand, file-by-file, with careful reasoning.
- **NO EMOJIS** - do not use emojis or non-textual characters.
- ASCII diagrams are encouraged for visualizing flows.
- Keep in-line comments to a minimum. Use external documentation for complex logic.
- In-line commentary should be value-add, concise, and focused on info not easily gleaned from the code.
<!-- END:code-discipline -->

<!-- BEGIN:no-legacy -->
### No Legacy Code - Full Migrations Only

We optimize for clean architecture, not backwards compatibility. **When we refactor, we fully migrate.**

- No "compat shims", "v2" file clones, or deprecation wrappers
- When changing behavior, migrate ALL callers and remove old code **in the same commit**
- No `_legacy` suffixes, no `_old` prefixes, no "will remove later" comments
- New files are only for genuinely new domains that don't fit existing modules
- The bar for adding files is very high

**Rationale**: Legacy compatibility code creates technical debt that compounds. A clean break is always better than a gradual migration that never completes.
<!-- END:no-legacy -->

<!-- BEGIN:dev-philosophy -->
## Development Philosophy

**Make it work, make it right, make it fast** - in that order.

**This codebase will outlive you** - every shortcut becomes someone else's burden. Patterns you establish will be copied. Corners you cut will be cut again.

**Fight entropy** - leave the codebase better than you found it.

**Inspiration vs. Recreation** - take the opportunity to explore unconventional or new ways to accomplish tasks. Do not be afraid to challenge assumptions or propose new ideas. BUT we also do not want to reinvent the wheel for the sake of it. If there is a well-established pattern or library take inspiration from it and make it your own. (or suggest it for inclusion in the codebase)
<!-- END:dev-philosophy -->

<!-- BEGIN:testing-philosophy -->
## Testing Philosophy: Diagnostics, Not Verdicts

**Tests are diagnostic tools, not success criteria.** A passing test suite does not mean the code is good. A failing test does not mean the code is wrong.

**When a test fails, ask three questions in order:**
1. Is the test itself correct and valuable?
2. Does the test align with our current design vision?
3. Is the code actually broken?

Only if all three answers are "yes" should you fix the code.

**Why this matters:**
- Tests encode assumptions. Assumptions can be wrong or outdated.
- Changing code to pass a bad test makes the codebase worse, not better.
- Evolving projects explore new territory - legacy testing assumptions don't always apply.

**What tests ARE good for:**
- **Regression detection**: Did a refactor break dependent modules? Did API changes break integrations?
- **Sanity checks**: Does initialization complete? Do core operations succeed? Does the happy path work?
- **Behavior documentation**: Tests show what the code currently does, not necessarily what it should do.

**What tests are NOT:**
- A definition of correctness
- A measure of code quality
- Something to "make pass" at all costs
- A specification to code against

**The real success metric**: Does the code further our project's vision and goals?
<!-- END:testing-philosophy -->

<!-- BEGIN:footer -->
---

we love you, Claude! do your best today
<!-- END:footer -->


---

## Project-Specific Content

<!-- Add your project's toolchain, architecture, workflows here -->
<!-- This section will not be touched by haj.sh -->

# zithril - Zig TUI Framework

*Light as a feather, hard as dragon scales.*

A Zig TUI framework for building terminal user interfaces. Immediate mode rendering, zero hidden state, built on rich_zig.

- **Minimum Zig**: 0.15.2
- **Dependencies**: rich_zig (terminal rendering primitives)

---

## Philosophy

- **Explicit over implicit** - You own all state. The framework never allocates behind your back.
- **Immediate mode** - Describe your entire UI every frame. No widget tree, no retained state.
- **Composition over inheritance** - Widgets are structs with a `render` function.
- **Built for Zig** - Comptime layouts, error unions, no hidden control flow.

---

## Zig Toolchain

```bash
zig build                    # Build library
zig build run-example-counter   # Run counter example
zig build run-example-ralph     # Run reference app
zig build test               # Run all tests
zig fmt src/                 # Format before commits
```

---

## Architecture

```
    Event --> Update --> View --> Render
      ^                            |
      |____________________________|
```

- **Event**: Keyboard, mouse, resize, or tick
- **Update**: Your function. Modify state, return an action (.none, .quit, .command)
- **View**: Your function. Call frame.render() to describe the UI
- **Render**: zithril diffs and draws only what changed

---

## Layer Stack

```
+--------------------------------------------------+
|              YOUR APPLICATION                     |
|  State --> update(Event) --> Action              |
|  State --> view(Frame) --> (renders widgets)     |
+--------------------------------------------------+
                      |
                      v
+--------------------------------------------------+
|                  zithril                          |
|  App        Event loop, terminal setup/teardown  |
|  Frame      Layout methods, render dispatch      |
|  Layout     Constraint solver                    |
|  Buffer     Cell grid with diff support          |
|  Widgets    Block, List, Table, Gauge, Text...   |
+--------------------------------------------------+
                      |
                      v
+--------------------------------------------------+
|                  rich_zig                         |
|  Style, Color, Text spans, ANSI rendering        |
+--------------------------------------------------+
                      |
                      v
+--------------------------------------------------+
|              Terminal Backend                     |
|  Raw mode, alternate screen, input events        |
+--------------------------------------------------+
```

---

## Core Types

### Constraint (layout)

| Constraint | Description |
|------------|-------------|
| `.length(n)` | Exactly n cells |
| `.min(n)` | At least n cells |
| `.max(n)` | At most n cells |
| `.flex(n)` | Proportional share (like CSS flex-grow) |
| `.ratio(a, b)` | Fraction a/b of available space |

### Event

- `.key` - KeyCode + modifiers (ctrl, alt, shift)
- `.mouse` - Position + kind (down, up, drag, scroll)
- `.resize` - New width/height
- `.tick` - Timer for animations/polling

### Action

- `.none` - Continue running
- `.quit` - Exit the app
- `.command` - Async operation (future)

---

## Key Patterns

### App Structure

```zig
const State = struct {
    count: i32 = 0,
};

pub fn main() !void {
    var app = zithril.App(State).init(.{
        .state = .{},
        .update = update,
        .view = view,
    });
    try app.run();
}

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| switch (key.code) {
            .char => |c| if (c == 'q') return .quit,
            else => {},
        },
        else => {},
    }
    return .none;
}

fn view(state: *State, frame: *zithril.Frame) void {
    frame.render(zithril.Block{ .title = "App" }, frame.size());
}
```

### Widget Interface

Widgets are structs with a `render` function:

```zig
const MyWidget = struct {
    title: []const u8,
    highlighted: bool = false,

    pub fn render(self: MyWidget, area: zithril.Rect, buf: *zithril.Buffer) void {
        const style = if (self.highlighted)
            zithril.Style{ .fg = .yellow, .bold = true }
        else
            zithril.Style{};
        buf.set_string(area.x, area.y, self.title, style);
    }
};
```

### Layout Composition

```zig
fn view(state: *State, frame: *zithril.Frame) void {
    const chunks = frame.layout(frame.size(), .vertical, &.{
        .length(3),     // Header: exactly 3 rows
        .flex(1),       // Content: fill remaining
        .length(1),     // Footer: exactly 1 row
    });

    frame.render(Header{}, chunks[0]);
    frame.render(Content{ .items = state.items }, chunks[1]);
    frame.render(StatusBar{}, chunks[2]);
}
```

### Focus Management (manual)

```zig
const Focus = enum { sidebar, main, popup };

const State = struct {
    focus: Focus = .sidebar,
};

fn update(state: *State, event: zithril.Event) zithril.Action {
    if (event == .key and event.key.code == .tab) {
        state.focus = switch (state.focus) {
            .sidebar => .main,
            .main => .sidebar,
            .popup => .popup,
        };
    }
    return .none;
}
```

---

## Built-in Widgets

| Widget | Purpose |
|--------|---------|
| `Block` | Borders and titles |
| `Text` | Single-line styled text |
| `Paragraph` | Multi-line with wrapping |
| `List` | Navigable item list |
| `Table` | Rows/columns with headers |
| `Gauge` | Progress bar |
| `Tabs` | Tab headers |
| `Scrollbar` | Scroll indicator |

---

## Bug Severity

### Critical - Must Fix Immediately

- `.?` on null (panics)
- `unreachable` reached at runtime
- Index out of bounds
- Integer overflow in release builds (undefined behavior)
- Use-after-free or double-free
- Memory leaks in long-running paths

### Important - Fix Before Merge

- Missing error handling (`try` without proper catch/return)
- `catch unreachable` without justification
- Ignoring return values from `!T` functions
- Race conditions in threaded code

### Contextual - Address When Convenient

- TODO/FIXME comments
- Unused imports or variables
- Suboptimal comptime usage
- Excessive debug output

---

## Available Claude Tools

### Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| coder-sonnet | sonnet | Fast, precise code changes |
| gemini-analyzer | sonnet | Large-context analysis via Gemini CLI |
| build-verifier | sonnet | Cross-platform build validation |

### Skills

| Skill | Purpose |
|-------|---------|
| `/test` | Run `zig build test` with optional optimization level |

---

## Version Updates (SemVer)

When making commits, update `version` in `build.zig.zon`:

- **MAJOR** (X.0.0): Breaking changes or incompatible API modifications
- **MINOR** (0.X.0): New features, backward-compatible additions
- **PATCH** (0.0.X): Bug fixes, small improvements, documentation

---

## Roadmap

- [x] Core rendering loop
- [x] Basic widgets (Block, Text, List, Table, Gauge)
- [x] Constraint-based layout
- [x] Keyboard input
- [ ] Mouse support
- [ ] Scrollable containers
- [ ] Text input widget
- [ ] Command/async pattern
- [ ] Animation helpers

