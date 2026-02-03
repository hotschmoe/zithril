// Terminal graphics protocol support for zithril TUI framework
// Provides detection and rendering for:
// - Sixel graphics (DEC VT340+, xterm, mlterm)
// - Kitty graphics protocol (kitty terminal)
// - iTerm2 inline images (iTerm2, WezTerm)
//
// Usage:
//   1. Detect terminal capabilities with GraphicsCapabilities.detect()
//   2. Check which protocol is supported
//   3. Use the appropriate encoder to generate escape sequences
//   4. Write sequences to terminal output

const std = @import("std");
const builtin = @import("builtin");

const is_windows = builtin.os.tag == .windows;

/// Graphics protocol types supported by terminals.
pub const GraphicsProtocol = enum {
    /// No graphics support.
    none,
    /// Sixel graphics (VT340+, xterm -ti vt340).
    sixel,
    /// Kitty graphics protocol.
    kitty,
    /// iTerm2 inline images.
    iterm2,

    /// Returns the display name of the protocol.
    pub fn name(self: GraphicsProtocol) []const u8 {
        return switch (self) {
            .none => "none",
            .sixel => "Sixel",
            .kitty => "Kitty",
            .iterm2 => "iTerm2",
        };
    }

    /// Returns the maximum theoretical resolution (protocol limit).
    pub fn maxResolution(self: GraphicsProtocol) struct { width: u32, height: u32 } {
        return switch (self) {
            .none => .{ .width = 0, .height = 0 },
            .sixel => .{ .width = 4096, .height = 4096 },
            .kitty => .{ .width = 10000, .height = 10000 },
            .iterm2 => .{ .width = 10000, .height = 10000 },
        };
    }
};

/// Graphics capabilities detected at runtime.
pub const GraphicsCapabilities = struct {
    /// Best available protocol for this terminal.
    protocol: GraphicsProtocol = .none,
    /// Whether Sixel is supported.
    sixel: bool = false,
    /// Whether Kitty graphics protocol is supported.
    kitty: bool = false,
    /// Whether iTerm2 inline images are supported.
    iterm2: bool = false,
    /// Cell width in pixels (if known).
    cell_width_px: ?u16 = null,
    /// Cell height in pixels (if known).
    cell_height_px: ?u16 = null,

    /// Detect graphics capabilities from environment.
    pub fn detect() GraphicsCapabilities {
        var caps = GraphicsCapabilities{};

        // Check for Kitty
        if (getEnv("KITTY_WINDOW_ID") != null) {
            caps.kitty = true;
            caps.protocol = .kitty;
        }

        // Check for iTerm2
        if (getEnv("ITERM_SESSION_ID") != null or getEnv("ITERM_PROFILE") != null) {
            caps.iterm2 = true;
            if (caps.protocol == .none) caps.protocol = .iterm2;
        }

        // Check for WezTerm (supports iTerm2 protocol)
        if (getEnv("WEZTERM_PANE") != null or getEnv("WEZTERM_UNIX_SOCKET") != null) {
            caps.iterm2 = true;
            caps.kitty = true;
            if (caps.protocol == .none) caps.protocol = .kitty;
        }

        // Check TERM for sixel hints
        if (getEnv("TERM")) |term| {
            if (std.mem.indexOf(u8, term, "sixel") != null or
                std.mem.indexOf(u8, term, "vt340") != null)
            {
                caps.sixel = true;
                if (caps.protocol == .none) caps.protocol = .sixel;
            }

            if (std.mem.startsWith(u8, term, "xterm")) {
                caps.sixel = true;
                if (caps.protocol == .none) caps.protocol = .sixel;
            }

            if (std.mem.startsWith(u8, term, "mlterm")) {
                caps.sixel = true;
                if (caps.protocol == .none) caps.protocol = .sixel;
            }
        }

        // Check for explicit sixel support
        if (getEnv("SIXEL_SUPPORT") != null) {
            caps.sixel = true;
            if (caps.protocol == .none) caps.protocol = .sixel;
        }

        return caps;
    }

    /// Check if any graphics protocol is available.
    pub fn hasGraphics(self: GraphicsCapabilities) bool {
        return self.protocol != .none;
    }

    /// Get the best available protocol.
    pub fn bestProtocol(self: GraphicsCapabilities) GraphicsProtocol {
        return self.protocol;
    }
};

/// Sixel graphics encoder.
/// Converts pixel data to Sixel escape sequences.
pub const SixelEncoder = struct {
    /// Color palette (up to 256 colors for standard Sixel).
    palette: [256]RGB = undefined,
    palette_size: u8 = 0,
    /// Use private color registers (better color accuracy).
    use_private_colors: bool = true,
    /// Aspect ratio hint.
    aspect_ratio: u8 = 1,

    pub const RGB = struct {
        r: u8,
        g: u8,
        b: u8,

        pub fn init(r: u8, g: u8, b: u8) RGB {
            return .{ .r = r, .g = g, .b = b };
        }

        pub fn toSixelPercent(self: RGB) struct { r: u8, g: u8, b: u8 } {
            return .{
                .r = @intCast((@as(u16, self.r) * 100) / 255),
                .g = @intCast((@as(u16, self.g) * 100) / 255),
                .b = @intCast((@as(u16, self.b) * 100) / 255),
            };
        }
    };

    /// Create a new Sixel encoder with default palette.
    pub fn init() SixelEncoder {
        var encoder = SixelEncoder{};
        encoder.initDefaultPalette();
        return encoder;
    }

    /// Initialize with a basic 16-color palette.
    pub fn initDefaultPalette(self: *SixelEncoder) void {
        const colors = [_]RGB{
            RGB.init(0, 0, 0), // Black
            RGB.init(128, 0, 0), // Maroon
            RGB.init(0, 128, 0), // Green
            RGB.init(128, 128, 0), // Olive
            RGB.init(0, 0, 128), // Navy
            RGB.init(128, 0, 128), // Purple
            RGB.init(0, 128, 128), // Teal
            RGB.init(192, 192, 192), // Silver
            RGB.init(128, 128, 128), // Gray
            RGB.init(255, 0, 0), // Red
            RGB.init(0, 255, 0), // Lime
            RGB.init(255, 255, 0), // Yellow
            RGB.init(0, 0, 255), // Blue
            RGB.init(255, 0, 255), // Fuchsia
            RGB.init(0, 255, 255), // Aqua
            RGB.init(255, 255, 255), // White
        };

        for (colors, 0..) |c, i| {
            self.palette[i] = c;
        }
        self.palette_size = 16;
    }

    /// Add a color to the palette.
    pub fn addColor(self: *SixelEncoder, color: RGB) ?u8 {
        if (self.palette_size >= 255) return null;
        self.palette[self.palette_size] = color;
        self.palette_size += 1;
        return self.palette_size - 1;
    }

    /// Find the closest color in the palette.
    pub fn findClosestColor(self: SixelEncoder, target: RGB) u8 {
        var best_idx: u8 = 0;
        var best_dist: u32 = std.math.maxInt(u32);

        for (0..self.palette_size) |i| {
            const c = self.palette[i];
            const dr = @as(i32, target.r) - @as(i32, c.r);
            const dg = @as(i32, target.g) - @as(i32, c.g);
            const db = @as(i32, target.b) - @as(i32, c.b);
            const dist: u32 = @intCast(dr * dr + dg * dg + db * db);

            if (dist < best_dist) {
                best_dist = dist;
                best_idx = @intCast(i);
            }
        }

        return best_idx;
    }

    /// Write the Sixel header escape sequence.
    pub fn writeHeader(self: SixelEncoder, writer: anytype) !void {
        // DCS (Device Control String) for Sixel
        // Format: ESC P <params> q
        // params: P1;P2;P3 where P1=aspect ratio, P2=unused, P3=horizontal grid
        const p3: u8 = if (self.use_private_colors) 0 else 1;
        try writer.print("\x1bP{d};{d};{d}q", .{ self.aspect_ratio, 0, p3 });
    }

    /// Write a color definition.
    pub fn writeColorDef(self: SixelEncoder, writer: anytype, idx: u8) !void {
        if (idx >= self.palette_size) return;
        const c = self.palette[idx];
        const pct = c.toSixelPercent();
        // Color definition: #<idx>;2;<r>;<g>;<b>
        // 2 = RGB color space
        try writer.print("#{d};2;{d};{d};{d}", .{ idx, pct.r, pct.g, pct.b });
    }

    /// Write all color definitions.
    pub fn writeAllColorDefs(self: SixelEncoder, writer: anytype) !void {
        for (0..self.palette_size) |i| {
            try self.writeColorDef(writer, @intCast(i));
        }
    }

    /// Write the Sixel footer (String Terminator).
    pub fn writeFooter(_: SixelEncoder, writer: anytype) !void {
        try writer.writeAll("\x1b\\");
    }

    /// Encode a row of sixels (6 vertical pixels).
    /// Returns the sixel character for a 6-pixel column.
    pub fn encodeSixel(bitmap: u6) u8 {
        return @as(u8, bitmap) + 63;
    }

    /// Get escape sequence for selecting a color.
    pub fn selectColor(_: SixelEncoder, writer: anytype, idx: u8) !void {
        try writer.print("#{d}", .{idx});
    }

    /// Write a graphics new line (move down 6 pixels).
    pub fn writeNewLine(_: SixelEncoder, writer: anytype) !void {
        try writer.writeByte('-');
    }

    /// Write a carriage return (move to start of current row).
    pub fn writeCR(_: SixelEncoder, writer: anytype) !void {
        try writer.writeByte('$');
    }
};

/// Kitty graphics protocol encoder.
/// Supports direct pixel data and image references.
pub const KittyEncoder = struct {
    /// Image format.
    pub const Format = enum(u8) {
        /// 24-bit RGB.
        rgb = 24,
        /// 32-bit RGBA.
        rgba = 32,
        /// PNG data.
        png = 100,
    };

    /// Transmission type.
    pub const Transmission = enum(u8) {
        /// Direct data in escape sequence.
        direct = 'd',
        /// File path.
        file = 'f',
        /// Temporary file path.
        temp_file = 't',
        /// Shared memory.
        shared_memory = 's',
    };

    /// Action to perform.
    pub const Action = enum(u8) {
        /// Transmit data.
        transmit = 't',
        /// Transmit and display.
        transmit_display = 'T',
        /// Query terminal.
        query = 'q',
        /// Display previously transmitted.
        display = 'p',
        /// Delete images.
        delete = 'd',
        /// Animate frames.
        animate = 'a',
        /// Compose frames.
        compose = 'c',
    };

    /// Image ID counter.
    next_id: u32 = 1,

    pub fn init() KittyEncoder {
        return .{};
    }

    /// Generate a unique image ID.
    pub fn nextImageId(self: *KittyEncoder) u32 {
        const id = self.next_id;
        self.next_id +|= 1;
        return id;
    }

    /// Write the start of a Kitty graphics command.
    pub fn writeCommandStart(writer: anytype, action: Action) !void {
        try writer.print("\x1b_Ga={c}", .{@intFromEnum(action)});
    }

    /// Write an image transmission command.
    pub fn writeTransmit(
        writer: anytype,
        image_id: u32,
        format: Format,
        width: u32,
        height: u32,
        more_data: bool,
    ) !void {
        try writer.print("\x1b_Ga=t,i={d},f={d},s={d},v={d}", .{
            image_id,
            @intFromEnum(format),
            width,
            height,
        });
        if (more_data) {
            try writer.writeAll(",m=1");
        }
    }

    /// Write a display command.
    pub fn writeDisplay(
        writer: anytype,
        image_id: u32,
        x: u32,
        y: u32,
        cols: ?u32,
        rows: ?u32,
    ) !void {
        try writer.print("\x1b_Ga=p,i={d},x={d},y={d}", .{ image_id, x, y });
        if (cols) |c| {
            try writer.print(",c={d}", .{c});
        }
        if (rows) |r| {
            try writer.print(",r={d}", .{r});
        }
    }

    /// Write a delete command.
    pub fn writeDelete(writer: anytype, image_id: ?u32) !void {
        if (image_id) |id| {
            try writer.print("\x1b_Ga=d,d=i,i={d}", .{id});
        } else {
            try writer.writeAll("\x1b_Ga=d,d=a");
        }
        try writeCommandEnd(writer);
    }

    /// Write base64-encoded data chunk.
    pub fn writeDataChunk(writer: anytype, data: []const u8, is_last: bool) !void {
        try writer.writeAll(";");
        try writeBase64(writer, data);
        if (!is_last) {
            try writer.writeAll(",m=1");
        }
        try writeCommandEnd(writer);
    }

    /// Write command terminator.
    pub fn writeCommandEnd(writer: anytype) !void {
        try writer.writeAll("\x1b\\");
    }
};

/// iTerm2 inline image protocol encoder.
pub const ITerm2Encoder = struct {
    /// Image options.
    pub const Options = struct {
        /// Width in cells (or auto if null).
        width: ?u32 = null,
        /// Height in cells (or auto if null).
        height: ?u32 = null,
        /// Preserve aspect ratio.
        preserve_aspect: bool = true,
        /// Whether image is inline (vs. download).
        inline_image: bool = true,
        /// Name for the image (optional).
        name: ?[]const u8 = null,
    };

    pub fn init() ITerm2Encoder {
        return .{};
    }

    /// Write an inline image command.
    pub fn writeImage(
        writer: anytype,
        data: []const u8,
        options: Options,
    ) !void {
        // OSC 1337 ; File=<args> : <base64 data> BEL
        try writer.writeAll("\x1b]1337;File=");

        // Write options
        var first = true;

        if (options.name) |n| {
            try writeParam(writer, &first, "name", n);
        }

        if (options.width) |w| {
            try writeNumParam(writer, &first, "width", w);
        }

        if (options.height) |h| {
            try writeNumParam(writer, &first, "height", h);
        }

        if (options.preserve_aspect) {
            try writeFlagParam(writer, &first, "preserveAspectRatio", true);
        }

        if (options.inline_image) {
            try writeFlagParam(writer, &first, "inline", true);
        }

        try writer.writeAll(":");

        // Write base64-encoded data
        try writeBase64(writer, data);

        // Terminate with BEL
        try writer.writeByte(0x07);
    }

    fn writeParam(writer: anytype, first: *bool, key: []const u8, value: []const u8) !void {
        if (!first.*) try writer.writeByte(';');
        first.* = false;
        try writer.writeAll(key);
        try writer.writeByte('=');
        try writer.writeAll(value);
    }

    fn writeNumParam(writer: anytype, first: *bool, key: []const u8, value: u32) !void {
        if (!first.*) try writer.writeByte(';');
        first.* = false;
        try writer.writeAll(key);
        try writer.print("={d}", .{value});
    }

    fn writeFlagParam(writer: anytype, first: *bool, key: []const u8, value: bool) !void {
        if (!first.*) try writer.writeByte(';');
        first.* = false;
        try writer.writeAll(key);
        try writer.print("={d}", .{@as(u8, if (value) 1 else 0)});
    }
};

/// Base64 encoding table.
const base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Write base64-encoded data to writer.
fn writeBase64(writer: anytype, data: []const u8) !void {
    var i: usize = 0;
    while (i + 3 <= data.len) : (i += 3) {
        const b0 = data[i];
        const b1 = data[i + 1];
        const b2 = data[i + 2];

        try writer.writeByte(base64_chars[b0 >> 2]);
        try writer.writeByte(base64_chars[((b0 & 0x03) << 4) | (b1 >> 4)]);
        try writer.writeByte(base64_chars[((b1 & 0x0F) << 2) | (b2 >> 6)]);
        try writer.writeByte(base64_chars[b2 & 0x3F]);
    }

    const remaining = data.len - i;
    if (remaining == 1) {
        const b0 = data[i];
        try writer.writeByte(base64_chars[b0 >> 2]);
        try writer.writeByte(base64_chars[(b0 & 0x03) << 4]);
        try writer.writeAll("==");
    } else if (remaining == 2) {
        const b0 = data[i];
        const b1 = data[i + 1];
        try writer.writeByte(base64_chars[b0 >> 2]);
        try writer.writeByte(base64_chars[((b0 & 0x03) << 4) | (b1 >> 4)]);
        try writer.writeByte(base64_chars[(b1 & 0x0F) << 2]);
        try writer.writeByte('=');
    }
}

/// Cross-platform environment variable getter.
fn getEnv(name: []const u8) ?[]const u8 {
    if (is_windows) {
        return std.process.getEnvVarOwned(std.heap.page_allocator, name) catch null;
    } else {
        return std.posix.getenv(name);
    }
}

// ============================================================
// SANITY TESTS - Type construction
// ============================================================

test "sanity: GraphicsProtocol enum values" {
    try std.testing.expect(GraphicsProtocol.none != GraphicsProtocol.sixel);
    try std.testing.expect(GraphicsProtocol.sixel != GraphicsProtocol.kitty);
    try std.testing.expect(GraphicsProtocol.kitty != GraphicsProtocol.iterm2);
}

test "sanity: GraphicsProtocol names" {
    try std.testing.expectEqualStrings("none", GraphicsProtocol.none.name());
    try std.testing.expectEqualStrings("Sixel", GraphicsProtocol.sixel.name());
    try std.testing.expectEqualStrings("Kitty", GraphicsProtocol.kitty.name());
    try std.testing.expectEqualStrings("iTerm2", GraphicsProtocol.iterm2.name());
}

test "sanity: GraphicsCapabilities construction" {
    const caps = GraphicsCapabilities{};
    try std.testing.expect(!caps.hasGraphics());
    try std.testing.expect(!caps.sixel);
    try std.testing.expect(!caps.kitty);
    try std.testing.expect(!caps.iterm2);
}

test "sanity: SixelEncoder construction" {
    const encoder = SixelEncoder.init();
    try std.testing.expectEqual(@as(u8, 16), encoder.palette_size);
}

test "sanity: KittyEncoder construction" {
    const encoder = KittyEncoder.init();
    try std.testing.expectEqual(@as(u32, 1), encoder.next_id);
}

test "sanity: ITerm2Encoder construction" {
    _ = ITerm2Encoder.init();
}

// ============================================================
// BEHAVIOR TESTS - Sixel encoding
// ============================================================

test "behavior: Sixel RGB to percent" {
    const white = SixelEncoder.RGB.init(255, 255, 255);
    const pct = white.toSixelPercent();
    try std.testing.expectEqual(@as(u8, 100), pct.r);
    try std.testing.expectEqual(@as(u8, 100), pct.g);
    try std.testing.expectEqual(@as(u8, 100), pct.b);

    const black = SixelEncoder.RGB.init(0, 0, 0);
    const black_pct = black.toSixelPercent();
    try std.testing.expectEqual(@as(u8, 0), black_pct.r);
    try std.testing.expectEqual(@as(u8, 0), black_pct.g);
    try std.testing.expectEqual(@as(u8, 0), black_pct.b);
}

test "behavior: Sixel character encoding" {
    try std.testing.expectEqual(@as(u8, 63), SixelEncoder.encodeSixel(@as(u6, 0)));
    try std.testing.expectEqual(@as(u8, 64), SixelEncoder.encodeSixel(@as(u6, 1)));
    try std.testing.expectEqual(@as(u8, 126), SixelEncoder.encodeSixel(@as(u6, 63)));
}

test "behavior: Sixel header format" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const encoder = SixelEncoder.init();

    try encoder.writeHeader(stream.writer());
    const written = stream.getWritten();

    try std.testing.expect(std.mem.startsWith(u8, written, "\x1bP"));
    try std.testing.expect(std.mem.indexOf(u8, written, "q") != null);
}

test "behavior: Sixel footer format" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const encoder = SixelEncoder.init();

    try encoder.writeFooter(stream.writer());
    try std.testing.expectEqualStrings("\x1b\\", stream.getWritten());
}

test "behavior: Sixel color definition format" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    var encoder = SixelEncoder.init();
    encoder.palette[0] = SixelEncoder.RGB.init(255, 0, 0);

    try encoder.writeColorDef(stream.writer(), 0);
    const written = stream.getWritten();

    try std.testing.expect(std.mem.startsWith(u8, written, "#0;2;"));
}

test "behavior: Sixel find closest color" {
    var encoder = SixelEncoder.init();
    encoder.palette[0] = SixelEncoder.RGB.init(255, 0, 0);
    encoder.palette[1] = SixelEncoder.RGB.init(0, 255, 0);
    encoder.palette_size = 2;

    const red_match = encoder.findClosestColor(SixelEncoder.RGB.init(200, 50, 50));
    const green_match = encoder.findClosestColor(SixelEncoder.RGB.init(50, 200, 50));

    try std.testing.expectEqual(@as(u8, 0), red_match);
    try std.testing.expectEqual(@as(u8, 1), green_match);
}

test "behavior: Sixel add color" {
    var encoder = SixelEncoder{};
    encoder.palette_size = 0;

    const idx = encoder.addColor(SixelEncoder.RGB.init(100, 100, 100));
    try std.testing.expect(idx != null);
    try std.testing.expectEqual(@as(u8, 0), idx.?);
    try std.testing.expectEqual(@as(u8, 1), encoder.palette_size);
}

// ============================================================
// BEHAVIOR TESTS - Kitty encoding
// ============================================================

test "behavior: Kitty image ID generation" {
    var encoder = KittyEncoder.init();
    try std.testing.expectEqual(@as(u32, 1), encoder.nextImageId());
    try std.testing.expectEqual(@as(u32, 2), encoder.nextImageId());
    try std.testing.expectEqual(@as(u32, 3), encoder.nextImageId());
}

test "behavior: Kitty command start format" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try KittyEncoder.writeCommandStart(stream.writer(), .transmit);
    try std.testing.expectEqualStrings("\x1b_Ga=t", stream.getWritten());
}

test "behavior: Kitty command end format" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try KittyEncoder.writeCommandEnd(stream.writer());
    try std.testing.expectEqualStrings("\x1b\\", stream.getWritten());
}

test "behavior: Kitty delete command format" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try KittyEncoder.writeDelete(stream.writer(), 42);
    const written = stream.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, written, "a=d") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "i=42") != null);
}

// ============================================================
// BEHAVIOR TESTS - iTerm2 encoding
// ============================================================

test "behavior: iTerm2 image header format" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try ITerm2Encoder.writeImage(stream.writer(), "test", .{
        .width = 10,
        .height = 20,
    });
    const written = stream.getWritten();

    try std.testing.expect(std.mem.startsWith(u8, written, "\x1b]1337;File="));
    try std.testing.expect(written[written.len - 1] == 0x07);
}

// ============================================================
// BEHAVIOR TESTS - Base64 encoding
// ============================================================

test "behavior: base64 encoding empty" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try writeBase64(stream.writer(), "");
    try std.testing.expectEqualStrings("", stream.getWritten());
}

test "behavior: base64 encoding single byte" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try writeBase64(stream.writer(), "M");
    try std.testing.expectEqualStrings("TQ==", stream.getWritten());
}

test "behavior: base64 encoding two bytes" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try writeBase64(stream.writer(), "Ma");
    try std.testing.expectEqualStrings("TWE=", stream.getWritten());
}

test "behavior: base64 encoding three bytes" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try writeBase64(stream.writer(), "Man");
    try std.testing.expectEqualStrings("TWFu", stream.getWritten());
}

test "behavior: base64 encoding longer string" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try writeBase64(stream.writer(), "Hello");
    try std.testing.expectEqualStrings("SGVsbG8=", stream.getWritten());
}

// ============================================================
// BEHAVIOR TESTS - GraphicsCapabilities
// ============================================================

test "behavior: GraphicsCapabilities.detect returns valid struct" {
    const caps = GraphicsCapabilities.detect();
    _ = caps.bestProtocol();
    _ = caps.hasGraphics();
}

test "behavior: GraphicsProtocol maxResolution" {
    const none_res = GraphicsProtocol.none.maxResolution();
    try std.testing.expectEqual(@as(u32, 0), none_res.width);
    try std.testing.expectEqual(@as(u32, 0), none_res.height);

    const sixel_res = GraphicsProtocol.sixel.maxResolution();
    try std.testing.expect(sixel_res.width > 0);
    try std.testing.expect(sixel_res.height > 0);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Sixel encoder palette full" {
    var encoder = SixelEncoder{};
    encoder.palette_size = 255;

    const result = encoder.addColor(SixelEncoder.RGB.init(0, 0, 0));
    try std.testing.expect(result == null);
}

test "regression: Sixel find color with empty palette" {
    var encoder = SixelEncoder{};
    encoder.palette_size = 1;
    encoder.palette[0] = SixelEncoder.RGB.init(128, 128, 128);

    const idx = encoder.findClosestColor(SixelEncoder.RGB.init(0, 0, 0));
    try std.testing.expectEqual(@as(u8, 0), idx);
}

test "regression: Kitty ID overflow" {
    var encoder = KittyEncoder{};
    encoder.next_id = std.math.maxInt(u32);
    const id = encoder.nextImageId();
    try std.testing.expectEqual(std.math.maxInt(u32), id);
}

test "regression: Sixel writeColorDef out of bounds" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    var encoder = SixelEncoder{};
    encoder.palette_size = 5;

    try encoder.writeColorDef(stream.writer(), 10);
    try std.testing.expectEqual(@as(usize, 0), stream.getWritten().len);
}
