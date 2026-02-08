const std = @import("std");
const testing_mod = @import("testing.zig");
const event_mod = @import("event.zig");
const action_mod = @import("action.zig");
const style_mod = @import("style.zig");

const TestHarness = testing_mod.TestHarness;
const Event = event_mod.Event;
const Key = event_mod.Key;
const KeyCode = event_mod.KeyCode;
const Modifiers = event_mod.Modifiers;
const MouseKind = event_mod.MouseKind;
const Action = action_mod.Action;
const Style = style_mod.Style;
const StyleAttribute = style_mod.StyleAttribute;

pub const Directive = union(enum) {
    size: struct { width: u16, height: u16 },
    key: u21,
    key_special: KeyCode,
    key_with_mods: struct { code: KeyCode, mods: Modifiers },
    type_text: []const u8,
    click: struct { x: u16, y: u16 },
    right_click: struct { x: u16, y: u16 },
    mouse_down: struct { x: u16, y: u16 },
    mouse_up: struct { x: u16, y: u16 },
    hover: struct { x: u16, y: u16 },
    drag: struct { x1: u16, y1: u16, x2: u16, y2: u16 },
    scroll_up: struct { x: u16, y: u16 },
    scroll_down: struct { x: u16, y: u16 },
    tick: void,
    tick_n: u32,
    expect_string: struct { x: u16, y: u16, text: []const u8 },
    expect_cell: struct { x: u16, y: u16, char: u21 },
    expect_empty: struct { x: u16, y: u16 },
    expect_style: struct { x: u16, y: u16, attr: BoundStyleAttr },
    expect_action: ActionKind,
    expect_quit: void,
    snapshot: []const u8,
    repeat: u32,
};

pub const ActionKind = enum { none, quit };

pub const BoundStyleAttr = enum {
    bold,
    italic,
    underline,
    dim,
    blink,
    reverse,
    strikethrough,
    overline,

    pub fn toStyleAttribute(self: BoundStyleAttr) StyleAttribute {
        return switch (self) {
            .bold => .bold,
            .italic => .italic,
            .underline => .underline,
            .dim => .dim,
            .blink => .blink,
            .reverse => .reverse,
            .strikethrough => .strike,
            .overline => .overline,
        };
    }
};

pub const ParseError = error{
    UnknownDirective,
    MissingArgument,
    InvalidInteger,
    InvalidKeyName,
    InvalidModifier,
    InvalidStyleAttribute,
    InvalidActionKind,
    UnterminatedString,
    InvalidEscapeSequence,
    EmptyScenario,
    OutOfMemory,
};

pub const ScenarioParser = struct {
    pub fn parse(allocator: std.mem.Allocator, text: []const u8) ParseError![]Directive {
        var directives: std.ArrayListUnmanaged(Directive) = .{};
        errdefer {
            freeDirectives(allocator, directives.items);
            directives.deinit(allocator);
        }

        var line_iter = std.mem.splitScalar(u8, text, '\n');
        while (line_iter.next()) |raw_line| {
            const line = std.mem.trimRight(u8, raw_line, " \t\r");
            if (parseLine(allocator, line)) |maybe_directive| {
                if (maybe_directive) |directive| {
                    directives.append(allocator, directive) catch return ParseError.OutOfMemory;
                }
            } else |err| {
                return err;
            }
        }

        return directives.toOwnedSlice(allocator) catch return ParseError.OutOfMemory;
    }

    pub fn freeDirectives(allocator: std.mem.Allocator, directives: []const Directive) void {
        for (directives) |d| {
            switch (d) {
                .type_text => |t| allocator.free(t),
                .expect_string => |es| allocator.free(es.text),
                else => {},
            }
        }
    }

    pub fn parseLine(allocator: std.mem.Allocator, line: []const u8) ParseError!?Directive {
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (trimmed.len == 0) return null;
        if (trimmed[0] == '#') return null;

        var tokens = TokenIterator.init(trimmed);
        const command = tokens.next() orelse return null;

        if (std.mem.eql(u8, command, "size")) {
            const w_str = tokens.next() orelse return ParseError.MissingArgument;
            const h_str = tokens.next() orelse return ParseError.MissingArgument;
            const w = parseU16(w_str) orelse return ParseError.InvalidInteger;
            const h = parseU16(h_str) orelse return ParseError.InvalidInteger;
            return Directive{ .size = .{ .width = w, .height = h } };
        }

        if (std.mem.eql(u8, command, "key")) {
            const arg = tokens.next() orelse return ParseError.MissingArgument;
            return @as(?Directive, try parseKeyDirective(arg));
        }

        if (std.mem.eql(u8, command, "type")) {
            const rest = tokens.rest();
            const text = try parseQuotedString(allocator, rest) orelse return ParseError.UnterminatedString;
            return Directive{ .type_text = text };
        }

        if (std.mem.eql(u8, command, "click")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            return Directive{ .click = .{ .x = x, .y = y } };
        }

        if (std.mem.eql(u8, command, "right_click")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            return Directive{ .right_click = .{ .x = x, .y = y } };
        }

        if (std.mem.eql(u8, command, "mouse_down")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            return Directive{ .mouse_down = .{ .x = x, .y = y } };
        }

        if (std.mem.eql(u8, command, "mouse_up")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            return Directive{ .mouse_up = .{ .x = x, .y = y } };
        }

        if (std.mem.eql(u8, command, "hover")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            return Directive{ .hover = .{ .x = x, .y = y } };
        }

        if (std.mem.eql(u8, command, "drag")) {
            const x1 = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y1 = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const x2 = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y2 = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            return Directive{ .drag = .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2 } };
        }

        if (std.mem.eql(u8, command, "scroll_up")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            return Directive{ .scroll_up = .{ .x = x, .y = y } };
        }

        if (std.mem.eql(u8, command, "scroll_down")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            return Directive{ .scroll_down = .{ .x = x, .y = y } };
        }

        if (std.mem.eql(u8, command, "tick")) {
            if (tokens.next()) |n_str| {
                const n = parseU32(n_str) orelse return ParseError.InvalidInteger;
                return Directive{ .tick_n = n };
            }
            return Directive{ .tick = {} };
        }

        if (std.mem.eql(u8, command, "expect_string")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const rest = tokens.rest();
            const text = try parseQuotedString(allocator, rest) orelse return ParseError.UnterminatedString;
            return Directive{ .expect_string = .{ .x = x, .y = y, .text = text } };
        }

        if (std.mem.eql(u8, command, "expect_cell")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const char_str = tokens.next() orelse return ParseError.MissingArgument;
            if (char_str.len == 0) return ParseError.MissingArgument;
            const char = std.unicode.utf8Decode(char_str[0..@min(char_str.len, 4)]) catch return ParseError.InvalidKeyName;
            return Directive{ .expect_cell = .{ .x = x, .y = y, .char = char } };
        }

        if (std.mem.eql(u8, command, "expect_empty")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            return Directive{ .expect_empty = .{ .x = x, .y = y } };
        }

        if (std.mem.eql(u8, command, "expect_style")) {
            const x = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const y = parseU16(tokens.next() orelse return ParseError.MissingArgument) orelse return ParseError.InvalidInteger;
            const attr_str = tokens.next() orelse return ParseError.MissingArgument;
            const attr = parseStyleAttr(attr_str) orelse return ParseError.InvalidStyleAttribute;
            return Directive{ .expect_style = .{ .x = x, .y = y, .attr = attr } };
        }

        if (std.mem.eql(u8, command, "expect_action")) {
            const kind_str = tokens.next() orelse return ParseError.MissingArgument;
            if (std.mem.eql(u8, kind_str, "none")) return Directive{ .expect_action = .none };
            if (std.mem.eql(u8, kind_str, "quit")) return Directive{ .expect_action = .quit };
            return ParseError.InvalidActionKind;
        }

        if (std.mem.eql(u8, command, "expect_quit")) {
            return Directive{ .expect_quit = {} };
        }

        if (std.mem.eql(u8, command, "snapshot")) {
            const name = tokens.next() orelse return ParseError.MissingArgument;
            return Directive{ .snapshot = name };
        }

        if (std.mem.eql(u8, command, "repeat")) {
            const n_str = tokens.next() orelse return ParseError.MissingArgument;
            const n = parseU32(n_str) orelse return ParseError.InvalidInteger;
            return Directive{ .repeat = n };
        }

        return ParseError.UnknownDirective;
    }

    fn parseKeyDirective(arg: []const u8) ParseError!Directive {
        if (arg.len == 1) {
            return Directive{ .key = arg[0] };
        }
        if (std.mem.indexOf(u8, arg, "+")) |_| {
            return parseModifiedKey(arg);
        }
        if (parseSpecialKey(arg)) |code| {
            return Directive{ .key_special = code };
        }
        return ParseError.InvalidKeyName;
    }

    fn parseModifiedKey(arg: []const u8) ParseError!Directive {
        var mods = Modifiers{};
        var remaining = arg;

        while (std.mem.indexOf(u8, remaining, "+")) |plus_idx| {
            const mod_str = remaining[0..plus_idx];
            remaining = remaining[plus_idx + 1 ..];

            if (std.mem.eql(u8, mod_str, "ctrl")) {
                mods.ctrl = true;
            } else if (std.mem.eql(u8, mod_str, "alt")) {
                mods.alt = true;
            } else if (std.mem.eql(u8, mod_str, "shift")) {
                mods.shift = true;
            } else {
                return ParseError.InvalidModifier;
            }
        }

        if (remaining.len == 1) {
            return Directive{ .key_with_mods = .{
                .code = KeyCode.fromChar(remaining[0]),
                .mods = mods,
            } };
        }

        if (parseSpecialKey(remaining)) |code| {
            return Directive{ .key_with_mods = .{
                .code = code,
                .mods = mods,
            } };
        }

        return ParseError.InvalidKeyName;
    }

    fn parseSpecialKey(name: []const u8) ?KeyCode {
        const map = .{
            .{ "enter", KeyCode{ .enter = {} } },
            .{ "escape", KeyCode{ .escape = {} } },
            .{ "tab", KeyCode{ .tab = {} } },
            .{ "backtab", KeyCode{ .backtab = {} } },
            .{ "backspace", KeyCode{ .backspace = {} } },
            .{ "up", KeyCode{ .up = {} } },
            .{ "down", KeyCode{ .down = {} } },
            .{ "left", KeyCode{ .left = {} } },
            .{ "right", KeyCode{ .right = {} } },
            .{ "home", KeyCode{ .home = {} } },
            .{ "end", KeyCode{ .end = {} } },
            .{ "page_up", KeyCode{ .page_up = {} } },
            .{ "page_down", KeyCode{ .page_down = {} } },
            .{ "insert", KeyCode{ .insert = {} } },
            .{ "delete", KeyCode{ .delete = {} } },
        };

        inline for (map) |entry| {
            if (std.mem.eql(u8, name, entry[0])) return entry[1];
        }

        if (name.len >= 2 and name[0] == 'f') {
            const num = std.fmt.parseInt(u8, name[1..], 10) catch return null;
            return KeyCode.fromF(num);
        }

        return null;
    }

    fn parseStyleAttr(name: []const u8) ?BoundStyleAttr {
        const map = .{
            .{ "bold", BoundStyleAttr.bold },
            .{ "italic", BoundStyleAttr.italic },
            .{ "underline", BoundStyleAttr.underline },
            .{ "dim", BoundStyleAttr.dim },
            .{ "blink", BoundStyleAttr.blink },
            .{ "reverse", BoundStyleAttr.reverse },
            .{ "strikethrough", BoundStyleAttr.strikethrough },
            .{ "overline", BoundStyleAttr.overline },
        };

        inline for (map) |entry| {
            if (std.mem.eql(u8, name, entry[0])) return entry[1];
        }
        return null;
    }

    fn parseQuotedString(allocator: std.mem.Allocator, input: []const u8) ParseError!?[]const u8 {
        const trimmed = std.mem.trimLeft(u8, input, " \t");
        if (trimmed.len < 2) return null;
        if (trimmed[0] != '"') return null;

        var result: std.ArrayListUnmanaged(u8) = .{};
        errdefer result.deinit(allocator);

        var i: usize = 1;
        while (i < trimmed.len) : (i += 1) {
            if (trimmed[i] == '"') {
                return result.toOwnedSlice(allocator) catch return ParseError.OutOfMemory;
            }
            if (trimmed[i] == '\\' and i + 1 < trimmed.len) {
                i += 1;
                const escaped: u8 = switch (trimmed[i]) {
                    '"' => '"',
                    '\\' => '\\',
                    'n' => '\n',
                    't' => '\t',
                    else => return ParseError.InvalidEscapeSequence,
                };
                result.append(allocator, escaped) catch return ParseError.OutOfMemory;
            } else {
                result.append(allocator, trimmed[i]) catch return ParseError.OutOfMemory;
            }
        }
        return null;
    }

    fn parseU16(str: []const u8) ?u16 {
        return std.fmt.parseInt(u16, str, 10) catch null;
    }

    fn parseU32(str: []const u8) ?u32 {
        return std.fmt.parseInt(u32, str, 10) catch null;
    }
};

const TokenIterator = struct {
    source: []const u8,
    pos: usize,

    fn init(source: []const u8) TokenIterator {
        return .{ .source = source, .pos = 0 };
    }

    fn next(self: *TokenIterator) ?[]const u8 {
        while (self.pos < self.source.len and self.source[self.pos] == ' ') {
            self.pos += 1;
        }
        if (self.pos >= self.source.len) return null;

        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != ' ') {
            self.pos += 1;
        }
        return self.source[start..self.pos];
    }

    fn rest(self: *TokenIterator) []const u8 {
        while (self.pos < self.source.len and self.source[self.pos] == ' ') {
            self.pos += 1;
        }
        return self.source[self.pos..];
    }
};

pub const ScenarioResult = struct {
    passed: bool,
    failures: std.ArrayListUnmanaged(Failure),
    total_directives: usize,
    allocator: std.mem.Allocator,

    pub const Failure = struct {
        line: usize,
        directive_text: []const u8,
        expected: []const u8,
        actual: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) ScenarioResult {
        return .{
            .passed = true,
            .failures = .{},
            .total_directives = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ScenarioResult) void {
        self.failures.deinit(self.allocator);
    }

    pub fn failCount(self: ScenarioResult) usize {
        return self.failures.items.len;
    }

    fn addFailure(self: *ScenarioResult, line: usize, directive_text: []const u8, expected: []const u8, actual: []const u8) void {
        self.passed = false;
        self.failures.append(self.allocator, .{
            .line = line,
            .directive_text = directive_text,
            .expected = expected,
            .actual = actual,
        }) catch {};
    }
};

pub fn ScenarioRunner(comptime State: type) type {
    return struct {
        const Self = @This();
        const Harness = TestHarness(State);
        const MaxWidgets: usize = Harness.MaxWidgets;
        const FrameType = @import("frame.zig").Frame(MaxWidgets);

        allocator: std.mem.Allocator,
        state: *State,
        update_fn: *const fn (*State, Event) Action,
        view_fn: *const fn (*State, *FrameType) void,

        pub fn init(
            allocator: std.mem.Allocator,
            state: *State,
            update_fn: *const fn (*State, Event) Action,
            view_fn: *const fn (*State, *FrameType) void,
        ) Self {
            return .{
                .allocator = allocator,
                .state = state,
                .update_fn = update_fn,
                .view_fn = view_fn,
            };
        }

        pub fn run(self: *Self, scenario_text: []const u8) !ScenarioResult {
            const directives = try ScenarioParser.parse(self.allocator, scenario_text);
            defer {
                ScenarioParser.freeDirectives(self.allocator, directives);
                self.allocator.free(directives);
            }

            var result = ScenarioResult.init(self.allocator);
            result.total_directives = directives.len;

            var width: u16 = 80;
            var height: u16 = 24;
            var start_idx: usize = 0;

            if (directives.len > 0 and directives[0] == .size) {
                width = directives[0].size.width;
                height = directives[0].size.height;
                start_idx = 1;
            }

            var harness = try Harness.init(self.allocator, .{
                .state = self.state,
                .update = self.update_fn,
                .view = self.view_fn,
                .width = width,
                .height = height,
            });
            defer harness.deinit();

            var i = start_idx;
            var source_line: usize = 0;
            var line_map: std.ArrayListUnmanaged(usize) = .{};
            defer line_map.deinit(self.allocator);
            {
                var line_iter = std.mem.splitScalar(u8, scenario_text, '\n');
                var directive_idx: usize = 0;
                var line_num: usize = 0;
                while (line_iter.next()) |raw_line| : (line_num += 1) {
                    const trimmed = std.mem.trimRight(u8, raw_line, " \t\r");
                    const stripped = std.mem.trimLeft(u8, trimmed, " \t");
                    if (stripped.len == 0 or stripped[0] == '#') continue;
                    line_map.append(self.allocator, line_num + 1) catch {};
                    directive_idx += 1;
                }
            }

            while (i < directives.len) : (i += 1) {
                source_line = if (i < line_map.items.len) line_map.items[i] else i + 1;
                const directive = directives[i];

                switch (directive) {
                    .size => {},
                    .repeat => |n| {
                        if (i + 1 < directives.len) {
                            i += 1;
                            const next_directive = directives[i];
                            var repeat_count: u32 = 0;
                            while (repeat_count < n) : (repeat_count += 1) {
                                self.executeDirective(&harness, next_directive, source_line, &result);
                            }
                        }
                    },
                    else => {
                        self.executeDirective(&harness, directive, source_line, &result);
                    },
                }
            }

            return result;
        }

        pub fn runFile(self: *Self, path: []const u8) !ScenarioResult {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();
            const text = try file.readToEndAlloc(self.allocator, 1024 * 1024);
            defer self.allocator.free(text);
            return self.run(text);
        }

        fn coordsInBounds(harness: *Harness, x: u16, y: u16) bool {
            return x < harness.current_buf.width and y < harness.current_buf.height;
        }

        fn addOobFailure(result: *ScenarioResult, line: usize, directive_name: []const u8, x: u16, y: u16, w: u16, h: u16) void {
            var buf: [128]u8 = undefined;
            const actual = std.fmt.bufPrint(&buf, "coordinates out of bounds: ({d}, {d}) exceeds {d}x{d}", .{ x, y, w, h }) catch "(out of bounds)";
            result.addFailure(line, directive_name, "within bounds", actual);
        }

        fn executeDirective(self: *Self, harness: *Harness, directive: Directive, line: usize, result: *ScenarioResult) void {
            _ = self;
            const buf_w = harness.current_buf.width;
            const buf_h = harness.current_buf.height;

            switch (directive) {
                .key => |char| {
                    harness.pressKey(char);
                },
                .key_special => |code| {
                    harness.pressSpecial(code);
                },
                .key_with_mods => |km| {
                    harness.pressKeyWith(km.code, km.mods);
                },
                .type_text => |text| {
                    for (text) |ch| {
                        harness.pressKey(ch);
                    }
                },
                .click => |pos| {
                    if (!coordsInBounds(harness, pos.x, pos.y)) {
                        addOobFailure(result, line, "click", pos.x, pos.y, buf_w, buf_h);
                        return;
                    }
                    harness.click(pos.x, pos.y);
                },
                .right_click => |pos| {
                    if (!coordsInBounds(harness, pos.x, pos.y)) {
                        addOobFailure(result, line, "right_click", pos.x, pos.y, buf_w, buf_h);
                        return;
                    }
                    harness.rightClick(pos.x, pos.y);
                },
                .mouse_down => |pos| {
                    if (!coordsInBounds(harness, pos.x, pos.y)) {
                        addOobFailure(result, line, "mouse_down", pos.x, pos.y, buf_w, buf_h);
                        return;
                    }
                    harness.mouseDown(pos.x, pos.y);
                },
                .mouse_up => |pos| {
                    if (!coordsInBounds(harness, pos.x, pos.y)) {
                        addOobFailure(result, line, "mouse_up", pos.x, pos.y, buf_w, buf_h);
                        return;
                    }
                    harness.mouseUp(pos.x, pos.y);
                },
                .hover => |pos| {
                    if (!coordsInBounds(harness, pos.x, pos.y)) {
                        addOobFailure(result, line, "hover", pos.x, pos.y, buf_w, buf_h);
                        return;
                    }
                    harness.hover(pos.x, pos.y);
                },
                .drag => |d| {
                    if (!coordsInBounds(harness, d.x1, d.y1)) {
                        addOobFailure(result, line, "drag", d.x1, d.y1, buf_w, buf_h);
                        return;
                    }
                    if (!coordsInBounds(harness, d.x2, d.y2)) {
                        addOobFailure(result, line, "drag", d.x2, d.y2, buf_w, buf_h);
                        return;
                    }
                    harness.drag(d.x1, d.y1, d.x2, d.y2);
                },
                .scroll_up => |pos| {
                    if (!coordsInBounds(harness, pos.x, pos.y)) {
                        addOobFailure(result, line, "scroll_up", pos.x, pos.y, buf_w, buf_h);
                        return;
                    }
                    harness.scroll(pos.x, pos.y, .scroll_up);
                },
                .scroll_down => |pos| {
                    if (!coordsInBounds(harness, pos.x, pos.y)) {
                        addOobFailure(result, line, "scroll_down", pos.x, pos.y, buf_w, buf_h);
                        return;
                    }
                    harness.scroll(pos.x, pos.y, .scroll_down);
                },
                .tick => {
                    harness.tick();
                },
                .tick_n => |n| {
                    harness.tickN(n);
                },
                .expect_string => |es| {
                    if (!coordsInBounds(harness, es.x, es.y)) {
                        addOobFailure(result, line, "expect_string", es.x, es.y, buf_w, buf_h);
                        return;
                    }
                    harness.expectString(es.x, es.y, es.text) catch {
                        result.addFailure(line, "expect_string", es.text, "(mismatch)");
                    };
                },
                .expect_cell => |ec| {
                    if (!coordsInBounds(harness, ec.x, ec.y)) {
                        addOobFailure(result, line, "expect_cell", ec.x, ec.y, buf_w, buf_h);
                        return;
                    }
                    harness.expectCell(ec.x, ec.y, ec.char) catch {
                        var buf: [32]u8 = undefined;
                        const actual_cell = harness.current_buf.get(ec.x, ec.y);
                        const expected_str = std.fmt.bufPrint(&buf, "U+{X:0>4}", .{ec.char}) catch "?";
                        var actual_buf: [32]u8 = undefined;
                        const actual_str = std.fmt.bufPrint(&actual_buf, "U+{X:0>4}", .{actual_cell.char}) catch "?";
                        result.addFailure(line, "expect_cell", expected_str, actual_str);
                    };
                },
                .expect_empty => |ee| {
                    if (!coordsInBounds(harness, ee.x, ee.y)) {
                        addOobFailure(result, line, "expect_empty", ee.x, ee.y, buf_w, buf_h);
                        return;
                    }
                    harness.expectEmpty(ee.x, ee.y) catch {
                        result.addFailure(line, "expect_empty", "(empty)", "(not empty)");
                    };
                },
                .expect_style => |es| {
                    if (!coordsInBounds(harness, es.x, es.y)) {
                        addOobFailure(result, line, "expect_style", es.x, es.y, buf_w, buf_h);
                        return;
                    }
                    const cell = harness.current_buf.get(es.x, es.y);
                    const rich_attr = es.attr.toStyleAttribute();
                    if (!cell.style.hasAttribute(rich_attr)) {
                        result.addFailure(line, "expect_style", @tagName(es.attr), "(missing)");
                    }
                },
                .expect_action => |kind| {
                    const match = switch (kind) {
                        .none => harness.last_action == .none,
                        .quit => harness.last_action == .quit,
                    };
                    if (!match) {
                        result.addFailure(line, "expect_action", @tagName(kind), @tagName(harness.last_action));
                    }
                },
                .expect_quit => {
                    if (harness.last_action != .quit) {
                        result.addFailure(line, "expect_quit", "quit", @tagName(harness.last_action));
                    }
                },
                .snapshot => |name| {
                    var path_buf: [512]u8 = undefined;
                    const path = std.fmt.bufPrint(&path_buf, "tests/golden/{s}.golden", .{name}) catch {
                        result.addFailure(line, "snapshot", name, "(path too long)");
                        return;
                    };
                    harness.expectSnapshotFile(path) catch {
                        result.addFailure(line, "snapshot", name, "(mismatch or missing)");
                    };
                },
                .size => {},
                .repeat => {},
            }
        }
    };
}

test "sanity: parse empty input" {
    const directives = try ScenarioParser.parse(std.testing.allocator, "");
    defer std.testing.allocator.free(directives);
    try std.testing.expectEqual(@as(usize, 0), directives.len);
}

test "sanity: parse comment-only input" {
    const directives = try ScenarioParser.parse(std.testing.allocator, "# this is a comment\n# another comment\n");
    defer std.testing.allocator.free(directives);
    try std.testing.expectEqual(@as(usize, 0), directives.len);
}

test "sanity: parse blank lines" {
    const directives = try ScenarioParser.parse(std.testing.allocator,
        \\
        \\
        \\
    );
    defer std.testing.allocator.free(directives);
    try std.testing.expectEqual(@as(usize, 0), directives.len);
}

test "sanity: parseLine returns null for blank" {
    const result = try ScenarioParser.parseLine(std.testing.allocator, "");
    try std.testing.expect(result == null);
}

test "sanity: parseLine returns null for comment" {
    const result = try ScenarioParser.parseLine(std.testing.allocator, "# comment");
    try std.testing.expect(result == null);
}

test "behavior: parse size directive" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "size 100 50")).?;
    try std.testing.expect(result == .size);
    try std.testing.expectEqual(@as(u16, 100), result.size.width);
    try std.testing.expectEqual(@as(u16, 50), result.size.height);
}

test "behavior: parse key character" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "key a")).?;
    try std.testing.expect(result == .key);
    try std.testing.expectEqual(@as(u21, 'a'), result.key);
}

test "behavior: parse key special" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "key enter")).?;
    try std.testing.expect(result == .key_special);
    try std.testing.expect(result.key_special == .enter);
}

test "behavior: parse key with modifiers" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "key ctrl+c")).?;
    try std.testing.expect(result == .key_with_mods);
    try std.testing.expect(result.key_with_mods.mods.ctrl);
    try std.testing.expect(!result.key_with_mods.mods.alt);
}

test "behavior: parse key ctrl+alt+x" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "key ctrl+alt+x")).?;
    try std.testing.expect(result == .key_with_mods);
    try std.testing.expect(result.key_with_mods.mods.ctrl);
    try std.testing.expect(result.key_with_mods.mods.alt);
}

test "behavior: parse key shift+enter" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "key shift+enter")).?;
    try std.testing.expect(result == .key_with_mods);
    try std.testing.expect(result.key_with_mods.mods.shift);
    try std.testing.expect(result.key_with_mods.code == .enter);
}

test "behavior: parse key special names" {
    const names = [_][]const u8{
        "escape", "tab",    "backtab", "backspace",
        "up",     "down",   "left",    "right",
        "home",   "end",    "page_up", "page_down",
        "insert", "delete",
    };
    for (names) |name| {
        var buf: [32]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "key {s}", .{name}) catch unreachable;
        const result = try ScenarioParser.parseLine(std.testing.allocator, line);
        try std.testing.expect(result != null);
        try std.testing.expect(result.? == .key_special);
    }
}

test "behavior: parse function keys" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "key f5")).?;
    try std.testing.expect(result == .key_special);
    try std.testing.expect(result.key_special == .f);
    try std.testing.expectEqual(@as(u8, 5), result.key_special.f);
}

test "behavior: parse type directive" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "type \"hello world\"")).?;
    defer std.testing.allocator.free(result.type_text);
    try std.testing.expect(result == .type_text);
    try std.testing.expectEqualStrings("hello world", result.type_text);
}

test "behavior: parse click" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "click 10 5")).?;
    try std.testing.expect(result == .click);
    try std.testing.expectEqual(@as(u16, 10), result.click.x);
    try std.testing.expectEqual(@as(u16, 5), result.click.y);
}

test "behavior: parse right_click" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "right_click 20 15")).?;
    try std.testing.expect(result == .right_click);
    try std.testing.expectEqual(@as(u16, 20), result.right_click.x);
    try std.testing.expectEqual(@as(u16, 15), result.right_click.y);
}

test "behavior: parse mouse_down" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "mouse_down 3 7")).?;
    try std.testing.expect(result == .mouse_down);
    try std.testing.expectEqual(@as(u16, 3), result.mouse_down.x);
    try std.testing.expectEqual(@as(u16, 7), result.mouse_down.y);
}

test "behavior: parse mouse_up" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "mouse_up 3 7")).?;
    try std.testing.expect(result == .mouse_up);
}

test "behavior: parse hover" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "hover 12 8")).?;
    try std.testing.expect(result == .hover);
    try std.testing.expectEqual(@as(u16, 12), result.hover.x);
    try std.testing.expectEqual(@as(u16, 8), result.hover.y);
}

test "behavior: parse drag" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "drag 0 0 10 10")).?;
    try std.testing.expect(result == .drag);
    try std.testing.expectEqual(@as(u16, 0), result.drag.x1);
    try std.testing.expectEqual(@as(u16, 0), result.drag.y1);
    try std.testing.expectEqual(@as(u16, 10), result.drag.x2);
    try std.testing.expectEqual(@as(u16, 10), result.drag.y2);
}

test "behavior: parse scroll_up" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "scroll_up 5 10")).?;
    try std.testing.expect(result == .scroll_up);
}

test "behavior: parse scroll_down" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "scroll_down 5 10")).?;
    try std.testing.expect(result == .scroll_down);
}

test "behavior: parse tick" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "tick")).?;
    try std.testing.expect(result == .tick);
}

test "behavior: parse tick with count" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "tick 5")).?;
    try std.testing.expect(result == .tick_n);
    try std.testing.expectEqual(@as(u32, 5), result.tick_n);
}

test "behavior: parse expect_string" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "expect_string 0 0 \"Count: 0\"")).?;
    defer std.testing.allocator.free(result.expect_string.text);
    try std.testing.expect(result == .expect_string);
    try std.testing.expectEqual(@as(u16, 0), result.expect_string.x);
    try std.testing.expectEqual(@as(u16, 0), result.expect_string.y);
    try std.testing.expectEqualStrings("Count: 0", result.expect_string.text);
}

test "behavior: parse expect_cell" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "expect_cell 5 3 X")).?;
    try std.testing.expect(result == .expect_cell);
    try std.testing.expectEqual(@as(u16, 5), result.expect_cell.x);
    try std.testing.expectEqual(@as(u16, 3), result.expect_cell.y);
    try std.testing.expectEqual(@as(u21, 'X'), result.expect_cell.char);
}

test "behavior: parse expect_empty" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "expect_empty 10 20")).?;
    try std.testing.expect(result == .expect_empty);
}

test "behavior: parse expect_style" {
    const attrs = [_][]const u8{
        "bold", "italic", "underline", "dim", "blink", "reverse", "strikethrough", "overline",
    };
    for (attrs) |attr| {
        var buf: [64]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "expect_style 0 0 {s}", .{attr}) catch unreachable;
        const result = try ScenarioParser.parseLine(std.testing.allocator, line);
        try std.testing.expect(result != null);
        try std.testing.expect(result.? == .expect_style);
    }
}

test "behavior: parse expect_action none" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "expect_action none")).?;
    try std.testing.expect(result == .expect_action);
    try std.testing.expect(result.expect_action == .none);
}

test "behavior: parse expect_action quit" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "expect_action quit")).?;
    try std.testing.expect(result == .expect_action);
    try std.testing.expect(result.expect_action == .quit);
}

test "behavior: parse expect_quit" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "expect_quit")).?;
    try std.testing.expect(result == .expect_quit);
}

test "behavior: parse snapshot" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "snapshot my_snapshot")).?;
    try std.testing.expect(result == .snapshot);
    try std.testing.expectEqualStrings("my_snapshot", result.snapshot);
}

test "behavior: parse repeat" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "repeat 3")).?;
    try std.testing.expect(result == .repeat);
    try std.testing.expectEqual(@as(u32, 3), result.repeat);
}

test "behavior: parse multi-line scenario" {
    const scenario =
        \\# Setup
        \\size 40 10
        \\
        \\# Actions
        \\key +
        \\key +
        \\key +
        \\
        \\# Assertions
        \\expect_string 0 0 "Count: 3"
    ;
    const directives = try ScenarioParser.parse(std.testing.allocator, scenario);
    defer {
        ScenarioParser.freeDirectives(std.testing.allocator, directives);
        std.testing.allocator.free(directives);
    }

    try std.testing.expectEqual(@as(usize, 5), directives.len);
    try std.testing.expect(directives[0] == .size);
    try std.testing.expect(directives[1] == .key);
    try std.testing.expect(directives[2] == .key);
    try std.testing.expect(directives[3] == .key);
    try std.testing.expect(directives[4] == .expect_string);
}

const RunnerTestHelpers = struct {
    const CounterState = struct {
        count: i32 = 0,
        last_key: ?u21 = null,
        ticks: u32 = 0,
        quit_requested: bool = false,
    };

    const FrameType = @import("frame.zig").Frame(64);

    fn update(state: *CounterState, ev: Event) Action {
        switch (ev) {
            .key => |k| {
                switch (k.code) {
                    .char => |c| {
                        state.last_key = c;
                        if (c == 'q') {
                            state.quit_requested = true;
                            return .{ .quit = {} };
                        }
                        if (c == '+') state.count += 1;
                        if (c == '-') state.count -= 1;
                    },
                    else => {},
                }
            },
            .tick => {
                state.ticks += 1;
            },
            else => {},
        }
        return .{ .none = {} };
    }

    fn view(state: *CounterState, frame: *FrameType) void {
        var count_buf: [32]u8 = undefined;
        const count_str = std.fmt.bufPrint(&count_buf, "Count: {d}", .{state.count}) catch "?";
        frame.buffer.setString(0, 0, count_str, Style.empty);

        if (state.last_key) |k| {
            var key_buf: [16]u8 = undefined;
            const key_str = std.fmt.bufPrint(&key_buf, "Key: {c}", .{@as(u8, @intCast(k & 0x7f))}) catch "?";
            frame.buffer.setString(0, 1, key_str, Style.empty);
        }
    }

    fn styledView(state: *CounterState, frame: *FrameType) void {
        _ = state;
        frame.buffer.setString(0, 0, "Bold", Style.init().bold());
        frame.buffer.setString(0, 1, "Normal", Style.empty);
    }
};

test "behavior: ScenarioRunner basic key and assertion" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\key +
        \\expect_string 0 0 "Count: 1"
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(usize, 0), result.failCount());
}

test "behavior: ScenarioRunner multiple increments" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\key +
        \\key +
        \\key +
        \\expect_string 0 0 "Count: 3"
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
}

test "behavior: ScenarioRunner detects assertion failure" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\key +
        \\expect_string 0 0 "Count: 999"
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(@as(usize, 1), result.failCount());
}

test "behavior: ScenarioRunner tick directive" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\tick
        \\tick
        \\tick
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(u32, 3), state.ticks);
}

test "behavior: ScenarioRunner tick_n directive" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\tick 5
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(u32, 5), state.ticks);
}

test "behavior: ScenarioRunner repeat directive" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\repeat 5
        \\key +
        \\expect_string 0 0 "Count: 5"
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(i32, 5), state.count);
}

test "behavior: ScenarioRunner quit detection" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\key q
        \\expect_quit
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
    try std.testing.expect(state.quit_requested);
}

test "behavior: ScenarioRunner expect_action none" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\key +
        \\expect_action none
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
}

test "behavior: ScenarioRunner expect_cell" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\expect_cell 0 0 C
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
}

test "behavior: ScenarioRunner expect_empty" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\expect_empty 39 9
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
}

test "behavior: ScenarioRunner expect_style" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.styledView,
    );

    const scenario =
        \\size 40 10
        \\expect_style 0 0 bold
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
}

test "behavior: ScenarioRunner type_text directive" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\type "+++"
        \\expect_string 0 0 "Count: 3"
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
}

test "behavior: ScenarioRunner default size without size directive" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\expect_string 0 0 "Count: 0"
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(result.passed);
}

test "behavior: ScenarioRunner multiple failures collected" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 40 10
        \\expect_string 0 0 "WRONG1"
        \\expect_string 0 0 "WRONG2"
        \\expect_string 0 0 "WRONG3"
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(@as(usize, 3), result.failCount());
}

test "regression: trailing whitespace in lines" {
    const result = try ScenarioParser.parseLine(std.testing.allocator, "key a   ");
    try std.testing.expect(result != null);
    try std.testing.expect(result.? == .key);
}

test "regression: leading whitespace in lines" {
    const result = try ScenarioParser.parseLine(std.testing.allocator, "  key a");
    try std.testing.expect(result != null);
    try std.testing.expect(result.? == .key);
}

test "regression: comment with leading whitespace" {
    const result = try ScenarioParser.parseLine(std.testing.allocator, "   # comment");
    try std.testing.expect(result == null);
}

test "regression: unknown directive returns error" {
    const result = ScenarioParser.parseLine(std.testing.allocator, "bogus_command");
    try std.testing.expectError(ParseError.UnknownDirective, result);
}

test "regression: missing argument returns error" {
    try std.testing.expectError(ParseError.MissingArgument, ScenarioParser.parseLine(std.testing.allocator, "size 10"));
    try std.testing.expectError(ParseError.MissingArgument, ScenarioParser.parseLine(std.testing.allocator, "key"));
    try std.testing.expectError(ParseError.MissingArgument, ScenarioParser.parseLine(std.testing.allocator, "click 10"));
    try std.testing.expectError(ParseError.MissingArgument, ScenarioParser.parseLine(std.testing.allocator, "expect_action"));
    try std.testing.expectError(ParseError.MissingArgument, ScenarioParser.parseLine(std.testing.allocator, "repeat"));
}

test "regression: invalid integer returns error" {
    try std.testing.expectError(ParseError.InvalidInteger, ScenarioParser.parseLine(std.testing.allocator, "size abc 10"));
    try std.testing.expectError(ParseError.InvalidInteger, ScenarioParser.parseLine(std.testing.allocator, "click 10 xyz"));
}

test "regression: invalid key name returns error" {
    try std.testing.expectError(ParseError.InvalidKeyName, ScenarioParser.parseLine(std.testing.allocator, "key notakey"));
}

test "regression: invalid modifier returns error" {
    try std.testing.expectError(ParseError.InvalidModifier, ScenarioParser.parseLine(std.testing.allocator, "key bogus+a"));
}

test "regression: invalid style attribute returns error" {
    try std.testing.expectError(ParseError.InvalidStyleAttribute, ScenarioParser.parseLine(std.testing.allocator, "expect_style 0 0 bogus"));
}

test "regression: invalid action kind returns error" {
    try std.testing.expectError(ParseError.InvalidActionKind, ScenarioParser.parseLine(std.testing.allocator, "expect_action bogus"));
}

test "regression: unterminated string returns error" {
    try std.testing.expectError(ParseError.UnterminatedString, ScenarioParser.parseLine(std.testing.allocator, "type \"no close"));
}

test "regression: quoted string with spaces preserved" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "expect_string 0 0 \"hello world foo\"")).?;
    defer std.testing.allocator.free(result.expect_string.text);
    try std.testing.expect(result == .expect_string);
    try std.testing.expectEqualStrings("hello world foo", result.expect_string.text);
}

test "regression: ScenarioResult init and deinit" {
    var result = ScenarioResult.init(std.testing.allocator);
    defer result.deinit();
    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(usize, 0), result.failCount());
}

test "regression: BoundStyleAttr conversion roundtrip" {
    const attrs = [_]BoundStyleAttr{
        .bold, .italic, .underline, .dim, .blink, .reverse, .strikethrough, .overline,
    };
    for (attrs) |attr| {
        const sa = attr.toStyleAttribute();
        _ = sa;
    }
}

test "behavior: escape sequence - escaped quote" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "type \"hello\\\"world\"")).?;
    defer std.testing.allocator.free(result.type_text);
    try std.testing.expect(result == .type_text);
    try std.testing.expectEqualStrings("hello\"world", result.type_text);
}

test "behavior: escape sequence - escaped backslash" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "type \"path\\\\to\"")).?;
    defer std.testing.allocator.free(result.type_text);
    try std.testing.expect(result == .type_text);
    try std.testing.expectEqualStrings("path\\to", result.type_text);
}

test "behavior: escape sequence - newline and tab" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "type \"line1\\nline2\\tend\"")).?;
    defer std.testing.allocator.free(result.type_text);
    try std.testing.expect(result == .type_text);
    try std.testing.expectEqualStrings("line1\nline2\tend", result.type_text);
}

test "behavior: escape sequence - invalid escape returns error" {
    try std.testing.expectError(ParseError.InvalidEscapeSequence, ScenarioParser.parseLine(std.testing.allocator, "type \"bad\\x\""));
}

test "behavior: escape sequence - in expect_string" {
    const result = (try ScenarioParser.parseLine(std.testing.allocator, "expect_string 0 0 \"tab\\there\"")).?;
    defer std.testing.allocator.free(result.expect_string.text);
    try std.testing.expect(result == .expect_string);
    try std.testing.expectEqualStrings("tab\there", result.expect_string.text);
}

test "behavior: coordinate bounds - click out of bounds" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 10 5
        \\click 100 200
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(@as(usize, 1), result.failCount());
}

test "behavior: coordinate bounds - expect_string out of bounds" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 10 5
        \\expect_string 50 50 "test"
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(@as(usize, 1), result.failCount());
}

test "behavior: coordinate bounds - drag both endpoints checked" {
    var state = RunnerTestHelpers.CounterState{};
    var runner = ScenarioRunner(RunnerTestHelpers.CounterState).init(
        std.testing.allocator,
        &state,
        RunnerTestHelpers.update,
        RunnerTestHelpers.view,
    );

    const scenario =
        \\size 10 5
        \\drag 0 0 100 100
    ;
    var result = try runner.run(scenario);
    defer result.deinit();

    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(@as(usize, 1), result.failCount());
}
