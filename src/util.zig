const std = @import("std");

pub const Vector = @Vector(2, u8);
pub const Vectori = @Vector(2, i8);
pub const dirs: [4]Vectori = .{
    Vectori{ -1, 0 },
    Vectori{ 0, 1 },
    Vectori{ 1, 0 },
    Vectori{ 0, -1 },
};
pub const dirsName = .{ "left", "up", "right", "down" };

// returns true if lhs is closer to ctx than rhs
pub fn cmpDistance(ctx: Vector, lhs: Vector, rhs: Vector) bool {
    // note: we are comparing the squared distance to avoid using sqrt (slow)
    const lhsdist = @max(ctx, lhs) - @min(ctx, lhs);
    const rhsdist = @max(ctx, rhs) - @min(ctx, rhs);
    return @reduce(.Add, rhsdist * rhsdist) > @reduce(.Add, lhsdist * lhsdist);
}
// for some reason std.PriorityQueue takes a fn that returns std.math.Order instead of bool
pub fn cmpDistanceOrder(ctx: Vector, lhs: Vector, rhs: Vector) std.math.Order {
    return switch (cmpDistance(ctx, lhs, rhs)) {
        true => std.math.Order.lt,
        false => std.math.Order.gt,
    };
}
