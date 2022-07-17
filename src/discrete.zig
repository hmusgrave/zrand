const std = @import("std");

const _shuffle = @import("discrete/shuffle.zig");
pub const shuffle = _shuffle.shuffle;
pub const permutation = _shuffle.permutation;

const _choice = @import("discrete/choice.zig");
pub const choice = _choice.choice;
pub const enum_choice = _choice.enum_choice;
pub const WeightedChoice = _choice.WeightedChoice;

const bernoulli = @import("discrete/bernoulli.zig").bernoulli;

test "test" {
    std.testing.refAllDecls(@This());
}
