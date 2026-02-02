# Rung Enhancement Wishlist

This document captures missing features and improvement ideas discovered while building Rung with zithril. It serves two purposes:

1. **Game roadmap** - What Rung needs to be a complete, polished game
2. **Framework feedback** - What zithril could add to make games like Rung easier to build

---

## Part A: Rung Game Features

### Critical (Blocking Gameplay)

These issues prevent levels from being completable or fundamentally break the game logic.

#### 1. Input Index Selection

**Problem**: All contacts/coils placed get hardcoded index 0. Players cannot specify which input (A, B, C) a contact references.

**Impact**: Levels requiring multiple inputs (AND, OR, XOR) cannot be solved correctly.

**Solution**: Add index cycling when placing contacts/coils. Options:
- Number keys 0-9 to set index before placing
- Shift+Tab to cycle index on selected component
- Display index label on each contact (A, B, etc.)

#### 2. Parallel Branch Support

**Problem**: The simulation engine (`ladder.zig`) only evaluates left-to-right linear flow. OR logic requires parallel branches that join back together.

**Impact**: Level 4 (OR gate) and all subsequent levels using branches are broken.

**Solution**: Rewrite simulation to:
- Track multiple active power paths
- Handle junction cells (T-splits, joins)
- Evaluate all branches and OR their results at junction points

#### 3. Level Selection Menu

**Problem**: Must play levels sequentially. No way to jump to a specific level or replay completed levels.

**Impact**: Testing/debugging specific levels requires playing through all prior levels.

**Solution**: Add a level select screen:
- Grid of level numbers (1-10)
- Show locked/unlocked/completed status
- Allow jumping to any unlocked level

---

### Important (Better UX)

These improve playability but don't block core gameplay.

#### 4. Undo/Redo

**Problem**: Placing a wrong component requires manually removing it. No way to undo multiple actions.

**Impact**: Frustrating when experimenting with solutions.

**Solution**: Implement action stack:
- Track diagram mutations as reversible operations
- Ctrl+Z to undo, Ctrl+Shift+Z or Ctrl+Y to redo
- Clear stack on level change

#### 5. Input Labels on Contacts

**Problem**: Placed contacts show `[ ]` but not which input they reference.

**Impact**: Complex diagrams become confusing; hard to verify wiring.

**Solution**: Render input label inside contact brackets:
- `[A]` for input A (normally open)
- `[/B]` for input B (normally closed)
- `(Y)` for output Y coil

#### 6. Victory/Completion Screen

**Problem**: Solving a level just changes status to "SOLVED". No celebration or clear transition.

**Impact**: Anticlimactic; unclear if the game recognized the solution.

**Solution**: Show a victory overlay:
- "Level X Complete!" message
- Stats (attempts, time if tracked)
- "Press N for next level" or "Press Enter to continue"

#### 7. Help Overlay

**Problem**: Controls are documented in README but not discoverable in-game.

**Impact**: New players must read external docs to learn controls.

**Solution**: Toggle help overlay with `?` key:
- Show keybindings
- Show component reference (NO, NC, coil meanings)
- Semi-transparent overlay that doesn't exit the game

---

### Polish (Nice-to-Have)

These would make Rung feel complete but are lower priority.

#### 8. Animated Power Flow

**Problem**: Simulation results are instant; no visual indication of how power flows through the circuit.

**Impact**: Harder to understand why a circuit fails; less satisfying to watch.

**Solution**: Animate power propagation:
- Highlight cells as power reaches them
- Different colors for energized vs. blocked paths
- Speed control (instant/slow/step-through)

#### 9. Save/Load Progress

**Problem**: Progress resets on every run.

**Impact**: Players must replay from level 1 each session.

**Solution**: Persist progress to file:
- Track highest unlocked level
- Optionally save per-level solutions
- Store in `~/.config/rung/` or similar

#### 10. Custom Level Editor

**Problem**: All levels are hardcoded in `levels.zig`.

**Impact**: Limited replayability; can't share user-created puzzles.

**Solution**: Add level editor mode:
- Create/edit truth tables
- Set initial diagram state
- Export/import level files

#### 11. Sound Effects

**Problem**: No audio feedback.

**Impact**: Less engaging; harder to know when actions succeed/fail without looking.

**Solution**: Add minimal sound cues:
- Click/beep on component placement
- Error buzz on invalid placement
- Success fanfare on level complete
- Note: Would require audio library integration

---

## Part B: Zithril Framework Wishlist

Features that would make building games like Rung easier in zithril.

### Would Directly Benefit Rung

#### 1. Modal Dialog Widget

**What**: A dialog/modal component with focus trapping and backdrop dimming.

**Why Rung needs it**: Help overlay, victory screen, level select menu, confirmation dialogs.

**Current workaround**: Manual overlay rendering, manual focus state management.

**Proposed API**:
```zig
const dialog = Modal{
    .title = "Level Complete!",
    .content = content_widget,
    .buttons = &.{ "Next Level", "Replay" },
    .on_close = handleClose,
};
frame.renderModal(dialog); // Renders on top, traps focus
```

#### 2. Grid Navigation State Helper

**What**: Utility for managing 2D cursor position with bounds checking, wrapping, and jump-to behavior.

**Why Rung needs it**: Diagram editor cursor, palette selection, level grid.

**Current workaround**: Manual bounds checking in every cursor move handler.

**Proposed API**:
```zig
const GridNav = struct {
    pos: Position,
    bounds: Rect,
    wrap: bool = false,

    pub fn move(self: *GridNav, dir: Direction) void { ... }
    pub fn jump(self: *GridNav, pos: Position) void { ... }
    pub fn clamp(self: *GridNav) void { ... }
};
```

#### 3. Undo/Redo State Stack

**What**: Generic undo/redo stack that stores state snapshots or operations.

**Why Rung needs it**: Diagram edit history.

**Current workaround**: No undo support, or custom implementation per app.

**Proposed API**:
```zig
const UndoStack = struct(comptime T: type) {
    pub fn push(self: *@This(), state: T) void { ... }
    pub fn undo(self: *@This()) ?T { ... }
    pub fn redo(self: *@This()) ?T { ... }
    pub fn canUndo(self: @This()) bool { ... }
    pub fn canRedo(self: @This()) bool { ... }
};
```

#### 4. Overlay/Layer Management

**What**: System for rendering widgets at different z-levels with proper ordering.

**Why Rung needs it**: Popups, tooltips, help overlay, debug panels.

**Current workaround**: Render order is implicit based on call order; no z-index control.

**Proposed API**:
```zig
frame.pushLayer(.overlay);
frame.render(popup, popup_area);
frame.popLayer();
// Overlay layer renders after main layer
```

#### 5. Tooltip Positioning Helper

**What**: Utility to calculate tooltip/popup position relative to an anchor, avoiding screen edges.

**Why Rung needs it**: Component descriptions on hover, error messages near cursor.

**Current workaround**: Manual position calculation with edge detection.

**Proposed API**:
```zig
const tooltip_pos = zithril.position.tooltip(
    anchor_rect,
    tooltip_size,
    screen_bounds,
    .prefer_above, // or .prefer_below, .prefer_right, etc.
);
```

---

### General Framework Improvements

These would benefit many apps, not just Rung.

#### 6. Flex Alignment Modes

**What**: Additional alignment options for flex layouts: center, space-between, space-around, space-evenly.

**Why**: Current flex only distributes proportionally. Centering content or spacing items evenly requires manual calculation.

**Proposed API**:
```zig
frame.layout(area, .horizontal, &constraints, .{
    .align = .center,        // or .space_between, .space_around
    .cross_align = .center,  // vertical alignment in horizontal layout
});
```

#### 7. Padding/Margin Convenience Types

**What**: Named type for padding/margin with per-side control.

**Why**: Currently must manually shrink areas for padding. Repetitive and error-prone.

**Proposed API**:
```zig
const Insets = struct {
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    left: u16 = 0,

    pub fn uniform(n: u16) Insets { ... }
    pub fn symmetric(v: u16, h: u16) Insets { ... }
    pub fn apply(self: Insets, rect: Rect) Rect { ... }
};

// Usage
const inner = Insets.uniform(1).apply(outer);
```

#### 8. Canvas/Grid Widget

**What**: A widget optimized for cell-based rendering with coordinate transformation.

**Why Rung needs it**: The ladder diagram is a logical grid mapped to screen coordinates.

**Current workaround**: Manual coordinate math everywhere.

**Proposed API**:
```zig
const canvas = Canvas{
    .cell_width = 5,
    .cell_height = 1,
    .grid_size = .{ .cols = 20, .rows = 10 },
};
// Convert grid coords to screen coords
const screen_pos = canvas.toScreen(grid_x, grid_y, area);
// Render a cell
canvas.setCell(buf, grid_x, grid_y, cell_content, style);
```

#### 9. Notification/Toast System

**What**: Transient messages that auto-dismiss after a timeout.

**Why**: Feedback for actions ("Saved!", "Invalid placement", "Level unlocked").

**Current workaround**: Manual timer + state + rendering.

**Proposed API**:
```zig
frame.toast("Level complete!", .{
    .duration_ms = 2000,
    .position = .bottom_center,
    .style = .success, // or .error, .info, .warning
});
```

#### 10. Percentage-Based Constraints

**What**: Layout constraint that takes a percentage of available space.

**Why**: Sometimes you want "30% width" rather than calculating pixels.

**Proposed API**:
```zig
.percent(30)  // 30% of available space
// Alongside existing: .length(n), .flex(n), .ratio(a, b), .min(n), .max(n)
```

---

## Priority Matrix

| Item | Effort | Impact | Priority |
|------|--------|--------|----------|
| Input index selection | Medium | Critical | P0 |
| Parallel branch simulation | High | Critical | P0 |
| Level selection menu | Medium | High | P1 |
| Undo/redo | Medium | High | P1 |
| Input labels on contacts | Low | Medium | P2 |
| Victory screen | Low | Medium | P2 |
| Help overlay | Low | Medium | P2 |
| Modal dialog (framework) | Medium | High | P1 |
| Grid navigation helper (framework) | Low | Medium | P2 |
| Animated power flow | High | Low | P3 |
| Save/load progress | Medium | Medium | P3 |
| Custom level editor | High | Low | P4 |
| Sound effects | High | Low | P4 |

---

## Notes

- This wishlist captures the current state as of the initial Rung implementation
- Items should be converted to beads issues when work begins
- Framework items may be filed upstream on zithril or discussed in FEATURES_GAP.md
