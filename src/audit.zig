const std = @import("std");
const buffer_mod = @import("buffer.zig");
const cell_mod = @import("cell.zig");
const geometry_mod = @import("geometry.zig");
const style_mod = @import("style.zig");
const color_mod = @import("color.zig");
const testing_mod = @import("testing.zig");

const Buffer = buffer_mod.Buffer;
const Cell = cell_mod.Cell;
const Rect = geometry_mod.Rect;
const Style = style_mod.Style;
const Color = style_mod.Color;
const ColorTriplet = color_mod.ColorTriplet;

pub const Severity = enum {
    pass,
    warn,
    fail,
};

pub const AuditCategory = enum {
    contrast,
    keyboard_navigation,
    focus_visibility,
    mouse_targets,
};

pub const Finding = struct {
    severity: Severity,
    region: Rect,
    message: []const u8,
    details: ?[]const u8,
};

pub const AuditResult = struct {
    category: AuditCategory,
    findings: []Finding,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *AuditResult) void {
        for (self.findings) |finding| {
            self.allocator.free(finding.message);
            if (finding.details) |d| {
                self.allocator.free(d);
            }
        }
        self.allocator.free(self.findings);
        self.* = undefined;
    }

    pub fn failCount(self: AuditResult) usize {
        var count: usize = 0;
        for (self.findings) |f| {
            if (f.severity == .fail) count += 1;
        }
        return count;
    }

    pub fn warnCount(self: AuditResult) usize {
        var count: usize = 0;
        for (self.findings) |f| {
            if (f.severity == .warn) count += 1;
        }
        return count;
    }

    pub fn passCount(self: AuditResult) usize {
        var count: usize = 0;
        for (self.findings) |f| {
            if (f.severity == .pass) count += 1;
        }
        return count;
    }

    pub fn passRate(self: AuditResult) f32 {
        const total = self.findings.len;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.passCount())) / @as(f32, @floatFromInt(total));
    }
};

pub const AuditReport = struct {
    results: std.ArrayListUnmanaged(AuditResult),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AuditReport {
        return .{
            .results = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AuditReport) void {
        for (self.results.items) |*r| {
            r.deinit();
        }
        self.results.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addResult(self: *AuditReport, result: AuditResult) !void {
        try self.results.append(self.allocator, result);
    }

    pub fn totalFindings(self: AuditReport) usize {
        var total: usize = 0;
        for (self.results.items) |r| {
            total += r.findings.len;
        }
        return total;
    }

    pub fn overallPassRate(self: AuditReport) f32 {
        var total_findings: usize = 0;
        var total_passes: usize = 0;
        for (self.results.items) |r| {
            total_findings += r.findings.len;
            total_passes += r.passCount();
        }
        if (total_findings == 0) return 0.0;
        return @as(f32, @floatFromInt(total_passes)) / @as(f32, @floatFromInt(total_findings));
    }

    pub fn summary(self: AuditReport, allocator: std.mem.Allocator) ![]const u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);
        var writer = buf.writer(allocator);

        try writer.print("Audit Report: {d} categories, {d} findings\n", .{
            self.results.items.len,
            self.totalFindings(),
        });
        try writer.print("Overall pass rate: {d:.1}%\n", .{self.overallPassRate() * 100.0});

        for (self.results.items) |r| {
            try writer.print("  [{s}] {d} findings ({d} pass, {d} warn, {d} fail)\n", .{
                @tagName(r.category),
                r.findings.len,
                r.passCount(),
                r.warnCount(),
                r.failCount(),
            });
        }

        return buf.toOwnedSlice(allocator);
    }
};

pub fn auditContrast(allocator: std.mem.Allocator, buf: *const Buffer) !AuditResult {
    var findings: std.ArrayListUnmanaged(Finding) = .{};
    errdefer {
        for (findings.items) |f| {
            allocator.free(f.message);
            if (f.details) |d| allocator.free(d);
        }
        findings.deinit(allocator);
    }

    var y: u16 = 0;
    while (y < buf.height) : (y += 1) {
        var x: u16 = 0;
        while (x < buf.width) {
            const cell = buf.get(x, y);
            const fg_color = cell.style.getForeground() orelse {
                x += 1;
                continue;
            };
            const bg_color = cell.style.getBackground() orelse {
                x += 1;
                continue;
            };

            if (fg_color.color_type == .default or bg_color.color_type == .default) {
                x += 1;
                continue;
            }

            const fg_triplet = fg_color.getTriplet() orelse {
                x += 1;
                continue;
            };
            const bg_triplet = bg_color.getTriplet() orelse {
                x += 1;
                continue;
            };

            const start_x = x;
            x += 1;
            while (x < buf.width) {
                const next_cell = buf.get(x, y);
                const next_fg = next_cell.style.getForeground() orelse break;
                const next_bg = next_cell.style.getBackground() orelse break;
                if (next_fg.color_type == .default or next_bg.color_type == .default) break;
                const next_fg_tri = next_fg.getTriplet() orelse break;
                const next_bg_tri = next_bg.getTriplet() orelse break;
                if (!next_fg_tri.eql(fg_triplet) or !next_bg_tri.eql(bg_triplet)) break;
                x += 1;
            }

            const region = Rect.init(start_x, y, x - start_x, 1);
            const ratio = fg_triplet.contrastRatio(bg_triplet);
            const level = fg_triplet.wcagLevel(bg_triplet);

            const severity: Severity = switch (level) {
                .fail, .aa_large => .fail,
                .aa => .warn,
                .aaa => .pass,
            };

            const message = try std.fmt.allocPrint(allocator, "Contrast ratio {d:.1}:1 ({s})", .{
                ratio,
                @tagName(level),
            });
            errdefer allocator.free(message);

            const details = try std.fmt.allocPrint(allocator, "fg=({d},{d},{d}) bg=({d},{d},{d})", .{
                fg_triplet.r, fg_triplet.g, fg_triplet.b,
                bg_triplet.r, bg_triplet.g, bg_triplet.b,
            });
            errdefer allocator.free(details);

            try findings.append(allocator, .{
                .severity = severity,
                .region = region,
                .message = message,
                .details = details,
            });
        }
    }

    return AuditResult{
        .category = .contrast,
        .findings = try findings.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

pub const KeyboardAuditConfig = struct {
    max_tabs: u16 = 20,
};

pub fn auditKeyboardNav(
    comptime State: type,
    allocator: std.mem.Allocator,
    harness: *testing_mod.TestHarness(State),
    config: KeyboardAuditConfig,
) !AuditResult {
    var findings: std.ArrayListUnmanaged(Finding) = .{};
    errdefer {
        for (findings.items) |f| {
            allocator.free(f.message);
            if (f.details) |d| allocator.free(d);
        }
        findings.deinit(allocator);
    }

    const saved_state = harness.state.*;

    const initial_cells = try allocator.alloc(Cell, harness.current_buf.cells.len);
    defer allocator.free(initial_cells);
    @memcpy(initial_cells, harness.current_buf.cells);

    const prev_cells = try allocator.alloc(Cell, harness.current_buf.cells.len);
    defer allocator.free(prev_cells);
    @memcpy(prev_cells, harness.current_buf.cells);

    var tab_stops: usize = 0;
    var cycle_complete = false;

    var tab_i: u16 = 0;
    while (tab_i < config.max_tabs) : (tab_i += 1) {
        harness.pressSpecial(.tab);

        const changed_rect = diffBoundingRect(
            harness.current_buf,
            prev_cells,
            harness.current_buf.width,
            harness.current_buf.height,
        );

        if (changed_rect) |rect| {
            tab_stops += 1;

            const message = try std.fmt.allocPrint(allocator, "Tab stop {d}: region changed", .{tab_stops});
            try findings.append(allocator, .{
                .severity = .pass,
                .region = rect,
                .message = message,
                .details = null,
            });
        }

        if (std.mem.eql(Cell, harness.current_buf.cells, initial_cells)) {
            cycle_complete = true;
            break;
        }

        @memcpy(prev_cells, harness.current_buf.cells);
    }

    if (tab_stops == 0) {
        const message = try allocator.dupe(u8, "No tab stops detected - keyboard navigation may be missing");
        try findings.append(allocator, .{
            .severity = .fail,
            .region = Rect.init(0, 0, harness.current_buf.width, harness.current_buf.height),
            .message = message,
            .details = null,
        });
    } else if (!cycle_complete) {
        const message = try std.fmt.allocPrint(
            allocator,
            "Found {d} tab stops but focus did not cycle back to start",
            .{tab_stops},
        );
        try findings.append(allocator, .{
            .severity = .warn,
            .region = Rect.init(0, 0, harness.current_buf.width, harness.current_buf.height),
            .message = message,
            .details = null,
        });
    }

    harness.state.* = saved_state;
    @memcpy(harness.current_buf.cells, initial_cells);
    @memcpy(harness.previous_buf.cells, initial_cells);

    return AuditResult{
        .category = .keyboard_navigation,
        .findings = try findings.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

pub fn auditFocusVisibility(
    comptime State: type,
    allocator: std.mem.Allocator,
    harness: *testing_mod.TestHarness(State),
    config: KeyboardAuditConfig,
) !AuditResult {
    var findings: std.ArrayListUnmanaged(Finding) = .{};
    errdefer {
        for (findings.items) |f| {
            allocator.free(f.message);
            if (f.details) |d| allocator.free(d);
        }
        findings.deinit(allocator);
    }

    const saved_state = harness.state.*;

    const initial_cells = try allocator.alloc(Cell, harness.current_buf.cells.len);
    defer allocator.free(initial_cells);
    @memcpy(initial_cells, harness.current_buf.cells);

    const prev_cells = try allocator.alloc(Cell, harness.current_buf.cells.len);
    defer allocator.free(prev_cells);
    @memcpy(prev_cells, harness.current_buf.cells);

    var tab_i: u16 = 0;
    var stop_num: usize = 0;

    while (tab_i < config.max_tabs) : (tab_i += 1) {
        harness.pressSpecial(.tab);

        const changed_rect = diffBoundingRect(
            harness.current_buf,
            prev_cells,
            harness.current_buf.width,
            harness.current_buf.height,
        );

        if (changed_rect) |rect| {
            stop_num += 1;

            const has_style_change = detectStyleChange(
                harness.current_buf,
                prev_cells,
                harness.current_buf.width,
                rect,
            );

            if (has_style_change) {
                const message = try std.fmt.allocPrint(
                    allocator,
                    "Focus stop {d}: visible style change detected",
                    .{stop_num},
                );
                try findings.append(allocator, .{
                    .severity = .pass,
                    .region = rect,
                    .message = message,
                    .details = null,
                });
            } else {
                const message = try std.fmt.allocPrint(
                    allocator,
                    "Focus stop {d}: no style change - focus indicator not visible",
                    .{stop_num},
                );
                try findings.append(allocator, .{
                    .severity = .fail,
                    .region = rect,
                    .message = message,
                    .details = null,
                });
            }
        }

        if (std.mem.eql(Cell, harness.current_buf.cells, initial_cells)) break;

        @memcpy(prev_cells, harness.current_buf.cells);
    }

    if (stop_num == 0) {
        const message = try allocator.dupe(u8, "No focus stops detected");
        try findings.append(allocator, .{
            .severity = .fail,
            .region = Rect.init(0, 0, harness.current_buf.width, harness.current_buf.height),
            .message = message,
            .details = null,
        });
    }

    harness.state.* = saved_state;
    @memcpy(harness.current_buf.cells, initial_cells);
    @memcpy(harness.previous_buf.cells, initial_cells);

    return AuditResult{
        .category = .focus_visibility,
        .findings = try findings.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn diffBoundingRect(
    buf: Buffer,
    prev_cells: []const Cell,
    width: u16,
    height: u16,
) ?Rect {
    var min_x: u16 = width;
    var min_y: u16 = height;
    var max_x: u16 = 0;
    var max_y: u16 = 0;
    var any_diff = false;

    var y: u16 = 0;
    while (y < height) : (y += 1) {
        var x: u16 = 0;
        while (x < width) : (x += 1) {
            const idx = @as(usize, y) * @as(usize, width) + @as(usize, x);
            const cur = buf.cells[idx];
            const prev = prev_cells[idx];
            if (!cur.eql(prev)) {
                any_diff = true;
                if (x < min_x) min_x = x;
                if (y < min_y) min_y = y;
                if (x + 1 > max_x) max_x = x + 1;
                if (y + 1 > max_y) max_y = y + 1;
            }
        }
    }

    if (!any_diff) return null;
    return Rect.init(min_x, min_y, max_x - min_x, max_y - min_y);
}

fn detectStyleChange(
    buf: Buffer,
    prev_cells: []const Cell,
    width: u16,
    rect: Rect,
) bool {
    const end_x = @min(rect.x + rect.width, width);
    const end_y = @min(rect.y + rect.height, buf.height);

    var y = rect.y;
    while (y < end_y) : (y += 1) {
        var x = rect.x;
        while (x < end_x) : (x += 1) {
            const idx = @as(usize, y) * @as(usize, width) + @as(usize, x);
            const cur = buf.cells[idx];
            const prev = prev_cells[idx];
            if (!cur.style.eql(prev.style)) return true;
        }
    }
    return false;
}

test "sanity: AuditResult init and deinit with no findings" {
    var result = AuditResult{
        .category = .contrast,
        .findings = try std.testing.allocator.alloc(Finding, 0),
        .allocator = std.testing.allocator,
    };
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.failCount());
    try std.testing.expectEqual(@as(usize, 0), result.warnCount());
    try std.testing.expectEqual(@as(usize, 0), result.passCount());
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result.passRate(), 0.001);
}

test "sanity: AuditReport init and deinit" {
    var report = AuditReport.init(std.testing.allocator);
    defer report.deinit();

    try std.testing.expectEqual(@as(usize, 0), report.totalFindings());
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), report.overallPassRate(), 0.001);
}

test "sanity: AuditReport summary with no results" {
    var report = AuditReport.init(std.testing.allocator);
    defer report.deinit();

    const text = try report.summary(std.testing.allocator);
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "0 categories") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "0 findings") != null);
}

test "behavior: AuditResult counts findings by severity" {
    const alloc = std.testing.allocator;
    var findings_list: std.ArrayListUnmanaged(Finding) = .{};
    defer findings_list.deinit(alloc);

    const msg_pass = try alloc.dupe(u8, "pass finding");
    errdefer alloc.free(msg_pass);
    const msg_warn = try alloc.dupe(u8, "warn finding");
    errdefer alloc.free(msg_warn);
    const msg_fail = try alloc.dupe(u8, "fail finding");
    errdefer alloc.free(msg_fail);

    try findings_list.append(alloc, .{
        .severity = .pass,
        .region = Rect.init(0, 0, 5, 1),
        .message = msg_pass,
        .details = null,
    });
    try findings_list.append(alloc, .{
        .severity = .warn,
        .region = Rect.init(5, 0, 5, 1),
        .message = msg_warn,
        .details = null,
    });
    try findings_list.append(alloc, .{
        .severity = .fail,
        .region = Rect.init(10, 0, 5, 1),
        .message = msg_fail,
        .details = null,
    });

    var result = AuditResult{
        .category = .contrast,
        .findings = try findings_list.toOwnedSlice(alloc),
        .allocator = alloc,
    };
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.passCount());
    try std.testing.expectEqual(@as(usize, 1), result.warnCount());
    try std.testing.expectEqual(@as(usize, 1), result.failCount());
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 3.0), result.passRate(), 0.001);
}

test "behavior: AuditReport aggregates multiple results" {
    const alloc = std.testing.allocator;
    var report = AuditReport.init(alloc);
    defer report.deinit();

    const msg1 = try alloc.dupe(u8, "good contrast");
    var findings1: [1]Finding = .{.{
        .severity = .pass,
        .region = Rect.init(0, 0, 10, 1),
        .message = msg1,
        .details = null,
    }};
    const owned1 = try alloc.dupe(Finding, &findings1);
    try report.addResult(.{
        .category = .contrast,
        .findings = owned1,
        .allocator = alloc,
    });

    const msg2 = try alloc.dupe(u8, "no tab stops");
    var findings2: [1]Finding = .{.{
        .severity = .fail,
        .region = Rect.init(0, 0, 80, 24),
        .message = msg2,
        .details = null,
    }};
    const owned2 = try alloc.dupe(Finding, &findings2);
    try report.addResult(.{
        .category = .keyboard_navigation,
        .findings = owned2,
        .allocator = alloc,
    });

    try std.testing.expectEqual(@as(usize, 2), report.totalFindings());
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), report.overallPassRate(), 0.001);

    const text = try report.summary(alloc);
    defer alloc.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "2 categories") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "2 findings") != null);
}

test "behavior: auditContrast on empty buffer returns no findings" {
    const alloc = std.testing.allocator;
    var buf = try Buffer.init(alloc, 20, 5);
    defer buf.deinit();

    var result = try auditContrast(alloc, &buf);
    defer result.deinit();

    try std.testing.expectEqual(AuditCategory.contrast, result.category);
    try std.testing.expectEqual(@as(usize, 0), result.findings.len);
}

test "behavior: auditContrast detects bad contrast" {
    const alloc = std.testing.allocator;
    var buf = try Buffer.init(alloc, 20, 5);
    defer buf.deinit();

    const low_contrast_style = Style.init()
        .fg(Color.fromRgb(30, 30, 30))
        .bg(Color.fromRgb(0, 0, 0));
    buf.setString(0, 0, "Hard to read", low_contrast_style);

    var result = try auditContrast(alloc, &buf);
    defer result.deinit();

    try std.testing.expect(result.findings.len > 0);
    try std.testing.expect(result.failCount() > 0);
}

test "behavior: auditContrast passes good contrast" {
    const alloc = std.testing.allocator;
    var buf = try Buffer.init(alloc, 20, 5);
    defer buf.deinit();

    const high_contrast_style = Style.init()
        .fg(Color.fromRgb(0, 0, 0))
        .bg(Color.fromRgb(255, 255, 255));
    buf.setString(0, 0, "Easy to read", high_contrast_style);

    var result = try auditContrast(alloc, &buf);
    defer result.deinit();

    try std.testing.expect(result.findings.len > 0);
    try std.testing.expectEqual(@as(usize, 0), result.failCount());
    try std.testing.expect(result.passCount() > 0);
}

test "behavior: auditContrast warns on AA but not AAA" {
    const alloc = std.testing.allocator;
    var buf = try Buffer.init(alloc, 20, 5);
    defer buf.deinit();

    const aa_style = Style.init()
        .fg(Color.fromRgb(118, 118, 118))
        .bg(Color.fromRgb(0, 0, 0));
    buf.setString(0, 0, "Medium", aa_style);

    var result = try auditContrast(alloc, &buf);
    defer result.deinit();

    try std.testing.expect(result.findings.len > 0);
    try std.testing.expect(result.warnCount() > 0);
    try std.testing.expectEqual(@as(usize, 0), result.failCount());
}

test "behavior: auditContrast groups contiguous same-style cells" {
    const alloc = std.testing.allocator;
    var buf = try Buffer.init(alloc, 20, 1);
    defer buf.deinit();

    const style1 = Style.init()
        .fg(Color.fromRgb(0, 0, 0))
        .bg(Color.fromRgb(255, 255, 255));
    const style2 = Style.init()
        .fg(Color.fromRgb(255, 0, 0))
        .bg(Color.fromRgb(255, 255, 255));

    buf.setString(0, 0, "AAAA", style1);
    buf.setString(4, 0, "BBBB", style2);

    var result = try auditContrast(alloc, &buf);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.findings.len);
    try std.testing.expectEqual(@as(u16, 0), result.findings[0].region.x);
    try std.testing.expectEqual(@as(u16, 4), result.findings[0].region.width);
    try std.testing.expectEqual(@as(u16, 4), result.findings[1].region.x);
    try std.testing.expectEqual(@as(u16, 4), result.findings[1].region.width);
}

const TestHarness = testing_mod.TestHarness;
const Event = @import("event.zig").Event;
const Action = @import("action.zig").Action;

const TestFrame = @import("frame.zig").Frame(64);

const FocusTestState = struct {
    focus: u8 = 0,
    num_items: u8 = 3,
};

fn focusTestUpdate(state: *FocusTestState, ev: Event) Action {
    switch (ev) {
        .key => |key| {
            switch (key.code) {
                .tab => {
                    state.focus = (state.focus + 1) % state.num_items;
                },
                .char => |c| {
                    if (c == 'q') return .{ .quit = {} };
                },
                else => {},
            }
        },
        else => {},
    }
    return .{ .none = {} };
}

fn focusTestView(state: *FocusTestState, frame: *TestFrame) void {
    const normal = Style.init().fg(Color.fromRgb(200, 200, 200));
    const focused = Style.init().fg(Color.fromRgb(255, 255, 0)).bold();

    const items = [_][]const u8{ "Item A", "Item B", "Item C" };
    for (items, 0..) |item, i| {
        const s = if (i == state.focus) focused else normal;
        frame.buffer.setString(0, @intCast(i), item, s);
    }
}

test "behavior: auditKeyboardNav detects tab stops" {
    const alloc = std.testing.allocator;
    var state = FocusTestState{};
    var harness = try TestHarness(FocusTestState).init(alloc, .{
        .state = &state,
        .update = focusTestUpdate,
        .view = focusTestView,
        .width = 20,
        .height = 5,
    });
    defer harness.deinit();

    var result = try auditKeyboardNav(FocusTestState, alloc, &harness, .{});
    defer result.deinit();

    try std.testing.expectEqual(AuditCategory.keyboard_navigation, result.category);
    try std.testing.expect(result.passCount() > 0);
}

test "behavior: auditFocusVisibility detects style changes" {
    const alloc = std.testing.allocator;
    var state = FocusTestState{};
    var harness = try TestHarness(FocusTestState).init(alloc, .{
        .state = &state,
        .update = focusTestUpdate,
        .view = focusTestView,
        .width = 20,
        .height = 5,
    });
    defer harness.deinit();

    var result = try auditFocusVisibility(FocusTestState, alloc, &harness, .{});
    defer result.deinit();

    try std.testing.expectEqual(AuditCategory.focus_visibility, result.category);
    try std.testing.expect(result.passCount() > 0);
    try std.testing.expectEqual(@as(usize, 0), result.failCount());
}

const NoTabState = struct {
    value: u8 = 0,
};

fn noTabUpdate(state: *NoTabState, ev: Event) Action {
    _ = state;
    _ = ev;
    return .{ .none = {} };
}

fn noTabView(state: *NoTabState, frame: *TestFrame) void {
    _ = state;
    frame.buffer.setString(0, 0, "Static content", Style.empty);
}

test "behavior: auditKeyboardNav fails when no tab stops" {
    const alloc = std.testing.allocator;
    var state = NoTabState{};
    var harness = try TestHarness(NoTabState).init(alloc, .{
        .state = &state,
        .update = noTabUpdate,
        .view = noTabView,
        .width = 20,
        .height = 5,
    });
    defer harness.deinit();

    var result = try auditKeyboardNav(NoTabState, alloc, &harness, .{});
    defer result.deinit();

    try std.testing.expect(result.failCount() > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.findings[0].message, "No tab stops") != null);
}

test "behavior: auditFocusVisibility fails when no focus stops" {
    const alloc = std.testing.allocator;
    var state = NoTabState{};
    var harness = try TestHarness(NoTabState).init(alloc, .{
        .state = &state,
        .update = noTabUpdate,
        .view = noTabView,
        .width = 20,
        .height = 5,
    });
    defer harness.deinit();

    var result = try auditFocusVisibility(NoTabState, alloc, &harness, .{});
    defer result.deinit();

    try std.testing.expect(result.failCount() > 0);
}

test "regression: empty buffer contrast audit returns zero findings" {
    const alloc = std.testing.allocator;
    var buf = try Buffer.init(alloc, 0, 0);
    defer buf.deinit();

    var result = try auditContrast(alloc, &buf);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.findings.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result.passRate(), 0.001);
}

test "regression: AuditResult passRate with all passes" {
    const alloc = std.testing.allocator;
    const msg = try alloc.dupe(u8, "all good");
    var findings: [1]Finding = .{.{
        .severity = .pass,
        .region = Rect.init(0, 0, 1, 1),
        .message = msg,
        .details = null,
    }};
    var result = AuditResult{
        .category = .contrast,
        .findings = try alloc.dupe(Finding, &findings),
        .allocator = alloc,
    };
    defer result.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result.passRate(), 0.001);
}

test "regression: AuditReport summary includes category names" {
    const alloc = std.testing.allocator;
    var report = AuditReport.init(alloc);
    defer report.deinit();

    const msg = try alloc.dupe(u8, "test finding");
    var findings: [1]Finding = .{.{
        .severity = .pass,
        .region = Rect.init(0, 0, 1, 1),
        .message = msg,
        .details = null,
    }};
    try report.addResult(.{
        .category = .contrast,
        .findings = try alloc.dupe(Finding, &findings),
        .allocator = alloc,
    });

    const text = try report.summary(alloc);
    defer alloc.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "contrast") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "1 findings") != null);
}

test "behavior: auditKeyboardNav restores harness state" {
    const alloc = std.testing.allocator;
    var state = FocusTestState{};
    var harness = try TestHarness(FocusTestState).init(alloc, .{
        .state = &state,
        .update = focusTestUpdate,
        .view = focusTestView,
        .width = 20,
        .height = 5,
    });
    defer harness.deinit();

    const initial_focus = state.focus;
    const initial_cells = try alloc.alloc(Cell, harness.current_buf.cells.len);
    defer alloc.free(initial_cells);
    @memcpy(initial_cells, harness.current_buf.cells);

    var result = try auditKeyboardNav(FocusTestState, alloc, &harness, .{});
    defer result.deinit();

    try std.testing.expectEqual(initial_focus, state.focus);
    try std.testing.expect(std.mem.eql(Cell, harness.current_buf.cells, initial_cells));
    try std.testing.expect(std.mem.eql(Cell, harness.previous_buf.cells, initial_cells));
}

test "behavior: auditFocusVisibility restores harness state" {
    const alloc = std.testing.allocator;
    var state = FocusTestState{};
    var harness = try TestHarness(FocusTestState).init(alloc, .{
        .state = &state,
        .update = focusTestUpdate,
        .view = focusTestView,
        .width = 20,
        .height = 5,
    });
    defer harness.deinit();

    const initial_focus = state.focus;
    const initial_cells = try alloc.alloc(Cell, harness.current_buf.cells.len);
    defer alloc.free(initial_cells);
    @memcpy(initial_cells, harness.current_buf.cells);

    var result = try auditFocusVisibility(FocusTestState, alloc, &harness, .{});
    defer result.deinit();

    try std.testing.expectEqual(initial_focus, state.focus);
    try std.testing.expect(std.mem.eql(Cell, harness.current_buf.cells, initial_cells));
    try std.testing.expect(std.mem.eql(Cell, harness.previous_buf.cells, initial_cells));
}

test "regression: Finding details field is optional" {
    const alloc = std.testing.allocator;
    const msg = try alloc.dupe(u8, "no details");
    const details = try alloc.dupe(u8, "some details");

    var findings_list: std.ArrayListUnmanaged(Finding) = .{};
    try findings_list.append(alloc, .{
        .severity = .pass,
        .region = Rect.init(0, 0, 1, 1),
        .message = msg,
        .details = null,
    });
    try findings_list.append(alloc, .{
        .severity = .warn,
        .region = Rect.init(1, 0, 1, 1),
        .message = try alloc.dupe(u8, "with details"),
        .details = details,
    });

    var result = AuditResult{
        .category = .contrast,
        .findings = try findings_list.toOwnedSlice(alloc),
        .allocator = alloc,
    };
    defer result.deinit();

    try std.testing.expect(result.findings[0].details == null);
    try std.testing.expect(result.findings[1].details != null);
}
