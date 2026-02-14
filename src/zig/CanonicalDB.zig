const std = @import("std");
const pg = @import("pg");
const builtin = @import("builtin");
const configs = @import("data/configs.zig");
pub const log = std.log.scoped(.example);
const canon = @import("data/canonical-entities.zig");
const ArrayList = std.ArrayList;

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
            \\WHERE venue = 'POLYMARKET'
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

    pub fn upsertEvents(self: *CanonicalDB, events: ArrayList(canon.CanonicalEvent)) !void {
        if (events.items.len == 0) return;

        // Start transaction
        try self.exec("BEGIN");
        errdefer self.exec("ROLLBACK") catch {};

        for (events.items) |event| {
            const event_type_str = switch (event.event_type) {
                .BINARY => "BINARY",
                .CATEGORICAL => "CATEGORICAL",
            };

            const status_str = switch (event.event_status) {
                .ACTIVE => "active",
                .CLOSED => "closed",
            };

            const venue_str = @tagName(event.venue_id);

            // Use ON CONFLICT to handle upserts
            _ = try self.pool.exec(
                \\INSERT INTO canonical_events (
                \\  event_id, venue, venue_event_id, event_name, event_description,
                \\  event_type, event_category, event_tags, start_date, expiry_date,
                \\  status, data_hash, created_at, updated_at
                \\) VALUES (
                \\  $1, $2, $3, $4, $5, $6, $7, $8,
                \\  $9, $10, $11, $12,
                \\  $13, $14
                \\)
                \\ON CONFLICT (venue, venue_event_id) DO UPDATE SET
                \\  venue = EXCLUDED.venue,
                \\  venue_event_id = EXCLUDED.venue_event_id,
                \\  event_name = EXCLUDED.event_name,
                \\  event_description = EXCLUDED.event_description,
                \\  event_type = EXCLUDED.event_type,
                \\  event_category = EXCLUDED.event_category,
                \\  event_tags = EXCLUDED.event_tags,
                \\  start_date = EXCLUDED.start_date,
                \\  expiry_date = EXCLUDED.expiry_date,
                \\  status = EXCLUDED.status,
                \\  data_hash = EXCLUDED.data_hash,
                \\  updated_at = $14
            , .{
                event.event_id,
                venue_str,
                event.venue_event_id,
                event.event_name,
                event.event_description,
                event_type_str,
                event.event_category,
                event.event_tags,
                event.start_date,
                event.expiry_date,
                status_str,
                &event.data_hash,
                event.created_at,
                event.updated_at,
            });
        }
        try self.exec("COMMIT");
    }

    pub fn updateEventsBulk(self: *CanonicalDB, events_to_update: ArrayList(canon.CanonicalEvent)) !void {
        if (events_to_update.items.len == 0) return;

        const allocator = self.allocator;

        // Start transaction
        try self.exec("BEGIN");
        errdefer self.exec("ROLLBACK") catch {};

        // Create temporary table with same structure
        try self.exec(
            \\CREATE TEMP TABLE temp_event_updates (
            \\  event_id BIGINT PRIMARY KEY,
            \\  venue TEXT NOT NULL,
            \\  venue_event_id TEXT NOT NULL,
            \\  event_name TEXT NOT NULL,
            \\  event_description TEXT,
            \\  event_type TEXT NOT NULL,
            \\  event_category TEXT,
            \\  event_tags TEXT[],
            \\  start_date TIMESTAMPTZ,
            \\  expiry_date TIMESTAMPTZ,
            \\  status TEXT NOT NULL,
            \\  data_hash BYTEA NOT NULL
            \\) ON COMMIT DROP
        );

        // Prepare CSV data for COPY
        var csv_buffer = std.ArrayList(u8).init(allocator);
        defer csv_buffer.deinit();

        for (events_to_update.items) |event| {
            const venue_str = @tagName(event.venue_id);

            const event_type_str = switch (event.event_type) {
                .BINARY => "BINARY",
                .CATEGORICAL => "CATEGORICAL",
            };

            const status_str = switch (event.event_status) {
                .active => "active",
                .pending => "pending",
                .resolved => "resolved",
                .cancelled => "cancelled",
                .expired => "expired",
            };

            // Build array string: {tag1,tag2,tag3}
            var tags_str = std.ArrayList(u8).init(allocator);
            defer tags_str.deinit();
            try tags_str.append('{');
            for (event.event_tags, 0..) |tag, i| {
                if (i > 0) try tags_str.append(',');
                // Escape quotes in tags
                try tags_str.append('"');
                for (tag) |c| {
                    if (c == '"') try tags_str.appendSlice("\\\"") else try tags_str.append(c);
                }
                try tags_str.append('"');
            }
            try tags_str.append('}');

            // Convert data_hash to hex string for BYTEA
            var hash_hex = std.ArrayList(u8).init(allocator);
            defer hash_hex.deinit();
            try hash_hex.appendSlice("\\\\x"); // Escaped backslash for CSV
            for (event.data_hash) |byte| {
                try hash_hex.writer().print("{x:0>2}", .{byte});
            }

            // Escape description for CSV
            var escaped_desc = std.ArrayList(u8).init(allocator);
            defer escaped_desc.deinit();
            for (event.event_description) |c| {
                if (c == '\t' or c == '\n' or c == '\r' or c == '\\') {
                    try escaped_desc.append('\\');
                }
                try escaped_desc.append(c);
            }

            // Build CSV row (tab-delimited)
            try csv_buffer.writer().print("{d}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{d}\t{d}\t{s}\t{s}\n", .{
                event.event_id,
                venue_str,
                event.venue_event_id,
                event.event_name,
                escaped_desc.items,
                event_type_str,
                event.event_category,
                tags_str.items,
                event.start_date,
                event.expiry_date,
                status_str,
                hash_hex.items,
            });
        }

        // Execute COPY command
        // Note: Syntax depends on your PostgreSQL driver
        // If your driver supports COPY FROM STDIN:
        try self.pool.copyFrom("COPY temp_event_updates FROM STDIN WITH (FORMAT csv, DELIMITER E'\\t', NULL '')", csv_buffer.items);

        // Perform the bulk update
        try self.exec(
            \\UPDATE canonical_events ce
            \\SET
            \\  venue = tmp.venue,
            \\  venue_event_id = tmp.venue_event_id,
            \\  event_name = tmp.event_name,
            \\  event_description = tmp.event_description,
            \\  event_type = tmp.event_type,
            \\  event_category = tmp.event_category,
            \\  event_tags = tmp.event_tags,
            \\  start_date = tmp.start_date,
            \\  expiry_date = tmp.expiry_date,
            \\  status = tmp.status,
            \\  data_hash = tmp.data_hash,
            \\  updated_at = now()
            \\FROM temp_event_updates tmp
            \\WHERE ce.event_id = tmp.event_id
        );

        // Commit transaction (temp table auto-drops)
        try self.exec("COMMIT");
    }

    // pub fn updateMarkets(markets_to_update: ArrayList(canon.CanonicalMarket)) !void {}
    // pub fn createMarkets(markets_to_create: ArrayList(canon.CanonicalMarket)) !void {}

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
            \\    start_date   BIGINT,
            \\    expiry_date  BIGINT,
            \\    status TEXT NOT NULL CHECK (
            \\        status IN ('active', 'pending', 'resolved', 'cancelled', 'expired')
            \\    ),
            \\    data_hash         BYTEA NOT NULL,               -- hash of canonical fields
            \\    created_at        BIGINT NOT NULL,
            \\    updated_at        BIGINT NOT NULL,
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
