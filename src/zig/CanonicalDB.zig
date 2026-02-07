const std = @import("std");
const pg = @import("pg");
const builtin = @import("builtin");
const configs = @import("data/configs.zig");
pub const log = std.log.scoped(.example);

pub const CanonicalDB = struct {
    allocator: std.mem.Allocator,
    pool: pg.Pool,

    pub fn init(allocator: std.mem.Allocator, config: configs.CanonicalDBConfig) !CanonicalDB {
        const pool = pg.Pool.init(allocator, .{ .size = config.pool_size, .connect = .{
            .port = 5432,
            .host = "127.0.0.1",
        }, .auth = .{
            .username = "postgres",
            .database = "postgres",
            .timeout = 10_000,
        } }) catch |err| {
            log.err("Failed to connect: {}", .{err});
            std.posix.exit(1);
        };

        return .{
            .allocator = allocator,
            .pool = pool,
        };
    }

    pub fn deinit(self: *CanonicalDB) !void {
        self.pool.deinit();
    }

    // SELECT event_id
    // FROM events
    // WHERE venue = "polymarket" AND venue_event_id = ?

    pub fn queryForResult(self: *CanonicalDB, query_string: []const u8) !pg.Result {
        log.info("\n\nExample 2", .{});
        // or we can fetch multiple rows:
        var conn = try self.pool.acquire();
        defer conn.release();
        return try conn.query("{}", .{query_string});
    }

    pub fn queryForResultAllocated(self: *CanonicalDB, allocator: std.mem.Allocator, query_string: []const u8) !*pg.Result {
        var conn = try self.pool.acquire();
        defer conn.release();
        return try pg.conn.queryOpts("{}", .{query_string}, .{ .allocator = allocator });
    }

    pub fn queryForRow(self: *CanonicalDB, query_string: []const u8) !pg.Result {
        log.info("\n\nExample 2", .{});
        // or we can fetch multiple rows:
        var conn = try self.pool.acquire();
        defer conn.release();
        return try conn.row("{}", .{query_string}) orelse unreachable;
    }

    //TODO for testing. consider removing this, or figure out a better way to init db
    pub fn migrate(
        self: *CanonicalDB,
        table_name: []const u8,
        columns: []const []const u8,
    ) !void {
        // Drop table
        {
            var buf = std.ArrayList(u8).init(self.allocator);
            defer buf.deinit();

            try buf.writer().print(
                "drop table if exists {s}",
                .{table_name},
            );

            _ = try self.pool.exec(buf.items, .{});
        }

        // Create table
        var conn = try self.pool.acquire();
        defer conn.release();

        var sql = std.ArrayList(u8).init(self.allocator);
        defer sql.deinit();

        const w = sql.writer();

        try w.print("create table {s} (", .{table_name});

        for (columns, 0..) |col, i| {
            if (i != 0) try w.writeAll(", ");
            try w.writeAll(col);
        }

        try w.writeAll(")");

        _ = conn.exec(sql.items, .{}) catch |err| {
            if (conn.err) |pg_err| {
                std.log.err("migration failed: {s}", .{pg_err.message});
                std.log.err("During statement: {}", .{sql.items});
            }
            return err;
        };
    }
};

// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.c_allocator;

//     // While a connection can be created directly, pools should be used in most
//     // cases. The pool's `acquire` method, to get a connection is thread-safe.
//     // The pool may start 1 background thread to reconnect disconnected
//     // connections (or connections in an invalid state).
//     var pool = pg.Pool.init(allocator, .{ .size = 5, .connect = .{
//         .port = 5432,
//         .host = "127.0.0.1",
//     }, .auth = .{
//         .username = "postgres",
//         .database = "postgres",
//         .timeout = 10_000,
//     } }) catch |err| {
//         log.err("Failed to connect: {}", .{err});
//         std.posix.exit(1);
//     };
//     defer pool.deinit();
// }
