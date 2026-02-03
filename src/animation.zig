// Animation helpers for zithril TUI framework
// Provides easing functions, duration tracking, and frame interpolation
// for smooth animations driven by tick events.
//
// Usage:
//   1. Create an Animation with a duration and easing function
//   2. Call update(delta_ms) each tick to advance the animation
//   3. Use progress() or value() to get the current interpolated value
//   4. Check isComplete() to know when to stop

const std = @import("std");

/// Easing functions for animation curves.
/// All functions map input [0.0, 1.0] to output [0.0, 1.0].
pub const Easing = enum {
    /// Constant velocity (no acceleration).
    linear,

    /// Slow start, accelerating.
    ease_in,

    /// Slow end, decelerating.
    ease_out,

    /// Slow start and end.
    ease_in_out,

    /// Quadratic ease in (t^2).
    quad_in,

    /// Quadratic ease out.
    quad_out,

    /// Quadratic ease in-out.
    quad_in_out,

    /// Cubic ease in (t^3).
    cubic_in,

    /// Cubic ease out.
    cubic_out,

    /// Cubic ease in-out.
    cubic_in_out,

    /// Elastic bounce at end.
    elastic_out,

    /// Overshoot and settle back.
    back_out,

    /// Multiple bounces at end.
    bounce_out,

    /// Apply the easing function to a progress value [0.0, 1.0].
    pub fn apply(self: Easing, t: f32) f32 {
        const clamped = @min(1.0, @max(0.0, t));
        return switch (self) {
            .linear => clamped,
            .ease_in => easeInCubic(clamped),
            .ease_out => easeOutCubic(clamped),
            .ease_in_out => easeInOutCubic(clamped),
            .quad_in => clamped * clamped,
            .quad_out => 1.0 - (1.0 - clamped) * (1.0 - clamped),
            .quad_in_out => quadInOut(clamped),
            .cubic_in => easeInCubic(clamped),
            .cubic_out => easeOutCubic(clamped),
            .cubic_in_out => easeInOutCubic(clamped),
            .elastic_out => elasticOut(clamped),
            .back_out => backOut(clamped),
            .bounce_out => bounceOut(clamped),
        };
    }

    fn easeInCubic(t: f32) f32 {
        return t * t * t;
    }

    fn easeOutCubic(t: f32) f32 {
        const u = 1.0 - t;
        return 1.0 - u * u * u;
    }

    fn easeInOutCubic(t: f32) f32 {
        if (t < 0.5) {
            return 4.0 * t * t * t;
        } else {
            const u = -2.0 * t + 2.0;
            return 1.0 - u * u * u / 2.0;
        }
    }

    fn quadInOut(t: f32) f32 {
        if (t < 0.5) {
            return 2.0 * t * t;
        } else {
            return 1.0 - (-2.0 * t + 2.0) * (-2.0 * t + 2.0) / 2.0;
        }
    }

    fn elasticOut(t: f32) f32 {
        if (t == 0.0) return 0.0;
        if (t == 1.0) return 1.0;

        const c4 = (2.0 * std.math.pi) / 3.0;
        return std.math.pow(f32, 2.0, -10.0 * t) * @sin((t * 10.0 - 0.75) * c4) + 1.0;
    }

    fn backOut(t: f32) f32 {
        const c1: f32 = 1.70158;
        const c3 = c1 + 1.0;
        const u = t - 1.0;
        return 1.0 + c3 * u * u * u + c1 * u * u;
    }

    fn bounceOut(t: f32) f32 {
        const n1: f32 = 7.5625;
        const d1: f32 = 2.75;

        if (t < 1.0 / d1) {
            return n1 * t * t;
        } else if (t < 2.0 / d1) {
            const adjusted = t - 1.5 / d1;
            return n1 * adjusted * adjusted + 0.75;
        } else if (t < 2.5 / d1) {
            const adjusted = t - 2.25 / d1;
            return n1 * adjusted * adjusted + 0.9375;
        } else {
            const adjusted = t - 2.625 / d1;
            return n1 * adjusted * adjusted + 0.984375;
        }
    }
};

/// Animation state tracker.
/// Manages timing and progress for a single animation.
pub const Animation = struct {
    /// Total duration in milliseconds.
    duration_ms: u32,
    /// Elapsed time in milliseconds.
    elapsed_ms: u32 = 0,
    /// Easing function to use.
    easing: Easing = .linear,
    /// Whether to loop the animation.
    looping: bool = false,
    /// Whether the animation is paused.
    paused: bool = false,
    /// Direction for ping-pong animations (true = forward).
    forward: bool = true,

    /// Create a new animation with the given duration.
    pub fn init(duration_ms: u32) Animation {
        return .{ .duration_ms = duration_ms };
    }

    /// Create an animation with duration and easing.
    pub fn initWithEasing(duration_ms: u32, easing: Easing) Animation {
        return .{ .duration_ms = duration_ms, .easing = easing };
    }

    /// Update the animation by the given delta time.
    /// Returns true if the animation is still active.
    pub fn update(self: *Animation, delta_ms: u32) bool {
        if (self.paused) return !self.isComplete();

        self.elapsed_ms +|= delta_ms;

        if (self.looping and self.elapsed_ms >= self.duration_ms) {
            self.elapsed_ms = self.elapsed_ms % self.duration_ms;
        }

        return !self.isComplete();
    }

    /// Get the raw progress (0.0 to 1.0) without easing.
    pub fn rawProgress(self: Animation) f32 {
        if (self.duration_ms == 0) return 1.0;
        const raw_t = @as(f32, @floatFromInt(self.elapsed_ms)) /
            @as(f32, @floatFromInt(self.duration_ms));
        return @min(1.0, raw_t);
    }

    /// Get the eased progress (0.0 to 1.0).
    pub fn progress(self: Animation) f32 {
        return self.easing.apply(self.rawProgress());
    }

    /// Interpolate a value between start and end based on current progress.
    pub fn value(self: Animation, start: f32, end: f32) f32 {
        return lerp(start, end, self.progress());
    }

    /// Interpolate an integer value between start and end.
    pub fn valueInt(self: Animation, start: i32, end: i32) i32 {
        const t = self.progress();
        const result = @as(f32, @floatFromInt(start)) * (1.0 - t) +
            @as(f32, @floatFromInt(end)) * t;
        return @intFromFloat(@round(result));
    }

    /// Interpolate a u16 value (common for positions).
    pub fn valueU16(self: Animation, start: u16, end: u16) u16 {
        const t = self.progress();
        const s = @as(f32, @floatFromInt(start));
        const e = @as(f32, @floatFromInt(end));
        const result = s * (1.0 - t) + e * t;
        return @intFromFloat(@max(0.0, @round(result)));
    }

    /// Check if the animation has completed.
    pub fn isComplete(self: Animation) bool {
        if (self.looping) return false;
        return self.elapsed_ms >= self.duration_ms;
    }

    /// Reset the animation to the beginning.
    pub fn reset(self: *Animation) void {
        self.elapsed_ms = 0;
        self.forward = true;
    }

    /// Pause the animation.
    pub fn pause(self: *Animation) void {
        self.paused = true;
    }

    /// Resume the animation.
    pub fn unpause(self: *Animation) void {
        self.paused = false;
    }

    /// Toggle pause state.
    pub fn togglePause(self: *Animation) void {
        self.paused = !self.paused;
    }

    /// Set the animation to loop.
    pub fn setLooping(self: *Animation, looping: bool) Animation {
        self.looping = looping;
        return self.*;
    }
};

/// Keyframe for multi-step animations.
pub const Keyframe = struct {
    /// Value at this keyframe.
    value: f32,
    /// Time position (0.0 to 1.0).
    time: f32,
    /// Easing to use until next keyframe.
    easing: Easing = .linear,
};

/// Multi-keyframe animation sequence.
pub fn KeyframeAnimation(comptime max_keyframes: usize) type {
    return struct {
        const Self = @This();

        keyframes: [max_keyframes]Keyframe = undefined,
        count: usize = 0,
        duration_ms: u32,
        elapsed_ms: u32 = 0,
        looping: bool = false,

        /// Create a new keyframe animation.
        pub fn init(duration_ms: u32) Self {
            return .{ .duration_ms = duration_ms };
        }

        /// Add a keyframe at the specified time position.
        pub fn addKeyframe(self: *Self, time: f32, val: f32, ease: Easing) bool {
            if (self.count >= max_keyframes) return false;
            self.keyframes[self.count] = .{
                .time = time,
                .value = val,
                .easing = ease,
            };
            self.count += 1;
            return true;
        }

        /// Update the animation.
        pub fn update(self: *Self, delta_ms: u32) bool {
            self.elapsed_ms +|= delta_ms;

            if (self.looping and self.elapsed_ms >= self.duration_ms) {
                self.elapsed_ms = self.elapsed_ms % self.duration_ms;
            }

            return !self.isComplete();
        }

        /// Get the current interpolated value.
        pub fn value(self: Self) f32 {
            if (self.count == 0) return 0.0;
            if (self.count == 1) return self.keyframes[0].value;

            const t = @as(f32, @floatFromInt(self.elapsed_ms)) /
                @as(f32, @floatFromInt(self.duration_ms));
            const clamped_t = @min(1.0, @max(0.0, t));

            // Find surrounding keyframes
            var prev_idx: usize = 0;
            var next_idx: usize = 0;
            for (0..self.count) |i| {
                if (self.keyframes[i].time <= clamped_t) {
                    prev_idx = i;
                }
                if (self.keyframes[i].time >= clamped_t and next_idx == 0) {
                    next_idx = i;
                    break;
                }
            }

            if (next_idx == 0) next_idx = self.count - 1;
            if (prev_idx == next_idx) return self.keyframes[prev_idx].value;

            const prev = self.keyframes[prev_idx];
            const next = self.keyframes[next_idx];

            // Calculate local progress between keyframes
            const time_range = next.time - prev.time;
            if (time_range == 0) return prev.value;

            const local_t = (clamped_t - prev.time) / time_range;
            const eased_t = prev.easing.apply(local_t);

            return lerp(prev.value, next.value, eased_t);
        }

        /// Check if animation is complete.
        pub fn isComplete(self: Self) bool {
            if (self.looping) return false;
            return self.elapsed_ms >= self.duration_ms;
        }

        /// Reset to beginning.
        pub fn reset(self: *Self) void {
            self.elapsed_ms = 0;
        }
    };
}

/// Duration helper for converting time units.
pub const Duration = struct {
    ms: u32,

    pub fn fromMs(ms: u32) Duration {
        return .{ .ms = ms };
    }

    pub fn fromSeconds(seconds: f32) Duration {
        return .{ .ms = @intFromFloat(seconds * 1000.0) };
    }

    pub fn fromFrames(frames: u32, fps: u32) Duration {
        if (fps == 0) return .{ .ms = 0 };
        return .{ .ms = (frames * 1000) / fps };
    }

    pub fn toSeconds(self: Duration) f32 {
        return @as(f32, @floatFromInt(self.ms)) / 1000.0;
    }

    pub fn toFrames(self: Duration, fps: u32) u32 {
        if (fps == 0) return 0;
        return (self.ms * fps) / 1000;
    }
};

/// Frame rate tracker for consistent animation timing.
pub const FrameTimer = struct {
    target_fps: u32 = 60,
    frame_duration_ms: u32 = 16,
    accumulated_ms: u32 = 0,
    frame_count: u64 = 0,

    /// Create a timer targeting the specified FPS.
    pub fn init(target_fps: u32) FrameTimer {
        const fps = if (target_fps == 0) 60 else target_fps;
        return .{
            .target_fps = fps,
            .frame_duration_ms = 1000 / fps,
        };
    }

    /// Update with elapsed time, returns number of frames to process.
    pub fn update(self: *FrameTimer, delta_ms: u32) u32 {
        self.accumulated_ms +|= delta_ms;
        const frames = self.accumulated_ms / self.frame_duration_ms;
        self.accumulated_ms = self.accumulated_ms % self.frame_duration_ms;
        self.frame_count +|= frames;
        return @intCast(frames);
    }

    /// Get milliseconds per frame for this timer.
    pub fn msPerFrame(self: FrameTimer) u32 {
        return self.frame_duration_ms;
    }
};

/// Linear interpolation between two values.
pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// Inverse linear interpolation: find t given value between a and b.
pub fn inverseLerp(a: f32, b: f32, value: f32) f32 {
    if (a == b) return 0.0;
    return (value - a) / (b - a);
}

/// Remap a value from one range to another.
pub fn remap(value: f32, in_min: f32, in_max: f32, out_min: f32, out_max: f32) f32 {
    const t = inverseLerp(in_min, in_max, value);
    return lerp(out_min, out_max, t);
}

/// Smoothstep interpolation (smooth cubic Hermite).
pub fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = @min(1.0, @max(0.0, (x - edge0) / (edge1 - edge0)));
    return t * t * (3.0 - 2.0 * t);
}

/// Smoother step (quintic interpolation, zero second derivative at edges).
pub fn smootherstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = @min(1.0, @max(0.0, (x - edge0) / (edge1 - edge0)));
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// ============================================================
// SANITY TESTS - Basic animation construction
// ============================================================

test "sanity: Animation construction" {
    const anim = Animation.init(1000);
    try std.testing.expectEqual(@as(u32, 1000), anim.duration_ms);
    try std.testing.expectEqual(@as(u32, 0), anim.elapsed_ms);
    try std.testing.expect(!anim.isComplete());
}

test "sanity: Animation with easing" {
    const anim = Animation.initWithEasing(500, .ease_out);
    try std.testing.expectEqual(Easing.ease_out, anim.easing);
}

test "sanity: Duration conversion from seconds" {
    const dur = Duration.fromSeconds(1.5);
    try std.testing.expectEqual(@as(u32, 1500), dur.ms);
}

test "sanity: Duration conversion from frames" {
    const dur = Duration.fromFrames(60, 60);
    try std.testing.expectEqual(@as(u32, 1000), dur.ms);
}

test "sanity: FrameTimer construction" {
    const timer = FrameTimer.init(60);
    try std.testing.expectEqual(@as(u32, 60), timer.target_fps);
    try std.testing.expectEqual(@as(u32, 16), timer.frame_duration_ms);
}

// ============================================================
// BEHAVIOR TESTS - Easing functions
// ============================================================

test "behavior: Easing.linear is identity" {
    try std.testing.expectEqual(@as(f32, 0.0), Easing.linear.apply(0.0));
    try std.testing.expectEqual(@as(f32, 0.5), Easing.linear.apply(0.5));
    try std.testing.expectEqual(@as(f32, 1.0), Easing.linear.apply(1.0));
}

test "behavior: Easing clamps input to [0, 1]" {
    try std.testing.expectEqual(@as(f32, 0.0), Easing.linear.apply(-0.5));
    try std.testing.expectEqual(@as(f32, 1.0), Easing.linear.apply(1.5));
}

test "behavior: Easing.ease_in starts slow" {
    const early = Easing.ease_in.apply(0.2);
    const linear_early: f32 = 0.2;
    try std.testing.expect(early < linear_early);
}

test "behavior: Easing.ease_out ends slow" {
    const late = Easing.ease_out.apply(0.8);
    const linear_late: f32 = 0.8;
    try std.testing.expect(late > linear_late);
}

test "behavior: Easing.ease_in_out symmetric" {
    const first_half = Easing.ease_in_out.apply(0.25);
    const second_half = Easing.ease_in_out.apply(0.75);
    try std.testing.expectApproxEqAbs(1.0 - second_half, first_half, 0.01);
}

test "behavior: Easing endpoints are always 0 and 1" {
    const easings = [_]Easing{
        .linear,    .ease_in,      .ease_out,    .ease_in_out,
        .quad_in,   .quad_out,     .quad_in_out, .cubic_in,
        .cubic_out, .cubic_in_out,
    };

    for (easings) |e| {
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), e.apply(0.0), 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), e.apply(1.0), 0.001);
    }
}

// ============================================================
// BEHAVIOR TESTS - Animation progress
// ============================================================

test "behavior: Animation progress increases with time" {
    var anim = Animation.init(1000);
    const p0 = anim.progress();

    _ = anim.update(500);
    const p1 = anim.progress();

    _ = anim.update(500);
    const p2 = anim.progress();

    try std.testing.expect(p0 < p1);
    try std.testing.expect(p1 < p2);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), p2, 0.001);
}

test "behavior: Animation value interpolation" {
    var anim = Animation.init(1000);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), anim.value(0.0, 100.0), 0.001);

    _ = anim.update(500);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), anim.value(0.0, 100.0), 0.001);

    _ = anim.update(500);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), anim.value(0.0, 100.0), 0.001);
}

test "behavior: Animation valueInt interpolation" {
    var anim = Animation.init(1000);
    _ = anim.update(500);
    try std.testing.expectEqual(@as(i32, 50), anim.valueInt(0, 100));
}

test "behavior: Animation valueU16 interpolation" {
    var anim = Animation.init(1000);
    _ = anim.update(500);
    try std.testing.expectEqual(@as(u16, 50), anim.valueU16(0, 100));
}

test "behavior: Animation completion" {
    var anim = Animation.init(100);
    try std.testing.expect(!anim.isComplete());

    _ = anim.update(50);
    try std.testing.expect(!anim.isComplete());

    _ = anim.update(50);
    try std.testing.expect(anim.isComplete());
}

test "behavior: Animation looping" {
    var anim = Animation.init(100);
    anim.looping = true;

    _ = anim.update(150);
    try std.testing.expect(!anim.isComplete());
    try std.testing.expectEqual(@as(u32, 50), anim.elapsed_ms);
}

test "behavior: Animation pause and resume" {
    var anim = Animation.init(1000);
    _ = anim.update(100);
    const progress_before = anim.progress();

    anim.pause();
    _ = anim.update(100);
    try std.testing.expectEqual(progress_before, anim.progress());

    anim.unpause();
    _ = anim.update(100);
    try std.testing.expect(anim.progress() > progress_before);
}

test "behavior: Animation reset" {
    var anim = Animation.init(1000);
    _ = anim.update(500);
    try std.testing.expect(anim.progress() > 0);

    anim.reset();
    try std.testing.expectEqual(@as(u32, 0), anim.elapsed_ms);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), anim.progress(), 0.001);
}

// ============================================================
// BEHAVIOR TESTS - Keyframe animation
// ============================================================

test "behavior: KeyframeAnimation basic" {
    var kf = KeyframeAnimation(4).init(1000);
    try std.testing.expect(kf.addKeyframe(0.0, 0.0, .linear));
    try std.testing.expect(kf.addKeyframe(0.5, 100.0, .linear));
    try std.testing.expect(kf.addKeyframe(1.0, 50.0, .linear));

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), kf.value(), 0.001);

    _ = kf.update(500);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), kf.value(), 1.0);

    _ = kf.update(500);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), kf.value(), 1.0);
}

// ============================================================
// BEHAVIOR TESTS - FrameTimer
// ============================================================

test "behavior: FrameTimer frame counting" {
    var timer = FrameTimer.init(60);
    const frames = timer.update(32);
    try std.testing.expectEqual(@as(u32, 2), frames);
}

test "behavior: FrameTimer accumulation" {
    var timer = FrameTimer.init(60);
    _ = timer.update(10);
    try std.testing.expectEqual(@as(u32, 10), timer.accumulated_ms);

    const frames = timer.update(10);
    try std.testing.expectEqual(@as(u32, 1), frames);
    try std.testing.expectEqual(@as(u32, 4), timer.accumulated_ms);
}

// ============================================================
// BEHAVIOR TESTS - Interpolation helpers
// ============================================================

test "behavior: lerp interpolation" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), lerp(0.0, 100.0, 0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), lerp(0.0, 100.0, 0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), lerp(0.0, 100.0, 1.0), 0.001);
}

test "behavior: inverseLerp" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), inverseLerp(0.0, 100.0, 0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), inverseLerp(0.0, 100.0, 50.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), inverseLerp(0.0, 100.0, 100.0), 0.001);
}

test "behavior: remap value ranges" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), remap(0.0, 0.0, 1.0, 0.0, 100.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), remap(0.5, 0.0, 1.0, 0.0, 100.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), remap(1.0, 0.0, 1.0, 0.0, 100.0), 0.001);
}

test "behavior: smoothstep transitions" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), smoothstep(0.0, 1.0, 0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), smoothstep(0.0, 1.0, 0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), smoothstep(0.0, 1.0, 1.0), 0.001);
}

test "behavior: smootherstep transitions" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), smootherstep(0.0, 1.0, 0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), smootherstep(0.0, 1.0, 0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), smootherstep(0.0, 1.0, 1.0), 0.001);
}

// ============================================================
// REGRESSION TESTS - Edge cases
// ============================================================

test "regression: Animation with zero duration" {
    var anim = Animation.init(0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), anim.progress(), 0.001);
    try std.testing.expect(anim.isComplete());
}

test "regression: Duration from zero fps" {
    const dur = Duration.fromFrames(60, 0);
    try std.testing.expectEqual(@as(u32, 0), dur.ms);
}

test "regression: FrameTimer with zero target fps" {
    const timer = FrameTimer.init(0);
    try std.testing.expectEqual(@as(u32, 60), timer.target_fps);
}

test "regression: inverseLerp with equal endpoints" {
    try std.testing.expectEqual(@as(f32, 0.0), inverseLerp(50.0, 50.0, 50.0));
}

test "regression: KeyframeAnimation with no keyframes" {
    const kf = KeyframeAnimation(4).init(1000);
    try std.testing.expectEqual(@as(f32, 0.0), kf.value());
}

test "regression: KeyframeAnimation max keyframes" {
    var kf = KeyframeAnimation(2).init(1000);
    try std.testing.expect(kf.addKeyframe(0.0, 0.0, .linear));
    try std.testing.expect(kf.addKeyframe(1.0, 100.0, .linear));
    try std.testing.expect(!kf.addKeyframe(0.5, 50.0, .linear));
}

test "regression: Animation saturating arithmetic" {
    var anim = Animation.init(100);
    _ = anim.update(std.math.maxInt(u32));
    try std.testing.expect(anim.isComplete());
}
