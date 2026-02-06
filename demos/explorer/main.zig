const std = @import("std");
const zithril = @import("zithril");

const FrameType = zithril.Frame(zithril.App(State).DefaultMaxWidgets);

const Focus = enum {
    tree,
    preview,
    search,
};

const State = struct {
    active_tab: usize = 0,
    tree_selected: ?usize = 0,
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
};

fn update(state: *State, event: zithril.Event) zithril.Action {
    switch (event) {
        .key => |key| {
            // Escape to close menu
            if (state.show_menu) {
                switch (key.code) {
                    .escape => {
                        state.show_menu = false;
                        return .none;
                    },
                    .char => |c| {
                        if (c == 'j') {
                            const current = state.menu_state.path[0];
                            state.menu_state.path[0] = @min(current + 1, 3);
                            return .none;
                        } else if (c == 'k') {
                            const current = state.menu_state.path[0];
                            if (current > 0) {
                                state.menu_state.path[0] = current - 1;
                            }
                            return .none;
                        }
                    },
                    .down => {
                        const current = state.menu_state.path[0];
                        state.menu_state.path[0] = @min(current + 1, 3);
                        return .none;
                    },
                    .up => {
                        const current = state.menu_state.path[0];
                        if (current > 0) {
                            state.menu_state.path[0] = current - 1;
                        }
                        return .none;
                    },
                    else => {},
                }
            }

            // Global key handling
            switch (key.code) {
                .char => |c| {
                    // Quit commands
                    if (c == 'q') return .quit;
                    if (c == 'c' and key.modifiers.ctrl) return .quit;

                    // Tab switching with number keys
                    if (c == '1') {
                        state.active_tab = 0;
                        return .none;
                    } else if (c == '2') {
                        state.active_tab = 1;
                        return .none;
                    } else if (c == '3') {
                        state.active_tab = 2;
                        return .none;
                    } else if (c == 'm') {
                        state.show_menu = !state.show_menu;
                        return .none;
                    }

                    // Focus-specific char handling
                    switch (state.focus) {
                        .tree => {
                            const max_items = countVisibleTreeItems(state);
                            if (c == 'j') {
                                if (state.tree_selected) |sel| {
                                    if (sel < max_items - 1) {
                                        state.tree_selected = sel + 1;
                                    }
                                }
                            } else if (c == 'k') {
                                if (state.tree_selected) |sel| {
                                    if (sel > 0) {
                                        state.tree_selected = sel - 1;
                                    }
                                }
                            }
                        },
                        .search => {
                            state.getSearchState().handleKey(key);
                        },
                        .preview => {},
                    }
                },
                .tab => {
                    state.focus = switch (state.focus) {
                        .tree => .search,
                        .search => .preview,
                        .preview => .tree,
                    };
                    return .none;
                },
                .enter => {
                    if (state.focus == .tree) {
                        if (state.tree_selected) |sel| {
                            const item_idx = getTreeItemIndex(sel, state);
                            if (item_idx == 0) {
                                state.src_expanded = !state.src_expanded;
                            } else if (item_idx == 1) {
                                state.docs_expanded = !state.docs_expanded;
                            }
                        }
                    }
                },
                .up => {
                    if (state.focus == .tree) {
                        if (state.tree_selected) |sel| {
                            if (sel > 0) {
                                state.tree_selected = sel - 1;
                            }
                        }
                    }
                },
                .down => {
                    if (state.focus == .tree) {
                        const max_items = countVisibleTreeItems(state);
                        if (state.tree_selected) |sel| {
                            if (sel < max_items - 1) {
                                state.tree_selected = sel + 1;
                            }
                        }
                    }
                },
                .escape => {
                    if (state.focus == .search) {
                        state.getSearchState().handleKey(key);
                    }
                },
                else => {
                    if (state.focus == .search) {
                        state.getSearchState().handleKey(key);
                    }
                },
            }
        },
        else => {},
    }

    return .none;
}

fn countVisibleTreeItems(state: *State) usize {
    var count: usize = 1; // src/
    if (state.src_expanded) count += 2; // main.zig, lib.zig
    count += 1; // docs/
    if (state.docs_expanded) count += 1; // README.md
    count += 1; // build.zig
    return count;
}

fn getTreeItemIndex(visible_idx: usize, state: *State) usize {
    // Map visible index to logical tree item index
    var current: usize = 0;
    if (visible_idx == current) return 0; // src/
    current += 1;

    if (state.src_expanded) {
        if (visible_idx == current) return 10; // main.zig
        current += 1;
        if (visible_idx == current) return 11; // lib.zig
        current += 1;
    }

    if (visible_idx == current) return 1; // docs/
    current += 1;

    if (state.docs_expanded) {
        if (visible_idx == current) return 12; // README.md
        current += 1;
    }

    if (visible_idx == current) return 2; // build.zig

    return 0;
}

fn view(state: *State, frame: *FrameType) void {
    const area = frame.size();

    // Main layout: tabs, content, search, status
    const main_chunks = zithril.layout(area, .vertical, &.{
        zithril.Constraint.len(3),
        zithril.Constraint.flexible(1),
        zithril.Constraint.len(3),
        zithril.Constraint.len(3),
    });

    // Render tabs
    renderTabs(state, frame, main_chunks.get(0));

    // Content area: tree + preview split
    const content = main_chunks.get(1);
    const content_chunks = zithril.layout(content, .horizontal, &.{
        zithril.Constraint.ratio(1, 3),
        zithril.Constraint.ratio(2, 3),
    });

    renderTree(state, frame, content_chunks.get(0));
    renderPreview(state, frame, content_chunks.get(1));

    // Render search bar
    renderSearch(state, frame, main_chunks.get(2));

    // Render status bar
    renderStatus(state, frame, main_chunks.get(3));

    // Overlay menu if visible
    if (state.show_menu) {
        renderMenu(state, frame, area);
    }
}

fn renderTabs(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    const inner = block.inner(area);
    frame.render(block, area);

    const tabs = zithril.Tabs{
        .titles = &.{ "Files", "Search", "Recent" },
        .selected = state.active_tab,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bold().fg(.yellow).bg(.blue),
        .divider = " | ",
    };
    frame.render(tabs, inner);
}

fn renderTree(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const border_style = if (state.focus == .tree)
        zithril.Style.init().fg(.yellow).bold()
    else
        zithril.Style.init().fg(.cyan);

    const block = zithril.Block{
        .title = " File Tree ",
        .border = .rounded,
        .border_style = border_style,
    };
    const inner = block.inner(area);
    frame.render(block, area);

    // Build tree structure
    const FileTree = zithril.Tree([]const u8);
    const FileTreeItem = zithril.TreeItem([]const u8);

    const src_children = [_]FileTreeItem{
        .{ .data = "main.zig", .children = &.{} },
        .{ .data = "lib.zig", .children = &.{} },
    };

    const docs_children = [_]FileTreeItem{
        .{ .data = "README.md", .children = &.{} },
    };

    const tree_items = [_]FileTreeItem{
        .{ .data = "src/", .expanded = state.src_expanded, .children = &src_children },
        .{ .data = "docs/", .expanded = state.docs_expanded, .children = &docs_children },
        .{ .data = "build.zig", .children = &.{} },
    };

    const tree = FileTree{
        .items = &tree_items,
        .selected = state.tree_selected,
        .offset = state.tree_offset,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white).bold(),
        .indent = 2,
        .render_fn = &renderFileName,
        .symbols = .{},
    };

    frame.render(tree, inner);
}

fn renderFileName(data: []const u8) []const u8 {
    return data;
}

fn renderPreview(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const border_style = if (state.focus == .preview)
        zithril.Style.init().fg(.yellow).bold()
    else
        zithril.Style.init().fg(.cyan);

    const block = zithril.Block{
        .title = " Preview ",
        .border = .rounded,
        .border_style = border_style,
    };
    const inner = block.inner(area);
    frame.render(block, area);

    if (state.tree_selected) |sel| {
        const item_idx = getTreeItemIndex(sel, state);
        const content = getPreviewContent(item_idx);
        const is_code = isCodeFile(item_idx);

        if (is_code) {
            const editor = zithril.CodeEditor{
                .content = content,
                .language = .zig,
                .theme = zithril.CodeEditorTheme.default,
                .show_line_numbers = true,
                .current_line = null,
                .scroll_offset = 0,
                .style = zithril.Style.empty,
            };
            frame.render(editor, inner);
        } else {
            const para = zithril.Paragraph{
                .text = content,
                .style = zithril.Style.init().fg(.white),
                .wrap = .word,
            };
            frame.render(para, inner);
        }
    } else {
        const para = zithril.Paragraph{
            .text = "No file selected",
            .style = zithril.Style.init().fg(.bright_black),
            .wrap = .word,
        };
        frame.render(para, inner);
    }
}

fn isCodeFile(item_idx: usize) bool {
    return item_idx == 10 or item_idx == 11 or item_idx == 2;
}

fn getPreviewContent(item_idx: usize) []const u8 {
    return switch (item_idx) {
        0 => "Directory: src/\nContains Zig source files for the project.",
        10 =>
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    const stdout = std.io.getStdOut().writer();
        \\    try stdout.print("Hello, {s}!\n", .{"World"});
        \\}
        ,
        11 =>
        \\const std = @import("std");
        \\
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\
        \\pub fn multiply(a: i32, b: i32) i32 {
        \\    return a * b;
        \\}
        \\
        \\test "add function" {
        \\    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
        \\}
        ,
        1 => "Directory: docs/\nContains project documentation and guides.",
        12 =>
        \\# Project Documentation
        \\
        \\Welcome to the file explorer demo!
        \\
        \\## Features
        \\- Interactive tree navigation
        \\- Code preview with syntax highlighting
        \\- Search functionality
        \\- Multiple view modes
        \\
        \\## Controls
        \\- j/k or arrow keys: navigate
        \\- Tab: cycle focus
        \\- Enter: expand/collapse folders
        \\- m: toggle context menu
        \\- 1/2/3: switch tabs
        \\- q: quit
        ,
        2 =>
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "explorer",
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\
        \\    b.installArtifact(exe);
        \\}
        ,
        else => "Unknown item",
    };
}

fn renderSearch(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const border_style = if (state.focus == .search)
        zithril.Style.init().fg(.yellow).bold()
    else
        zithril.Style.init().fg(.cyan);

    const block = zithril.Block{
        .title = " Search ",
        .border = .rounded,
        .border_style = border_style,
    };
    const inner = block.inner(area);
    frame.render(block, area);

    const input = zithril.TextInput{
        .state = state.getSearchState(),
        .style = zithril.Style.init().fg(.white),
        .cursor_style = zithril.Style.init().reverse(),
        .placeholder = "Type to search files...",
        .placeholder_style = zithril.Style.init().fg(.bright_black),
    };
    frame.render(input, inner);
}

fn renderStatus(state: *State, frame: *FrameType, area: zithril.Rect) void {
    const block = zithril.Block{
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };
    const inner = block.inner(area);
    frame.render(block, area);

    const selected_name = if (state.tree_selected) |sel| blk: {
        const idx = getTreeItemIndex(sel, state);
        break :blk getItemName(idx);
    } else "none";

    var status_buf: [128]u8 = undefined;
    const status_text = std.fmt.bufPrint(&status_buf, "Files: 5 | Dirs: 2 | Selected: {s} | Focus: {s} | [Tab] cycle | [m] menu | [q] quit", .{ selected_name, @tagName(state.focus) }) catch "Status";

    const para = zithril.Paragraph{
        .text = status_text,
        .style = zithril.Style.init().fg(.white),
        .wrap = .none,
    };
    frame.render(para, inner);
}

fn getItemName(item_idx: usize) []const u8 {
    return switch (item_idx) {
        0 => "src/",
        10 => "main.zig",
        11 => "lib.zig",
        1 => "docs/",
        12 => "README.md",
        2 => "build.zig",
        else => "unknown",
    };
}

fn renderMenu(state: *State, frame: *FrameType, area: zithril.Rect) void {
    _ = area;

    const menu_items = [_]zithril.MenuItem{
        .{ .label = "Open", .shortcut = "Enter" },
        .{ .label = "Copy", .shortcut = "c" },
        .{ .separator = true },
        .{ .label = "Delete", .shortcut = "d", .enabled = false },
    };

    const menu_area = zithril.Rect.init(25, 8, 28, 8);

    const menu = zithril.Menu{
        .items = &menu_items,
        .style = zithril.Style.init().fg(.white),
        .highlight_style = zithril.Style.init().bg(.blue).fg(.white),
        .border = .rounded,
        .border_style = zithril.Style.init().fg(.cyan),
    };

    menu.render(menu_area, frame.buffer, state.menu_state);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = State{};

    var app = zithril.App(State).init(.{
        .state = &state,
        .update = update,
        .view = view,
    });

    try app.run(allocator);
}

pub const panic = zithril.terminal_panic;
