// App runtime for zithril TUI framework
// Generic application type parameterized by user state

const std = @import("std");
const builtin = @import("builtin");
const frame_mod = @import("frame.zig");
const event_mod = @import("event.zig");
const action_mod = @import("action.zig");
const buffer_mod = @import("buffer.zig");
const backend_mod = @import("backend.zig");
const input_mod = @import("input.zig");
const cell_mod = @import("cell.zig");

const is_windows = builtin.os.tag == .windows;
const windows = if (is_windows) std.os.windows else void;

pub const Frame = frame_mod.Frame;
pub const Event = event_mod.Event;
pub const Action = action_mod.Action;
pub const Buffer = buffer_mod.Buffer;
pub const Backend = backend_mod.Backend;
pub const Input = input_mod.Input;

/// App is the main runtime type, generic over the user's state type.
/// The user provides their own State struct and function pointers for update and view.
///
/// Fields:
/// - state: Instance of the user's State type
/// - update_fn: Function pointer for handling events, returns an Action
/// - view_fn: Function pointer for rendering the UI
/// - tick_rate_ms: Timer interval for tick events (0 = disabled)
/// - mouse_capture: Enable mouse event reporting
/// - paste_bracket: Enable bracketed paste mode
/// - alternate_screen: Use alternate screen buffer
pub fn App(comptime State: type) type {
    return struct {
        const Self = @This();

        /// Default max widgets for frame layout cache.
        pub const DefaultMaxWidgets: usize = 64;

        /// Pointer to user-owned state instance.
        state: *State,

        /// Update function: receives state and event, returns an Action.
        /// Signature: fn(*State, Event) Action
        update_fn: *const fn (*State, Event) Action,

        /// View function: receives state and frame, renders the UI.
        /// Signature: fn(*State, *Frame(N)) void
        /// The frame provides layout and render methods.
        view_fn: *const fn (*State, *Frame(DefaultMaxWidgets)) void,

        /// Timer interval in milliseconds for tick events.
        /// Set to 0 to disable tick events.
        tick_rate_ms: u32,

        /// Enable mouse event reporting.
        /// When true, the terminal backend will capture mouse events.
        mouse_capture: bool,

        /// Enable bracketed paste mode.
        /// Distinguishes pasted text from typed text.
        paste_bracket: bool,

        /// Use alternate screen buffer.
        /// Preserves original terminal content on exit.
        alternate_screen: bool,

        /// Configuration options for App initialization.
        pub const Config = struct {
            /// Pointer to user-owned state instance.
            state: *State,
            /// Update function pointer.
            update: *const fn (*State, Event) Action,
            /// View function pointer.
            view: *const fn (*State, *Frame(DefaultMaxWidgets)) void,
            /// Timer interval in milliseconds for tick events (0 = disabled).
            tick_rate_ms: u32 = 0,
            /// Enable mouse event reporting.
            mouse_capture: bool = false,
            /// Enable bracketed paste mode.
            paste_bracket: bool = false,
            /// Use alternate screen buffer.
            alternate_screen: bool = true,
        };

        /// Initialize an App with the given configuration.
        pub fn init(config: Config) Self {
            return .{
                .state = config.state,
                .update_fn = config.update,
                .view_fn = config.view,
                .tick_rate_ms = config.tick_rate_ms,
                .mouse_capture = config.mouse_capture,
                .paste_bracket = config.paste_bracket,
                .alternate_screen = config.alternate_screen,
            };
        }

        /// Returns a BackendConfig derived from this App's configuration.
        /// Used by the event loop to initialize the terminal backend.
        pub fn backendConfig(self: Self) @import("backend.zig").BackendConfig {
            return .{
                .alternate_screen = self.alternate_screen,
                .hide_cursor = true,
                .mouse_capture = self.mouse_capture,
                .bracketed_paste = self.paste_bracket,
            };
        }

        /// Call the update function with an event.
        /// Returns the action to be processed by the runtime.
        pub fn update(self: *Self, event: Event) Action {
            return self.update_fn(self.state, event);
        }

        /// Call the view function with a frame.
        /// The view function should use frame.render() to draw widgets.
        pub fn view(self: *Self, frame: *Frame(DefaultMaxWidgets)) void {
            self.view_fn(self.state, frame);
        }

        /// Error type for run operations.
        pub const RunError = error{
            OutOfMemory,
            NotATty,
            TerminalQueryFailed,
            TerminalSetFailed,
            IoError,
        };

        /// Run the main event loop until Action.quit is returned.
        ///
        /// Main loop:
        /// 1. Poll for events (keyboard, mouse, resize, or tick timeout)
        /// 2. Call update function with the event
        /// 3. Check action - if .quit, exit loop
        /// 4. Call view function to describe the UI
        /// 5. Render by diffing buffers and writing changes to terminal
        /// 6. Repeat
        pub fn run(self: *Self, allocator: std.mem.Allocator) RunError!void {
            // Initialize terminal backend
            var backend = Backend.init(self.backendConfig()) catch |err| {
                return switch (err) {
                    error.NotATty => RunError.NotATty,
                    error.TerminalQueryFailed => RunError.TerminalQueryFailed,
                    error.TerminalSetFailed => RunError.TerminalSetFailed,
                    error.IoError => RunError.IoError,
                };
            };
            defer backend.deinit();

            // Initialize input parser
            var input = Input.init();

            // Get initial terminal size
            const initial_size = backend.getSize();

            // Create double buffers for diffing
            var current_buf = Buffer.init(allocator, initial_size.width, initial_size.height) catch {
                return RunError.OutOfMemory;
            };
            defer current_buf.deinit();

            var previous_buf = Buffer.init(allocator, initial_size.width, initial_size.height) catch {
                return RunError.OutOfMemory;
            };
            defer previous_buf.deinit();

            // Allocate update buffer for diff results
            const max_updates = @as(usize, initial_size.width) * @as(usize, initial_size.height);
            var updates = allocator.alloc(buffer_mod.CellUpdate, max_updates) catch {
                return RunError.OutOfMemory;
            };
            defer allocator.free(updates);

            // Calculate tick timeout in nanoseconds (0 means no timeout/poll mode)
            const tick_timeout_ns: ?u64 = if (self.tick_rate_ms > 0)
                @as(u64, self.tick_rate_ms) * std.time.ns_per_ms
            else
                null;

            // Track last tick time for tick events
            var last_tick: i128 = std.time.nanoTimestamp();

            // Clear screen initially
            backend.clearScreen();
            backend.cursorHome();

            // Initial render
            {
                current_buf.clear();
                var frame = Frame(DefaultMaxWidgets).init(&current_buf);
                self.view(&frame);
                try renderBuffer(&backend, &current_buf, &previous_buf, updates);
                @memcpy(previous_buf.cells, current_buf.cells);
            }

            // Main event loop
            while (true) {
                // Poll for events or wait for tick timeout
                const maybe_event = try pollEvent(&input, &backend, tick_timeout_ns);

                // Handle tick event generation
                const event: Event = if (maybe_event) |e|
                    e
                else if (tick_timeout_ns) |timeout| blk: {
                    const now = std.time.nanoTimestamp();
                    if (now - last_tick >= @as(i128, timeout)) {
                        last_tick = now;
                        break :blk Event{ .tick = {} };
                    }
                    continue;
                } else continue;

                // Handle resize events specially - resize buffers
                if (event == .resize) {
                    const new_size = event.resize;
                    const new_max_updates = @as(usize, new_size.width) * @as(usize, new_size.height);

                    current_buf.resize(new_size.width, new_size.height) catch {
                        return RunError.OutOfMemory;
                    };
                    previous_buf.resize(new_size.width, new_size.height) catch {
                        return RunError.OutOfMemory;
                    };

                    allocator.free(updates);
                    updates = allocator.alloc(buffer_mod.CellUpdate, new_max_updates) catch {
                        return RunError.OutOfMemory;
                    };

                    // Clear screen on resize
                    backend.clearScreen();
                    backend.cursorHome();
                }

                // Call update function
                const action = self.update(event);

                // Check for quit action
                if (action.isQuit()) {
                    break;
                }

                // TODO: Handle command actions in the future

                // Clear current buffer and call view function
                current_buf.clear();
                var frame = Frame(DefaultMaxWidgets).init(&current_buf);
                self.view(&frame);

                // Render changes to terminal
                try renderBuffer(&backend, &current_buf, &previous_buf, updates);

                // Swap buffers (copy current to previous for next diff)
                @memcpy(previous_buf.cells, current_buf.cells);
            }
        }

        /// Poll for an input event from the terminal.
        /// Returns null if no event is available within the timeout.
        fn pollEvent(input: *Input, backend: *Backend, timeout_ns: ?u64) RunError!?Event {
            _ = timeout_ns; // TODO: Implement proper polling with timeout

            // Read available input bytes
            var buf: [256]u8 = undefined;
            const bytes_read = if (is_windows) blk: {
                const stdin_handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch {
                    return RunError.IoError;
                };
                const file = std.fs.File{ .handle = stdin_handle };
                break :blk file.read(&buf) catch |err| {
                    switch (err) {
                        error.WouldBlock => return null,
                        else => return RunError.IoError,
                    }
                };
            } else blk: {
                break :blk std.posix.read(std.posix.STDIN_FILENO, &buf) catch |err| {
                    switch (err) {
                        error.WouldBlock => return null,
                        else => return RunError.IoError,
                    }
                };
            };

            if (bytes_read == 0) {
                return null;
            }

            // Parse input bytes into events
            if (input.parse(buf[0..bytes_read])) |parsed_event| {
                _ = backend; // Backend used for future resize detection
                return parsed_event;
            }

            return null;
        }

        /// Render buffer changes to the terminal using buffered Output.
        /// Uses rich_zig's ANSI rendering for proper color and attribute output.
        fn renderBuffer(
            backend: *Backend,
            current: *Buffer,
            previous: *Buffer,
            update_buffer: []buffer_mod.CellUpdate,
        ) RunError!void {
            const changes = current.diff(previous.*, update_buffer);

            if (changes.len == 0) {
                return;
            }

            // Use buffered output with rich_zig ANSI rendering
            var out = backend_mod.DefaultOutput.init(backend.handle);

            // Begin synchronized output to prevent tearing
            if (backend.capabilities.sync_output) {
                out.beginSyncOutput();
            }

            var last_x: ?u16 = null;
            var last_y: ?u16 = null;

            for (changes) |change| {
                // Move cursor if not consecutive (different row or non-adjacent column)
                const consecutive = last_x != null and last_y != null and
                    last_y.? == change.y and last_x.? + 1 == change.x;

                if (!consecutive) {
                    out.cursorTo(change.x, change.y);
                }

                // Set style using rich_zig ANSI rendering
                if (!change.cell.style.isEmpty()) {
                    out.setStyle(change.cell.style);
                } else {
                    out.resetStyle();
                }

                // Write character
                if (change.cell.width > 0) {
                    out.writeChar(change.cell.char, backend_mod.Style.empty);
                }

                last_x = change.x;
                last_y = change.y;
            }

            // Reset style at the end
            out.resetStyle();

            // End synchronized output
            if (backend.capabilities.sync_output) {
                out.endSyncOutput();
            }

            // Flush buffered output to terminal
            out.flush();
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
    var state = TestHelpers.SimpleState{ .count = 42 };
    const app = App(TestHelpers.SimpleState).init(.{
        .state = &state,
        .update = TestHelpers.simpleUpdate,
        .view = TestHelpers.simpleView,
    });

    try std.testing.expectEqual(@as(i32, 42), app.state.count);
}

test "sanity: App update modifies state" {
    var state = TestHelpers.SimpleState{ .count = 0 };
    var app = App(TestHelpers.SimpleState).init(.{
        .state = &state,
        .update = TestHelpers.simpleUpdate,
        .view = TestHelpers.simpleView,
    });

    _ = app.update(Event{ .tick = {} });
    try std.testing.expectEqual(@as(i32, 1), app.state.count);

    _ = app.update(Event{ .tick = {} });
    try std.testing.expectEqual(@as(i32, 2), app.state.count);
}

test "sanity: App update returns quit action" {
    var state = TestHelpers.EmptyState{};
    var app = App(TestHelpers.EmptyState).init(.{
        .state = &state,
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
    var state = NestedTestHelpers.NestedState{
        .inner = .{ .value = 100 },
        .name = "test",
    };
    var app = App(NestedTestHelpers.NestedState).init(.{
        .state = &state,
        .update = NestedTestHelpers.nestedUpdate,
        .view = NestedTestHelpers.nestedView,
    });

    try std.testing.expectEqual(@as(u32, 100), app.state.inner.value);

    _ = app.update(Event{ .tick = {} });
    try std.testing.expectEqual(@as(u32, 101), app.state.inner.value);
}

const ViewTestHelpers = struct {
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
    var state = ViewTestHelpers.RenderState{ .rendered = false };
    var app = App(ViewTestHelpers.RenderState).init(.{
        .state = &state,
        .update = ViewTestHelpers.renderUpdate,
        .view = ViewTestHelpers.renderView,
    });

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
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
    var state = TestHelpers.EmptyState{};
    const app = App(TestHelpers.EmptyState).init(.{
        .state = &state,
        .update = TestHelpers.emptyUpdate,
        .view = TestHelpers.emptyView,
    });

    _ = app;
}

const EventTrackingHelpers = struct {
    const EventType = enum { none, key, mouse, resize, tick, command_result };

    const TrackingState = struct {
        last_event_type: EventType = .none,
    };

    fn trackingUpdate(state: *TrackingState, event: Event) Action {
        state.last_event_type = switch (event) {
            .key => .key,
            .mouse => .mouse,
            .resize => .resize,
            .tick => .tick,
            .command_result => .command_result,
        };
        return Action.none_action;
    }

    fn trackingView(state: *TrackingState, frame: *Frame(App(TrackingState).DefaultMaxWidgets)) void {
        _ = state;
        _ = frame;
    }
};

test "regression: App handles all event types in update" {
    var state = EventTrackingHelpers.TrackingState{};
    var app = App(EventTrackingHelpers.TrackingState).init(.{
        .state = &state,
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

// ============================================================
// CONFIG TESTS - Runtime configuration options
// ============================================================

test "config: App.Config has correct defaults" {
    var state = TestHelpers.SimpleState{};
    const config = App(TestHelpers.SimpleState).Config{
        .state = &state,
        .update = TestHelpers.simpleUpdate,
        .view = TestHelpers.simpleView,
    };

    try std.testing.expectEqual(@as(u32, 0), config.tick_rate_ms);
    try std.testing.expect(!config.mouse_capture);
    try std.testing.expect(!config.paste_bracket);
    try std.testing.expect(config.alternate_screen);
}

test "config: App stores configuration values" {
    var state = TestHelpers.SimpleState{};
    const app = App(TestHelpers.SimpleState).init(.{
        .state = &state,
        .update = TestHelpers.simpleUpdate,
        .view = TestHelpers.simpleView,
        .tick_rate_ms = 100,
        .mouse_capture = true,
        .paste_bracket = true,
        .alternate_screen = false,
    });

    try std.testing.expectEqual(@as(u32, 100), app.tick_rate_ms);
    try std.testing.expect(app.mouse_capture);
    try std.testing.expect(app.paste_bracket);
    try std.testing.expect(!app.alternate_screen);
}

test "config: backendConfig translates App config to BackendConfig" {
    var state = TestHelpers.SimpleState{};
    const app = App(TestHelpers.SimpleState).init(.{
        .state = &state,
        .update = TestHelpers.simpleUpdate,
        .view = TestHelpers.simpleView,
        .mouse_capture = true,
        .paste_bracket = true,
        .alternate_screen = false,
    });

    const backend_config = app.backendConfig();

    try std.testing.expect(!backend_config.alternate_screen);
    try std.testing.expect(backend_config.hide_cursor);
    try std.testing.expect(backend_config.mouse_capture);
    try std.testing.expect(backend_config.bracketed_paste);
}

test "config: backendConfig uses defaults correctly" {
    var state = TestHelpers.SimpleState{};
    const app = App(TestHelpers.SimpleState).init(.{
        .state = &state,
        .update = TestHelpers.simpleUpdate,
        .view = TestHelpers.simpleView,
    });

    const backend_config = app.backendConfig();

    try std.testing.expect(backend_config.alternate_screen);
    try std.testing.expect(backend_config.hide_cursor);
    try std.testing.expect(!backend_config.mouse_capture);
    try std.testing.expect(!backend_config.bracketed_paste);
}
