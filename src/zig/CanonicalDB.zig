const std = @import("std");
const pg = @import("pg");
const builtin = @import("builtin");
const configs = @import("data/configs.zig");
pub const log = std.log.scoped(.example);
const canon = @import("data/canonical-entities.zig");

pub const CanonicalDB = struct {
    allocator: std.mem.Allocator,
    pool: *pg.Pool,

    pub fn init(allocator: std.mem.Allocator, config: configs.CanonicalDBConfig) !CanonicalDB {
        const pool = pg.Pool.init(allocator, .{
            .size = config.pool_size,
            .connect = .{
                .port = config.port,
                .host = config.host,
            },
            .auth = .{
                .username = config.username,
                .password = config.password,
                .database = config.database,
                .timeout = config.timeout,
            },
        }) catch |err| {
            log.err("Failed to connect: {}", .{err});
            std.posix.exit(1);
        };

        return .{
            .allocator = allocator,
            .pool = pool,
        };
    }

    pub fn deinit(self: *CanonicalDB) void {
        self.pool.deinit();
    }

    pub fn exec(self: *CanonicalDB, statement: []const u8) !void {
        _ = try self.pool.exec(statement, .{});
    }

    pub fn queryForResult(self: *CanonicalDB, query_string: []const u8) !pg.Result {
        log.info("\n\nExample 2", .{});
        // or we can fetch multiple rows:
        var conn = try self.pool.acquire();
        defer conn.release();
        return try conn.query("{}", .{query_string});
    }

    pub fn queryForResultAllocated(self: *CanonicalDB, allocator: std.mem.Allocator, query_string: []const u8) !void {
        var conn = try self.pool.acquire();
        defer conn.release();

        var result = try conn.queryOpts(query_string, .{}, .{ .allocator = allocator });
        defer result.deinit();

        while (try result.next()) |row| {
            const id = row.get(i64, 1);

            // string values are only valid until the next call to next()
            // dupe the value if needed
            log.info("User {d}", .{id});
        }
    }

    pub fn queryForRow(self: *CanonicalDB, query_string: []const u8) !pg.Result {
        log.info("\n\nExample 2", .{});
        // or we can fetch multiple rows:
        var conn = try self.pool.acquire();
        defer conn.release();
        return try conn.row("{}", .{query_string}) orelse unreachable;
    }

    pub fn clearTable(self: *CanonicalDB) !void {
        _ = try self.pool.exec("drop table if exists canonical_events", .{});
    }

    pub fn initTable(self: *CanonicalDB, creation_statement: []const u8) !void {
        var conn = try self.pool.acquire();
        defer conn.release();
        _ = conn.exec(creation_statement, .{}) catch |err| {
            if (conn.err) |pg_err| {
                std.log.err("table creation failed: {s}", .{pg_err.message});
            }
            return err;
        };
    }

    pub fn initTableTEST(self: *CanonicalDB) !void {
        var conn = try self.pool.acquire();
        defer conn.release();

        // exec returns the # of rows affected for insert/select/delete
        _ = conn.exec("create table pg_example_users (id integer, name text)", .{}) catch |err| {
            if (conn.err) |pg_err| {
                // conn.err is an optional PostgreSQL error. It has many fields,
                // many of which are nullable, but the `message`, `code` and
                // `severity` are always present.
                log.err("create failure: {s}", .{pg_err.message});
            }
            return err;
        };
    }

    //TODO for testing. consider removing this, or figure out a better way to init db
    pub fn migrate(
        self: *CanonicalDB,
        table_name: []const u8,
        columns: []const []const u8,
    ) !void {
        // Drop table
        {
            var buf = std.ArrayList(u8).initCapacity(self.allocator, 1); //TODO what is the right init size here?
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
