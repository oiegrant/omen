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
const qb = @import("utils/QueryBuilder.zig");

const ParsedEvents = []pp.ParsedPolymarketEvent;

const EVENTS_PER_CALL = 100;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    //Get full active event list into memeory
    //TODO configManager based on config name
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
    var canonicalDB = try cdb.CanonicalDB.init(allocator, canonical_db_config);
    defer canonicalDB.deinit();

    try canonicalDB.clearTable();
    try canonicalDB.initTable();

    var eventsCache = try canonicalDB.getActiveEventsFromDB(allocator);
    defer {
        var iter = eventsCache.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        eventsCache.deinit(allocator);
    }

    var marketsCache = try canonicalDB.getActiveMarketsFromDB(allocator);
    defer {
        var iter = eventsCache.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        marketsCache.deinit(allocator);
    }

    var client = http.Client{ .allocator = allocator };
    defer _ = client.deinit();

    var builder: qb.QueryBuilder = qb.QueryBuilder.init(allocator);
    defer builder.deinit();

    try builder.addInt("limit", EVENTS_PER_CALL);
    try builder.addString("order", "id");
    try builder.addBool("ascending", false);
    try builder.addBool("closed", false);
    try builder.addBool("active", true);

    var offset: u32 = 0;

    //fetch raw -> find diffs -> write to db
    while (true) {
        try builder.addInt("offset", offset);
        const events: std.json.Parsed(ParsedEvents) = try fetchParsedForBatch(allocator, &client, builder);
        defer events.deinit();

        var canonical_events_to_create = try ArrayList(canon.CanonicalEvent).initCapacity(allocator, EVENTS_PER_CALL);
        defer canonical_events_to_create.deinit(allocator);
        var canonical_events_to_update = try ArrayList(canon.CanonicalEvent).initCapacity(allocator, EVENTS_PER_CALL);
        defer canonical_events_to_update.deinit(allocator);
        var canonical_markets_to_create = try ArrayList(canon.CanonicalMarket).initCapacity(allocator, EVENTS_PER_CALL);
        defer canonical_markets_to_create.deinit(allocator);
        var canonical_markets_to_update = try ArrayList(canon.CanonicalMarket).initCapacity(allocator, EVENTS_PER_CALL);
        defer canonical_markets_to_update.deinit(allocator);

        var seen_events_set = std.AutoHashMap([]const u8, null).init(allocator);
        defer seen_events_set.deinit();

        var seen_markets_set = std.AutoHashMap([]const u8, null).init(allocator);
        defer seen_markets_set.deinit();

        for (events.value) |event| {
            seen_events_set.put(event.id, null);
            if (eventsCache.get(event.id)) |cachedEvent| {
                const pulled_event_hash = hashEventCanonical(allocator, event);
                if (cachedEvent.data_hash != pulled_event_hash) {
                    // event exists but needs an update
                    buildCanonicalEventForUpdate(allocator, event, &canonical_events_to_update, pulled_event_hash);
                }
            } else {
                //handle new event
                buildCanonicalEventForCreate(allocator, event, &canonical_events_to_create);
            }

            const markets = event.markets;
            for (markets) |market| {
                seen_markets_set.put(market.id, null);
                if (marketsCache.get(market.id)) |cachedMarket| {
                    const pulled_market_hash = hashMarket(allocator, market);
                    if (cachedMarket.data_hash != pulled_market_hash) {
                        //market exists but needs an update
                        buildCanonicalMarketForUpdate(allocator, market, &canonical_markets_to_update, pulled_market_hash);
                    }
                } else {
                    //handle new market
                    buildCanonicalMarketForCreate(allocator, market, &canonical_markets_to_create);
                }
            }
        }

        //check if cache has events/markets that are not in the seen sets -> if so, need to update them as closed?

        canonicalDB.updateEvents(canonical_events_to_update);
        canonicalDB.createEvents(canonical_events_to_create);
        canonicalDB.updateMarkets(canonical_markets_to_update);
        canonicalDB.createMarkets(canonical_markets_to_create);

        if (events.value.len < EVENTS_PER_CALL) {
            break;
        }
        offset += EVENTS_PER_CALL;

        //TODO remove temp
        if (offset > 1000) {
            break;
        }

        // break if events comeback as empty

        // or if the number of events is less than our limit
    }
}

pub fn fetchParsedForBatch(allocator: std.mem.Allocator, client: *http.Client, builder: qb.QueryBuilder) !std.json.Parsed(ParsedEvents) {
    var result_body = std.Io.Writer.Allocating.init(allocator);
    defer result_body.deinit();
    const builturl: []u8 = try builder.toUrl(constants.GAMMA_API_URL ++ "/events");
    defer allocator.free(builturl);
    print("URL = {s}\n", .{builturl});
    const uri = try std.Uri.parse(builturl);
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
    defer allocator.free(sliced_body);

    return try std.json.parseFromSlice(ParsedEvents, allocator, sliced_body, .{ .ignore_unknown_fields = true });
}

pub fn parseToCanonicalData(
    allocator: std.mem.Allocator,
    events: std.json.Parsed(ParsedEvents),
    canonical_events: *std.ArrayList(canon.CanonicalEvent),
    canonical_markets: *std.ArrayList(canon.CanonicalMarket),
) !void {
    for (events.value) |event| {
        const markets = event.markets;
        const tags = event.tags;

        // Parse venue event ID
        const venue_event_id = try allocator.dupe(u8, event.id);
        const event_id = try std.fmt.parseInt(u64, event.id, 10); //TODO GO how do we handle events here?

        // Build persistent tags array
        const tag_arr = try allocator.alloc([]const u8, tags.len);
        for (tags, 0..) |tag, i| {
            tag_arr[i] = try allocator.dupe(u8, tag.label);
        }

        // Parse dates
        const start_date = try parseDateToTimestamp(event.startDate);
        const expiry_date = try parseDateToTimestamp(event.endDate);

        // Determine event type based on first market's outcomes
        const event_type = if (markets.len > 0)
            try determineEventType(markets[0].outcomes)
        else
            canon.EventType.BINARY;

        // Process each market
        for (markets) |market| {
            const market_id = try std.fmt.parseInt(u64, market.id, 10);

            // Parse outcomes from JSON-like strings
            const outcomes = try parseOutcomes(allocator, market.outcomes, market.clobTokenIds, market_id);

            const market_start_date = try parseDateToTimestamp(market.startDate);
            const market_expiry_date = try parseDateToTimestamp(market.endDate);

            const temp_market = canon.CanonicalMarket{
                .venue_market_id = try allocator.dupe(u8, market.id),
                .event_id = event_id,
                .market_id = market_id,
                .market_description = try allocator.dupe(u8, if (market.question.len > 0) market.question else market.description),
                .start_date = market_start_date,
                .expiry_date = market_expiry_date,
                .market_status = determineMarketStatus(market.active, market.closed, market.umaResolutionStatus),
                .market_type = canon.MarketType.BINARY,
                .outcomes = outcomes,
            };

            try canonical_markets.append(temp_market);
        }

        // Create canonical event
        const temp_event = canon.CanonicalEvent{
            .venue_id = canon.VenueID.POLYMARKET,
            .venue_event_id = venue_event_id,
            .event_id = event_id,
            .event_name = try allocator.dupe(u8, event.title),
            .event_description = try allocator.dupe(u8, event.description),
            .event_type = event_type,
            .event_category = if (tags.len > 0) try allocator.dupe(u8, tags[0].label) else try allocator.dupe(u8, "Uncategorized"),
            .event_tags = tag_arr,
            .start_date = start_date,
            .expiry_date = expiry_date,
            .event_status = determineEventStatus(event.active, event.closed),
        };

        try canonical_events.append(temp_event);
    }
}

// Helper: Parse ISO 8601 date string to Unix timestamp
fn parseDateToTimestamp(date_str: []const u8) !i64 {
    if (date_str.len == 0) return 0;

    // Expected format: "2024-12-31T23:59:59Z" or similar
    // For a quick implementation, you might use a library or manual parsing
    // Here's a simplified version that assumes ISO format

    // Simple approach: try to use std functions or return 0 for now
    // You may want to use a proper date parsing library

    // Placeholder - parse using your preferred method
    // This is a stub - you'll need proper ISO 8601 parsing
    _ = date_str;
    return 0; // TODO: Implement proper date parsing
}

// Helper: Determine event status
fn determineEventStatus(active: bool, closed: bool) canon.EventStatus {
    if (closed) return .CLOSED;
    if (active) return .ACTIVE;
    return .PENDING_RESOLUTION;
}

// Helper: Determine market status
fn determineMarketStatus(active: bool, closed: bool, resolution_status: []const u8) canon.MarketStatus {
    if (resolution_status.len > 0 and !std.mem.eql(u8, resolution_status, "")) {
        if (std.mem.eql(u8, resolution_status, "disputed")) return .DISPUTED;
        if (std.mem.eql(u8, resolution_status, "resolved")) return .RESOLVED;
    }
    if (closed) return .CLOSED;
    if (active) return .ACTIVE;
    return .PRE_OPEN;
}

// Helper: Determine event type from outcomes string
fn determineEventType(outcomes_str: []const u8) !canon.EventType {
    // outcomes_str might be like: '["Yes","No"]' or '["Option A","Option B","Option C"]'
    // Count commas to estimate number of outcomes (rough heuristic)
    var comma_count: usize = 0;
    for (outcomes_str) |c| {
        if (c == ',') comma_count += 1;
    }

    // If 1 comma, likely 2 outcomes (binary)
    // If more commas, likely categorical
    return if (comma_count <= 1) .BINARY else .CATEGORICAL;
}

// Helper: Parse outcomes and clob token IDs from JSON-like strings
fn parseOutcomes(
    allocator: std.mem.Allocator,
    outcomes_str: []const u8,
    clob_token_ids_str: []const u8,
    market_id: u64,
) ![]canon.CanonicalOutcome {
    // Parse outcomes: '["Yes","No"]' -> ["Yes", "No"]
    const outcome_names = try parseJsonStringArray(allocator, outcomes_str);
    defer {
        for (outcome_names) |name| allocator.free(name);
        allocator.free(outcome_names);
    }

    // Parse clob token IDs: '["123","456"]' -> ["123", "456"]
    const clob_ids = try parseJsonStringArray(allocator, clob_token_ids_str);
    defer {
        for (clob_ids) |id| allocator.free(id);
        allocator.free(clob_ids);
    }

    // Create outcomes array
    const outcomes = try allocator.alloc(canon.CanonicalOutcome, outcome_names.len);
    for (outcomes, 0..) |*outcome, i| {
        outcome.* = canon.CanonicalOutcome{
            .market_id = market_id,
            .outcome_id = i,
            .outcome_name = try allocator.dupe(u8, outcome_names[i]),
            .token_id = try allocator.dupe(u8, if (i < clob_ids.len) clob_ids[i] else ""),
            .clob_token_id = try allocator.dupe(u8, if (i < clob_ids.len) clob_ids[i] else ""),
        };
    }

    return outcomes;
}

// Helper: Parse JSON string array like '["Yes","No"]'
fn parseJsonStringArray(allocator: std.mem.Allocator, json_str: []const u8) ![][]const u8 {
    if (json_str.len == 0) return try allocator.alloc([]const u8, 0);

    var result = std.ArrayList([]const u8).init(allocator);
    defer result.deinit();

    var in_string = false;
    var start: usize = 0;

    for (json_str, 0..) |c, i| {
        if (c == '"') {
            if (in_string) {
                // End of string - extract it
                const str = try allocator.dupe(u8, json_str[start..i]);
                try result.append(str);
                in_string = false;
            } else {
                // Start of string
                start = i + 1;
                in_string = true;
            }
        }
    }

    return result.toOwnedSlice();
}

pub fn hashEventCanonical(
    allocator: std.mem.Allocator,
    event: *const canon.CanonicalEvent,
) ![32]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();

    // IMPORTANT: fixed order, fixed encoding
    try buf.appendSlice(event.event_name);
    try buf.append(0);

    try buf.appendSlice(event.event_description);
    try buf.append(0);

    try buf.appendSlice(event.event_type);
    try buf.append(0);

    try buf.appendSlice(event.event_category);
    try buf.append(0);

    for (event.event_tags) |tag| {
        try buf.appendSlice(tag);
        try buf.append(0);
    }

    try buf.writer().print("{d}", .{event.start_date_unix});
    try buf.append(0);

    try buf.writer().print("{d}", .{event.expiry_date_unix});
    try buf.append(0);

    try buf.appendSlice(event.resolution_source);

    // SHA-256
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(buf.items, &hash, .{});

    return hash;
}

pub fn f() !void {}

//A sample write to view data
// const test_data =
//     \\INSERT INTO canonical_events (
//     \\        event_id, venue, venue_event_id, event_name, event_description,
//     \\        event_type, event_category, event_tags, start_date, expiry_date,
//     \\        status, data_hash
//     \\    ) VALUES (
//     \\        12345,
//     \\        'polymarket',
//     \\        'PM-001',
//     \\        'Test Event',
//     \\        'This is a test event for debugging',
//     \\        'market',
//     \\        'finance',
//     \\        ARRAY['test', 'debug'],
//     \\        now(),
//     \\        now() + interval '7 days',
//     \\        'active',
//     \\        decode('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'hex')
//     \\    )
//     \\    ON CONFLICT (venue, venue_event_id) DO NOTHING;
// ;
// try canonicalDB.exec(test_data);
