const zigsnake = @import("zigsnake");
const std = @import("std");
const httpz = @import("httpz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // More advance cases will use a custom "Handler" instead of "void".
    // The last parameter is our handler instance, since we have a "void"
    // handler, we passed a void ({}) value.
    var server = try httpz.Server(void).init(allocator, .{ .port = 5882 }, {});
    defer {
        // clean shutdown, finishes serving any live request
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.get("/", getIndex, .{});
    router.post("/move", postMove, .{});

    // blocks
    try server.listen();
}

fn getIndex(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    try res.json(.{
        .apiversion = "1",
        .author = "dmrgn",
        .color = "#ff0000",
        .head = "default",
        .tail = "default",
    }, .{});
}

const Vector = @Vector(2, u8);
const Vectori = @Vector(2, i8);
const NodeInfo = struct {
    parent: ?Vector,
    distance: u8,
    self: Vector,
};
const dirs: [4]Vectori = .{
    Vectori{ -1, 0 },
    Vectori{ 0, 1 },
    Vectori{ 1, 0 },
    Vectori{ 0, -1 },
};
const dirsName = .{ "left", "up", "right", "down" };

// returns true if lhs is closer to ctx than rhs
fn cmpDistance(ctx: Vector, lhs: Vector, rhs: Vector) bool {
    // note: we are comparing the squared distance to avoid using sqrt (slow)
    const lhsdist = @max(ctx, lhs) - @min(ctx, lhs);
    const rhsdist = @max(ctx, rhs) - @min(ctx, rhs);
    return @reduce(.Add, rhsdist * rhsdist) > @reduce(.Add, lhsdist * lhsdist);
}
// for some reason std.PriorityQueue takes a fn that returns std.math.Order instead of bool
fn cmpDistanceOrder(ctx: Vector, lhs: Vector, rhs: Vector) std.math.Order {
    return switch (cmpDistance(ctx, lhs, rhs)) {
        true => std.math.Order.lt,
        false => std.math.Order.gt,
    };
}

fn tryToSpread(visited: *std.AutoHashMap(Vector, NodeInfo), visitQueue: *std.PriorityQueue(Vector, Vector, cmpDistanceOrder), snakePieces: [11][11]bool, node: Vector) !void {
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

fn postMove(req: *httpz.Request, res: *httpz.Response) !void {
    if (try req.jsonObject()) |moveRequest| {
        const boardJson = moveRequest.get("board").?.object;
        const foodJson = boardJson.get("food").?.array;
        const snakesJson = boardJson.get("snakes").?.array;
        const selfJson = moveRequest.get("you").?.object;
        const selfHead = Vector{ @intCast(selfJson.get("head").?.object.get("x").?.integer), @intCast(selfJson.get("head").?.object.get("y").?.integer) };
        std.debug.print("New request =============== {} {}\n", .{ selfHead[0], selfHead[1] });

        // get food vectors
        var food: std.ArrayList(Vector) = .empty;
        for (foodJson.items) |foodItemValue| {
            const foodItem = foodItemValue.object;
            try food.append(res.arena, Vector{ @intCast(foodItem.get("x").?.integer), @intCast(foodItem.get("y").?.integer) });
        }

        // create a collection of just snake pieces as vectors
        var pieces: std.ArrayList(Vector) = .empty;
        // turn it into a 2d array for fast lookup
        var snakePieces: [11][11]bool = .{.{false} ** 11} ** 11;
        for (snakesJson.items) |snakeValue| {
            const snake = snakeValue.object;
            const snakeBody = snake.get("body").?.array;
            for (snakeBody.items) |snakePieceValue| {
                const snakePiece = snakePieceValue.object;
                const pieceX: u8 = @intCast(snakePiece.get("x").?.integer);
                const pieceY: u8 = @intCast(snakePiece.get("y").?.integer);
                try pieces.append(res.arena, Vector{ pieceX, pieceY });
                snakePieces[pieceX][pieceY] = true;
            }
        }

        // sort food by closest
        std.mem.sort(Vector, food.items, selfHead, cmpDistance);

        if (food.items.len > 0) {
            std.debug.print("Heading towards: {} {}\n", .{ food.items[0][0], food.items[0][1] });
        }

        // let's use A* to pathfind to food.items[0], avoiding tail segments
        var visitQueue = std.PriorityQueue(Vector, Vector, cmpDistanceOrder).init(res.arena, food.items[0]);
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
                std.mem.sort(Vector, visitedArray.items, selfHead, cmpDistance);
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
        const move = switch (dir[0] + dir[1] * 2) {
            dirs[0][0] + dirs[0][1] * 2 => "left",
            dirs[1][0] + dirs[1][1] * 2 => "up",
            dirs[2][0] + dirs[2][1] * 2 => "right",
            dirs[3][0] + dirs[3][1] * 2 => "down",
            else => "error",
        };

        res.status = 200;
        try res.json(.{
            .move = move,
        }, .{});
    }
}
