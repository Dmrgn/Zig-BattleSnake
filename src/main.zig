const zigsnake = @import("zigsnake");
const std = @import("std");
const httpz = @import("httpz");

const util = @import("util.zig");
const Vector = util.Vector;
const Vectori = util.Vectori;

const astar = @import("astar.zig");

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
        var snakePieces: std.ArrayList(Vector) = .empty;
        // turn it into a 2d array for fast lookup
        var snakeGrid: [11][11]bool = .{.{false} ** 11} ** 11;
        // and into an arraylist representing each snake
        // var snakes: std.ArrayList(std.ArrayList(Vector)) = .empty;
        for (snakesJson.items) |snakeValue| {
            const snake = snakeValue.object;
            const snakeBody = snake.get("body").?.array;
            // const snake
            for (snakeBody.items) |snakePieceValue| {
                const snakePiece = snakePieceValue.object;
                const pieceX: u8 = @intCast(snakePiece.get("x").?.integer);
                const pieceY: u8 = @intCast(snakePiece.get("y").?.integer);
                try snakePieces.append(res.arena, Vector{ pieceX, pieceY });
                snakeGrid[pieceX][pieceY] = true;
            }
        }

        const astarOpinion = try astar.astarModel(res, selfHead, &food, snakeGrid);

        res.status = 200;
        try res.json(.{
            .move = astarOpinion,
        }, .{});
    }
}
