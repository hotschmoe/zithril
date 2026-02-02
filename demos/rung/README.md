# Rung

*A ladder logic puzzle game built with zithril.*

```
     +----[ ]----[ ]----( )----+
     |  A     B      Y         |
     +-------------------------+
```

Learn programmable logic controllers (PLCs) through 10 progressively challenging puzzles. Wire up contacts, coils, and logic to match the required truth table.

---

## Purpose

Rung serves two goals:

1. **Framework stress test** - Push zithril's capabilities: interactive grids, real-time simulation, complex state, visual feedback
2. **Educational game** - Teach ladder logic fundamentals in an engaging way

This demo lives in zithril to help mature the TUI framework. Once zithril stabilizes, Rung will be extracted as a standalone project.

---

## Running

```bash
zig build run-rung
```

---

## Gameplay

Each level presents:
- A **truth table** showing required input/output behavior
- An empty or partial **ladder diagram** to complete
- A **component palette** to drag/place elements

Your goal: wire the ladder so all truth table rows pass.

### Controls

| Key | Action |
|-----|--------|
| Arrow keys | Move cursor |
| Space | Place/remove component |
| Tab | Cycle component type |
| Enter | Run simulation |
| R | Reset level |
| N | Next level (when solved) |
| Q | Quit |

---

## Ladder Logic Primer

Ladder logic reads left-to-right, top-to-bottom. Power flows from the left rail through contacts to energize coils on the right.

### Components

```
--[ ]--   Normally Open (NO) contact
         Closed when input is TRUE

--[/]--   Normally Closed (NC) contact
         Closed when input is FALSE

--( )--   Output coil
         Energized when power reaches it

--[L]--   Latch coil
         Stays on until reset

--[U]--   Unlatch coil
         Resets a latched output
```

### Example: AND Logic

```
     +----[ ]----[ ]----( )----+
     |  A     B      Y         |
     +-------------------------+

Truth table:
  A   B  | Y
  -------+---
  0   0  | 0
  0   1  | 0
  1   0  | 0
  1   1  | 1
```

### Example: OR Logic

```
     +----[ ]--------( )----+
     |  A         Y         |
     +----[ ]---------------+
     |  B                   |
     +-----------------------+

Truth table:
  A   B  | Y
  -------+---
  0   0  | 0
  0   1  | 1
  1   0  | 1
  1   1  | 1
```

---

## Level Progression

| Level | Concept | Components |
|-------|---------|------------|
| 1 | Direct wire | NO contact, coil |
| 2 | NOT gate | NC contact |
| 3 | AND gate | Series contacts |
| 4 | OR gate | Parallel branches |
| 5 | NAND gate | Combined logic |
| 6 | NOR gate | Combined logic |
| 7 | XOR gate | Complex branching |
| 8 | Latching | Latch/Unlatch coils |
| 9 | Sequencing | Multiple rungs |
| 10 | Motor control | Start/stop circuit |

---

## Architecture

```
demos/rung/
  main.zig        Entry point, App setup
  game.zig        Game state machine, level progression
  ladder.zig      Ladder logic simulation engine
  levels.zig      Level definitions (diagrams, truth tables)
  widgets.zig     Custom widgets (grid editor, truth table, palette)
```

### Key Types

```zig
// A single cell in the ladder diagram
const Cell = union(enum) {
    empty,
    wire: WireType,
    contact: Contact,
    coil: Coil,
    junction: JunctionType,
};

// The complete game state
const GameState = struct {
    level: usize,
    diagram: Diagram,
    cursor: Position,
    selected_component: ComponentType,
    simulation_running: bool,
    truth_table_results: []bool,
};
```

---

## Framework Stress Points

This demo specifically exercises:

- **Grid-based rendering** - The ladder diagram is a 2D grid with cell-level rendering
- **Cursor navigation** - Precise movement within a constrained space
- **State diffing** - Simulation runs update cells rapidly
- **Color/style** - Visual feedback for power flow, errors, success states
- **Layout nesting** - Multiple panels (diagram, palette, truth table, status)
- **Input handling** - Modal behavior (editing vs. simulating)

---

## Future Enhancements

When extracted as standalone:

- [ ] More levels (20+)
- [ ] Timers and counters
- [ ] Custom level editor
- [ ] Level sharing
- [ ] Animated power flow
- [ ] Sound effects
- [ ] Save/load progress
