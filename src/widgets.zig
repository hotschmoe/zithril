// Widgets module for zithril TUI framework
// Re-exports all built-in widgets

pub const block = @import("widgets/block.zig");
pub const Block = block.Block;
pub const BorderType = block.BorderType;
pub const BorderChars = block.BorderChars;

pub const text = @import("widgets/text.zig");
pub const Text = text.Text;
pub const Alignment = text.Alignment;

pub const list = @import("widgets/list.zig");
pub const List = list.List;

pub const gauge = @import("widgets/gauge.zig");
pub const Gauge = gauge.Gauge;

pub const paragraph = @import("widgets/paragraph.zig");
pub const Paragraph = paragraph.Paragraph;
pub const Wrap = paragraph.Wrap;

pub const table = @import("widgets/table.zig");
pub const Table = table.Table;

pub const tabs = @import("widgets/tabs.zig");
pub const Tabs = tabs.Tabs;

pub const scrollbar = @import("widgets/scrollbar.zig");
pub const Scrollbar = scrollbar.Scrollbar;
pub const Orientation = scrollbar.Orientation;

pub const clear = @import("widgets/clear.zig");
pub const Clear = clear.Clear;

pub const scroll_view = @import("widgets/scroll_view.zig");
pub const ScrollView = scroll_view.ScrollView;
pub const ScrollState = scroll_view.ScrollState;
pub const ScrollableList = scroll_view.ScrollableList;

pub const text_input = @import("widgets/text_input.zig");
pub const TextInput = text_input.TextInput;
pub const TextInputState = text_input.TextInputState;

pub const sparkline = @import("widgets/sparkline.zig");
pub const Sparkline = sparkline.Sparkline;
pub const SparklineDirection = sparkline.Direction;

pub const bar_chart = @import("widgets/bar_chart.zig");
pub const BarChart = bar_chart.BarChart;
pub const Bar = bar_chart.Bar;
pub const BarGroup = bar_chart.BarGroup;
pub const BarChartOrientation = bar_chart.Orientation;

pub const chart = @import("widgets/chart.zig");
pub const Chart = chart.Chart;
pub const Axis = chart.Axis;
pub const LineDataset = chart.LineDataset;
pub const ScatterDataset = chart.ScatterDataset;
pub const Markers = chart.Markers;
pub const ChartLabel = chart.Label;

pub const line_gauge = @import("widgets/line_gauge.zig");
pub const LineGauge = line_gauge.LineGauge;
pub const LineSet = line_gauge.LineSet;

pub const canvas = @import("widgets/canvas.zig");
pub const Canvas = canvas.Canvas;
pub const CanvasMarker = canvas.Marker;
pub const CanvasShape = canvas.Shape;
pub const CanvasPainter = canvas.Painter;
pub const CanvasCircle = canvas.Circle;
pub const CanvasLine = canvas.Line;
pub const CanvasRectangle = canvas.Rectangle;
pub const CanvasPoints = canvas.Points;

pub const tree = @import("widgets/tree.zig");
pub const Tree = tree.Tree;
pub const TreeItem = tree.TreeItem;
pub const TreeState = tree.TreeState;
pub const TreeSymbols = tree.TreeSymbols;
pub const MutableTreeItem = tree.MutableTreeItem;

pub const menu = @import("widgets/menu.zig");
pub const Menu = menu.Menu;
pub const MenuItem = menu.MenuItem;
pub const MenuState = menu.MenuState;
pub const MenuSymbols = menu.MenuSymbols;

pub const calendar = @import("widgets/calendar.zig");
pub const Calendar = calendar.Calendar;
pub const daysInMonth = calendar.daysInMonth;
pub const isLeapYear = calendar.isLeapYear;
pub const dayOfWeek = calendar.dayOfWeek;

test "widgets module" {
    _ = block;
    _ = text;
    _ = list;
    _ = gauge;
    _ = paragraph;
    _ = table;
    _ = tabs;
    _ = scrollbar;
    _ = clear;
    _ = scroll_view;
    _ = text_input;
    _ = sparkline;
    _ = bar_chart;
    _ = chart;
    _ = line_gauge;
    _ = canvas;
    _ = tree;
    _ = menu;
    _ = calendar;
}
