const std = @import("std");
const httpz = @import("httpz");

const util = @import("util.zig");
const Vector = util.Vector;
const Vectori = util.Vectori;

const NodeInfo = struct {
    distance: u8,
    score: f32,
    self: Vector,
};

pub fn tryToSpread(res: *httpz.Response, visited: *std.AutoHashMap(Vector, NodeInfo), visitQueue: *std.ArrayList(NodeInfo), snakePieces: [11][11]bool, selfLength: u8, diffusion: [11][11]f32, node: Vector) !f32 {
    _ = selfLength;
    _ = snakePieces;
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
        if (pos[0] < 0 or pos[0] > 10 or pos[1] < 0 or pos[1] > 10)
            continue;
        if (visited.contains(@intCast(pos)) or diffusion[@intCast(pos[0])][@intCast(pos[1])] < 0.05) {
            // TODO: look into how we can handle already visited nodes
            continue;
        }
        std.debug.print("\t\ttry to spread: {} {} : {} {}\n", .{ pos[0], pos[1], @as(u8, @intCast(pos[0])), @as(u8, @intCast(pos[1])) });
        // visit it
        const nodeInfo: NodeInfo = .{
            .distance = thisNodeInfo.?.distance + 1,
            .self = @intCast(pos),
            .score = thisNodeInfo.?.score * diffusion[@intCast(pos[0])][@intCast(pos[1])],
        };
        try visited.put(@intCast(pos), nodeInfo);
        try visitQueue.append(res.arena, nodeInfo);
    }
    // score this node
    return thisNodeInfo.?.score;
}

// simulate one turn on the given diffusion grid.
pub fn simulateDiffusionTurn(res: *httpz.Response, diffusion: *[11][11]f32, snakes: std.ArrayList(std.ArrayList(Vector)), queues: *std.ArrayList(std.ArrayList(NodeInfo)), visited: *std.ArrayList(std.AutoHashMap(Vector, NodeInfo)), turn: u8) !void {
    // remove last tail piece
    if (turn > 0) {
        for (snakes.items) |snake| {
            if (snake.items.len < turn)
                continue;
            const lastPiece = snake.items[snake.items.len - turn];
            diffusion[@intCast(lastPiece[0])][@intCast(lastPiece[1])] = 1.0;
        }
    }
    // diffuse heads
    for (queues.items, 0..) |*queue, index| {
        // the more nodes (possibilities), the lower probability of each node
        const diffusionStrength = 1.0 / @as(f32, @floatFromInt(queue.items.len));
        // spread each node at this distance
        while (queue.items.len > 0 and queue.items[0].distance == turn) {
            const nextToSpread = queue.orderedRemove(0);
            const nodei = @as(Vectori, @intCast(nextToSpread.self));
            const toTry: [4]Vectori = .{
                Vectori{ -1, 0 } + nodei,
                Vectori{ 0, 1 } + nodei,
                Vectori{ 1, 0 } + nodei,
                Vectori{ 0, -1 } + nodei,
            };
            for (toTry) |posi| {
                // check if this is a free square
                if (posi[0] < 0 or posi[0] > 10 or posi[1] < 0 or posi[1] > 10 or diffusion[@intCast(posi[0])][@intCast(posi[1])] == 0 or visited.items[index].contains(@intCast(posi)))
                    continue;
                const pos = @as(Vector, @intCast(posi));
                // visit it
                const nodeInfo: NodeInfo = .{
                    .distance = nextToSpread.distance + 1,
                    .self = pos,
                    .score = diffusionStrength,
                };
                try visited.items[index].put(pos, nodeInfo);
                try queue.append(res.arena, nodeInfo);
            }
            // update this square in the diffusion grid
            const nodeX: usize = @intCast(nextToSpread.self[0]);
            const nodeY: usize = @intCast(nextToSpread.self[1]);
            diffusion[nodeX][nodeY] *= 1 - diffusionStrength;
        }
    }
}

// get space's opinion on where to go next based on board state
pub fn spaceModel(res: *httpz.Response, selfHead: Vector, selfLength: u8, food: *std.ArrayList(Vector), snakePieces: [11][11]bool, snakes: std.ArrayList(std.ArrayList(Vector))) ![4]f32 {
    _ = food;

    // for each direction that is valid,
    // let's bfs and count the probability area of accessible spaces in the diffusion
    var scores: [4]f32 = .{ 0, 0, 0, 0 };
    for (util.dirs, 0..) |dir, dirIndex| {
        var turn: u8 = 1;
        // let's make a diffusion grid that we can use to keep track of possible positions
        // this should work better than treating snakes like fixed walls
        // each [i][j] represents the probability of that space being available this turn
        var snakePiecesDiffusion: [11][11]f32 = .{.{1.0} ** 11} ** 11;
        // set snake occupied positions to 0 space available for the initial turn
        for (0..11) |i| {
            for (0..11) |j| {
                snakePiecesDiffusion[i][j] = if (snakePieces[i][j]) 0 else 1;
            }
        }
        // setup queues to diffuse using BFS on each snake's head (not our own)
        var diffusionQueues: std.ArrayList(std.ArrayList(NodeInfo)) = .empty;
        // setup the visited hashmaps for BFS on each snake's head (not our own)
        var diffusionVisited: std.ArrayList(std.AutoHashMap(Vector, NodeInfo)) = .empty;
        for (snakes.items, 0..) |snakeBody, index| {
            const headInfo: NodeInfo = .{
                .distance = 0,
                .score = 0,
                .self = snakeBody.items[0],
            };
            try diffusionVisited.append(res.arena, std.AutoHashMap(Vector, NodeInfo).init(res.arena));
            try diffusionVisited.items[index].put(snakeBody.items[0], headInfo);
            try diffusionQueues.append(res.arena, .empty);
            // we need to omit diffusing our own head
            if (std.meta.eql(snakeBody.items[0], selfHead))
                continue;
            // add the head as the first item in each queue
            try diffusionQueues.items[index].append(res.arena, headInfo);
        }
        // simulate the first turn of diffusion
        try simulateDiffusionTurn(res, &snakePiecesDiffusion, snakes, &diffusionQueues, &diffusionVisited, 0);
        try simulateDiffusionTurn(res, &snakePiecesDiffusion, snakes, &diffusionQueues, &diffusionVisited, 1);

        for (0..11) |y| {
            for (0..11) |x| {
                std.debug.print("{d:6.2}", .{snakePiecesDiffusion[x][10 - y]});
            }
            std.debug.print("\n", .{});
        }

        const posi: Vectori = @intCast(@as(Vectori, @intCast(selfHead)) + dir);
        // check if this direction is valid
        if (posi[0] < 0 or posi[0] > 10 or posi[1] < 0 or posi[1] > 10 or snakePieces[@intCast(posi[0])][@intCast(posi[1])])
            continue;
        const pos: Vector = @intCast(posi);
        // score this space with bfs
        const nodeInfo: NodeInfo = .{
            .distance = 1,
            .score = snakePiecesDiffusion[@intCast(pos[0])][@intCast(pos[1])],
            .self = pos,
        };
        std.debug.print("spread position: {} {}\n", .{ pos[0], pos[1] });
        var visitQueue: std.ArrayList(NodeInfo) = .empty;
        try visitQueue.append(res.arena, nodeInfo);
        var visited = std.AutoHashMap(Vector, NodeInfo).init(res.arena);
        try visited.put(pos, nodeInfo);
        // empty the visit queue and sum connected node's scores
        var score: f32 = 0;
        while (visitQueue.items.len > 0) {
            // diffuse to simulate the next turn
            try simulateDiffusionTurn(res, &snakePiecesDiffusion, snakes, &diffusionQueues, &diffusionVisited, turn);
            std.debug.print("\tturn: {} queue length: {}\n", .{ turn, visitQueue.items.len });
            for (visitQueue.items) |queueItem| {
                std.debug.print("\t\tqueue: {} {}\n", .{ queueItem.self[0], queueItem.self[1] });
            }
            while (visitQueue.items.len > 0 and visitQueue.items[0].distance == turn) {
                const nextToSpread = visitQueue.orderedRemove(0);
                score += try tryToSpread(res, &visited, &visitQueue, snakePieces, selfLength, snakePiecesDiffusion, nextToSpread.self);
            }
            std.debug.print("\tscore: {d:6.3}\n", .{score});
            turn += 1;
            if (turn <= 3) {
                for (0..11) |y| {
                    for (0..11) |x| {
                        std.debug.print("{d:6.2}", .{snakePiecesDiffusion[x][10 - y]});
                    }
                    std.debug.print("\n", .{});
                }
            }
        }
        // set the score for this direction
        scores[dirIndex] = score;
    }

    return scores;
}
