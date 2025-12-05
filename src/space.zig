const std = @import("std");
const httpz = @import("httpz");

const util = @import("util.zig");
const Vector = util.Vector;
const Vectori = util.Vectori;

const NodeInfo = struct {
    parent: ?Vector,
    distance: u8,
    score: f32,
    self: Vector,
};

pub fn tryToSpread(res: *httpz.Response, visited: *std.AutoHashMap(Vector, NodeInfo), visitQueue: *std.ArrayList(Vector), snakePieces: [11][11]bool, selfLength: u8, node: Vector) !f32 {
    _ = selfLength;
    const nodei: Vectori = @intCast(node);
    const thisNodeInfo = visited.get(node);
    // if we don't contribute anything, then just return
    // since none of our children will contribute either
    if (thisNodeInfo.?.score <= 0.05)
        return 0;
    // otherwise let's add our children to the queue
    const toTry: [4]Vectori = .{
        Vectori{ -1, 0 } + nodei,
        Vectori{ 0, 1 } + nodei,
        Vectori{ 1, 0 } + nodei,
        Vectori{ 0, -1 } + nodei,
    };
    for (toTry) |pos| {
        // check if this is a free square
        if (pos[0] < 0 or pos[0] > 10 or pos[1] < 0 or pos[1] > 10 or snakePieces[@intCast(pos[0])][@intCast(pos[1])] or visited.contains(@intCast(pos)))
            continue;
        // visit it
        try visited.put(@intCast(pos), .{
            .distance = thisNodeInfo.?.distance + 1,
            .parent = node,
            .self = @intCast(pos),
            .score = thisNodeInfo.?.score * 0.95, // TODO: consider lowering by tail length or not lowering
        });
        try visitQueue.append(res.arena, @intCast(pos));
    }
    // score this node
    return thisNodeInfo.?.score;
}

// get space's opinion on where to go next based on board state
pub fn spaceModel(res: *httpz.Response, selfHead: Vector, selfLength: u8, food: *std.ArrayList(Vector), snakePieces: [11][11]bool, snakes: std.ArrayList(std.ArrayList(Vector))) ![4]f32 {
    _ = food;
    _ = snakes;

    // for each direction that is valid,
    // let's bfs and count the number of accessible spaces
    var scores: [4]f32 = .{ 0, 0, 0, 0 };
    for (util.dirs, 0..) |dir, dirIndex| {
        const posi: Vectori = @intCast(@as(Vectori, @intCast(selfHead)) + dir);
        // check if this direction is valid
        if (posi[0] < 0 or posi[0] > 10 or posi[1] < 0 or posi[1] > 10 or snakePieces[@intCast(posi[0])][@intCast(posi[1])])
            continue;
        const pos: Vector = @intCast(posi);
        // score this space with bfs
        var visitQueue: std.ArrayList(Vector) = .empty;
        try visitQueue.append(res.arena, pos);
        var visited = std.AutoHashMap(Vector, NodeInfo).init(res.arena);
        try visited.put(pos, .{
            .distance = 1,
            .parent = null,
            .score = 1,
            .self = pos,
        });
        // empty the visit queue and sum connected node's scores
        var score: f32 = 1;
        while (visitQueue.items.len > 0) {
            const nextToSpread = visitQueue.orderedRemove(0);
            score += try tryToSpread(res, &visited, &visitQueue, snakePieces, selfLength, nextToSpread);
        }
        // set the score for this direction
        scores[dirIndex] = score;
    }

    return scores;
}
