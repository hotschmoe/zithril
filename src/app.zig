// App runtime for zithril TUI framework
// Generic application type parameterized by user state

const std = @import("std");
const frame_mod = @import("frame.zig");
const event_mod = @import("event.zig");
const action_mod = @import("action.zig");

pub const Frame = frame_mod.Frame;
pub const Event = event_mod.Event;
pub const Action = action_mod.Action;

/// App is the main runtime type, generic over the user's state type.
/// The user provides their own State struct and function pointers for update and view.
///
/// Fields:
/// - state: Instance of the user's State type
/// - update_fn: Function pointer for handling events, returns an Action
/// - view_fn: Function pointer for rendering the UI
pub fn App(comptime State: type) type {
    return struct {
        const Self = @This();

        /// Default max widgets for frame layout cache.
        pub const DefaultMaxWidgets: usize = 64;

        /// User-defined state instance.
        state: State,

        /// Update function: receives state and event, returns an Action.
        /// Signature: fn(*State, Event) Action
        update_fn: *const fn (*State, Event) Action,

        /// View function: receives state and frame, renders the UI.
        /// Signature: fn(*State, *Frame(N)) void
        /// The frame provides layout and render methods.
        view_fn: *const fn (*State, *Frame(DefaultMaxWidgets)) void,

        /// Configuration options.
        pub const Config = struct {
            /// Initial state instance.
            state: State,
            /// Update function pointer.
            update: *const fn (*State, Event) Action,
            /// View function pointer.
            view: *const fn (*State, *Frame(DefaultMaxWidgets)) void,
        };

        /// Initialize an App with the given configuration.
        pub fn init(config: Config) Self {
            return .{
                .state = config.state,
                .update_fn = config.update,
                .view_fn = config.view,
            };
        }

        /// Call the update function with an event.
        /// Returns the action to be processed by the runtime.
        pub fn update(self: *Self, event: Event) Action {
            return self.update_fn(&self.state, event);
        }

        /// Call the view function with a frame.
        /// The view function should use frame.render() to draw widgets.
        pub fn view(self: *Self, frame: *Frame(DefaultMaxWidgets)) void {
            self.view_fn(&self.state, frame);
        }
    };
}

// ============================================================
// SANITY TESTS - Basic App construction
// ============================================================

const TestHelpers = struct {
    const SimpleState = struct {
        count: i32 = 0,
    };

    fn simpleUpdate(state: *SimpleState, event: Event) Action {
        _ = event;
        state.count += 1;
        return Action.none_action;
    }

    fn simpleView(state: *SimpleState, frame: *Frame(App(SimpleState).DefaultMaxWidgets)) void {
        _ = state;
        _ = frame;
    }

    const EmptyState = struct {};

    fn emptyUpdate(state: *EmptyState, event: Event) Action {
        _ = state;
        _ = event;
        return Action.none_action;
    }

    fn emptyView(state: *EmptyState, frame: *Frame(App(EmptyState).DefaultMaxWidgets)) void {
        _ = state;
        _ = frame;
    }

    fn quitOnEscapeUpdate(state: *EmptyState, event: Event) Action {
        _ = state;
        switch (event) {
            .key => |key| {
                if (key.code == .escape) {
                    return Action.quit_action;
                }
            },
            else => {},
        }
        return Action.none_action;
    }
};

test "sanity: App init with simple state" {
    const app = App(TestHelpers.SimpleState).init(.{
        .state = .{ .count = 42 },
        .update = TestHelpers.simpleUpdate,
        .view = TestHelpers.simpleView,
    });

    try std.testing.expectEqual(@as(i32, 42), app.state.count);
}

test "sanity: App update modifies state" {
    var app = App(TestHelpers.SimpleState).init(.{
        .state = .{ .count = 0 },
        .update = TestHelpers.simpleUpdate,
        .view = TestHelpers.simpleView,
    });

    _ = app.update(Event{ .tick = {} });
    try std.testing.expectEqual(@as(i32, 1), app.state.count);

    _ = app.update(Event{ .tick = {} });
    try std.testing.expectEqual(@as(i32, 2), app.state.count);
}

test "sanity: App update returns quit action" {
    var app = App(TestHelpers.EmptyState).init(.{
        .state = .{},
        .update = TestHelpers.quitOnEscapeUpdate,
        .view = TestHelpers.emptyView,
    });

    const action1 = app.update(Event{ .tick = {} });
    try std.testing.expect(action1.isNone());

    const action2 = app.update(Event{ .key = .{ .code = .escape } });
    try std.testing.expect(action2.isQuit());
}

// ============================================================
// BEHAVIOR TESTS - App with complex state
// ============================================================

const NestedTestHelpers = struct {
    const Inner = struct {
        value: u32,
    };

    const NestedState = struct {
        inner: Inner,
        name: []const u8,
    };

    fn nestedUpdate(state: *NestedState, event: Event) Action {
        _ = event;
        state.inner.value += 1;
        return Action.none_action;
    }

    fn nestedView(state: *NestedState, frame: *Frame(App(NestedState).DefaultMaxWidgets)) void {
        _ = state;
        _ = frame;
    }
};

test "behavior: App with nested state" {
    var app = App(NestedTestHelpers.NestedState).init(.{
        .state = .{
            .inner = .{ .value = 100 },
            .name = "test",
        },
        .update = NestedTestHelpers.nestedUpdate,
        .view = NestedTestHelpers.nestedView,
    });

    try std.testing.expectEqual(@as(u32, 100), app.state.inner.value);

    _ = app.update(Event{ .tick = {} });
    try std.testing.expectEqual(@as(u32, 101), app.state.inner.value);
}

const ViewTestHelpers = struct {
    const buffer_mod = @import("buffer.zig");
    const Buffer = buffer_mod.Buffer;

    const RenderState = struct {
        rendered: bool = false,
    };

    fn renderUpdate(state: *RenderState, event: Event) Action {
        _ = state;
        _ = event;
        return Action.none_action;
    }

    fn renderView(state: *RenderState, frame: *Frame(App(RenderState).DefaultMaxWidgets)) void {
        _ = frame;
        state.rendered = true;
    }
};

test "behavior: App view receives mutable frame" {
    var app = App(ViewTestHelpers.RenderState).init(.{
        .state = .{ .rendered = false },
        .update = ViewTestHelpers.renderUpdate,
        .view = ViewTestHelpers.renderView,
    });

    var buf = try ViewTestHelpers.Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();
    var frame = Frame(App(ViewTestHelpers.RenderState).DefaultMaxWidgets).init(&buf);

    try std.testing.expect(!app.state.rendered);
    app.view(&frame);
    try std.testing.expect(app.state.rendered);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: App with empty state struct" {
    const app = App(TestHelpers.EmptyState).init(.{
        .state = .{},
        .update = TestHelpers.emptyUpdate,
        .view = TestHelpers.emptyView,
    });

    _ = app;
}

const EventTrackingHelpers = struct {
    const EventType = enum { none, key, mouse, resize, tick };

    const TrackingState = struct {
        last_event_type: EventType = .none,
    };

    fn trackingUpdate(state: *TrackingState, event: Event) Action {
        state.last_event_type = switch (event) {
            .key => .key,
            .mouse => .mouse,
            .resize => .resize,
            .tick => .tick,
        };
        return Action.none_action;
    }

    fn trackingView(state: *TrackingState, frame: *Frame(App(TrackingState).DefaultMaxWidgets)) void {
        _ = state;
        _ = frame;
    }
};

test "regression: App handles all event types in update" {
    var app = App(EventTrackingHelpers.TrackingState).init(.{
        .state = .{},
        .update = EventTrackingHelpers.trackingUpdate,
        .view = EventTrackingHelpers.trackingView,
    });

    _ = app.update(Event{ .key = .{ .code = .enter } });
    try std.testing.expect(app.state.last_event_type == .key);

    _ = app.update(Event{ .mouse = .{ .x = 0, .y = 0, .kind = .down } });
    try std.testing.expect(app.state.last_event_type == .mouse);

    _ = app.update(Event{ .resize = .{ .width = 80, .height = 24 } });
    try std.testing.expect(app.state.last_event_type == .resize);

    _ = app.update(Event{ .tick = {} });
    try std.testing.expect(app.state.last_event_type == .tick);
}
