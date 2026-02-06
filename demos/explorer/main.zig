const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);

const Focus = enum { tree, preview, search };

const FileEntry = struct {
    name: []const u8,
    content: []const u8,
    is_code: bool = false,
};

// Flat file entries indexed by ID. Directories have IDs 0-2, files 10-12.
const file_entries = std.StaticStringMap(FileEntry).initComptime(.{
    .{ "src/", .{ .name = "src/", .content = "Directory: src/\nContains Zig source files for the project." } },
    .{ "main.zig", .{ .name = "main.zig", .is_code = true, .content = "const std = @import(\"std\");\n\npub fn main() !void {\n    const stdout = std.io.getStdOut().writer();\n    try stdout.print(\"Hello, {s}!\\n\", .{\"World\"});\n}" } },
    .{ "lib.zig", .{ .name = "lib.zig", .is_code = true, .content = "const std = @import(\"std\");\n\npub fn add(a: i32, b: i32) i32 {\n    return a + b;\n}" } },
    .{ "docs/", .{ .name = "docs/", .content = "Directory: docs/\nContains project documentation and guides." } },
    .{ "README.md", .{ .name = "README.md", .content = "# Project Documentation\n\nWelcome to the file explorer demo!\n\n## Controls\n- j/k: navigate\n- Tab: cycle focus\n- Enter: expand/collapse\n- m: context menu\n- q: quit" } },
    .{ "build.zig", .{ .name = "build.zig", .is_code = true, .content = "const std = @import(\"std\");\n\npub fn build(b: *std.Build) void {\n    const target = b.standardTargetOptions(.{});\n    _ = target;\n}" } },
});

// Visible tree order depends on expansion state
const tree_order_all = [_][]const u8{ "src/", "main.zig", "lib.zig", "docs/", "README.md", "build.zig" };
const tree_order_src_only = [_][]const u8{ "src/", "main.zig", "lib.zig", "docs/", "build.zig" };
const tree_order_docs_only = [_][]const u8{ "src/", "docs/", "README.md", "build.zig" };
const tree_order_none = [_][]const u8{ "src/", "docs/", "build.zig" };

const State = struct {
    active_tab: usize = 0,
    tree_selected: usize = 0,
    tree_offset: usize = 0,
    show_menu: bool = false,
    menu_state: zithril.MenuState = .{},
    search_buf: [256]u8 = [_]u8{0} ** 256,
    search_state: ?zithril.TextInputState = null,
    focus: Focus = .tree,
    src_expanded: bool = true,
    docs_expanded: bool = false,

    fn getSearchState(self: *State) *zithril.TextInputState {
        if (self.search_state == null) {
            self.search_state = zithril.TextInputState.init(&self.search_buf);
        }
        return &self.search_state.?;
    }

    fn visibleItems(self: *const State) []const []const u8 {
        if (self.src_expanded and self.docs_expanded) return &tree_order_all;
        if (self.src_expanded) return &tree_order_src_only;
        if (self.docs_expanded) return &tree_order_docs_only;
        return &tree_order_none;
    }

    fn selectedKey(self: *const State) []const u8 {
        const items = self.visibleItems();
        return if (self.tree_selected < items.len) items[self.tree_selected] else "src/";
    }

    fn moveTree(self: *State, delta: i32) void {
        const max = self.visibleItems().len;
        if (delta > 0) {
            self.tree_selected = @min(self.tree_selected + 1, max - 1);
        } else if (self.tree_selected > 0) {
            self.tree_selected -= 1;
        }
    }
};

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            if (state.show_menu) {
                switch (key.code) {
                    .escape => { state.show_menu = false; return .none; },
                    .char => |c| if (c == 'j' or c == 'k') { menuNav(state, c == 'j'); return .none; },
                    .down => { menuNav(state, true); return .none; },
                    .up => { menuNav(state, false); return .none; },
                    else => {},
                }
            }

            switch (key.code) {
                .char => |c| {
                    if (c == 'q') return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;
                    if (c >= '1' and c <= '3') { state.active_tab = c - '1'; return .none; }
                    if (c == 'm') { state.show_menu = !state.show_menu; return .none; }

                    switch (state.focus) {
                        .tree => {
                            if (c == 'j') state.moveTree(1);
                            if (c == 'k') state.moveTree(-1);
                        },
                        .search => state.getSearchState().handleKey(key),
                        .preview => {},
                    }
                },
                .tab => { state.focus = switch (state.focus) { .tree => .search, .search => .preview, .preview => .tree }; return .none; },
                .enter => {
                    if (state.focus == .tree) {
                        const key_name = state.selectedKey();
                        if (std.mem.eql(u8, key_name, "src/")) state.src_expanded = !state.src_expanded;
                        if (std.mem.eql(u8, key_name, "docs/")) state.docs_expanded = !state.docs_expanded;
                    }
                },
                .down => if (state.focus == .tree) state.moveTree(1),
                .up => if (state.focus == .tree) state.moveTree(-1),
                else => if (state.focus == .search) state.getSearchState().handleKey(key),
            }
        },
        else => {},
    }
    return .none;
}

fn menuNav(state: *State, down: bool) void {
    const current = state.menu_state.path[0];
    if (down) {
        state.menu_state.path[0] = @min(current + 1, 3);
    } else if (current > 0) {
        state.menu_state.path[0] = current - 1;
    }
}

fn focusBorderStyle(focused: bool) zithril.Style {
    return if (focused) zithril.Style.init().fg(.yellow).bold() else zithril.Style.init().fg(.cyan);
}

fn view(state: *State, frame: *FrameType) void {
    const area = frame.size();
    const main = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
    });
    const content = zithril.layout(main.get(1), .horizontal, &.{
        zithril.Constraint.ratio(1, 3),
        zithril.Constraint.ratio(2, 3),
    });

    renderTabs(state, frame, main.get(0));
    renderTree(state, frame, content.get(0));
    renderPreview(state, frame, content.get(1));
    renderSearch(state, frame, main.get(2));
    renderStatus(state, frame, main.get(3));

    if (state.show_menu) renderMenu(state, frame);
}

fn renderTabs(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .border = .rounded, .border_style = zithril.Style.init().fg(.cyan) };
    frame.render(block, area);
    frame.render(zithril.Tabs{
        .titles = &.{ "Files", "Search", "Recent" },
        .selected = state.active_tab,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bold().fg(.yellow).bg(.blue),
        .divider = " | ",
    }, block.inner(area));
}

fn renderTree(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .title = " File Tree ", .border = .rounded, .border_style = focusBorderStyle(state.focus == .tree) };
    frame.render(block, area);

    const FileTree = zithril.Tree([]const u8);
    const Item = zithril.TreeItem([]const u8);

    const src_children = [_]Item{
        .{ .data = "main.zig", .children = &.{} },
        .{ .data = "lib.zig", .children = &.{} },
    };
    const docs_children = [_]Item{
        .{ .data = "README.md", .children = &.{} },
    };
    const tree_items = [_]Item{
        .{ .data = "src/", .expanded = state.src_expanded, .children = &src_children },
        .{ .data = "docs/", .expanded = state.docs_expanded, .children = &docs_children },
        .{ .data = "build.zig", .children = &.{} },
    };

    frame.render(FileTree{
        .items = &tree_items,
        .selected = state.tree_selected,
        .offset = state.tree_offset,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white).bold(),
        .indent = 2,
        .render_fn = &struct {
            fn f(data: []const u8) []const u8 { return data; }
        }.f,
        .symbols = .{},
    }, block.inner(area));
}

fn renderPreview(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .title = " Preview ", .border = .rounded, .border_style = focusBorderStyle(state.focus == .preview) };
    frame.render(block, area);
    const inner = block.inner(area);

    const entry = file_entries.get(state.selectedKey());
    if (entry) |e| {
        if (e.is_code) {
            frame.render(zithril.CodeEditor{
                .content = e.content,
                .language = .zig,
                .theme = zithril.CodeEditorTheme.default,
                .show_line_numbers = true,
                .current_line = null,
                .scroll_offset = 0,
                .style = zithril.Style.empty,
            }, inner);
        } else {
            frame.render(zithril.Paragraph{
                .text = e.content,
                .style = zithril.Style.init().fg(.white),
                .wrap = .word,
            }, inner);
        }
    } else {
        frame.render(zithril.Paragraph{
            .text = "No file selected",
            .style = zithril.Style.init().fg(.bright_black),
            .wrap = .word,
        }, inner);
    }
}

fn renderSearch(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .title = " Search ", .border = .rounded, .border_style = focusBorderStyle(state.focus == .search) };
    frame.render(block, area);
    frame.render(zithril.TextInput{
        .state = state.getSearchState(),
        .style = zithril.Style.init().fg(.white),
        .cursor_style = zithril.Style.init().reverse(),
        .placeholder = "Type to search files...",
        .placeholder_style = zithril.Style.init().fg(.bright_black),
    }, block.inner(area));
}

fn renderStatus(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{ .border = .rounded, .border_style = zithril.Style.init().fg(.cyan) };
    frame.render(block, area);

    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "Files: 5 | Dirs: 2 | Selected: {s} | Focus: {s} | [Tab] cycle | [m] menu | [q] quit", .{ state.selectedKey(), @tagName(state.focus) }) catch "Status";
    frame.render(zithril.Paragraph{ .text = text, .style = zithril.Style.init().fg(.white), .wrap = .none }, block.inner(area));
}

fn renderMenu(state: *State, frame: *FrameType) void {
    const menu_items = [_]zithril.MenuItem{
        .{ .label = "Open", .shortcut = "Enter" },
        .{ .label = "Copy", .shortcut = "c" },
        .{ .separator = true },
        .{ .label = "Delete", .shortcut = "d", .enabled = false },
    };

    const menu = zithril.Menu{
        .items = &menu_items,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white),
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    menu.render(zithril.Rect.init(25, 8, 28, 8), frame.buffer, state.menu_state);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var state = State{};
    var app = zithril.App(State).init(.{
        .state = &state,
        .update = update,
        .view = view,
    });
    try app.run(gpa.allocator());
}

pub const panic = zithril.terminal_panic;
