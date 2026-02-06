const std = @import("std");
pub const rich_zig = @import("rich_zig");

pub const AdaptiveColor = rich_zig.AdaptiveColor;
pub const ColorTriplet = rich_zig.ColorTriplet;
pub const Color = rich_zig.Color;
pub const ColorSystem = rich_zig.ColorSystem;
pub const WcagLevel = ColorTriplet.WcagLevel;
pub const gradient = rich_zig.gradient;
pub const BackgroundMode = rich_zig.BackgroundMode;

test "sanity: AdaptiveColor can be created" {
    const ac = AdaptiveColor.fromRgb(255, 100, 50);
    const resolved = ac.resolve(.truecolor);
    try std.testing.expect(resolved.triplet != null);
}

test "sanity: AdaptiveColor with explicit fallbacks" {
    const ac = AdaptiveColor.init(
        Color.fromRgb(255, 100, 50),
        Color.from256(208),
        Color.yellow,
    );
    _ = ac.resolve(.standard);
    _ = ac.resolve(.eight_bit);
    _ = ac.resolve(.truecolor);
}

// ============================================================
// BEHAVIOR TESTS - HSL color space
// ============================================================

test "behavior: ColorTriplet HSL round-trip" {
    const original = ColorTriplet{ .r = 200, .g = 100, .b = 50 };
    const hsl = original.toHsl();
    const recovered = ColorTriplet.fromHsl(hsl.h, hsl.s, hsl.l);
    try std.testing.expect(@abs(@as(i16, original.r) - @as(i16, recovered.r)) <= 1);
    try std.testing.expect(@abs(@as(i16, original.g) - @as(i16, recovered.g)) <= 1);
    try std.testing.expect(@abs(@as(i16, original.b) - @as(i16, recovered.b)) <= 1);
}

test "behavior: blendHsl red to green goes through yellow" {
    const red = ColorTriplet{ .r = 255, .g = 0, .b = 0 };
    const green = ColorTriplet{ .r = 0, .g = 255, .b = 0 };
    const mid = ColorTriplet.blendHsl(red, green, 0.5);
    try std.testing.expect(mid.r > 100);
    try std.testing.expect(mid.g > 100);
    try std.testing.expect(mid.b < 50);
}

// ============================================================
// BEHAVIOR TESTS - Gradient
// ============================================================

test "behavior: gradient produces correct endpoints" {
    const stops = [_]ColorTriplet{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
    };
    var output: [5]ColorTriplet = undefined;
    gradient(&stops, &output, false);
    try std.testing.expectEqual(@as(u8, 255), output[0].r);
    try std.testing.expectEqual(@as(u8, 255), output[4].b);
}

test "behavior: gradient with HSL mode" {
    const stops = [_]ColorTriplet{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
    };
    var output: [3]ColorTriplet = undefined;
    gradient(&stops, &output, true);
    try std.testing.expect(output[1].r > 100);
    try std.testing.expect(output[1].g > 100);
}

// ============================================================
// BEHAVIOR TESTS - WCAG contrast
// ============================================================

test "behavior: contrastRatio black on white" {
    const black = ColorTriplet{ .r = 0, .g = 0, .b = 0 };
    const white = ColorTriplet{ .r = 255, .g = 255, .b = 255 };
    const ratio = black.contrastRatio(white);
    try std.testing.expect(ratio > 20.5 and ratio < 21.5);
}

test "behavior: contrastRatio same color is 1" {
    const c = ColorTriplet{ .r = 128, .g = 128, .b = 128 };
    const ratio = c.contrastRatio(c);
    try std.testing.expect(ratio > 0.99 and ratio < 1.01);
}

test "behavior: wcagLevel black on white is aaa" {
    const black = ColorTriplet{ .r = 0, .g = 0, .b = 0 };
    const white = ColorTriplet{ .r = 255, .g = 255, .b = 255 };
    try std.testing.expectEqual(WcagLevel.aaa, black.wcagLevel(white));
}

test "behavior: luminance of black is near 0" {
    const black = ColorTriplet{ .r = 0, .g = 0, .b = 0 };
    try std.testing.expect(black.luminance() < 0.01);
}

test "behavior: luminance of white is near 1" {
    const white = ColorTriplet{ .r = 255, .g = 255, .b = 255 };
    try std.testing.expect(white.luminance() > 0.99);
}
