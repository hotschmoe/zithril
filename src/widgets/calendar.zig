// Calendar widget for zithril TUI framework
// Monthly calendar display with date selection and event markers

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");
const text_mod = @import("text.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Alignment = text_mod.Alignment;

/// Calendar widget that displays a monthly calendar grid.
///
/// Renders a month view with selectable days, today highlighting, and optional
/// event markers. Supports showing days from adjacent months to fill the grid.
pub const Calendar = struct {
    /// Year to display (e.g., 2026).
    year: i32,

    /// Month to display (1-12).
    month: u8,

    /// Currently selected day (1-31), or null for no selection.
    selected_day: ?u8 = null,

    /// Show days from previous/next month to fill empty cells.
    show_adjacent_months: bool = true,

    /// Show week numbers in the leftmost column.
    show_week_numbers: bool = false,

    /// Base style for the calendar.
    style: Style = Style.empty,

    /// Style for today's date.
    today_style: Style = Style.init().bold(),

    /// Style for the selected day.
    selected_style: Style = Style.init().reverse(),

    /// Style for days from previous/next month.
    adjacent_style: Style = Style.init().dim(),

    /// Style for the header (month/year and weekday names).
    header_style: Style = Style.init().bold(),

    /// Days that should be marked (e.g., days with events).
    marked_days: []const u8 = &.{},

    /// Style for marked days.
    marked_style: Style = Style.init().underline(),

    /// Today's date for highlighting (day of month, 1-31).
    /// If null, today highlighting is disabled.
    today: ?struct { year: i32, month: u8, day: u8 } = null,

    /// First day of week: 0=Sunday, 1=Monday.
    first_day_of_week: u8 = 0,

    /// Render the calendar into the buffer at the given area.
    pub fn render(self: Calendar, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.month < 1 or self.month > 12) return;

        var current_y = area.y;

        // Render month/year header
        if (area.height >= 1) {
            self.renderHeader(area.x, current_y, area.width, buf);
            current_y +|= 1;
        }

        // Render weekday names
        if (current_y < area.y +| area.height) {
            self.renderWeekdays(area.x, current_y, area.width, buf);
            current_y +|= 1;
        }

        // Render day grid
        self.renderDays(area.x, current_y, area.width, area.y +| area.height -| current_y, buf);
    }

    /// Render the month/year header line.
    fn renderHeader(self: Calendar, x: u16, y: u16, width: u16, buf: *Buffer) void {
        const month_names = [_][]const u8{
            "January", "February", "March",     "April",   "May",      "June",
            "July",    "August",   "September", "October", "November", "December",
        };

        if (self.month < 1 or self.month > 12) return;
        const month_name = month_names[self.month - 1];

        // Format: "   January 2026"
        var header_buf: [32]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "{s} {d}", .{ month_name, self.year }) catch return;

        // Center the header
        const header_len: u16 = @intCast(@min(header.len, width));
        const offset = (width -| header_len) / 2;

        buf.setString(x +| offset, y, header[0..header_len], self.header_style);
    }

    /// Render the weekday name row.
    fn renderWeekdays(self: Calendar, x: u16, y: u16, width: u16, buf: *Buffer) void {
        const weekday_names = if (self.first_day_of_week == 0)
            [_][]const u8{ "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
        else
            [_][]const u8{ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" };

        const start_x = if (self.show_week_numbers) x +| 3 else x;

        // Each day takes 3 characters (2 for name + 1 space), except last
        var col_x = start_x;
        for (weekday_names) |name| {
            if (col_x +| 2 > x +| width) break;
            buf.setString(col_x, y, name, self.header_style);
            col_x +|= 3;
        }
    }

    /// Render the day grid.
    fn renderDays(self: Calendar, x: u16, y: u16, width: u16, max_rows: u16, buf: *Buffer) void {
        if (max_rows == 0) return;

        const days_in_month = daysInMonth(self.year, self.month);
        const first_day_dow = dayOfWeek(self.year, self.month, 1);

        // Adjust first day based on first_day_of_week setting
        const adjusted_first_dow = if (self.first_day_of_week == 0)
            first_day_dow
        else
            (first_day_dow + 6) % 7;

        const start_x = if (self.show_week_numbers) x +| 3 else x;

        // Calculate previous month info for adjacent days
        const prev_month: u8 = if (self.month == 1) 12 else self.month - 1;
        const prev_year: i32 = if (self.month == 1) self.year - 1 else self.year;
        const prev_month_days = daysInMonth(prev_year, prev_month);

        var row: u16 = 0;
        var col: u8 = 0;
        var day: i16 = 1 - @as(i16, adjusted_first_dow);

        while (row < max_rows) : (row += 1) {
            // Render week number if enabled
            if (self.show_week_numbers) {
                const week_num = self.weekNumber(day, adjusted_first_dow, days_in_month);
                var week_buf: [3]u8 = undefined;
                const week_str = std.fmt.bufPrint(&week_buf, "{d:2}", .{week_num}) catch "  ";
                buf.setString(x, y +| row, week_str, self.adjacent_style);
            }

            col = 0;
            while (col < 7) : (col += 1) {
                const col_x = start_x +| @as(u16, col) * 3;
                if (col_x +| 2 > x +| width) break;

                if (day < 1) {
                    // Previous month's day
                    if (self.show_adjacent_months) {
                        const adj_day: u8 = @intCast(prev_month_days + @as(i16, @intCast(day)));
                        self.renderDay(col_x, y +| row, adj_day, true, false, false, buf);
                    }
                } else if (day > days_in_month) {
                    // Next month's day
                    if (self.show_adjacent_months) {
                        const adj_day: u8 = @intCast(day - @as(i16, days_in_month));
                        self.renderDay(col_x, y +| row, adj_day, true, false, false, buf);
                    }
                } else {
                    // Current month's day
                    const current_day: u8 = @intCast(day);
                    const is_today = self.isToday(current_day);
                    const is_selected = self.selected_day == current_day;
                    self.renderDay(col_x, y +| row, current_day, false, is_today, is_selected, buf);
                }

                day += 1;
            }

            // Stop if we've rendered all days and filled the first row of next month
            if (day > days_in_month + 7) break;
        }
    }

    /// Render a single day cell.
    fn renderDay(
        self: Calendar,
        x: u16,
        y: u16,
        day: u8,
        is_adjacent: bool,
        is_today: bool,
        is_selected: bool,
        buf: *Buffer,
    ) void {
        var day_buf: [3]u8 = undefined;
        const day_str = std.fmt.bufPrint(&day_buf, "{d:2}", .{day}) catch "  ";

        // Determine style based on day type
        var day_style = self.style;

        if (is_adjacent) {
            day_style = day_style.patch(self.adjacent_style);
        } else {
            // Check if day is marked
            for (self.marked_days) |marked| {
                if (marked == day) {
                    day_style = day_style.patch(self.marked_style);
                    break;
                }
            }

            if (is_today) {
                day_style = day_style.patch(self.today_style);
            }

            if (is_selected) {
                day_style = day_style.patch(self.selected_style);
            }
        }

        buf.setString(x, y, day_str, day_style);
    }

    /// Check if a day is today.
    fn isToday(self: Calendar, day: u8) bool {
        if (self.today) |t| {
            return t.year == self.year and t.month == self.month and t.day == day;
        }
        return false;
    }

    /// Calculate week of month (1-6) for a given day.
    fn weekNumber(_: Calendar, day: i16, _: u8, _: u8) u8 {
        if (day < 1) return 0;
        const d: u8 = @intCast(@min(day, 31));
        return (d - 1) / 7 + 1;
    }

    /// Get the inner content area (useful for composing with Block).
    pub fn inner(area: Rect) Rect {
        return area;
    }

    /// Navigate to the previous month.
    pub fn prevMonth(self: *Calendar) void {
        if (self.month == 1) {
            self.month = 12;
            self.year -= 1;
        } else {
            self.month -= 1;
        }
        // Clamp selected day to new month's range
        if (self.selected_day) |day| {
            const max_day = daysInMonth(self.year, self.month);
            if (day > max_day) {
                self.selected_day = max_day;
            }
        }
    }

    /// Navigate to the next month.
    pub fn nextMonth(self: *Calendar) void {
        if (self.month == 12) {
            self.month = 1;
            self.year += 1;
        } else {
            self.month += 1;
        }
        // Clamp selected day to new month's range
        if (self.selected_day) |day| {
            const max_day = daysInMonth(self.year, self.month);
            if (day > max_day) {
                self.selected_day = max_day;
            }
        }
    }

    /// Navigate to the previous day.
    pub fn prevDay(self: *Calendar) void {
        if (self.selected_day) |day| {
            if (day > 1) {
                self.selected_day = day - 1;
            } else {
                self.prevMonth();
                self.selected_day = daysInMonth(self.year, self.month);
            }
        } else {
            self.selected_day = 1;
        }
    }

    /// Navigate to the next day.
    pub fn nextDay(self: *Calendar) void {
        if (self.selected_day) |day| {
            const max_day = daysInMonth(self.year, self.month);
            if (day < max_day) {
                self.selected_day = day + 1;
            } else {
                self.nextMonth();
                self.selected_day = 1;
            }
        } else {
            self.selected_day = 1;
        }
    }

    /// Navigate to the previous week (same day of week).
    pub fn prevWeek(self: *Calendar) void {
        if (self.selected_day) |day| {
            if (day > 7) {
                self.selected_day = day - 7;
            } else {
                self.prevMonth();
                const max_day = daysInMonth(self.year, self.month);
                const new_day = @as(i16, max_day) - 7 + @as(i16, day);
                self.selected_day = if (new_day > 0) @intCast(new_day) else 1;
            }
        } else {
            self.selected_day = 1;
        }
    }

    /// Navigate to the next week (same day of week).
    pub fn nextWeek(self: *Calendar) void {
        if (self.selected_day) |day| {
            const max_day = daysInMonth(self.year, self.month);
            if (day + 7 <= max_day) {
                self.selected_day = day + 7;
            } else {
                self.nextMonth();
                const overflow = day + 7 - max_day;
                self.selected_day = @min(overflow, daysInMonth(self.year, self.month));
            }
        } else {
            self.selected_day = 1;
        }
    }

    /// Navigate to the first day of the month.
    pub fn firstDay(self: *Calendar) void {
        self.selected_day = 1;
    }

    /// Navigate to the last day of the month.
    pub fn lastDay(self: *Calendar) void {
        self.selected_day = daysInMonth(self.year, self.month);
    }
};

/// Returns the number of days in a given month.
pub fn daysInMonth(year: i32, month: u8) u8 {
    const days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month < 1 or month > 12) return 0;
    if (month == 2 and isLeapYear(year)) return 29;
    return days[month - 1];
}

/// Returns true if the given year is a leap year.
pub fn isLeapYear(year: i32) bool {
    if (@mod(year, 400) == 0) return true;
    if (@mod(year, 100) == 0) return false;
    if (@mod(year, 4) == 0) return true;
    return false;
}

/// Returns the day of week for a given date.
/// Uses Zeller's congruence (0=Sunday, 1=Monday, ..., 6=Saturday).
pub fn dayOfWeek(year: i32, month: u8, day: u8) u8 {
    // Adjust month and year for Zeller's formula (Jan/Feb are months 13/14 of prev year)
    var m: i32 = month;
    var y: i32 = year;
    if (m < 3) {
        m += 12;
        y -= 1;
    }

    const d: i32 = day;
    const k: i32 = @mod(y, 100);
    const j: i32 = @divFloor(y, 100);

    // Zeller's congruence for Gregorian calendar
    var h = d + @divFloor(13 * (m + 1), 5) + k + @divFloor(k, 4) + @divFloor(j, 4) - 2 * j;
    h = @mod(h, 7);

    // Convert from Zeller's output (0=Saturday) to 0=Sunday
    return @intCast(@mod(h + 6, 7));
}

// ============================================================
// SANITY TESTS - Basic Calendar functionality
// ============================================================

test "sanity: Calendar with default values" {
    const cal = Calendar{ .year = 2026, .month = 1 };
    try std.testing.expectEqual(@as(i32, 2026), cal.year);
    try std.testing.expectEqual(@as(u8, 1), cal.month);
    try std.testing.expect(cal.selected_day == null);
    try std.testing.expect(cal.show_adjacent_months);
    try std.testing.expect(!cal.show_week_numbers);
}

test "sanity: Calendar with selection" {
    const cal = Calendar{
        .year = 2026,
        .month = 2,
        .selected_day = 15,
    };
    try std.testing.expectEqual(@as(u8, 15), cal.selected_day.?);
}

test "sanity: Calendar with marked days" {
    const marked = [_]u8{ 5, 10, 15, 20 };
    const cal = Calendar{
        .year = 2026,
        .month = 3,
        .marked_days = &marked,
    };
    try std.testing.expectEqual(@as(usize, 4), cal.marked_days.len);
}

// ============================================================
// BEHAVIOR TESTS - Date calculations
// ============================================================

test "behavior: daysInMonth returns correct values" {
    try std.testing.expectEqual(@as(u8, 31), daysInMonth(2026, 1)); // January
    try std.testing.expectEqual(@as(u8, 28), daysInMonth(2026, 2)); // February (non-leap)
    try std.testing.expectEqual(@as(u8, 29), daysInMonth(2024, 2)); // February (leap)
    try std.testing.expectEqual(@as(u8, 30), daysInMonth(2026, 4)); // April
    try std.testing.expectEqual(@as(u8, 31), daysInMonth(2026, 12)); // December
}

test "behavior: daysInMonth handles invalid months" {
    try std.testing.expectEqual(@as(u8, 0), daysInMonth(2026, 0));
    try std.testing.expectEqual(@as(u8, 0), daysInMonth(2026, 13));
}

test "behavior: isLeapYear" {
    try std.testing.expect(!isLeapYear(2023));
    try std.testing.expect(isLeapYear(2024));
    try std.testing.expect(!isLeapYear(2025));
    try std.testing.expect(!isLeapYear(2026));
    try std.testing.expect(!isLeapYear(1900)); // divisible by 100 but not 400
    try std.testing.expect(isLeapYear(2000)); // divisible by 400
}

test "behavior: dayOfWeek returns correct day" {
    // 2026-01-01 is Thursday (4)
    try std.testing.expectEqual(@as(u8, 4), dayOfWeek(2026, 1, 1));

    // 2026-02-01 is Sunday (0)
    try std.testing.expectEqual(@as(u8, 0), dayOfWeek(2026, 2, 1));

    // Known dates for verification
    // 2024-01-01 is Monday (1)
    try std.testing.expectEqual(@as(u8, 1), dayOfWeek(2024, 1, 1));

    // 2000-01-01 was Saturday (6)
    try std.testing.expectEqual(@as(u8, 6), dayOfWeek(2000, 1, 1));
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: Calendar renders header" {
    var buf = try Buffer.init(std.testing.allocator, 22, 8);
    defer buf.deinit();

    const cal = Calendar{
        .year = 2026,
        .month = 1,
    };
    cal.render(Rect.init(0, 0, 22, 8), &buf);

    // Check that "January 2026" appears somewhere in the first row
    // The header should be centered
    var found_j = false;
    for (0..22) |x| {
        if (buf.get(@intCast(x), 0).char == 'J') {
            found_j = true;
            break;
        }
    }
    try std.testing.expect(found_j);
}

test "behavior: Calendar renders weekday names" {
    var buf = try Buffer.init(std.testing.allocator, 22, 8);
    defer buf.deinit();

    const cal = Calendar{
        .year = 2026,
        .month = 1,
    };
    cal.render(Rect.init(0, 0, 22, 8), &buf);

    // Check for "Su" in second row (weekday header)
    try std.testing.expectEqual(@as(u21, 'S'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, 'u'), buf.get(1, 1).char);
}

test "behavior: Calendar renders days" {
    var buf = try Buffer.init(std.testing.allocator, 22, 8);
    defer buf.deinit();

    const cal = Calendar{
        .year = 2026,
        .month = 1,
        .show_adjacent_months = false,
    };
    cal.render(Rect.init(0, 0, 22, 8), &buf);

    // January 2026 starts on Thursday
    // First row of days (row 2): should have day 1 on Thursday (position 4)
    // Position = (4 days offset) * 3 chars = 12
    // The number "1" should appear right-aligned in the cell
    var found_one = false;
    for (0..22) |x| {
        const cell = buf.get(@intCast(x), 2);
        if (cell.char == '1') {
            found_one = true;
            break;
        }
    }
    try std.testing.expect(found_one);
}

test "behavior: Calendar shows today styling" {
    var buf = try Buffer.init(std.testing.allocator, 22, 8);
    defer buf.deinit();

    const cal = Calendar{
        .year = 2026,
        .month = 2,
        .today = .{ .year = 2026, .month = 2, .day = 2 },
        .today_style = Style.init().bold(),
    };
    cal.render(Rect.init(0, 0, 22, 8), &buf);

    // February 2026 starts on Sunday, so day 2 is on Monday (col 1)
    // The "2" should have bold style
    // Find the "2" in row 2
    var found_bold_2 = false;
    for (0..22) |x| {
        const cell = buf.get(@intCast(x), 2);
        if (cell.char == '2' and cell.style.hasAttribute(.bold)) {
            found_bold_2 = true;
            break;
        }
    }
    try std.testing.expect(found_bold_2);
}

// ============================================================
// BEHAVIOR TESTS - Navigation
// ============================================================

test "behavior: Calendar.prevMonth navigates correctly" {
    var cal = Calendar{ .year = 2026, .month = 3 };
    cal.prevMonth();
    try std.testing.expectEqual(@as(u8, 2), cal.month);
    try std.testing.expectEqual(@as(i32, 2026), cal.year);

    cal.month = 1;
    cal.prevMonth();
    try std.testing.expectEqual(@as(u8, 12), cal.month);
    try std.testing.expectEqual(@as(i32, 2025), cal.year);
}

test "behavior: Calendar.nextMonth navigates correctly" {
    var cal = Calendar{ .year = 2026, .month = 11 };
    cal.nextMonth();
    try std.testing.expectEqual(@as(u8, 12), cal.month);
    try std.testing.expectEqual(@as(i32, 2026), cal.year);

    cal.nextMonth();
    try std.testing.expectEqual(@as(u8, 1), cal.month);
    try std.testing.expectEqual(@as(i32, 2027), cal.year);
}

test "behavior: Calendar.prevMonth clamps selected day" {
    var cal = Calendar{
        .year = 2026,
        .month = 3,
        .selected_day = 31,
    };
    cal.prevMonth(); // February has 28 days
    try std.testing.expectEqual(@as(u8, 28), cal.selected_day.?);
}

test "behavior: Calendar.prevDay wraps to previous month" {
    var cal = Calendar{
        .year = 2026,
        .month = 2,
        .selected_day = 1,
    };
    cal.prevDay();
    try std.testing.expectEqual(@as(u8, 1), cal.month);
    try std.testing.expectEqual(@as(u8, 31), cal.selected_day.?);
}

test "behavior: Calendar.nextDay wraps to next month" {
    var cal = Calendar{
        .year = 2026,
        .month = 1,
        .selected_day = 31,
    };
    cal.nextDay();
    try std.testing.expectEqual(@as(u8, 2), cal.month);
    try std.testing.expectEqual(@as(u8, 1), cal.selected_day.?);
}

test "behavior: Calendar.firstDay selects day 1" {
    var cal = Calendar{
        .year = 2026,
        .month = 5,
        .selected_day = 15,
    };
    cal.firstDay();
    try std.testing.expectEqual(@as(u8, 1), cal.selected_day.?);
}

test "behavior: Calendar.lastDay selects last day" {
    var cal = Calendar{
        .year = 2026,
        .month = 2,
        .selected_day = 1,
    };
    cal.lastDay();
    try std.testing.expectEqual(@as(u8, 28), cal.selected_day.?);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Calendar handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const cal = Calendar{ .year = 2026, .month = 1 };
    cal.render(Rect.init(0, 0, 0, 0), &buf);

    // Buffer should be unchanged
    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: Calendar handles 1x1 area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const cal = Calendar{ .year = 2026, .month = 1 };
    cal.render(Rect.init(0, 0, 1, 1), &buf);

    // Should render something (partial header) without crashing
}

test "regression: Calendar handles invalid month gracefully" {
    var buf = try Buffer.init(std.testing.allocator, 22, 8);
    defer buf.deinit();

    const cal = Calendar{ .year = 2026, .month = 0 };
    cal.render(Rect.init(0, 0, 22, 8), &buf);

    // Should return early without crashing
}

test "regression: Calendar handles leap year February" {
    var buf = try Buffer.init(std.testing.allocator, 22, 8);
    defer buf.deinit();

    const cal = Calendar{
        .year = 2024,
        .month = 2,
        .selected_day = 29,
    };
    cal.render(Rect.init(0, 0, 22, 8), &buf);

    // Should render day 29 for leap year February
}

test "regression: Calendar with week numbers" {
    var buf = try Buffer.init(std.testing.allocator, 25, 8);
    defer buf.deinit();

    const cal = Calendar{
        .year = 2026,
        .month = 1,
        .show_week_numbers = true,
    };
    cal.render(Rect.init(0, 0, 25, 8), &buf);

    // Should render week numbers in leftmost column (row 2+)
    // Week 1 should appear as "1" or " 1" in the first 2 cells of day rows
    // Search rows 2-7 for any digit in the first 2 columns
    var found_week = false;
    for (2..8) |row| {
        for (0..2) |x| {
            const cell = buf.get(@intCast(x), @intCast(row));
            if (cell.char >= '1' and cell.char <= '6') {
                found_week = true;
                break;
            }
        }
        if (found_week) break;
    }
    try std.testing.expect(found_week);
}

test "regression: Calendar Monday start" {
    var buf = try Buffer.init(std.testing.allocator, 22, 8);
    defer buf.deinit();

    const cal = Calendar{
        .year = 2026,
        .month = 1,
        .first_day_of_week = 1, // Monday
    };
    cal.render(Rect.init(0, 0, 22, 8), &buf);

    // Check for "Mo" as first weekday in second row
    try std.testing.expectEqual(@as(u21, 'M'), buf.get(0, 1).char);
    try std.testing.expectEqual(@as(u21, 'o'), buf.get(1, 1).char);
}
