// Mouse utilities for zithril TUI framework
// Provides helpers for hit testing, clickable regions, hover detection, and drag selection

const std = @import("std");
const geometry = @import("geometry.zig");
const event_mod = @import("event.zig");

pub const Rect = geometry.Rect;
pub const Position = geometry.Position;
pub const Mouse = event_mod.Mouse;
pub const MouseKind = event_mod.MouseKind;

/// A clickable region with an identifier for hit testing.
/// Use this to track which UI elements receive mouse events.
pub fn HitRegion(comptime IdType: type) type {
    return struct {
        const Self = @This();

        id: IdType,
        rect: Rect,

        pub fn init(id: IdType, rect: Rect) Self {
            return .{ .id = id, .rect = rect };
        }

        /// Check if a mouse event hits this region.
        pub fn contains(self: Self, mouse: Mouse) bool {
            return self.rect.contains(mouse.x, mouse.y);
        }

        /// Check if a point hits this region.
        pub fn containsPoint(self: Self, x: u16, y: u16) bool {
            return self.rect.contains(x, y);
        }
    };
}

/// A collection of hit regions for testing multiple areas at once.
/// MaxRegions is the maximum number of regions that can be registered.
pub fn HitTester(comptime IdType: type, comptime MaxRegions: usize) type {
    return struct {
        const Self = @This();
        const Region = HitRegion(IdType);

        regions: [MaxRegions]Region = undefined,
        count: usize = 0,

        pub fn init() Self {
            return .{};
        }

        /// Register a hit region. Returns false if capacity is full.
        pub fn register(self: *Self, id: IdType, rect: Rect) bool {
            if (self.count >= MaxRegions) return false;
            self.regions[self.count] = Region.init(id, rect);
            self.count += 1;
            return true;
        }

        /// Clear all registered regions.
        pub fn clear(self: *Self) void {
            self.count = 0;
        }

        /// Find which region (if any) contains the mouse position.
        /// Returns the ID of the first matching region, or null if none match.
        /// Regions are tested in reverse order (last registered = highest priority).
        pub fn hitTest(self: Self, mouse: Mouse) ?IdType {
            return self.hitTestPoint(mouse.x, mouse.y);
        }

        /// Find which region contains the given point.
        pub fn hitTestPoint(self: Self, x: u16, y: u16) ?IdType {
            // Test in reverse order for z-order priority (later = on top)
            var i: usize = self.count;
            while (i > 0) {
                i -= 1;
                if (self.regions[i].containsPoint(x, y)) {
                    return self.regions[i].id;
                }
            }
            return null;
        }

        /// Get all regions that contain the mouse position.
        /// Useful when regions overlap and you need to know all hits.
        pub fn hitTestAll(self: Self, mouse: Mouse, results: []IdType) []IdType {
            var found: usize = 0;
            for (self.regions[0..self.count]) |region| {
                if (found >= results.len) break;
                if (region.contains(mouse)) {
                    results[found] = region.id;
                    found += 1;
                }
            }
            return results[0..found];
        }
    };
}

/// Tracks hover state for a single region.
/// Detects enter/exit transitions.
pub const HoverState = struct {
    inside: bool = false,
    last_x: u16 = 0,
    last_y: u16 = 0,

    /// Transition result from updating hover state.
    pub const Transition = enum {
        /// No change in hover state.
        none,
        /// Mouse entered the region.
        entered,
        /// Mouse exited the region.
        exited,
        /// Mouse moved within the region.
        moved,
    };

    /// Update hover state with new mouse position.
    /// Returns the transition type.
    pub fn update(self: *HoverState, rect: Rect, mouse: Mouse) Transition {
        const now_inside = rect.contains(mouse.x, mouse.y);
        const was_inside = self.inside;

        self.inside = now_inside;
        self.last_x = mouse.x;
        self.last_y = mouse.y;

        if (now_inside and !was_inside) {
            return .entered;
        } else if (!now_inside and was_inside) {
            return .exited;
        } else if (now_inside) {
            return .moved;
        }
        return .none;
    }

    /// Reset hover state (e.g., when region moves or is hidden).
    pub fn reset(self: *HoverState) void {
        self.inside = false;
    }

    /// Check if currently hovering.
    pub fn isHovering(self: HoverState) bool {
        return self.inside;
    }
};

/// Tracks drag selection state.
/// Use for implementing click-and-drag selection of regions or text.
pub const DragState = struct {
    /// Whether a drag is currently active.
    active: bool = false,

    /// Button that initiated the drag (from mouse event modifier interpretation).
    button_down: bool = false,

    /// Starting position of the drag.
    start: Position = .{ .x = 0, .y = 0 },

    /// Current position of the drag.
    current: Position = .{ .x = 0, .y = 0 },

    /// Process a mouse event and update drag state.
    /// Returns true if a drag operation state changed.
    pub fn handleMouse(self: *DragState, mouse: Mouse) bool {
        switch (mouse.kind) {
            .down => {
                self.active = true;
                self.button_down = true;
                self.start = .{ .x = mouse.x, .y = mouse.y };
                self.current = self.start;
                return true;
            },
            .up => {
                if (self.active) {
                    self.active = false;
                    self.button_down = false;
                    self.current = .{ .x = mouse.x, .y = mouse.y };
                    return true;
                }
                return false;
            },
            .drag => {
                if (self.active) {
                    self.current = .{ .x = mouse.x, .y = mouse.y };
                    return true;
                }
                return false;
            },
            .move => {
                // Movement without button doesn't affect drag
                return false;
            },
            .scroll_up, .scroll_down => {
                // Scroll events don't affect drag
                return false;
            },
        }
    }

    /// Cancel the current drag operation.
    pub fn cancel(self: *DragState) void {
        self.active = false;
        self.button_down = false;
    }

    /// Reset to initial state.
    pub fn reset(self: *DragState) void {
        self.active = false;
        self.button_down = false;
        self.start = .{ .x = 0, .y = 0 };
        self.current = .{ .x = 0, .y = 0 };
    }

    /// Get the selection rectangle (normalized so width/height are positive).
    /// Returns null if no drag is active.
    pub fn selectionRect(self: DragState) ?Rect {
        if (!self.active and !self.button_down) return null;

        const x1 = @min(self.start.x, self.current.x);
        const y1 = @min(self.start.y, self.current.y);
        const x2 = @max(self.start.x, self.current.x);
        const y2 = @max(self.start.y, self.current.y);

        return Rect.init(
            x1,
            y1,
            x2 - x1 + 1,
            y2 - y1 + 1,
        );
    }

    /// Check if the drag has moved from its starting position.
    pub fn hasMoved(self: DragState) bool {
        return self.start.x != self.current.x or self.start.y != self.current.y;
    }

    /// Get the delta from start to current position.
    pub fn delta(self: DragState) struct { dx: i32, dy: i32 } {
        return .{
            .dx = @as(i32, self.current.x) - @as(i32, self.start.x),
            .dy = @as(i32, self.current.y) - @as(i32, self.start.y),
        };
    }
};

/// Scroll wheel accumulator for smooth scrolling.
/// Accumulates scroll events and provides integer scroll amounts.
pub const ScrollAccumulator = struct {
    /// Accumulated scroll amount (can be fractional from some mice).
    accumulated: i32 = 0,

    /// Number of scroll events to count as one scroll unit.
    /// Set higher for slower scrolling.
    sensitivity: i32 = 1,

    /// Process a mouse event and return scroll delta if threshold reached.
    /// Returns positive for scroll down, negative for scroll up.
    pub fn handleMouse(self: *ScrollAccumulator, mouse: Mouse) ?i32 {
        switch (mouse.kind) {
            .scroll_up => {
                self.accumulated -= 1;
            },
            .scroll_down => {
                self.accumulated += 1;
            },
            else => return null,
        }

        if (@abs(self.accumulated) >= self.sensitivity) {
            const result = @divTrunc(self.accumulated, self.sensitivity);
            self.accumulated = @rem(self.accumulated, self.sensitivity);
            return result;
        }
        return null;
    }

    /// Reset accumulated scroll.
    pub fn reset(self: *ScrollAccumulator) void {
        self.accumulated = 0;
    }
};

// ============================================================
// SANITY TESTS - Basic type construction
// ============================================================

test "sanity: HitRegion construction" {
    const region = HitRegion(u32).init(42, Rect.init(10, 20, 100, 50));
    try std.testing.expectEqual(@as(u32, 42), region.id);
    try std.testing.expectEqual(@as(u16, 10), region.rect.x);
}

test "sanity: HitTester construction" {
    const tester = HitTester(u32, 16).init();
    try std.testing.expectEqual(@as(usize, 0), tester.count);
}

test "sanity: HoverState construction" {
    const hover = HoverState{};
    try std.testing.expect(!hover.inside);
}

test "sanity: DragState construction" {
    const drag = DragState{};
    try std.testing.expect(!drag.active);
}

test "sanity: ScrollAccumulator construction" {
    const scroll = ScrollAccumulator{};
    try std.testing.expectEqual(@as(i32, 0), scroll.accumulated);
}

// ============================================================
// BEHAVIOR TESTS - Hit testing
// ============================================================

test "behavior: HitRegion contains mouse" {
    const region = HitRegion(u32).init(1, Rect.init(10, 10, 20, 20));

    // Inside
    try std.testing.expect(region.contains(Mouse.init(15, 15, .down)));
    try std.testing.expect(region.contains(Mouse.init(10, 10, .down)));
    try std.testing.expect(region.contains(Mouse.init(29, 29, .down)));

    // Outside
    try std.testing.expect(!region.contains(Mouse.init(9, 15, .down)));
    try std.testing.expect(!region.contains(Mouse.init(30, 15, .down)));
    try std.testing.expect(!region.contains(Mouse.init(15, 9, .down)));
    try std.testing.expect(!region.contains(Mouse.init(15, 30, .down)));
}

test "behavior: HitTester register and test" {
    var tester = HitTester(u32, 16).init();

    try std.testing.expect(tester.register(1, Rect.init(0, 0, 10, 10)));
    try std.testing.expect(tester.register(2, Rect.init(20, 0, 10, 10)));
    try std.testing.expect(tester.register(3, Rect.init(0, 20, 10, 10)));

    try std.testing.expectEqual(@as(?u32, 1), tester.hitTest(Mouse.init(5, 5, .down)));
    try std.testing.expectEqual(@as(?u32, 2), tester.hitTest(Mouse.init(25, 5, .down)));
    try std.testing.expectEqual(@as(?u32, 3), tester.hitTest(Mouse.init(5, 25, .down)));
    try std.testing.expectEqual(@as(?u32, null), tester.hitTest(Mouse.init(15, 15, .down)));
}

test "behavior: HitTester z-order priority" {
    const tester_init = HitTester(u32, 16).init();
    var tester = tester_init;

    // Register overlapping regions
    try std.testing.expect(tester.register(1, Rect.init(0, 0, 20, 20)));
    try std.testing.expect(tester.register(2, Rect.init(5, 5, 20, 20))); // Overlaps region 1

    // Later region has higher priority
    try std.testing.expectEqual(@as(?u32, 2), tester.hitTest(Mouse.init(10, 10, .down)));

    // First region still accessible in non-overlapping area
    try std.testing.expectEqual(@as(?u32, 1), tester.hitTest(Mouse.init(2, 2, .down)));
}

test "behavior: HitTester clear" {
    var tester = HitTester(u32, 16).init();

    _ = tester.register(1, Rect.init(0, 0, 10, 10));
    try std.testing.expectEqual(@as(usize, 1), tester.count);

    tester.clear();
    try std.testing.expectEqual(@as(usize, 0), tester.count);
    try std.testing.expectEqual(@as(?u32, null), tester.hitTest(Mouse.init(5, 5, .down)));
}

// ============================================================
// BEHAVIOR TESTS - Hover tracking
// ============================================================

test "behavior: HoverState enter/exit transitions" {
    var hover = HoverState{};
    const rect = Rect.init(10, 10, 20, 20);

    // Initial state - outside
    try std.testing.expect(!hover.isHovering());

    // Enter
    const enter = hover.update(rect, Mouse.init(15, 15, .move));
    try std.testing.expect(enter == .entered);
    try std.testing.expect(hover.isHovering());

    // Move within
    const move = hover.update(rect, Mouse.init(16, 16, .move));
    try std.testing.expect(move == .moved);
    try std.testing.expect(hover.isHovering());

    // Exit
    const exit = hover.update(rect, Mouse.init(50, 50, .move));
    try std.testing.expect(exit == .exited);
    try std.testing.expect(!hover.isHovering());

    // Stay outside
    const stay = hover.update(rect, Mouse.init(51, 51, .move));
    try std.testing.expect(stay == .none);
}

test "behavior: HoverState reset" {
    var hover = HoverState{};
    const rect = Rect.init(10, 10, 20, 20);

    _ = hover.update(rect, Mouse.init(15, 15, .move));
    try std.testing.expect(hover.isHovering());

    hover.reset();
    try std.testing.expect(!hover.isHovering());
}

// ============================================================
// BEHAVIOR TESTS - Drag selection
// ============================================================

test "behavior: DragState basic drag operation" {
    var drag = DragState{};

    // Start drag
    try std.testing.expect(drag.handleMouse(Mouse.init(10, 10, .down)));
    try std.testing.expect(drag.active);
    try std.testing.expectEqual(@as(u16, 10), drag.start.x);
    try std.testing.expectEqual(@as(u16, 10), drag.start.y);

    // Drag to new position
    try std.testing.expect(drag.handleMouse(Mouse.init(20, 15, .drag)));
    try std.testing.expect(drag.active);
    try std.testing.expectEqual(@as(u16, 20), drag.current.x);
    try std.testing.expectEqual(@as(u16, 15), drag.current.y);

    // End drag
    try std.testing.expect(drag.handleMouse(Mouse.init(25, 20, .up)));
    try std.testing.expect(!drag.active);
}

test "behavior: DragState selectionRect normalized" {
    var drag = DragState{};

    // Drag from bottom-right to top-left
    _ = drag.handleMouse(Mouse.init(20, 20, .down));
    _ = drag.handleMouse(Mouse.init(10, 10, .drag));

    const rect = drag.selectionRect();
    try std.testing.expect(rect != null);
    try std.testing.expectEqual(@as(u16, 10), rect.?.x);
    try std.testing.expectEqual(@as(u16, 10), rect.?.y);
    try std.testing.expectEqual(@as(u16, 11), rect.?.width);
    try std.testing.expectEqual(@as(u16, 11), rect.?.height);
}

test "behavior: DragState delta" {
    var drag = DragState{};

    _ = drag.handleMouse(Mouse.init(10, 10, .down));
    _ = drag.handleMouse(Mouse.init(15, 8, .drag));

    const d = drag.delta();
    try std.testing.expectEqual(@as(i32, 5), d.dx);
    try std.testing.expectEqual(@as(i32, -2), d.dy);
}

test "behavior: DragState hasMoved" {
    var drag = DragState{};

    _ = drag.handleMouse(Mouse.init(10, 10, .down));
    try std.testing.expect(!drag.hasMoved());

    _ = drag.handleMouse(Mouse.init(11, 10, .drag));
    try std.testing.expect(drag.hasMoved());
}

test "behavior: DragState cancel" {
    var drag = DragState{};

    _ = drag.handleMouse(Mouse.init(10, 10, .down));
    try std.testing.expect(drag.active);

    drag.cancel();
    try std.testing.expect(!drag.active);
}

// ============================================================
// BEHAVIOR TESTS - Scroll accumulator
// ============================================================

test "behavior: ScrollAccumulator default sensitivity" {
    var scroll = ScrollAccumulator{};

    // Each scroll event triggers immediately with sensitivity=1
    try std.testing.expectEqual(@as(?i32, -1), scroll.handleMouse(Mouse.init(0, 0, .scroll_up)));
    try std.testing.expectEqual(@as(?i32, 1), scroll.handleMouse(Mouse.init(0, 0, .scroll_down)));
}

test "behavior: ScrollAccumulator higher sensitivity" {
    var scroll = ScrollAccumulator{ .sensitivity = 3 };

    // Need 3 scroll events to trigger
    try std.testing.expectEqual(@as(?i32, null), scroll.handleMouse(Mouse.init(0, 0, .scroll_down)));
    try std.testing.expectEqual(@as(?i32, null), scroll.handleMouse(Mouse.init(0, 0, .scroll_down)));
    try std.testing.expectEqual(@as(?i32, 1), scroll.handleMouse(Mouse.init(0, 0, .scroll_down)));

    // Accumulated resets after trigger
    try std.testing.expectEqual(@as(?i32, null), scroll.handleMouse(Mouse.init(0, 0, .scroll_down)));
}

test "behavior: ScrollAccumulator ignores non-scroll events" {
    var scroll = ScrollAccumulator{};

    try std.testing.expectEqual(@as(?i32, null), scroll.handleMouse(Mouse.init(0, 0, .down)));
    try std.testing.expectEqual(@as(?i32, null), scroll.handleMouse(Mouse.init(0, 0, .up)));
    try std.testing.expectEqual(@as(?i32, null), scroll.handleMouse(Mouse.init(0, 0, .drag)));
    try std.testing.expectEqual(@as(?i32, null), scroll.handleMouse(Mouse.init(0, 0, .move)));
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: HitTester capacity limit" {
    var tester = HitTester(u32, 2).init();

    try std.testing.expect(tester.register(1, Rect.init(0, 0, 10, 10)));
    try std.testing.expect(tester.register(2, Rect.init(10, 0, 10, 10)));
    try std.testing.expect(!tester.register(3, Rect.init(20, 0, 10, 10))); // Should fail

    try std.testing.expectEqual(@as(usize, 2), tester.count);
}

test "regression: DragState move without button has no effect" {
    var drag = DragState{};

    // Move without pressing button
    try std.testing.expect(!drag.handleMouse(Mouse.init(10, 10, .move)));
    try std.testing.expect(!drag.active);
    try std.testing.expect(drag.selectionRect() == null);
}

test "regression: DragState up without down has no effect" {
    var drag = DragState{};

    // Release without pressing
    try std.testing.expect(!drag.handleMouse(Mouse.init(10, 10, .up)));
    try std.testing.expect(!drag.active);
}

test "regression: HoverState tracks last position" {
    var hover = HoverState{};
    const rect = Rect.init(10, 10, 20, 20);

    _ = hover.update(rect, Mouse.init(15, 15, .move));
    try std.testing.expectEqual(@as(u16, 15), hover.last_x);
    try std.testing.expectEqual(@as(u16, 15), hover.last_y);

    _ = hover.update(rect, Mouse.init(50, 50, .move));
    try std.testing.expectEqual(@as(u16, 50), hover.last_x);
    try std.testing.expectEqual(@as(u16, 50), hover.last_y);
}
