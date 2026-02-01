// zithril - Zig TUI framework
// Built on rich_zig for terminal rendering primitives

const std = @import("std");
pub const rich_zig = @import("rich_zig");

// Geometry types
pub const geometry = @import("geometry.zig");
pub const Rect = geometry.Rect;
pub const Position = geometry.Position;

// Style types (wrapper around rich_zig)
pub const style_mod = @import("style.zig");
pub const Style = style_mod.Style;
pub const Color = style_mod.Color;
pub const StyleAttribute = style_mod.StyleAttribute;

// Layout types
pub const layout_mod = @import("layout.zig");
pub const Constraint = layout_mod.Constraint;
pub const Direction = layout_mod.Direction;
pub const layout = layout_mod.layout;
pub const BoundedRects = layout_mod.BoundedRects;

// Event types
pub const event = @import("event.zig");
pub const Event = event.Event;
pub const Key = event.Key;
pub const KeyCode = event.KeyCode;
pub const Modifiers = event.Modifiers;
pub const Mouse = event.Mouse;
pub const MouseKind = event.MouseKind;
pub const Size = event.Size;

// Action types
pub const action = @import("action.zig");
pub const Action = action.Action;
pub const Command = action.Command;

// Cell type (buffer building block)
pub const cell_mod = @import("cell.zig");
pub const Cell = cell_mod.Cell;

// Buffer (2D cell grid)
pub const buffer_mod = @import("buffer.zig");
pub const Buffer = buffer_mod.Buffer;
pub const CellUpdate = buffer_mod.CellUpdate;

// Frame (rendering context)
pub const frame_mod = @import("frame.zig");
pub const Frame = frame_mod.Frame;

// App runtime
pub const app_mod = @import("app.zig");
pub const App = app_mod.App;

// Terminal backend
pub const backend_mod = @import("backend.zig");
pub const Backend = backend_mod.Backend;
pub const BackendConfig = backend_mod.BackendConfig;
pub const ColorSupport = backend_mod.ColorSupport;
pub const TerminalSize = backend_mod.TerminalSize;
pub const detectColorSupport = backend_mod.detectColorSupport;
pub const getTerminalSize = backend_mod.getTerminalSize;
pub const terminal_panic = backend_mod.panic;

// Input parsing
pub const input_mod = @import("input.zig");
pub const Input = input_mod.Input;

test "style wrapper" {
    const style = Style.init().bold().fg(.red);
    try std.testing.expect(style.hasAttribute(.bold));

    const base = Style.init().fg(.green);
    const merged = base.patch(style);
    try std.testing.expect(merged.hasAttribute(.bold));
}

test "geometry re-export" {
    const rect = Rect.init(0, 0, 80, 24);
    try std.testing.expectEqual(@as(u32, 1920), rect.area());

    const pos = Position.init(10, 20);
    try std.testing.expectEqual(@as(u16, 10), pos.x);
}

test "layout re-export" {
    const c1 = Constraint.len(10);
    const c2 = Constraint.minSize(20);
    const c3 = Constraint.maxSize(30);
    const c4 = Constraint.fractional(1, 3);
    const c5 = Constraint.flexible(2);

    try std.testing.expectEqual(@as(u16, 10), c1.apply(100));
    try std.testing.expectEqual(@as(u16, 20), c2.apply(100));
    try std.testing.expectEqual(@as(u16, 30), c3.apply(100));
    try std.testing.expectEqual(@as(u16, 33), c4.apply(100));
    try std.testing.expectEqual(@as(u16, 100), c5.apply(100));

    try std.testing.expect(Direction.horizontal != Direction.vertical);
}

test "event re-export" {
    const key_event = Event{ .key = .{ .code = .escape, .modifiers = Modifiers.ctrl_only() } };
    try std.testing.expect(key_event == .key);
    try std.testing.expect(key_event.key.code == .escape);
    try std.testing.expect(key_event.key.modifiers.ctrl);

    const mouse_event = Event{ .mouse = Mouse.init(5, 10, .down) };
    try std.testing.expect(mouse_event == .mouse);
    try std.testing.expect(mouse_event.mouse.kind == .down);

    const resize_event = Event{ .resize = Size.init(120, 40) };
    try std.testing.expect(resize_event == .resize);
    try std.testing.expectEqual(@as(u16, 120), resize_event.resize.width);

    const tick_event = Event{ .tick = {} };
    try std.testing.expect(tick_event == .tick);

    const char_key = KeyCode.fromChar('q');
    try std.testing.expect(char_key.isChar());

    const f5_key = KeyCode.fromF(5);
    try std.testing.expect(f5_key != null);
}

test "action re-export" {
    const none_action = Action{ .none = {} };
    try std.testing.expect(none_action.isNone());

    const quit_action = Action{ .quit = {} };
    try std.testing.expect(quit_action.isQuit());

    const cmd_action = Action{ .command = Command.empty() };
    try std.testing.expect(cmd_action.isCommand());

    try std.testing.expect(Action.none_action.isNone());
    try std.testing.expect(Action.quit_action.isQuit());
}

test "cell re-export" {
    const cell = Cell.init('X');
    try std.testing.expectEqual(@as(u21, 'X'), cell.char);
    try std.testing.expectEqual(@as(u8, 1), cell.width);

    const wide_cell = Cell.init(0x4E2D);
    try std.testing.expect(wide_cell.isWide());

    const styled_cell = Cell.styled('A', Style.init().bold());
    try std.testing.expect(styled_cell.style.hasAttribute(.bold));
}

test "buffer re-export" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    try std.testing.expectEqual(@as(u16, 80), buf.width);
    try std.testing.expectEqual(@as(u16, 24), buf.height);

    buf.set(5, 5, Cell.styled('X', Style.init().bold()));
    const cell = buf.get(5, 5);
    try std.testing.expectEqual(@as(u21, 'X'), cell.char);
    try std.testing.expect(cell.style.hasAttribute(.bold));
}

test "backend re-export" {
    const default_config = BackendConfig{};
    try std.testing.expect(default_config.alternate_screen);
    try std.testing.expect(default_config.hide_cursor);
    try std.testing.expect(!default_config.mouse_capture);
    try std.testing.expect(!default_config.bracketed_paste);

    const custom_config = BackendConfig{
        .mouse_capture = true,
        .bracketed_paste = true,
    };
    try std.testing.expect(custom_config.mouse_capture);
    try std.testing.expect(custom_config.bracketed_paste);
}

test "backend queries re-export" {
    // Test ColorSupport enum
    try std.testing.expectEqual(@as(u32, 16), ColorSupport.basic.colorCount());
    try std.testing.expectEqual(@as(u32, 256), ColorSupport.extended.colorCount());
    try std.testing.expectEqual(@as(u32, 16_777_216), ColorSupport.true_color.colorCount());

    // Test detectColorSupport function exists and returns valid value
    const color_support = detectColorSupport();
    try std.testing.expect(color_support == .basic or color_support == .extended or color_support == .true_color);

    // Test getTerminalSize function exists and returns valid dimensions
    const size = getTerminalSize();
    try std.testing.expect(size.width > 0);
    try std.testing.expect(size.height > 0);
}

test "frame re-export" {
    var buf = try Buffer.init(std.testing.allocator, 100, 50);
    defer buf.deinit();

    var frame = Frame(16).init(&buf);

    try std.testing.expectEqual(@as(u16, 100), frame.size().width);
    try std.testing.expectEqual(@as(u16, 50), frame.size().height);

    const chunks = frame.layout(frame.size(), Direction.vertical, &.{
        Constraint.len(10),
        Constraint.flexible(1),
    });
    try std.testing.expectEqual(@as(usize, 2), chunks.len);
    try std.testing.expectEqual(@as(u16, 10), chunks.get(0).height);
    try std.testing.expectEqual(@as(u16, 40), chunks.get(1).height);
}

test "cellupdate re-export" {
    const update = CellUpdate{
        .x = 5,
        .y = 10,
        .cell = Cell.init('X'),
    };
    try std.testing.expectEqual(@as(u16, 5), update.x);
    try std.testing.expectEqual(@as(u16, 10), update.y);
    try std.testing.expectEqual(@as(u21, 'X'), update.cell.char);
}

test "app re-export" {
    const TestState = struct { count: i32 = 0 };
    const S = struct {
        fn update(state: *TestState, ev: Event) Action {
            _ = ev;
            state.count += 1;
            return Action.none_action;
        }
        fn view(_: *TestState, _: *Frame(App(TestState).DefaultMaxWidgets)) void {}
    };

    const app = App(TestState).init(.{
        .state = .{ .count = 10 },
        .update = S.update,
        .view = S.view,
    });

    try std.testing.expectEqual(@as(i32, 10), app.state.count);
}

test "input re-export" {
    var parser = Input.init();
    try std.testing.expectEqual(@as(usize, 0), parser.buffer_len);

    // Parse a simple key
    const parsed_event = parser.parse("a");
    try std.testing.expect(parsed_event != null);
    try std.testing.expect(parsed_event.? == .key);
}
