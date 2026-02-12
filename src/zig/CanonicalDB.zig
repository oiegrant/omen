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

    pub fn getActiveEventsFromDB(self: *CanonicalDB, allocator: std.mem.Allocator) !std.StringHashMap(canon.CanonicalEventCacheField) {
        const query_string =
            \\SELECT
            \\venue_event_id,
            \\event_id,
            \\data_hash,
            \\created_at
            \\FROM canonical_events
            \\WHERE venue = 'polymarket'
            \\AND status IN ('active', 'pending')
        ;
        var conn = try self.pool.acquire();
        defer conn.release();

        var result = try conn.queryOpts(query_string, .{}, .{ .allocator = allocator });
        defer result.deinit();

        var cacheEventsMap = std.StringHashMap(canon.CanonicalEventCacheField).init(allocator);
        errdefer {
            var it = cacheEventsMap.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.venue_event_id);
            }
            cacheEventsMap.deinit();
        }

        while (try result.next()) |row| {
            const venue_event_id = try allocator.dupe(u8, row.get([]const u8, 0));
            errdefer allocator.free(venue_event_id);

            const event_id: u64 = @intCast(row.get(i64, 1));

            const data_hash = blk: {
                const slice = row.get([]const u8, 2);
                if (slice.len != 32) {
                    std.debug.print("ERROR: data_hash length is {d}, expected 32\n", .{slice.len});
                    return error.InvalidDataHashLength;
                }
                var hash: [32]u8 = undefined;
                @memcpy(&hash, slice);
                break :blk hash;
            };

            const created_at = row.get(i64, 3);

            const temp_cache_field = canon.CanonicalEventCacheField{
                .venue_event_id = venue_event_id,
                .event_id = event_id,
                .data_hash = data_hash,
                .created_at = created_at,
            };

            try cacheEventsMap.put(venue_event_id, temp_cache_field);
        }

        return cacheEventsMap;
    }

    pub fn getActiveMarketsFromDB(self: *CanonicalDB, allocator: std.mem.Allocator) !std.StringHashMap(canon.CanonicalMarketCacheField) {
        const query_string =
            \\SELECT
            \\venue_market_id,
            \\market_id,
            \\data_hash,
            \\created_at
            \\FROM canonical_markets
            \\WHERE venue = 'polymarket'
            \\AND market_status IN ('active', 'pending')
        ;
        var conn = try self.pool.acquire();
        defer conn.release();

        var result = try conn.queryOpts(query_string, .{}, .{ .allocator = allocator });
        defer result.deinit();

        var cacheMarketsMap = std.StringHashMap(canon.CanonicalMarketCacheField).init(allocator);
        errdefer {
            var it = cacheMarketsMap.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.venue_market_id);
            }
            cacheMarketsMap.deinit();
        }

        while (try result.next()) |row| {
            const venue_market_id = try allocator.dupe(u8, row.get([]const u8, 0));
            errdefer allocator.free(venue_market_id);

            const market_id: u64 = @intCast(row.get(i64, 1));

            const data_hash = blk: {
                const slice = row.get([]const u8, 2);
                if (slice.len != 32) {
                    std.debug.print("ERROR: data_hash length is {d}, expected 32\n", .{slice.len});
                    return error.InvalidDataHashLength;
                }
                var hash: [32]u8 = undefined;
                @memcpy(&hash, slice);
                break :blk hash;
            };

            const created_at = row.get(i64, 3);

            const temp_cache_field = canon.CanonicalMarketCacheField{
                .venue_market_id = venue_market_id,
                .market_id = market_id,
                .data_hash = data_hash,
                .created_at = created_at,
            };

            try cacheMarketsMap.put(venue_market_id, temp_cache_field);
        }

        return cacheMarketsMap;
    }

    pub fn queryForRow(self: *CanonicalDB, query_string: []const u8) !pg.Result {
        log.info("\n\nExample 2", .{});
        // or we can fetch multiple rows:
        var conn = try self.pool.acquire();
        defer conn.release();
        return try conn.row("{}", .{query_string}) orelse unreachable;
    }

    pub fn clearEventsTable(self: *CanonicalDB) !void {
        _ = try self.pool.exec("drop table if exists canonical_events", .{});
    }

    pub fn clearMarketsTable(self: *CanonicalDB) !void {
        _ = try self.pool.exec("drop table if exists canonical_markets", .{});
    }

    pub fn initEventsTable(self: *CanonicalDB) !void {
        const creation_statement =
            \\CREATE TABLE canonical_events (
            \\    event_id        BIGINT PRIMARY KEY,
            \\    venue           TEXT NOT NULL,
            \\    venue_event_id  TEXT NOT NULL,
            \\    event_name        TEXT NOT NULL,
            \\    event_description TEXT,
            \\    event_type        TEXT NOT NULL CHECK (
            \\        event_type IN ('BINARY', 'CATEGORICAL')
            \\    ),
            \\    event_category    TEXT,
            \\    event_tags        TEXT[],
            \\    start_date   TIMESTAMPTZ,
            \\    expiry_date  TIMESTAMPTZ,
            \\    status TEXT NOT NULL CHECK (
            \\        status IN ('active', 'pending', 'resolved', 'cancelled', 'expired')
            \\    ),
            \\    data_hash         BYTEA NOT NULL,               -- hash of canonical fields
            \\    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            \\    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
            \\    UNIQUE (venue, venue_event_id)
            \\);
        ;
        var conn = try self.pool.acquire();
        defer conn.release();
        _ = conn.exec(creation_statement, .{}) catch |err| {
            if (conn.err) |pg_err| {
                std.log.err("table creation failed: {s}", .{pg_err.message});
            }
            return err;
        };
    }

    pub fn initMarketsTable(self: *CanonicalDB) !void {
        const creation_statement =
            \\CREATE TABLE canonical_markets (
            \\    market_id        BIGINT PRIMARY KEY,
            \\    event_id         BIGINT NOT NULL REFERENCES canonical_events(event_id),
            \\    venue            TEXT NOT NULL,
            \\    venue_market_id  TEXT NOT NULL,
            \\    market_description TEXT NOT NULL,
            \\    market_type        TEXT NOT NULL CHECK (
            \\        market_type IN ('BINARY')
            \\    ),
            \\    start_date       TIMESTAMPTZ,
            \\    expiry_date      TIMESTAMPTZ,
            \\    market_status    TEXT NOT NULL CHECK (
            \\        market_status IN (
            \\            'PRE_OPEN',
            \\            'ACTIVE',
            \\            'PENDING_RESOLUTION',
            \\            'RESOLVED',
            \\            'CLOSED'
            \\        )
            \\    ),
            \\    data_hash        BYTEA NOT NULL,
            \\    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            \\    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            \\    UNIQUE (venue, venue_market_id)
            \\);
        ;
        var conn = try self.pool.acquire();
        defer conn.release();
        _ = conn.exec(creation_statement, .{}) catch |err| {
            if (conn.err) |pg_err| {
                std.log.err("table creation failed: {s}", .{pg_err.message});
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
