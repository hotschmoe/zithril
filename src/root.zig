// zithril - Zig TUI framework
// Built on rich_zig for terminal rendering primitives

const std = @import("std");
pub const rich_zig = @import("rich_zig");

// Error types
pub const errors = @import("errors.zig");
pub const Error = errors.Error;
pub const ErrorContext = errors.ErrorContext;
pub const mapAllocError = errors.mapAllocError;
pub const withContext = errors.withContext;
pub const withContextHere = errors.withContextHere;

// Geometry types
pub const geometry = @import("geometry.zig");
pub const Rect = geometry.Rect;
pub const Position = geometry.Position;

// Spacing types
pub const spacing_mod = @import("spacing.zig");
pub const Padding = spacing_mod.Padding;
pub const Margin = spacing_mod.Margin;
pub const Spacing = spacing_mod.Spacing;

// Style types (wrapper around rich_zig)
pub const style_mod = @import("style.zig");
pub const Style = style_mod.Style;
pub const Color = style_mod.Color;
pub const StyleAttribute = style_mod.StyleAttribute;
pub const ColorSystem = style_mod.ColorSystem;
pub const ColorType = style_mod.ColorType;
pub const ColorTriplet = style_mod.ColorTriplet;
pub const Segment = style_mod.Segment;
pub const ControlCode = style_mod.ControlCode;
pub const ControlType = style_mod.ControlType;

// Layout types
pub const layout_mod = @import("layout.zig");
pub const Constraint = layout_mod.Constraint;
pub const Direction = layout_mod.Direction;
pub const Flex = layout_mod.Flex;
pub const LayoutOptions = layout_mod.LayoutOptions;
pub const layout = layout_mod.layout;
pub const layoutWithFlex = layout_mod.layoutWithFlex;
pub const layoutWithOptions = layout_mod.layoutWithOptions;
pub const BoundedRects = layout_mod.BoundedRects;

// Event types
pub const event = @import("event.zig");
pub const Event = event.Event;
pub const Key = event.Key;
pub const KeyCode = event.KeyCode;
pub const KeyAction = event.KeyAction;
pub const Modifiers = event.Modifiers;
pub const Mouse = event.Mouse;
pub const MouseKind = event.MouseKind;
pub const Size = event.Size;

// Mouse utilities
pub const mouse_util = @import("mouse.zig");
pub const HitRegion = mouse_util.HitRegion;
pub const HitTester = mouse_util.HitTester;
pub const HoverState = mouse_util.HoverState;
pub const DragState = mouse_util.DragState;
pub const ScrollAccumulator = mouse_util.ScrollAccumulator;

// Action types
pub const action = @import("action.zig");
pub const Action = action.Action;
pub const Command = action.Command;
pub const CommandResult = action.CommandResult;

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
pub const TerminalType = backend_mod.TerminalType;
pub const TerminalCapabilities = backend_mod.TerminalCapabilities;
pub const Output = backend_mod.Output;
pub const DefaultOutput = backend_mod.DefaultOutput;
pub const detectColorSupport = backend_mod.detectColorSupport;
pub const detectTerminalType = backend_mod.detectTerminalType;
pub const getTerminalSize = backend_mod.getTerminalSize;
pub const colorSupportToSystem = backend_mod.colorSupportToSystem;
pub const terminal_panic = backend_mod.panic;

// Input parsing
pub const input_mod = @import("input.zig");
pub const Input = input_mod.Input;

// Text utilities
pub const text_mod = @import("text.zig");
pub const displayWidth = text_mod.displayWidth;

// Theme system
pub const theme_mod = @import("theme.zig");
pub const Theme = theme_mod.Theme;

// ANSI parsing
pub const ansi_mod = @import("ansi.zig");
pub const AnsiText = ansi_mod.Text;
pub const AnsiSpan = ansi_mod.Span;
pub const fromAnsi = ansi_mod.fromAnsi;
pub const stripAnsi = ansi_mod.stripAnsi;
pub const parseAnsiToSegments = ansi_mod.parseAnsiToSegments;
pub const freeAnsiSegments = ansi_mod.freeSegments;

// Measurement protocol
pub const measurement_mod = @import("measurement.zig");
pub const Measurement = measurement_mod.Measurement;
pub const fromConstraint = measurement_mod.fromConstraint;

// Highlighter (pattern-based text highlighting)
pub const highlighter_mod = @import("highlighter.zig");
pub const Highlighter = highlighter_mod.Highlighter;
pub const HighlightRule = highlighter_mod.HighlightRule;
pub const HighlightMatch = highlighter_mod.Match;
pub const highlightText = highlighter_mod.highlightText;
pub const reprHighlighter = highlighter_mod.repr;

// Animation helpers
pub const animation = @import("animation.zig");
pub const Animation = animation.Animation;
pub const Easing = animation.Easing;
pub const Keyframe = animation.Keyframe;
pub const KeyframeAnimation = animation.KeyframeAnimation;
pub const Duration = animation.Duration;
pub const FrameTimer = animation.FrameTimer;
pub const lerp = animation.lerp;
pub const inverseLerp = animation.inverseLerp;
pub const remap = animation.remap;
pub const smoothstep = animation.smoothstep;
pub const smootherstep = animation.smootherstep;

// Terminal graphics protocols
pub const graphics = @import("graphics.zig");
pub const GraphicsProtocol = graphics.GraphicsProtocol;
pub const GraphicsCapabilities = graphics.GraphicsCapabilities;
pub const SixelEncoder = graphics.SixelEncoder;
pub const KittyEncoder = graphics.KittyEncoder;
pub const ITerm2Encoder = graphics.ITerm2Encoder;

// Testing utilities
pub const testing = @import("testing.zig");
pub const TestRecorder = testing.TestRecorder;
pub const TestPlayer = testing.TestPlayer;
pub const MockBackend = testing.MockBackend;
pub const Snapshot = testing.Snapshot;
pub const TestHarness = testing.TestHarness;
pub const bufferToAnnotatedText = testing.bufferToAnnotatedText;
pub const expectCell = testing.expectCell;
pub const expectCellStyle = testing.expectCellStyle;
pub const expectString = testing.expectString;

// Scenario DSL
pub const scenario = @import("scenario.zig");
pub const ScenarioParser = scenario.ScenarioParser;
pub const ScenarioRunner = scenario.ScenarioRunner;
pub const ScenarioResult = scenario.ScenarioResult;
pub const ScenarioDirective = scenario.Directive;

// Audit utilities (QA analysis)
pub const audit = @import("audit.zig");
pub const AuditResult = audit.AuditResult;
pub const AuditReport = audit.AuditReport;
pub const AuditCategory = audit.AuditCategory;
pub const Severity = audit.Severity;
pub const AuditFinding = audit.Finding;
pub const auditContrast = audit.auditContrast;
pub const auditKeyboardNav = audit.auditKeyboardNav;
pub const auditFocusVisibility = audit.auditFocusVisibility;
pub const KeyboardAuditConfig = audit.KeyboardAuditConfig;

// Widgets
pub const widgets = @import("widgets.zig");
pub const Block = widgets.Block;
pub const BorderType = widgets.BorderType;
pub const BorderChars = widgets.BorderChars;
pub const Text = widgets.Text;
pub const List = widgets.List;
pub const Gauge = widgets.Gauge;
pub const Paragraph = widgets.Paragraph;
pub const Wrap = widgets.Wrap;
pub const Alignment = widgets.Alignment;
pub const Tabs = widgets.Tabs;
pub const Scrollbar = widgets.Scrollbar;
pub const Orientation = widgets.Orientation;
pub const Table = widgets.Table;
pub const Clear = widgets.Clear;
pub const ScrollView = widgets.ScrollView;
pub const ScrollState = widgets.ScrollState;
pub const ScrollableList = widgets.ScrollableList;
pub const TextInput = widgets.TextInput;
pub const TextInputState = widgets.TextInputState;

// Data visualization widgets
pub const Sparkline = widgets.Sparkline;
pub const SparklineDirection = widgets.SparklineDirection;
pub const BarChart = widgets.BarChart;
pub const Bar = widgets.Bar;
pub const BarGroup = widgets.BarGroup;
pub const BarChartOrientation = widgets.BarChartOrientation;
pub const Chart = widgets.Chart;
pub const ChartAxis = widgets.Axis;
pub const LineDataset = widgets.LineDataset;
pub const ScatterDataset = widgets.ScatterDataset;
pub const ChartMarkers = widgets.Markers;
pub const ChartLabel = widgets.ChartLabel;
pub const LineGauge = widgets.LineGauge;
pub const LineSet = widgets.LineSet;

// Drawing widgets
pub const Canvas = widgets.Canvas;
pub const CanvasMarker = widgets.CanvasMarker;
pub const CanvasShape = widgets.CanvasShape;
pub const CanvasPainter = widgets.CanvasPainter;
pub const CanvasCircle = widgets.CanvasCircle;
pub const CanvasLine = widgets.CanvasLine;
pub const CanvasRectangle = widgets.CanvasRectangle;
pub const CanvasPoints = widgets.CanvasPoints;

// Navigation widgets
pub const Tree = widgets.Tree;
pub const TreeItem = widgets.TreeItem;
pub const TreeState = widgets.TreeState;
pub const TreeSymbols = widgets.TreeSymbols;
pub const MutableTreeItem = widgets.MutableTreeItem;
pub const Menu = widgets.Menu;
pub const MenuItem = widgets.MenuItem;
pub const MenuState = widgets.MenuState;
pub const MenuSymbols = widgets.MenuSymbols;

// Specialty widgets
pub const Calendar = widgets.Calendar;
pub const BigText = widgets.BigText;
pub const PixelSize = widgets.PixelSize;
pub const Font8x8 = widgets.Font8x8;
pub const CodeEditor = widgets.CodeEditor;
pub const CodeEditorLanguage = widgets.CodeEditorLanguage;
pub const CodeEditorTheme = widgets.CodeEditorTheme;
pub const TokenType = widgets.TokenType;

// Color utilities (rich_zig v1.4.0)
pub const color_mod = @import("color.zig");
pub const AdaptiveColor = color_mod.AdaptiveColor;
pub const WcagLevel = color_mod.WcagLevel;
pub const gradient = color_mod.gradient;
pub const BackgroundMode = color_mod.BackgroundMode;

// Pretty printing
pub const pretty_mod = @import("pretty.zig");
pub const Pretty = pretty_mod.Pretty;
pub const PrettyTheme = pretty_mod.PrettyTheme;
pub const PrettyOptions = pretty_mod.PrettyOptions;
pub const formatToBuffer = pretty_mod.formatToBuffer;
pub const freeSegments = pretty_mod.freeSegments;
pub const prettyFormat = pretty_mod.pretty;
pub const prettyFormatWithOptions = pretty_mod.prettyWithOptions;

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

test "spacing re-export" {
    // Test Padding
    const p = Padding.all(5);
    try std.testing.expectEqual(@as(u16, 5), p.top);
    try std.testing.expectEqual(@as(u16, 5), p.right);

    const p2 = Padding.symmetric(10, 5);
    try std.testing.expectEqual(@as(u16, 5), p2.top);
    try std.testing.expectEqual(@as(u16, 10), p2.left);

    // Test Margin
    const m = Margin.all(3);
    try std.testing.expectEqual(@as(u16, 3), m.top);

    // Test Spacing
    const s = Spacing.init(8);
    try std.testing.expectEqual(@as(u16, 8), s.value);
    try std.testing.expectEqual(@as(u16, 0), Spacing.none.value);

    // Test apply
    const rect = Rect.init(0, 0, 100, 50);
    const inner_rect = p.apply(rect);
    try std.testing.expectEqual(@as(u16, 5), inner_rect.x);
    try std.testing.expectEqual(@as(u16, 90), inner_rect.width);
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

test "mouse utilities re-export" {
    // Test HitTester
    var tester = HitTester(u32, 8).init();
    try std.testing.expect(tester.register(1, Rect.init(0, 0, 20, 10)));
    try std.testing.expect(tester.register(2, Rect.init(30, 0, 20, 10)));

    try std.testing.expectEqual(@as(?u32, 1), tester.hitTest(Mouse.init(10, 5, .down)));
    try std.testing.expectEqual(@as(?u32, 2), tester.hitTest(Mouse.init(40, 5, .down)));
    try std.testing.expectEqual(@as(?u32, null), tester.hitTest(Mouse.init(25, 5, .down)));

    // Test HoverState
    var hover = HoverState{};
    const rect = Rect.init(10, 10, 20, 20);
    try std.testing.expect(!hover.isHovering());
    const transition = hover.update(rect, Mouse.init(15, 15, .move));
    try std.testing.expect(transition == .entered);
    try std.testing.expect(hover.isHovering());

    // Test DragState
    var drag = DragState{};
    _ = drag.handleMouse(Mouse.init(10, 10, .down));
    try std.testing.expect(drag.active);
    _ = drag.handleMouse(Mouse.init(20, 20, .drag));
    try std.testing.expect(drag.hasMoved());
    const sel = drag.selectionRect();
    try std.testing.expect(sel != null);
    try std.testing.expectEqual(@as(u16, 11), sel.?.width);

    // Test ScrollAccumulator
    var scroll = ScrollAccumulator{};
    try std.testing.expectEqual(@as(?i32, -1), scroll.handleMouse(Mouse.init(0, 0, .scroll_up)));
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

    // Test CommandResult
    const result = CommandResult.success(42, null);
    try std.testing.expect(result.isSuccess());
    try std.testing.expectEqual(@as(u32, 42), result.id);

    // Test command_result event
    const result_event = Event{ .command_result = result };
    try std.testing.expect(result_event == .command_result);
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

    // Test colorSupportToSystem conversion
    try std.testing.expectEqual(ColorSystem.standard, colorSupportToSystem(.basic));
    try std.testing.expectEqual(ColorSystem.eight_bit, colorSupportToSystem(.extended));
    try std.testing.expectEqual(ColorSystem.truecolor, colorSupportToSystem(.true_color));
}

test "output re-export" {
    // Test Output type exists and can be instantiated
    const TestOutput = Output(256);
    const builtin = @import("builtin");
    const handle = if (builtin.os.tag == .windows)
        (std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch unreachable)
    else
        std.posix.STDOUT_FILENO;
    var out = TestOutput.initWithColorSystem(handle, ColorSystem.truecolor);
    try std.testing.expect(out.isEmpty());

    // Test DefaultOutput type exists
    try std.testing.expect(@sizeOf(DefaultOutput) > 0);
}

test "terminal type re-export" {
    // Test TerminalType enum is accessible
    const term_type = detectTerminalType();
    _ = term_type;

    // Test feature detection methods
    try std.testing.expect(TerminalType.windows_terminal.supportsTrueColor());
    try std.testing.expect(TerminalType.iterm2.supportsTrueColor());
    try std.testing.expect(TerminalType.kitty.supportsTrueColor());
    try std.testing.expect(!TerminalType.cmd_exe.supportsTrueColor());

    // Test TerminalCapabilities
    const caps = TerminalCapabilities.fromTerminalType(.xterm, .extended);
    try std.testing.expect(caps.terminal_type == .xterm);
    try std.testing.expect(caps.color_support == .extended);
    try std.testing.expect(caps.unicode);
    try std.testing.expect(caps.mouse);
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

    var state = TestState{ .count = 10 };
    const app = App(TestState).init(.{
        .state = &state,
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

test "widgets re-export" {
    // Test Block widget is accessible
    const block = Block{
        .title = "Test",
        .border = BorderType.rounded,
        .title_alignment = Alignment.center,
    };
    try std.testing.expectEqualStrings("Test", block.title.?);
    try std.testing.expect(block.border == .rounded);
    try std.testing.expect(block.title_alignment == .center);

    // Test BorderChars
    const chars = BorderType.plain.chars();
    try std.testing.expectEqual(@as(u21, '+'), chars.top_left);

    // Test Block.inner
    const area = Rect.init(0, 0, 20, 10);
    const inner_area = block.inner(area);
    try std.testing.expectEqual(@as(u16, 1), inner_area.x);
    try std.testing.expectEqual(@as(u16, 18), inner_area.width);
}

test "block render" {
    var buf = try Buffer.init(std.testing.allocator, 20, 10);
    defer buf.deinit();

    const block = Block{
        .title = "Hello",
        .border = .rounded,
        .border_style = Style.init().fg(.cyan),
    };

    var frame = Frame(16).init(&buf);
    frame.render(block, frame.size());

    // Check top-left corner is rounded
    try std.testing.expectEqual(@as(u21, 0x256D), buf.get(0, 0).char);

    // Check title is rendered
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(1, 0).char);
}

test "animation re-export" {
    // Test Animation type
    var anim = Animation.init(1000);
    try std.testing.expectEqual(@as(u32, 1000), anim.duration_ms);
    try std.testing.expect(!anim.isComplete());

    _ = anim.update(500);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), anim.rawProgress(), 0.001);

    // Test Easing
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), Easing.linear.apply(0.5), 0.001);

    // Test Duration
    const dur = Duration.fromSeconds(1.5);
    try std.testing.expectEqual(@as(u32, 1500), dur.ms);

    // Test FrameTimer
    var timer = FrameTimer.init(60);
    try std.testing.expectEqual(@as(u32, 16), timer.msPerFrame());

    // Test interpolation helpers
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), lerp(0.0, 100.0, 0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), inverseLerp(0.0, 100.0, 50.0), 0.001);
}

test "graphics re-export" {
    // Test GraphicsProtocol
    try std.testing.expectEqualStrings("Sixel", GraphicsProtocol.sixel.name());
    try std.testing.expectEqualStrings("Kitty", GraphicsProtocol.kitty.name());

    // Test GraphicsCapabilities
    const caps = GraphicsCapabilities.detect();
    _ = caps.hasGraphics();

    // Test SixelEncoder
    const sixel = SixelEncoder.init();
    try std.testing.expect(sixel.palette_size > 0);

    // Test KittyEncoder
    var kitty = KittyEncoder.init();
    try std.testing.expectEqual(@as(u32, 1), kitty.nextImageId());

    // Test ITerm2Encoder
    _ = ITerm2Encoder.init();
}

test "testing utilities re-export" {
    // Test TestRecorder
    var recorder = TestRecorder(256).init();
    try std.testing.expectEqual(@as(usize, 0), recorder.len());

    const key_ev = testing.keyEvent('a');
    try std.testing.expect(recorder.recordSimple(key_ev));
    try std.testing.expectEqual(@as(usize, 1), recorder.len());

    // Test TestPlayer
    var player = TestPlayer(256).init(recorder.getEvents());
    try std.testing.expect(!player.isDone());
    _ = player.next();
    try std.testing.expect(player.isDone());

    // Test MockBackend
    var mock = try MockBackend.init(std.testing.allocator, 80, 24);
    defer mock.deinit();

    try std.testing.expectEqual(@as(u16, 80), mock.width);
    try std.testing.expectEqual(@as(u16, 24), mock.height);

    try mock.write("Test");
    try std.testing.expectEqualStrings("Test", mock.getOutput());

    // Test Snapshot
    var buf = try Buffer.init(std.testing.allocator, 10, 2);
    defer buf.deinit();

    buf.setString(0, 0, "Hello", Style.empty);

    var snapshot = try Snapshot.fromBuffer(std.testing.allocator, buf);
    defer snapshot.deinit();

    try std.testing.expect(std.mem.indexOf(u8, snapshot.text, "Hello") != null);

    // Test helper functions
    try expectCell(buf, 0, 0, 'H');
    try expectString(buf, 0, 0, "Hello");

    // Test bufferToAnnotatedText
    const annotated = try bufferToAnnotatedText(std.testing.allocator, buf);
    defer std.testing.allocator.free(annotated);
    try std.testing.expect(std.mem.indexOf(u8, annotated, "10x2") != null);
}

test "color utilities re-export" {
    // AdaptiveColor
    const ac = AdaptiveColor.fromRgb(255, 100, 50);
    const resolved = ac.resolve(.truecolor);
    try std.testing.expect(resolved.triplet != null);

    // Gradient
    const stops = [_]ColorTriplet{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
    };
    var output: [3]ColorTriplet = undefined;
    gradient(&stops, &output, false);
    try std.testing.expectEqual(@as(u8, 255), output[0].r);

    // WCAG
    const black = ColorTriplet{ .r = 0, .g = 0, .b = 0 };
    const white = ColorTriplet{ .r = 255, .g = 255, .b = 255 };
    try std.testing.expectEqual(WcagLevel.aaa, black.wcagLevel(white));

    // BackgroundMode
    const mode: BackgroundMode = .dark;
    try std.testing.expect(mode == .dark);
}

test "sync output re-export" {
    try std.testing.expectEqualStrings("\x1b[?2026h", Backend.SYNC_OUTPUT_BEGIN);
    try std.testing.expectEqualStrings("\x1b[?2026l", Backend.SYNC_OUTPUT_END);
    try std.testing.expect(TerminalType.kitty.supportsSyncOutput());
    try std.testing.expect(!TerminalType.unknown.supportsSyncOutput());
}
