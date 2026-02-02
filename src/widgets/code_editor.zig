// CodeEditor widget for zithril TUI framework
// Code viewer with syntax highlighting, line numbers, and scrolling

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const geometry = @import("../geometry.zig");
const style_mod = @import("../style.zig");

pub const Buffer = buffer_mod.Buffer;
pub const Cell = buffer_mod.Cell;
pub const Rect = geometry.Rect;
pub const Style = style_mod.Style;
pub const Color = style_mod.Color;

/// Supported programming languages for syntax highlighting.
pub const Language = enum {
    zig,
    rust,
    python,
    javascript,
    json,
    yaml,
    markdown,
    go,
    c,
    plain,
};

/// Token types for syntax highlighting.
pub const TokenType = enum {
    keyword,
    string,
    number,
    comment,
    operator,
    builtin,
    type_name,
    attribute,
    normal,
};

/// Color theme for syntax highlighting.
pub const Theme = struct {
    keyword: Style = Style.init().fg(.magenta).bold(),
    string: Style = Style.init().fg(.green),
    number: Style = Style.init().fg(.cyan),
    comment: Style = Style.init().fg(.bright_black),
    operator: Style = Style.init().fg(.yellow),
    builtin: Style = Style.init().fg(.cyan),
    type_name: Style = Style.init().fg(.yellow),
    attribute: Style = Style.init().fg(.blue),
    normal: Style = Style.empty,

    pub const default = Theme{};

    pub fn getStyle(self: Theme, token_type: TokenType) Style {
        return switch (token_type) {
            .keyword => self.keyword,
            .string => self.string,
            .number => self.number,
            .comment => self.comment,
            .operator => self.operator,
            .builtin => self.builtin,
            .type_name => self.type_name,
            .attribute => self.attribute,
            .normal => self.normal,
        };
    }
};

/// CodeEditor widget for viewing code with syntax highlighting.
///
/// Features:
/// - Line numbers with configurable style
/// - Syntax highlighting for multiple languages
/// - Current line highlighting
/// - Horizontal and vertical scrolling
pub const CodeEditor = struct {
    /// Source code content
    content: []const u8,

    /// Programming language for syntax highlighting
    language: Language = .plain,

    /// Show line numbers
    show_line_numbers: bool = true,

    /// Highlight the current line
    highlight_current_line: bool = true,

    /// Tab display width
    tab_width: u8 = 4,

    /// Base style for code
    style: Style = Style.empty,

    /// Style for line numbers
    line_number_style: Style = Style.init().fg(.bright_black),

    /// Style for current line background
    current_line_style: Style = Style.init().bg(.bright_black),

    /// Current line (0-indexed, for highlighting)
    current_line: usize = 0,

    /// Vertical scroll offset (lines)
    scroll_y: usize = 0,

    /// Horizontal scroll offset (columns)
    scroll_x: usize = 0,

    /// Syntax highlighting theme
    theme: Theme = Theme.default,

    /// Line number gutter width (0 = auto)
    line_number_width: u16 = 0,

    /// Render the code editor into the buffer.
    pub fn render(self: CodeEditor, area: Rect, buf: *Buffer) void {
        if (area.isEmpty()) return;
        if (self.content.len == 0) return;

        // Calculate line number gutter width
        const total_lines = self.countLines();
        const gutter_width = if (!self.show_line_numbers)
            @as(u16, 0)
        else if (self.line_number_width > 0)
            self.line_number_width
        else
            self.calculateGutterWidth(total_lines);

        // Content area starts after gutter
        const content_x = area.x +| gutter_width;
        const content_width = if (area.width > gutter_width) area.width - gutter_width else 0;

        if (content_width == 0) return;

        var line_iter = LineIterator.init(self.content);
        var line_num: usize = 0;
        var y: u16 = 0;

        // Skip lines before scroll_y
        while (line_num < self.scroll_y) : (line_num += 1) {
            if (line_iter.next() == null) return;
        }

        // Render visible lines
        while (line_iter.next()) |line| {
            if (y >= area.height) break;

            const screen_y = area.y +| y;
            const is_current = line_num == self.current_line;

            // Render line number if enabled
            if (self.show_line_numbers and gutter_width > 0) {
                self.renderLineNumber(line_num + 1, area.x, screen_y, gutter_width, is_current, buf);
            }

            // Render line content with syntax highlighting
            self.renderLine(
                line,
                content_x,
                screen_y,
                content_width,
                is_current,
                buf,
            );

            line_num += 1;
            y += 1;
        }
    }

    fn calculateGutterWidth(self: CodeEditor, total_lines: usize) u16 {
        _ = self;
        // Width = digits + 2 (for padding and separator)
        var digits: u16 = 1;
        var n = total_lines;
        while (n >= 10) : (n /= 10) {
            digits += 1;
        }
        return digits + 2;
    }

    fn countLines(self: CodeEditor) usize {
        if (self.content.len == 0) return 0;
        var count: usize = 1;
        for (self.content) |c| {
            if (c == '\n') count += 1;
        }
        return count;
    }

    fn renderLineNumber(
        self: CodeEditor,
        num: usize,
        x: u16,
        y: u16,
        width: u16,
        is_current: bool,
        buf: *Buffer,
    ) void {
        var num_buf: [16]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{num}) catch return;

        const style = if (is_current and self.highlight_current_line)
            self.line_number_style.patch(self.current_line_style)
        else
            self.line_number_style;

        // Fill gutter background if highlighting current line
        if (is_current and self.highlight_current_line) {
            var gx = x;
            while (gx < x +| width) : (gx += 1) {
                buf.set(gx, y, Cell.styled(' ', self.current_line_style));
            }
        }

        // Right-align number, leave space for separator
        const num_width: u16 = @intCast(num_str.len);
        const padding = if (width > num_width + 1) width - num_width - 1 else 0;
        var write_x = x +| padding;

        for (num_str) |c| {
            if (write_x >= x +| width) break;
            buf.set(write_x, y, Cell.styled(c, style));
            write_x += 1;
        }
    }

    fn renderLine(
        self: CodeEditor,
        line: []const u8,
        x: u16,
        y: u16,
        width: u16,
        is_current: bool,
        buf: *Buffer,
    ) void {
        // Apply current line background first
        if (is_current and self.highlight_current_line) {
            var fill_x = x;
            while (fill_x < x +| width) : (fill_x += 1) {
                buf.set(fill_x, y, Cell.styled(' ', self.current_line_style));
            }
        }

        // Tokenize and render
        var tokenizer = Tokenizer.init(line, self.language);
        var col: usize = 0;
        var screen_x: u16 = x;

        while (tokenizer.next()) |token| {
            const token_style = if (is_current and self.highlight_current_line)
                self.theme.getStyle(token.type).patch(self.current_line_style)
            else
                self.theme.getStyle(token.type);

            for (token.text) |c| {
                // Handle tabs
                if (c == '\t') {
                    const spaces = self.tab_width - @as(u8, @intCast(col % self.tab_width));
                    var i: u8 = 0;
                    while (i < spaces) : (i += 1) {
                        if (col >= self.scroll_x and screen_x < x +| width) {
                            buf.set(screen_x, y, Cell.styled(' ', token_style));
                            screen_x += 1;
                        }
                        col += 1;
                    }
                } else {
                    if (col >= self.scroll_x and screen_x < x +| width) {
                        buf.set(screen_x, y, Cell.styled(c, token_style));
                        screen_x += 1;
                    }
                    col += 1;
                }
            }
        }
    }

    /// Get the number of lines in the content.
    pub fn lineCount(self: CodeEditor) usize {
        return self.countLines();
    }
};

/// Simple line iterator that splits on newlines.
const LineIterator = struct {
    content: []const u8,
    pos: usize,

    pub fn init(content: []const u8) LineIterator {
        return .{ .content = content, .pos = 0 };
    }

    pub fn next(self: *LineIterator) ?[]const u8 {
        if (self.pos >= self.content.len) return null;

        const start = self.pos;
        while (self.pos < self.content.len and self.content[self.pos] != '\n') {
            self.pos += 1;
        }

        const end = self.pos;
        if (self.pos < self.content.len) {
            self.pos += 1; // Skip newline
        }

        return self.content[start..end];
    }
};

/// Token from the tokenizer.
const Token = struct {
    text: []const u8,
    type: TokenType,
};

/// Simple keyword-based tokenizer for syntax highlighting.
const Tokenizer = struct {
    line: []const u8,
    pos: usize,
    language: Language,
    in_string: bool,
    string_char: u8,

    pub fn init(line: []const u8, language: Language) Tokenizer {
        return .{
            .line = line,
            .pos = 0,
            .language = language,
            .in_string = false,
            .string_char = 0,
        };
    }

    pub fn next(self: *Tokenizer) ?Token {
        if (self.pos >= self.line.len) return null;

        const start = self.pos;

        // Check for comments first
        if (self.isCommentStart()) {
            return self.consumeComment(start);
        }

        // Check for strings
        if (self.isStringStart()) {
            return self.consumeString(start);
        }

        // Check for numbers
        if (self.isNumberStart()) {
            return self.consumeNumber(start);
        }

        // Check for operators
        if (self.isOperator(self.line[self.pos])) {
            self.pos += 1;
            return Token{ .text = self.line[start..self.pos], .type = .operator };
        }

        // Check for identifiers/keywords
        if (self.isIdentifierStart(self.line[self.pos])) {
            return self.consumeIdentifier(start);
        }

        // Whitespace or other
        self.pos += 1;
        return Token{ .text = self.line[start..self.pos], .type = .normal };
    }

    fn isCommentStart(self: *Tokenizer) bool {
        if (self.pos >= self.line.len) return false;

        return switch (self.language) {
            .zig, .rust, .c, .go, .javascript, .json => self.line[self.pos] == '/' and
                self.pos + 1 < self.line.len and self.line[self.pos + 1] == '/',
            .python, .yaml => self.line[self.pos] == '#',
            .markdown => false,
            .plain => false,
        };
    }

    fn consumeComment(self: *Tokenizer, start: usize) Token {
        // Consume rest of line as comment
        self.pos = self.line.len;
        return Token{ .text = self.line[start..], .type = .comment };
    }

    fn isStringStart(self: *Tokenizer) bool {
        if (self.pos >= self.line.len) return false;
        const c = self.line[self.pos];
        return c == '"' or c == '\'';
    }

    fn consumeString(self: *Tokenizer, start: usize) Token {
        const quote = self.line[self.pos];
        self.pos += 1;

        while (self.pos < self.line.len) {
            const c = self.line[self.pos];
            if (c == '\\' and self.pos + 1 < self.line.len) {
                self.pos += 2; // Skip escape sequence
            } else if (c == quote) {
                self.pos += 1;
                break;
            } else {
                self.pos += 1;
            }
        }

        return Token{ .text = self.line[start..self.pos], .type = .string };
    }

    fn isNumberStart(self: *Tokenizer) bool {
        if (self.pos >= self.line.len) return false;
        const c = self.line[self.pos];
        return c >= '0' and c <= '9';
    }

    fn consumeNumber(self: *Tokenizer, start: usize) Token {
        // Handle hex, binary, octal prefixes
        if (self.pos + 1 < self.line.len and self.line[self.pos] == '0') {
            const next_c = self.line[self.pos + 1];
            if (next_c == 'x' or next_c == 'X' or next_c == 'b' or next_c == 'B' or next_c == 'o' or next_c == 'O') {
                self.pos += 2;
            }
        }

        while (self.pos < self.line.len) {
            const c = self.line[self.pos];
            if ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F') or c == '_' or c == '.') {
                self.pos += 1;
            } else {
                break;
            }
        }

        return Token{ .text = self.line[start..self.pos], .type = .number };
    }

    fn isOperator(self: *Tokenizer, c: u8) bool {
        _ = self;
        return switch (c) {
            '+', '-', '*', '/', '%', '=', '<', '>', '!', '&', '|', '^', '~', ':', ';', ',', '.', '(', ')', '[', ']', '{', '}' => true,
            else => false,
        };
    }

    fn isIdentifierStart(self: *Tokenizer, c: u8) bool {
        _ = self;
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c == '@';
    }

    fn isIdentifierChar(self: *Tokenizer, c: u8) bool {
        return self.isIdentifierStart(c) or (c >= '0' and c <= '9');
    }

    fn consumeIdentifier(self: *Tokenizer, start: usize) Token {
        // Handle Zig builtins (@import, etc.)
        const is_builtin = self.line[self.pos] == '@';

        while (self.pos < self.line.len and self.isIdentifierChar(self.line[self.pos])) {
            self.pos += 1;
        }

        const text = self.line[start..self.pos];

        if (is_builtin) {
            return Token{ .text = text, .type = .builtin };
        }

        const token_type = self.classifyIdentifier(text);
        return Token{ .text = text, .type = token_type };
    }

    fn classifyIdentifier(self: *Tokenizer, text: []const u8) TokenType {
        return switch (self.language) {
            .zig => classifyZigIdentifier(text),
            .rust => classifyRustIdentifier(text),
            .python => classifyPythonIdentifier(text),
            .javascript, .json => classifyJsIdentifier(text),
            .go => classifyGoIdentifier(text),
            .c => classifyCIdentifier(text),
            .yaml, .markdown, .plain => .normal,
        };
    }
};

fn classifyZigIdentifier(text: []const u8) TokenType {
    const keywords = [_][]const u8{
        "const",      "var",        "fn",        "pub",
        "return",     "if",         "else",      "while",
        "for",        "switch",     "break",     "continue",
        "struct",     "enum",       "union",     "error",
        "try",        "catch",      "defer",     "errdefer",
        "comptime",   "inline",     "unreachable", "undefined",
        "null",       "true",       "false",     "and",
        "or",         "orelse",     "async",     "await",
        "suspend",    "resume",     "test",      "extern",
        "export",     "align",      "threadlocal", "nosuspend",
        "noinline",   "callconv",   "volatile",  "anytype",
        "anyframe",   "asm",        "linksection", "allowzero",
        "packed",     "usingnamespace",
    };

    const types = [_][]const u8{
        "void",  "bool",  "anyerror", "noreturn",
        "type",  "anyopaque", "comptime_int", "comptime_float",
        "u8",    "u16",   "u32",      "u64",   "u128",  "usize",
        "i8",    "i16",   "i32",      "i64",   "i128",  "isize",
        "f16",   "f32",   "f64",      "f80",   "f128",
        "c_int", "c_uint", "c_long", "c_ulong",
    };

    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw)) return .keyword;
    }

    for (types) |t| {
        if (std.mem.eql(u8, text, t)) return .type_name;
    }

    // Check if it starts with uppercase (likely a type)
    if (text.len > 0 and text[0] >= 'A' and text[0] <= 'Z') {
        return .type_name;
    }

    return .normal;
}

fn classifyRustIdentifier(text: []const u8) TokenType {
    const keywords = [_][]const u8{
        "fn",     "let",   "mut",    "const",  "pub",    "return",
        "if",     "else",  "while",  "for",    "loop",   "match",
        "struct", "enum",  "impl",   "trait",  "type",   "mod",
        "use",    "self",  "Self",   "super",  "crate",  "where",
        "async",  "await", "move",   "ref",    "static", "unsafe",
        "true",   "false", "as",     "in",     "dyn",    "extern",
    };

    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw)) return .keyword;
    }

    if (text.len > 0 and text[0] >= 'A' and text[0] <= 'Z') {
        return .type_name;
    }

    return .normal;
}

fn classifyPythonIdentifier(text: []const u8) TokenType {
    const keywords = [_][]const u8{
        "def",     "class",  "if",       "elif",    "else",
        "for",     "while",  "return",   "yield",   "import",
        "from",    "as",     "try",      "except",  "finally",
        "raise",   "with",   "pass",     "break",   "continue",
        "and",     "or",     "not",      "in",      "is",
        "lambda",  "global", "nonlocal", "True",    "False",
        "None",    "async",  "await",    "assert",  "del",
    };

    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw)) return .keyword;
    }

    if (text.len > 0 and text[0] >= 'A' and text[0] <= 'Z') {
        return .type_name;
    }

    return .normal;
}

fn classifyJsIdentifier(text: []const u8) TokenType {
    const keywords = [_][]const u8{
        "function", "const",    "let",     "var",     "return",
        "if",       "else",     "for",     "while",   "do",
        "switch",   "case",     "default", "break",   "continue",
        "class",    "extends",  "new",     "this",    "super",
        "import",   "export",   "from",    "async",   "await",
        "try",      "catch",    "finally", "throw",   "typeof",
        "instanceof", "in",     "of",      "true",    "false",
        "null",     "undefined",
    };

    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw)) return .keyword;
    }

    if (text.len > 0 and text[0] >= 'A' and text[0] <= 'Z') {
        return .type_name;
    }

    return .normal;
}

fn classifyGoIdentifier(text: []const u8) TokenType {
    const keywords = [_][]const u8{
        "func",      "var",      "const",    "type",     "struct",
        "interface", "map",      "chan",     "package",  "import",
        "return",    "if",       "else",     "for",      "range",
        "switch",    "case",     "default",  "break",    "continue",
        "go",        "select",   "defer",    "fallthrough",
        "true",      "false",    "nil",
    };

    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw)) return .keyword;
    }

    if (text.len > 0 and text[0] >= 'A' and text[0] <= 'Z') {
        return .type_name;
    }

    return .normal;
}

fn classifyCIdentifier(text: []const u8) TokenType {
    const keywords = [_][]const u8{
        "auto",     "break",    "case",     "char",     "const",
        "continue", "default",  "do",       "double",   "else",
        "enum",     "extern",   "float",    "for",      "goto",
        "if",       "inline",   "int",      "long",     "register",
        "restrict", "return",   "short",    "signed",   "sizeof",
        "static",   "struct",   "switch",   "typedef",  "union",
        "unsigned", "void",     "volatile", "while",    "_Bool",
        "_Complex", "_Imaginary", "NULL",
    };

    for (keywords) |kw| {
        if (std.mem.eql(u8, text, kw)) return .keyword;
    }

    if (text.len > 0 and text[0] >= 'A' and text[0] <= 'Z') {
        return .type_name;
    }

    return .normal;
}

// ============================================================
// SANITY TESTS - Basic CodeEditor functionality
// ============================================================

test "sanity: CodeEditor with default values" {
    const editor = CodeEditor{ .content = "hello" };
    try std.testing.expectEqualStrings("hello", editor.content);
    try std.testing.expect(editor.show_line_numbers);
    try std.testing.expect(editor.highlight_current_line);
    try std.testing.expect(editor.language == .plain);
}

test "sanity: CodeEditor with custom settings" {
    const editor = CodeEditor{
        .content = "const x = 1;",
        .language = .zig,
        .show_line_numbers = false,
        .tab_width = 2,
    };
    try std.testing.expect(editor.language == .zig);
    try std.testing.expect(!editor.show_line_numbers);
    try std.testing.expectEqual(@as(u8, 2), editor.tab_width);
}

test "sanity: CodeEditor lineCount" {
    const single = CodeEditor{ .content = "line 1" };
    try std.testing.expectEqual(@as(usize, 1), single.lineCount());

    const multi = CodeEditor{ .content = "line 1\nline 2\nline 3" };
    try std.testing.expectEqual(@as(usize, 3), multi.lineCount());

    const empty = CodeEditor{ .content = "" };
    try std.testing.expectEqual(@as(usize, 0), empty.lineCount());
}

// ============================================================
// BEHAVIOR TESTS - Tokenizer
// ============================================================

test "behavior: Tokenizer recognizes Zig keywords" {
    const line = "const fn return";
    var tokenizer = Tokenizer.init(line, .zig);

    const t1 = tokenizer.next().?;
    try std.testing.expectEqualStrings("const", t1.text);
    try std.testing.expect(t1.type == .keyword);

    _ = tokenizer.next(); // space

    const t2 = tokenizer.next().?;
    try std.testing.expectEqualStrings("fn", t2.text);
    try std.testing.expect(t2.type == .keyword);
}

test "behavior: Tokenizer recognizes strings" {
    const line = "\"hello world\"";
    var tokenizer = Tokenizer.init(line, .zig);

    const t = tokenizer.next().?;
    try std.testing.expectEqualStrings("\"hello world\"", t.text);
    try std.testing.expect(t.type == .string);
}

test "behavior: Tokenizer recognizes comments" {
    const line = "x // this is a comment";
    var tokenizer = Tokenizer.init(line, .zig);

    _ = tokenizer.next(); // x
    _ = tokenizer.next(); // space

    const t = tokenizer.next().?;
    try std.testing.expectEqualStrings("// this is a comment", t.text);
    try std.testing.expect(t.type == .comment);
}

test "behavior: Tokenizer recognizes numbers" {
    const line = "42 0xFF 3.14";
    var tokenizer = Tokenizer.init(line, .zig);

    const t1 = tokenizer.next().?;
    try std.testing.expectEqualStrings("42", t1.text);
    try std.testing.expect(t1.type == .number);

    _ = tokenizer.next(); // space

    const t2 = tokenizer.next().?;
    try std.testing.expectEqualStrings("0xFF", t2.text);
    try std.testing.expect(t2.type == .number);
}

test "behavior: Tokenizer recognizes builtins" {
    const line = "@import @intCast";
    var tokenizer = Tokenizer.init(line, .zig);

    const t1 = tokenizer.next().?;
    try std.testing.expectEqualStrings("@import", t1.text);
    try std.testing.expect(t1.type == .builtin);
}

test "behavior: Tokenizer recognizes type names" {
    const line = "u32 MyStruct";
    var tokenizer = Tokenizer.init(line, .zig);

    const t1 = tokenizer.next().?;
    try std.testing.expectEqualStrings("u32", t1.text);
    try std.testing.expect(t1.type == .type_name);

    _ = tokenizer.next(); // space

    const t2 = tokenizer.next().?;
    try std.testing.expectEqualStrings("MyStruct", t2.text);
    try std.testing.expect(t2.type == .type_name);
}

// ============================================================
// BEHAVIOR TESTS - Rendering
// ============================================================

test "behavior: CodeEditor renders line numbers" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const editor = CodeEditor{
        .content = "line one\nline two",
        .show_line_numbers = true,
    };
    editor.render(Rect.init(0, 0, 40, 10), &buf);

    // With 2 lines, gutter is 3 chars wide (1 digit + 2 padding)
    // Line number 1 is at position 0 (right-aligned in gutter with space for separator)
    // Find where '1' is rendered in first 3 columns
    var found_1 = false;
    var found_2 = false;
    for (0..4) |x| {
        if (buf.get(@intCast(x), 0).char == '1') found_1 = true;
        if (buf.get(@intCast(x), 1).char == '2') found_2 = true;
    }
    try std.testing.expect(found_1);
    try std.testing.expect(found_2);
}

test "behavior: CodeEditor renders content" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const editor = CodeEditor{
        .content = "hello",
        .show_line_numbers = false,
    };
    editor.render(Rect.init(0, 0, 40, 10), &buf);

    try std.testing.expectEqual(@as(u21, 'h'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(2, 0).char);
}

test "behavior: CodeEditor highlights keywords" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const editor = CodeEditor{
        .content = "const",
        .language = .zig,
        .show_line_numbers = false,
    };
    editor.render(Rect.init(0, 0, 40, 10), &buf);

    // Check that the keyword has a non-empty style (colored)
    const cell = buf.get(0, 0);
    try std.testing.expect(cell.char == 'c');
    try std.testing.expect(!cell.style.isEmpty());
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: CodeEditor handles empty area" {
    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const editor = CodeEditor{ .content = "hello" };
    editor.render(Rect.init(0, 0, 0, 0), &buf);

    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: CodeEditor handles empty content" {
    var buf = try Buffer.init(std.testing.allocator, 40, 10);
    defer buf.deinit();

    const editor = CodeEditor{ .content = "" };
    editor.render(Rect.init(0, 0, 40, 10), &buf);

    for (buf.cells) |cell| {
        try std.testing.expect(cell.isDefault());
    }
}

test "regression: CodeEditor handles scroll offset" {
    var buf = try Buffer.init(std.testing.allocator, 40, 5);
    defer buf.deinit();

    const editor = CodeEditor{
        .content = "line 0\nline 1\nline 2\nline 3\nline 4\nline 5",
        .scroll_y = 2,
        .show_line_numbers = false,
    };
    editor.render(Rect.init(0, 0, 40, 5), &buf);

    // First visible line should be "line 2"
    try std.testing.expectEqual(@as(u21, 'l'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(1, 0).char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(2, 0).char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).char);
    try std.testing.expectEqual(@as(u21, ' '), buf.get(4, 0).char);
    try std.testing.expectEqual(@as(u21, '2'), buf.get(5, 0).char);
}

test "regression: CodeEditor clips long lines" {
    var buf = try Buffer.init(std.testing.allocator, 10, 5);
    defer buf.deinit();

    const editor = CodeEditor{
        .content = "this is a very long line that should be clipped",
        .show_line_numbers = false,
    };
    editor.render(Rect.init(0, 0, 10, 5), &buf);

    // Should not crash and content should be clipped
    try std.testing.expectEqual(@as(u21, 't'), buf.get(0, 0).char);
    try std.testing.expectEqual(@as(u21, 'h'), buf.get(1, 0).char);
}

test "regression: LineIterator handles content without trailing newline" {
    var iter = LineIterator.init("line1\nline2");

    try std.testing.expectEqualStrings("line1", iter.next().?);
    try std.testing.expectEqualStrings("line2", iter.next().?);
    try std.testing.expect(iter.next() == null);
}

test "regression: LineIterator handles empty lines" {
    var iter = LineIterator.init("a\n\nb");

    try std.testing.expectEqualStrings("a", iter.next().?);
    try std.testing.expectEqualStrings("", iter.next().?);
    try std.testing.expectEqualStrings("b", iter.next().?);
    try std.testing.expect(iter.next() == null);
}
