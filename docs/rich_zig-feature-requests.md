# rich_zig Feature Requests -- Implementation Guide

Implementation guide for new features in [rich_zig](https://github.com/hotschmoe/rich_zig) v1.4.0. These features were identified by comparing zithril against [zigzag](https://github.com/meszmate/zigzag) and represent gaps in our terminal rendering layer.

Context: zithril is a TUI framework built on rich_zig. These features belong in rich_zig because they are terminal-primitive capabilities, not TUI-specific.

---

## Current State (v1.3.0)

What rich_zig already has that is relevant:

| Capability | Location | Notes |
|------------|----------|-------|
| `Color.fromHex("#ff0000")` | `src/color.zig:80` | Parses 6-digit hex with optional `#` prefix |
| `ColorTriplet.blend(c1, c2, t)` | `src/color.zig:31` | Linear RGB interpolation between two colors |
| `Color.downgrade(target)` | `src/color.zig:98` | Truecolor -> 256 -> 16 conversion |
| Terminal detection (env vars) | `src/terminal.zig` | COLORTERM, TERM, TERM_PROGRAM, NO_COLOR, FORCE_COLOR |
| `TerminalInfo.color_system` | `src/terminal.zig:8` | Detected ColorSystem (standard/eight_bit/truecolor) |

---

## Feature 1: Adaptive Colors

**Priority**: High | **Effort**: Low | **File**: `src/color.zig`

### What

A color that automatically downgrades itself to match the terminal's detected color system. Currently, users must manually call `color.downgrade(system)`. An adaptive color carries the intent "use the best version of this color the terminal supports."

### Why

TUI apps want to specify colors at the highest fidelity (truecolor) and have them degrade gracefully on limited terminals. This should be automatic, not manual.

### Design

Add an `AdaptiveColor` type that bundles multiple color representations:

```zig
pub const AdaptiveColor = struct {
    truecolor: Color,       // Best representation (RGB)
    eight_bit: ?Color,      // Optional hand-picked 256-color fallback
    standard: ?Color,       // Optional hand-picked 16-color fallback

    pub fn resolve(self: AdaptiveColor, system: ColorSystem) Color {
        return switch (system) {
            .truecolor => self.truecolor,
            .eight_bit => self.eight_bit orelse self.truecolor.downgrade(.eight_bit),
            .standard => self.standard orelse self.truecolor.downgrade(.standard),
        };
    }

    // Convenience: create with auto-downgrade (no hand-picked fallbacks)
    pub fn fromRgb(r: u8, g: u8, b: u8) AdaptiveColor {
        return .{
            .truecolor = Color.fromRgb(r, g, b),
            .eight_bit = null,
            .standard = null,
        };
    }

    // Create with explicit fallbacks for when auto-downgrade picks wrong colors
    pub fn init(truecolor: Color, eight_bit: ?Color, standard: ?Color) AdaptiveColor {
        return .{
            .truecolor = truecolor,
            .eight_bit = eight_bit,
            .standard = standard,
        };
    }
};
```

### Where It Connects

`Style` should accept `AdaptiveColor` as a color source. Two approaches:

**Option A** -- Add an `adaptive_color` / `adaptive_bgcolor` field to `Style`:

```zig
pub const Style = struct {
    color: ?Color = null,
    bgcolor: ?Color = null,
    adaptive_color: ?AdaptiveColor = null,
    adaptive_bgcolor: ?AdaptiveColor = null,
    // ...

    pub fn resolveColor(self: Style, system: ColorSystem) ?Color {
        if (self.adaptive_color) |ac| return ac.resolve(system);
        return self.color;
    }
};
```

**Option B** -- Resolve at render time. Keep `Style` unchanged; have `renderAnsi()` accept the target `ColorSystem` (it already does) and add a helper that resolves adaptive colors before constructing the style.

Option B is simpler and avoids growing `Style`. Recommend Option B.

### Integration Point

In `Style.renderAnsi()` (`src/style.zig`), colors are already downgraded via `downgrade()`. The adaptive color system extends this by allowing explicit fallback overrides.

### Tests to Write

```zig
test "AdaptiveColor auto-downgrade" {
    const ac = AdaptiveColor.fromRgb(255, 100, 50);
    const resolved = ac.resolve(.standard);
    try std.testing.expectEqual(ColorType.standard, resolved.color_type);
}

test "AdaptiveColor explicit fallback" {
    const ac = AdaptiveColor.init(
        Color.fromRgb(255, 100, 50),
        Color.from256(208),   // hand-picked orange
        Color.yellow,         // hand-picked standard
    );
    try std.testing.expect(ac.resolve(.standard).eql(Color.yellow));
    try std.testing.expect(ac.resolve(.eight_bit).eql(Color.from256(208)));
}
```

### Export

Add to `src/root.zig`:

```zig
pub const AdaptiveColor = color.AdaptiveColor;
```

---

## Feature 2: Color Interpolation and Gradients

**Priority**: Low | **Effort**: Low | **File**: `src/color.zig`

### What

Extend the existing `ColorTriplet.blend()` to support:
1. Multi-stop gradients (blend across N colors)
2. HSL interpolation (for perceptually smoother color transitions)

### Why

Gradients are useful for progress bars, heatmaps, sparklines, and status indicators. Linear RGB blending produces muddy midpoints for some color pairs (e.g., red-to-green goes through brown). HSL interpolation follows the color wheel.

### Design

Add functions to `ColorTriplet`:

```zig
// HSL conversion
pub fn toHsl(self: ColorTriplet) struct { h: f32, s: f32, l: f32 } {
    const r_f: f32 = @as(f32, @floatFromInt(self.r)) / 255.0;
    const g_f: f32 = @as(f32, @floatFromInt(self.g)) / 255.0;
    const b_f: f32 = @as(f32, @floatFromInt(self.b)) / 255.0;

    const max_c = @max(r_f, @max(g_f, b_f));
    const min_c = @min(r_f, @min(g_f, b_f));
    const delta = max_c - min_c;

    // Lightness
    const l = (max_c + min_c) / 2.0;

    // Saturation
    const s = if (delta == 0.0) 0.0
        else delta / (1.0 - @abs(2.0 * l - 1.0));

    // Hue (0-360)
    var h: f32 = 0.0;
    if (delta != 0.0) {
        if (max_c == r_f) {
            h = 60.0 * @mod((g_f - b_f) / delta, 6.0);
        } else if (max_c == g_f) {
            h = 60.0 * ((b_f - r_f) / delta + 2.0);
        } else {
            h = 60.0 * ((r_f - g_f) / delta + 4.0);
        }
    }
    if (h < 0.0) h += 360.0;

    return .{ .h = h, .s = s, .l = l };
}

pub fn fromHsl(h: f32, s: f32, l: f32) ColorTriplet {
    // Standard HSL to RGB conversion
    const c = (1.0 - @abs(2.0 * l - 1.0)) * s;
    const x = c * (1.0 - @abs(@mod(h / 60.0, 2.0) - 1.0));
    const m = l - c / 2.0;

    var r1: f32 = 0;
    var g1: f32 = 0;
    var b1: f32 = 0;

    if (h < 60.0) { r1 = c; g1 = x; }
    else if (h < 120.0) { r1 = x; g1 = c; }
    else if (h < 180.0) { g1 = c; b1 = x; }
    else if (h < 240.0) { g1 = x; b1 = c; }
    else if (h < 300.0) { r1 = x; b1 = c; }
    else { r1 = c; b1 = x; }

    return .{
        .r = @intFromFloat(@round((r1 + m) * 255.0)),
        .g = @intFromFloat(@round((g1 + m) * 255.0)),
        .b = @intFromFloat(@round((b1 + m) * 255.0)),
    };
}

// HSL-space interpolation for perceptually smooth transitions
pub fn blendHsl(c1: ColorTriplet, c2: ColorTriplet, t: f32) ColorTriplet {
    const clamped_t = @max(0.0, @min(1.0, t));
    const hsl1 = c1.toHsl();
    const hsl2 = c2.toHsl();

    // Shortest path around the hue wheel
    var dh = hsl2.h - hsl1.h;
    if (dh > 180.0) dh -= 360.0;
    if (dh < -180.0) dh += 360.0;

    var h = hsl1.h + dh * clamped_t;
    if (h < 0.0) h += 360.0;
    if (h >= 360.0) h -= 360.0;

    return ColorTriplet.fromHsl(
        h,
        hsl1.s + (hsl2.s - hsl1.s) * clamped_t,
        hsl1.l + (hsl2.l - hsl1.l) * clamped_t,
    );
}
```

Add a standalone gradient function:

```zig
// Generate N colors across a multi-stop gradient
// stops: array of ColorTriplets defining the gradient
// n: number of output colors
// Returns: caller-provided buffer filled with interpolated colors
pub fn gradient(
    stops: []const ColorTriplet,
    output: []ColorTriplet,
    comptime use_hsl: bool,
) void {
    if (stops.len == 0 or output.len == 0) return;
    if (stops.len == 1) {
        for (output) |*c| c.* = stops[0];
        return;
    }

    const n = output.len;
    for (0..n) |i| {
        const t = if (n == 1) 0.0 else @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
        const scaled = t * @as(f32, @floatFromInt(stops.len - 1));
        const idx = @min(@as(usize, @intFromFloat(scaled)), stops.len - 2);
        const local_t = scaled - @as(f32, @floatFromInt(idx));

        output[i] = if (use_hsl)
            ColorTriplet.blendHsl(stops[idx], stops[idx + 1], local_t)
        else
            ColorTriplet.blend(stops[idx], stops[idx + 1], local_t);
    }
}
```

### Tests to Write

```zig
test "ColorTriplet HSL round-trip" {
    const original = ColorTriplet{ .r = 200, .g = 100, .b = 50 };
    const hsl = original.toHsl();
    const recovered = ColorTriplet.fromHsl(hsl.h, hsl.s, hsl.l);
    // Allow +/- 1 for rounding
    try std.testing.expect(@abs(@as(i16, original.r) - @as(i16, recovered.r)) <= 1);
    try std.testing.expect(@abs(@as(i16, original.g) - @as(i16, recovered.g)) <= 1);
    try std.testing.expect(@abs(@as(i16, original.b) - @as(i16, recovered.b)) <= 1);
}

test "blendHsl red to green goes through yellow" {
    const red = ColorTriplet{ .r = 255, .g = 0, .b = 0 };
    const green = ColorTriplet{ .r = 0, .g = 255, .b = 0 };
    const mid = ColorTriplet.blendHsl(red, green, 0.5);
    // Mid-point should be yellowish (high R, high G, low B)
    try std.testing.expect(mid.r > 100);
    try std.testing.expect(mid.g > 100);
    try std.testing.expect(mid.b < 50);
}

test "gradient produces correct count" {
    const stops = [_]ColorTriplet{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
    };
    var output: [5]ColorTriplet = undefined;
    gradient(&stops, &output, false);
    // First and last should match first and last stops
    try std.testing.expectEqual(@as(u8, 255), output[0].r);
    try std.testing.expectEqual(@as(u8, 255), output[4].b);
}
```

---

## Feature 3: WCAG Contrast Ratio

**Priority**: Low | **Effort**: Low | **File**: `src/color.zig`

### What

Calculate the [WCAG 2.1 contrast ratio](https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio) between two colors. This enables accessibility-aware color selection.

### Why

When displaying text, foreground/background color pairs need sufficient contrast for readability. WCAG defines minimum ratios: 4.5:1 for normal text, 3:1 for large text. TUI apps benefit from being able to validate and auto-select accessible color pairings.

### Design

Add to `ColorTriplet`:

```zig
// Relative luminance per WCAG 2.1
// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
pub fn luminance(self: ColorTriplet) f64 {
    const r = linearize(@as(f64, @floatFromInt(self.r)) / 255.0);
    const g = linearize(@as(f64, @floatFromInt(self.g)) / 255.0);
    const b = linearize(@as(f64, @floatFromInt(self.b)) / 255.0);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

fn linearize(v: f64) f64 {
    return if (v <= 0.04045)
        v / 12.92
    else
        std.math.pow(f64, (v + 0.055) / 1.055, 2.4);
}

// WCAG contrast ratio (1:1 to 21:1)
pub fn contrastRatio(self: ColorTriplet, other: ColorTriplet) f64 {
    const l1 = self.luminance();
    const l2 = other.luminance();
    const lighter = @max(l1, l2);
    const darker = @min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
}

// WCAG compliance levels
pub const WcagLevel = enum {
    fail,   // < 3:1
    aa_large, // >= 3:1 (large text only)
    aa,     // >= 4.5:1
    aaa,    // >= 7:1
};

pub fn wcagLevel(self: ColorTriplet, other: ColorTriplet) WcagLevel {
    const ratio = self.contrastRatio(other);
    if (ratio >= 7.0) return .aaa;
    if (ratio >= 4.5) return .aa;
    if (ratio >= 3.0) return .aa_large;
    return .fail;
}
```

### Tests to Write

```zig
test "contrastRatio black on white is ~21" {
    const black = ColorTriplet{ .r = 0, .g = 0, .b = 0 };
    const white = ColorTriplet{ .r = 255, .g = 255, .b = 255 };
    const ratio = black.contrastRatio(white);
    try std.testing.expect(ratio > 20.5 and ratio < 21.5);
}

test "contrastRatio same color is 1" {
    const c = ColorTriplet{ .r = 128, .g = 128, .b = 128 };
    const ratio = c.contrastRatio(c);
    try std.testing.expect(ratio > 0.99 and ratio < 1.01);
}

test "wcagLevel black on white is AAA" {
    const black = ColorTriplet{ .r = 0, .g = 0, .b = 0 };
    const white = ColorTriplet{ .r = 255, .g = 255, .b = 255 };
    try std.testing.expectEqual(ColorTriplet.WcagLevel.aaa, black.wcagLevel(white));
}
```

---

## Feature 4: Synchronized Output (DEC Mode 2026)

**Priority**: High | **Effort**: Low | **File**: `src/terminal.zig`

### What

[Synchronized output](https://gist.github.com/christianparpart/d8a62cc1ab659194571ec44513a0065c) wraps a batch of terminal writes in begin/end markers so the terminal holds rendering until the batch is complete. This prevents visual tearing during frame updates.

### Protocol

```
Begin: ESC [ ? 2026 h    (DEC private mode set)
End:   ESC [ ? 2026 l    (DEC private mode reset)
```

The terminal buffers all output between begin/end and renders it atomically.

### Design

Add escape sequence constants and helper functions:

```zig
// In src/terminal.zig

pub const sync_output_begin = "\x1b[?2026h";
pub const sync_output_end = "\x1b[?2026l";

pub fn beginSyncOutput(writer: anytype) !void {
    try writer.writeAll(sync_output_begin);
}

pub fn endSyncOutput(writer: anytype) !void {
    try writer.writeAll(sync_output_end);
}
```

### Terminal Support Detection

Add to `TerminalInfo`:

```zig
pub const TerminalInfo = struct {
    // ... existing fields ...
    supports_sync_output: bool = false,
};
```

Detection logic (add to `detect()`):

```zig
// Terminals known to support DEC mode 2026 (synchronized output)
info.supports_sync_output = detectSyncOutput();

fn detectSyncOutput() bool {
    // Known supporting terminals:
    // - kitty, WezTerm, foot, Alacritty (0.15+), contour
    // - mintty, Windows Terminal (1.18+)
    // - iTerm2 (3.5+), tmux (3.4+)
    if (getEnv("TERM_PROGRAM")) |prog| {
        defer std.heap.page_allocator.free(prog);
        const supported = [_][]const u8{
            "WezTerm", "kitty", "Alacritty", "contour", "mintty",
        };
        for (supported) |t| {
            if (std.mem.eql(u8, prog, t)) return true;
        }
    }
    if (getEnv("WT_SESSION")) |wt| {
        defer std.heap.page_allocator.free(wt);
        return true;
    }
    // foot identifies via TERM=foot or TERM=foot-extra
    if (getEnv("TERM")) |term| {
        defer std.heap.page_allocator.free(term);
        if (std.mem.startsWith(u8, term, "foot")) return true;
    }
    return false;
}
```

### Export

Add to `src/root.zig`:

```zig
pub const beginSyncOutput = terminal.beginSyncOutput;
pub const endSyncOutput = terminal.endSyncOutput;
pub const sync_output_begin = terminal.sync_output_begin;
pub const sync_output_end = terminal.sync_output_end;
```

### zithril Integration Note

After this is implemented in rich_zig, zithril's rendering loop (`src/backend.zig`) should wrap frame output:

```
beginSyncOutput(writer)
  ... emit all cell diffs ...
endSyncOutput(writer)
flush()
```

### Tests to Write

```zig
test "sync output escape sequences" {
    try std.testing.expectEqualStrings("\x1b[?2026h", sync_output_begin);
    try std.testing.expectEqualStrings("\x1b[?2026l", sync_output_end);
}

test "beginSyncOutput writes correct sequence" {
    var buf: [32]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try beginSyncOutput(stream.writer());
    try std.testing.expectEqualStrings("\x1b[?2026h", stream.getWritten());
}
```

---

## Feature 5: Dark Background Detection

**Priority**: Low | **Effort**: Low | **File**: `src/terminal.zig`

### What

Detect whether the terminal has a dark or light background. This enables adaptive theming -- choosing high-contrast colors that work on both dark and light terminals.

### Why

A theme that looks good on a dark terminal may be unreadable on a light one. Currently, TUI apps must guess or hardcode. Several env-based heuristics can detect this reliably.

### Design

Add to `TerminalInfo`:

```zig
pub const BackgroundMode = enum {
    dark,
    light,
    unknown,
};

pub const TerminalInfo = struct {
    // ... existing fields ...
    background_mode: BackgroundMode = .unknown,
};
```

Detection heuristic (add to `detect()`):

```zig
info.background_mode = detectBackground();

fn detectBackground() BackgroundMode {
    // COLORFGBG is set by some terminals (rxvt, xterm, others)
    // Format: "foreground;background" where values are color indices
    // Background 0-6 = dark, 7-15 = light (approximation)
    if (getEnv("COLORFGBG")) |fgbg| {
        defer std.heap.page_allocator.free(fgbg);
        if (std.mem.lastIndexOfScalar(u8, fgbg, ';')) |sep| {
            const bg_str = fgbg[sep + 1..];
            const bg = std.fmt.parseInt(u8, bg_str, 10) catch return .unknown;
            return if (bg < 7) .dark else .light;
        }
    }

    // macOS Terminal.app defaults to light
    if (getEnv("TERM_PROGRAM")) |prog| {
        defer std.heap.page_allocator.free(prog);
        if (std.mem.eql(u8, prog, "Apple_Terminal")) return .light;
    }

    // Most modern terminals default to dark
    return .dark;
}
```

**Note**: The OSC 11 query (`\x1b]11;?\x07`) can get the actual background RGB from the terminal, but it requires reading a response from stdin, which is complex in a library context (timing, blocking, interference with app input). The env-based heuristic is sufficient for v1.4.0. OSC 11 can be added later as an opt-in query.

### Tests to Write

```zig
test "BackgroundMode enum" {
    const mode: BackgroundMode = .dark;
    try std.testing.expectEqual(BackgroundMode.dark, mode);
}
```

---

## Summary: Files to Modify

| File | Changes |
|------|---------|
| `src/color.zig` | `AdaptiveColor` struct, `toHsl`/`fromHsl`/`blendHsl` on `ColorTriplet`, `gradient()` function, `luminance`/`contrastRatio`/`wcagLevel` on `ColorTriplet` |
| `src/terminal.zig` | `sync_output_begin`/`end` constants, `beginSyncOutput`/`endSyncOutput` functions, `supports_sync_output` field, `background_mode` field, detection functions |
| `src/root.zig` | Export new public types and functions |
| `build.zig.zon` | Bump version to `1.4.0` |

## Implementation Order

1. **Synchronized output** (Feature 4) -- smallest change, highest value, no dependencies
2. **Adaptive colors** (Feature 1) -- builds on existing `Color.downgrade()`
3. **WCAG contrast ratio** (Feature 3) -- standalone, no dependencies
4. **Color interpolation** (Feature 2) -- builds on existing `ColorTriplet.blend()`
5. **Dark background detection** (Feature 5) -- standalone, lowest priority

## Testing

Run the full test suite after each feature:

```bash
zig build test
```

All new functions should have corresponding tests in the same file (following the existing pattern in `src/color.zig` and `src/terminal.zig`).

## Version

Bump `build.zig.zon` version from `1.3.0` to `1.4.0` (new features, backward-compatible).
