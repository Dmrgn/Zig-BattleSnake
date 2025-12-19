const zigsnake = @import("zigsnake");
const std = @import("std");
const httpz = @import("httpz");

const util = @import("util.zig");
const Vector = util.Vector;
const Vectori = util.Vectori;

const astar = @import("astar.zig");
const space = @import("space.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var port: u16 = 5882;
    if (std.os.argv.len == 3 and std.mem.eql(u8, std.mem.span(std.os.argv[1]), "--port")) {
        port = try std.fmt.parseInt(u16, std.mem.span(std.os.argv[2]), 10);
    }

    // More advance cases will use a custom "Handler" instead of "void".
    // The last parameter is our handler instance, since we have a "void"
    // handler, we passed a void ({}) value.
    var server = try httpz.Server(void).init(allocator, .{ .port = port, .address = "0.0.0.0" }, {});
    defer {
        // clean shutdown, finishes serving any live request
        server.stop();
        server.deinit();
    }
    std.debug.print("Running on port {}\n", .{port});

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
        .color = "#8928d4",
        .head = "evil",
        .tail = "flame",
    }, .{});
}

fn postMove(req: *httpz.Request, res: *httpz.Response) !void {
    if (try req.jsonObject()) |moveRequest| {
        const boardJson = moveRequest.get("board").?.object;
        const foodJson = boardJson.get("food").?.array;
        const snakesJson = boardJson.get("snakes").?.array;
        const selfJson = moveRequest.get("you").?.object;
        const selfHead = Vector{ @intCast(selfJson.get("head").?.object.get("x").?.integer), @intCast(selfJson.get("head").?.object.get("y").?.integer) };
        const selfLength: u8 = @intCast(selfJson.get("length").?.integer);
        std.debug.print("New request =============== {} {}\n", .{ selfHead[0], selfHead[1] });

        // get food vectors
        var food: std.ArrayList(Vector) = .empty;
        for (foodJson.items) |foodItemValue| {
            const foodItem = foodItemValue.object;
            try food.append(res.arena, Vector{ @intCast(foodItem.get("x").?.integer), @intCast(foodItem.get("y").?.integer) });
        }

        // create a collection of just snake pieces as vectors
        var snakePieces: std.ArrayList(Vector) = .empty;
        // turn it into a 2d array for fast lookup
        var snakeGrid: [11][11]bool = .{.{false} ** 11} ** 11;
        // and into an arraylist representing each snake
        var snakes: std.ArrayList(std.ArrayList(Vector)) = .empty;
        for (snakesJson.items) |snakeValue| {
            const snake = snakeValue.object;
            const snakeBody = snake.get("body").?.array;
            try snakes.append(res.arena, .empty);
            // const snake
            for (snakeBody.items) |snakePieceValue| {
                const snakePiece = snakePieceValue.object;
                const pieceX: u8 = @intCast(snakePiece.get("x").?.integer);
                const pieceY: u8 = @intCast(snakePiece.get("y").?.integer);
                try snakes.items[snakes.items.len - 1].append(res.arena, Vector{ pieceX, pieceY });
                try snakePieces.append(res.arena, Vector{ pieceX, pieceY });
                snakeGrid[pieceX][pieceY] = true;
            }
        }

        const astarOpinion = try astar.astarModel(res, selfHead, &food, snakeGrid);
        const spaceOpinion = try space.spaceModel(res, selfHead, selfLength, &food, snakeGrid, snakes);

        std.debug.print("l:{d:6.5} u:{d:6.5} r:{d:6.5} d:{d:6.5}\n", .{ spaceOpinion[0], spaceOpinion[1], spaceOpinion[2], spaceOpinion[3] });
        // normalize scores
        const astarScore: @Vector(4, f32) = astarOpinion;
        var totalScore: @Vector(4, f32) = spaceOpinion;
        totalScore *= astarScore;
        var largest: f32 = 0;
        var largestIndex: usize = 0;
        for (0..4) |index| {
            if (totalScore[index] > largest) {
                largest = totalScore[index];
                largestIndex = index;
            }
        }
        totalScore /= .{ largest, largest, largest, largest };

        res.status = 200;
        try res.json(.{
            .move = util.dirToMove(util.dirs[largestIndex]),
        }, .{});
    }
}
