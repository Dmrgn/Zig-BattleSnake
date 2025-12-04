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

// returns true if lhs is closer to ctx than rhs
fn cmpDistance(ctx: Vector, lhs: Vector, rhs: Vector) bool {
    // note: we are comparing the squared distance to avoid using sqrt (slow)
    const lhsdist = @max(ctx, lhs) - @min(ctx, lhs);
    const rhsdist = @max(ctx, rhs) - @min(ctx, rhs);
    return @reduce(.Add, rhsdist * rhsdist) > @reduce(.Add, lhsdist * lhsdist);
}

fn postMove(req: *httpz.Request, res: *httpz.Response) !void {
    if (try req.jsonObject()) |moveRequest| {
        const boardJson = moveRequest.get("board").?.object;
        const foodJson = boardJson.get("food").?.array;
        const snakesJson = boardJson.get("snakes").?.array;
        const selfJson = moveRequest.get("you").?.object;
        const selfHead: Vector = Vector{ @intCast(selfJson.get("head").?.object.get("x").?.integer), @intCast(selfJson.get("head").?.object.get("y").?.integer) };

        // get food vectors
        var food: std.ArrayList(Vector) = .empty;
        defer food.deinit(res.arena);
        for (foodJson.items) |foodItemValue| {
            const foodItem = foodItemValue.object;
            try food.append(res.arena, Vector{ @intCast(foodItem.get("x").?.integer), @intCast(foodItem.get("y").?.integer) });
        }

        // create a collection of just snake pieces as vectors
        var pieces: std.ArrayList(Vector) = .empty;
        defer pieces.deinit(res.arena);
        for (snakesJson.items) |snakeValue| {
            const snake = snakeValue.object;
            const snakeBody = snake.get("body").?.array;
            for (snakeBody.items) |snakePieceValue| {
                const snakePiece = snakePieceValue.object;
                try pieces.append(res.arena, Vector{ @intCast(snakePiece.get("x").?.integer), @intCast(snakePiece.get("y").?.integer) });
            }
        }

        // sort food by closest
        std.mem.sort(Vector, food.items, selfHead, cmpDistance);

        if (food.items.len > 0) {
            std.debug.print("Heading towards: {} {}\n", .{ food.items[0][0], food.items[0][1] });
        }

        // let's use A* to pathfind to food.items[0]
        const visitQueue = std.PriorityQueue(Vector, food.items[0], cmpDistance);
        defer visitQueue.deinit();
        visitQueue.add(self: *PriorityQueue(@Vector(2,u8),Context), elem: @Vector(2,u8))

        res.status = 200;
        try res.json(.{
            .move = "left",
        }, .{});
    }
}
