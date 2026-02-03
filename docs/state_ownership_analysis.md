# State Ownership Analysis

Deep dive into state ownership patterns for zithril, comparing options and their tradeoffs.

---

## The Problem

zithril's `App.init()` copies state by value:

```zig
.state = config.state,  // Value copy
```

This causes three classes of bugs:

1. **Double free**: `defer state.deinit()` frees original, but app mutates the copy
2. **Stale references**: Checking `state.flag` after run, but `app.state.flag` was modified
3. **Broken internal pointers**: Slices pointing to arrays within the struct still point to original

---

## Option 1: Current Approach (Value Copy)

**How it works**: State is copied into App. User must use `app.state` after init.

```zig
var state = MyState{};
var app = App(MyState).init(.{ .state = state, ... });
defer app.state.deinit();  // Must use app.state
try app.run();
if (app.state.submitted) { ... }  // Must use app.state
```

**Pros**:
- Simple for trivial states (no allocations, no internal pointers)
- No lifetime management - App owns the copy
- Familiar to users of Elm/TEA architecture

**Cons**:
- Silent footgun for complex states
- Internal pointers break without fixup
- Easy to accidentally reference original
- Requires documentation discipline

**When it works well**:
- State is plain data (integers, bools, fixed arrays)
- No allocator-owned memory
- No slices pointing to internal arrays

---

## Option 2: Pointer Semantics

**How it works**: App stores `*State` instead of `State`. User owns state.

```zig
pub fn App(comptime State: type) type {
    return struct {
        state: *State,  // Pointer, not value
        // ...
    };
}
```

Usage:

```zig
var state = MyState.init(allocator);
defer state.deinit();

var app = App(MyState).init(.{ .state = &state, ... });
try app.run();

if (state.submitted) { ... }  // Original IS the working state
```

**Pros**:
- Eliminates all three bug classes
- Explicit ownership - user owns state, app borrows it
- Internal pointers just work
- No copy overhead for large states
- Matches Zig's "explicit over implicit" philosophy

**Cons**:
- User must ensure state outlives app (but this is explicit)
- Slightly more verbose initialization
- Breaking API change

**Implementation**:

```zig
pub fn App(comptime State: type) type {
    return struct {
        state: *State,

        pub const Config = struct {
            state: *State,  // Takes pointer
            update: *const fn (*State, Event) Action,
            view: *const fn (*State, *Frame) void,
            // ...
        };

        pub fn init(config: Config) Self {
            return .{
                .state = config.state,
                // ...
            };
        }

        pub fn update(self: *Self, event: Event) Action {
            return self.update_fn(self.state, event);
        }
    };
}
```

---

## Option 3: Ratatui Pattern (No App Owns State)

**How ratatui works**: Terminal handles rendering, user owns everything else.

```rust
// Rust/ratatui
let mut terminal = Terminal::new(backend)?;
let mut app = App::new();  // User-defined, not framework type

loop {
    terminal.draw(|frame| {
        // Closure captures app by reference
        ui(frame, &app);
    })?;

    if handle_events(&mut app)? {
        break;
    }
}
```

Key insight: ratatui has no `App` type that owns state. The `Terminal` only manages buffers and rendering. User state lives entirely outside the framework.

**Translated to Zig**:

```zig
pub fn main() !void {
    var terminal = zithril.Terminal.init(allocator, .{}) catch ...;
    defer terminal.deinit();

    var state = MyState.init();
    defer state.deinit();

    while (true) {
        // Draw - terminal.draw takes a render callback
        terminal.draw(struct {
            fn render(frame: *Frame, ctx: *MyState) void {
                // Render using ctx (our state)
                frame.render(Block{ .title = "App" }, frame.size());
            }
        }.render, &state);

        // Poll and handle events
        if (terminal.poll()) |event| {
            if (update(&state, event) == .quit) break;
        }
    }
}
```

**Pros**:
- Complete separation of concerns
- User has full control over state lifetime
- No ownership confusion possible
- Matches ratatui users' mental model

**Cons**:
- More boilerplate for simple apps
- No unified "app" concept
- User manages event loop manually
- Diverges from current zithril API

---

## Option 4: Dual API

**How it works**: Provide both value and pointer APIs.

```zig
// Value semantics (simple states)
var app = App(State).init(.{ .state = .{ .count = 0 }, ... });

// Pointer semantics (complex states)
var state = ComplexState.init(allocator);
var app = App(*ComplexState).initWithPtr(.{ .state = &state, ... });
```

**Pros**:
- Backwards compatible
- User chooses based on their needs
- Gradual migration path

**Cons**:
- Two code paths to maintain
- Confusing which to use
- Doesn't prevent misuse of value API

---

## Option 5: Comptime Detection

**How it works**: Use comptime reflection to detect problematic state types.

```zig
pub fn App(comptime State: type) type {
    // Warn if State has internal pointers
    if (comptime hasInternalPointers(State)) {
        @compileLog("Warning: State has internal pointers, consider pointer semantics");
    }
    // ...
}

fn hasInternalPointers(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;

    for (info.@"struct".fields) |field| {
        if (@typeInfo(field.type) == .pointer) {
            // Has a pointer field - might be internal
            return true;
        }
    }
    return false;
}
```

**Pros**:
- Catches issues at compile time
- Educational - teaches users about the pitfall
- No runtime overhead

**Cons**:
- Heuristic - can't reliably detect internal vs external pointers
- False positives (external pointers are fine)
- Doesn't solve the problem, just warns

---

## Comparison Matrix

| Criterion | Value Copy | Pointer | Ratatui-style | Dual API |
|-----------|------------|---------|---------------|----------|
| Safety | Low | High | High | Medium |
| Simplicity | High | High | Medium | Low |
| Zig idiom | Medium | High | High | Low |
| Breaking change | No | Yes | Yes | No |
| Boilerplate | Low | Low | Medium | Medium |
| Footgun risk | High | Low | Low | Medium |

---

## What Other Frameworks Do

### ratatui (Rust)

- **Pattern**: Terminal owns buffers, user owns state
- **State passing**: By reference through closures
- **Ownership**: Explicit Rust borrowing semantics

```rust
terminal.draw(|f| render(f, &app))?;
```

### bubbletea (Go)

- **Pattern**: Elm architecture with Model/Update/View
- **State passing**: By value (Go copies structs)
- **Ownership**: GC handles cleanup

```go
type model struct { ... }
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) { ... }
```

Go's GC makes the copy semantics safe - no double frees.

### Brick (Haskell)

- **Pattern**: Pure functional, state threaded through
- **State passing**: Immutable, new state returned
- **Ownership**: GC handles everything

### Textual (Python)

- **Pattern**: Class-based OOP
- **State passing**: Reference semantics (Python objects)
- **Ownership**: GC

---

## What Leverages Zig Best?

Zig's philosophy emphasizes:

1. **Explicit over implicit** - Pointer semantics make ownership explicit
2. **No hidden allocations** - Both value and pointer satisfy this
3. **Comptime power** - Could use for detection/documentation
4. **Manual memory management** - User should control lifetimes

**Recommendation**: Pointer semantics aligns best with Zig idioms.

The value-copy approach hides an ownership transfer that Zig programmers expect to be explicit. In Zig, when you see:

```zig
var app = App.init(.{ .state = state });
```

You don't expect `state` to be copied and become disconnected. You expect either:
- `app` borrows `state` (pointer semantics)
- `state` is moved into `app` (but Zig doesn't have moves)

The pointer approach makes the relationship clear:

```zig
var app = App.init(.{ .state = &state });  // Clearly a borrow
```

---

## Migration Path

If we move to pointer semantics:

### Phase 1: Add Pointer Support

```zig
// New API alongside old
pub fn initWithPtr(config: PtrConfig) Self { ... }
```

### Phase 2: Document and Deprecate

- Document value-copy pitfalls prominently
- Add comptime warning for value API
- Recommend pointer API for new code

### Phase 3: Remove Value API (Major Version)

- Remove value-copy init
- Pointer becomes the only API

---

## Recommendation

**Short term**: Document current behavior thoroughly (done in USAGE.md)

**Medium term**: Add pointer-based `initWithPtr()` as recommended API

**Long term**: Consider ratatui-style separation if the ecosystem grows

The pointer approach is:
- Most aligned with Zig philosophy
- Safest for users
- Minimal API change
- Clear mental model

---

## References

- [ratatui Terminal docs](https://docs.rs/ratatui/latest/ratatui/struct.Terminal.html)
- [ratatui state discussion](https://forum.ratatui.rs/t/how-do-i-represent-application-state-ergonomically/54)
- [Zig style guide on ownership](https://ziglang.org/documentation/master/#Pointers)
