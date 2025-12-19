const std = @import("std");
const httpz = @import("httpz");

const util = @import("util.zig");
const Vector = util.Vector;
const Vectori = util.Vectori;

const NodeInfo = struct {
    parent: ?Vector,
    distance: u8,
    self: Vector,
};

pub fn tryToSpread(visited: *std.AutoHashMap(Vector, NodeInfo), visitQueue: *std.PriorityQueue(Vector, Vector, util.cmpDistanceOrder), snakePieces: [11][11]bool, node: Vector) !void {
    const nodei: Vectori = @intCast(node);
    const thisNodeInfo = visited.get(node);
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
        });
        try visitQueue.add(@intCast(pos));
    }
}

// get astar's opinion on where to go next based on board state
pub fn astarModel(
    res: *httpz.Response,
    selfHead: Vector,
    food: *std.ArrayList(Vector),
    snakePieces: [11][11]bool,
) ![4]f32 {
    // sort food by closest
    std.mem.sort(Vector, food.items, selfHead, util.cmpDistance);

    if (food.items.len > 0) {
        std.debug.print("Heading towards: {} {}\n", .{ food.items[0][0], food.items[0][1] });
    }

    // let's use A* to pathfind to food.items[0], avoiding tail segments
    var visitQueue = std.PriorityQueue(Vector, Vector, util.cmpDistanceOrder).init(res.arena, food.items[0]);
    var visited = std.AutoHashMap(Vector, NodeInfo).init(res.arena);
    // add the three directions
    try visitQueue.add(selfHead);
    try visited.put(selfHead, .{
        .distance = 0,
        .parent = null,
        .self = selfHead,
    });

    while (visitQueue.items.len > 0) {
        const nextToSpread = visitQueue.remove();
        // check if we have arrived
        if (std.meta.eql(nextToSpread, food.items[0]))
            break;
        // otherwise, spread
        try tryToSpread(&visited, &visitQueue, snakePieces, nextToSpread);
    }

    const target = blk: {
        if (visited.contains(food.items[0]))
            break :blk food.items[0]
        else {
            // if no move was found then path to the furthest node (stay alive as long as possible)
            var visitedArray: std.ArrayList(Vector) = .empty;
            var visitedIter = visited.iterator();
            while (visitedIter.next()) |node| {
                try visitedArray.append(res.arena, node.key_ptr.*);
            }
            // now sort to find the furthest
            std.mem.sort(Vector, visitedArray.items, selfHead, util.cmpDistance);
            break :blk visitedArray.items[visitedArray.items.len - 1];
        }
    };

    // find which direction we need to go to get here
    var node = target;
    if (visited.get(node).?.parent != null) {
        while (!std.meta.eql(visited.get(node).?.parent.?, selfHead)) {
            std.debug.print("{} {} has parent {} {}\n", .{ node[0], node[1], visited.get(node).?.parent.?[0], visited.get(node).?.parent.?[1] });
            node = visited.get(node).?.parent.?;
        }
    }
    const dir: Vectori = @as(Vectori, @intCast(node)) - @as(Vectori, @intCast(selfHead));
    var scores: [4]f32 = .{ 0.8, 0.8, 0.8, 0.8 };
    scores[util.dirToIndex(dir)] = 1.0;

    return scores;
}
