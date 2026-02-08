const std = @import("std");
const print = std.debug.print;
const http = std.http;
const constants = @import("consts.zig");
const canon = @import("data/canonical-entities.zig");
const pp = @import("data/polymarket-parsed.zig");
const configs = @import("data/configs.zig");
const cdb = @import("CanonicalDB.zig");
const ArrayList = std.ArrayList;
const pg = @import("pg");

const ParsedEvents = []pp.ParsedPolymarketEvent;

const EVENTS_PER_CALL = 100;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    //Get full active event list into memeory
    const canonical_db_config = configs.CanonicalDBConfig{
        .pool_size = 5,
        .port = 5432,
        .host = "127.0.0.1",
        .username = "postgres",
        .password = "postgres",
        .database = "postgres",
        .timeout = 10_000,
    };

    //Clear and create table - temp for testing
    var canonicalDB = try cdb.CanonicalDB.init(gpa.allocator(), canonical_db_config);
    defer canonicalDB.deinit();
    try canonicalDB.clearTable();
    const creation_statement =
        \\CREATE TABLE canonical_events (
        \\    event_id        BIGINT PRIMARY KEY,
        \\    venue           TEXT NOT NULL,
        \\    venue_event_id  TEXT NOT NULL,
        \\    event_name        TEXT NOT NULL,
        \\    event_description TEXT,
        \\    event_type        TEXT,
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
    try canonicalDB.initTable(creation_statement);

    const full_event_id_query =
        \\SELECT
        \\venue_event_id,
        \\event_id,
        \\updated_at,
        \\expiry_date,
        \\status
        \\FROM canonical_events
        \\WHERE venue = 'polymarket'
        \\AND status IN ('active', 'pending')
    ;

    //TODO set this into local memory? or just save for reference? Maybe just extract the info you need into an array and toss the result
    const full_event_table = try canonicalDB.queryForResultAllocated(gpa.allocator(), full_event_id_query);
    defer full_event_table.deinit();

    var client = http.Client{ .allocator = gpa.allocator() };
    defer _ = client.deinit();

    var result_body = std.Io.Writer.Allocating.init(gpa.allocator());
    defer result_body.deinit();

    const uri = try std.Uri.parse(constants.GAMMA_API_URL ++ "/" ++ "events");
    var request = try client.fetch(.{
        .location = .{ .uri = uri },
        .response_writer = &result_body.writer,
    });

    if (request.status.class() == .success) {
        //TODO improve logging for request failure/success
        // print("{s}", .{result_body.written()});
        // print("Type: {}", .{@TypeOf(result_body)});
    } else {
        print("request failed: {?s}", .{request.status.phrase()});
    }
    const sliced_body = try result_body.toOwnedSlice();
    defer gpa.allocator().free(sliced_body);

    const events: std.json.Parsed(ParsedEvents) = try std.json.parseFromSlice(ParsedEvents, gpa.allocator(), sliced_body, .{ .ignore_unknown_fields = true });
    defer events.deinit();

    var canonical_events = try ArrayList(canon.CanonicalEvent).initCapacity(gpa.allocator(), EVENTS_PER_CALL);
    defer canonical_events.deinit(gpa.allocator());

    var canonical_markets = try ArrayList(canon.CanonicalMarket).initCapacity(gpa.allocator(), EVENTS_PER_CALL);
    defer canonical_markets.deinit(gpa.allocator());

    // If already exists -> diff canonical fields
    //
    // If doesn't exist ->
    //

    // for (events.value) |event| {

    //     const markets = event.markets;
    //     const tags = event.tags;
    //     const venue_event_id = try std.fmt.parseInt(u64, event.id, 10);

    //     const tag_arr = try gpa.allocator().alloc([]const u8, tags.len);
    //     defer gpa.allocator().free(tag_arr);
    //     for (tags, 0..) |tag, i| {
    //         tag_arr[i] = tag.label;
    //     }

    //     for (markets) |market| {

    //         const temp_market: canon.CanonicalMarket = canon.CanonicalMarket {
    //             .venue_market_id =
    //             .event_id = ,
    //             .market_id = ,
    //             .market_description = ,
    //             .start_date = ,
    //             .expiry_date = ,
    //             .market_status = ,
    //             .market_type = ,
    //             .outcomes = ,
    //         }
    //     }

    //     const temp_event: canon.CanonicalEvent = canon.CanonicalEvent{
    //         .venue_id = canon.VenueID.POLYMARKET,
    //         .venue_event_id = venue_event_id,
    //         .event_id = 123,
    //         .event_name = "name",
    //         .event_description = "desc",
    //         .event_type = canon.EventType.BINARY,
    //         .event_category = "cat",
    //         .event_tags = tag_arr,
    //         .start_date = 45678,
    //         .expiry_date = 98765,
    //         .event_status = canon.EventStatus.ACTIVE,
    //     };

    //     try canonical_events.append(gpa.allocator(), temp_event);
    // }
    print("hello", .{});

    for (canonical_events.items) |cevent| {
        print("{}\n", .{cevent.event_id});
    }
}
