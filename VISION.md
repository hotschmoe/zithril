# zithril Vision

*Light as a feather, hard as dragon scales.*

---

## The Problem

Building terminal UIs in Zig today means either:

1. **Rolling your own** - Raw ANSI escapes, manual input parsing, ad-hoc layout
2. **FFI to C libraries** - ncurses brings C's baggage (global state, implicit allocation, opaque errors)
3. **Porting from other languages** - Losing Zig's comptime power, fighting the type system

None of these respect Zig's core values: explicit allocation, no hidden control flow, composition over inheritance.

---

## The Solution

zithril is a TUI framework that feels native to Zig.

```
    You describe your UI.
    zithril renders it.
    You own all the state.
    That's it.
```

---

## Core Beliefs

### 1. Immediate Mode is the Right Model

Retained-mode widget trees create hidden state, lifecycle complexity, and synchronization bugs. Immediate mode is simpler:

```
    Your State  -->  view(state, frame)  -->  Screen
```

No widget tree to manage. No "did I update the right component?" questions. You describe what you want; we draw it.

### 2. The User Owns Everything

zithril never:
- Allocates memory without your allocator
- Stores state between frames
- Calls functions you didn't pass in
- Spawns threads or goroutines

If something exists, you created it. If something happens, you caused it.

### 3. Composition via Functions, Not Inheritance

Widgets are data. Rendering is a function. Combine them however you want.

```zig
// This is a widget:
const MyWidget = struct {
    title: []const u8,
    pub fn render(self: @This(), area: Rect, buf: *Buffer) void { ... }
};

// No base classes. No virtual methods. No trait objects.
// Just a struct and a function.
```

### 4. Zig All the Way Down

- Comptime constraint validation
- Error unions for all fallible operations
- No `anytype` soup - generic parameters are bounded
- Slices instead of iterator chains

---

## What zithril Is

- A rendering loop that calls your functions
- A layout solver that divides rectangles
- A collection of composable widgets
- A terminal backend that handles the ugly parts

## What zithril Is Not

- A state management library (use your own structs)
- An async runtime (return Commands, we'll execute them)
- A component framework (no lifecycle, no mounting)
- A styling system (rich_zig handles that)

---

## Target Users

### Primary: Zig Developers Building Tools

```
    CLI dashboards
    Log viewers
    Process monitors
    REPL interfaces
    Interactive debuggers
```

People who want a TUI but don't want to learn a framework that fights Zig.

### Secondary: Learners

zithril should be simple enough to read top-to-bottom. The entire core should fit in a few thousand lines. If you understand Zig, you can understand zithril.

---

## Success Criteria

### Simplicity

Can a new user build a working TUI in under 100 lines? Can they understand what every line does?

### Performance

Does the framework add measurable overhead beyond raw terminal writes? (It shouldn't.)

### Reliability

Does the terminal always restore to a clean state? Do panics leave the terminal broken? (They shouldn't.)

### Composability

Can users build complex UIs from simple parts without fighting the framework?

---

## Non-Goals

- **Cross-platform GUI**: We're terminal-only. Use something else for windowed apps.
- **Web rendering**: No HTML/CSS backend. Terminal semantics only.
- **Backwards compatibility**: We break APIs to make them better. Pin your dependencies.
- **Plugin architecture**: Widgets are structs. "Plugins" are just more structs.

---

## The Long Game

zithril is infrastructure. It exists to make building Zig tools pleasant.

```
    Today:    Counter examples, list views, progress bars
    Soon:     Process orchestrators, log aggregators, system monitors
    Later:    A standard tool for Zig developers who need terminal UI
```

The goal is not to be the most feature-rich TUI framework. It's to be the one that Zig developers reach for because it respects how they think.

---

## Guiding Questions

When making design decisions, ask:

1. **Would this surprise a Zig programmer?**
   If yes, find another way.

2. **Does this require hidden state?**
   If yes, make it explicit or don't do it.

3. **Can this be done at comptime?**
   If yes, do it at comptime.

4. **Does this add complexity for the common case?**
   If yes, make it optional or reconsider.

---

*"Light as a feather, hard as dragon scales."*

The framework should be so lightweight you forget it's there. But when you need it, it should be rock solid.
