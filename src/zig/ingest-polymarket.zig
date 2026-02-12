const std = @import("std");
const print = std.debug.print;
const http = std.http;
const ArrayList = std.ArrayList;
const constants = @import("consts.zig");
const canon = @import("data/canonical-entities.zig");
const pp = @import("data/polymarket-parsed.zig");
const configs = @import("data/configs.zig");
const cdb = @import("CanonicalDB.zig");
const pg = @import("pg");
const qb = @import("utils/QueryBuilder.zig");
const DateTime = @import("utils/DateTimeUtils.zig");
const SnowFlakeGenerator = @import("utils/SnowFlakeGenerator.zig");

const ParsedEvents = []pp.ParsedPolymarketEvent;

const EVENTS_PER_CALL = 500;

pub fn main() !void {
    var main_timer = try std.time.Timer.start();
    var api_timer: u64 = 0;
    var parse_timer: u64 = 0;
    var api_queries: u64 = 0;
    var total_events: u64 = 0;
    var total_markets: u64 = 0;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // const datacenter_id = try std.fmt.parseInt(u16, std.os.getenv("DATACENTER_ID") orelse "0", 10);
    // const worker_id = try std.fmt.parseInt(u16, std.os.getenv("WORKER_ID") orelse "0", 10);

    var snow_flake_generator = try SnowFlakeGenerator.Snowflake.init(1, 1);

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

    try canonicalDB.clearMarketsTable();
    try canonicalDB.clearEventsTable();
    try canonicalDB.initEventsTable();
    try canonicalDB.initMarketsTable();

    var marketsCache = try canonicalDB.getActiveMarketsFromDB(allocator);
    defer {
        var iter = marketsCache.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        marketsCache.deinit();
    }

    var eventsCache = try canonicalDB.getActiveEventsFromDB(allocator);
    defer {
        var iter = eventsCache.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        eventsCache.deinit();
    }

    var client = http.Client{ .allocator = allocator };
    defer _ = client.deinit();

    var offset: u32 = 0;

    //fetch raw -> find diffs -> write to db
    while (true) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const api_start = main_timer.read();
        const events: std.json.Parsed(ParsedEvents) = try fetchParsedForBatch(arena_alloc, &client, offset);
        const api_end = main_timer.read();
        api_timer += (api_end - api_start);
        api_queries += 1;

        const parse_start = main_timer.read();

        var canonical_events_to_create = try ArrayList(canon.CanonicalEvent).initCapacity(arena_alloc, EVENTS_PER_CALL);
        var canonical_events_to_update = try ArrayList(canon.CanonicalEvent).initCapacity(arena_alloc, EVENTS_PER_CALL);
        var canonical_markets_to_create = try ArrayList(canon.CanonicalMarket).initCapacity(arena_alloc, EVENTS_PER_CALL);
        var canonical_markets_to_update = try ArrayList(canon.CanonicalMarket).initCapacity(arena_alloc, EVENTS_PER_CALL);

        //TODO create a hashset implementation
        var seen_events_set = std.StringHashMap(u1).init(arena_alloc);
        var seen_markets_set = std.StringHashMap(u1).init(arena_alloc);

        for (events.value) |event| {
            const markets = event.markets;
            var event_id: u64 = 0;
            _ = try seen_events_set.put(event.id, 1);
            if (eventsCache.get(event.id)) |cachedEvent| {
                const pulled_event_hash = hashParsedEvent(&event);
                const eventHashesDifferent = try hashesEqual(cachedEvent.data_hash, pulled_event_hash);
                if (!eventHashesDifferent) {
                    // event exists but needs an update
                    event_id = cachedEvent.event_id;

                    try buildCanonicalEventForUpdate(arena_alloc, event, &canonical_events_to_update, pulled_event_hash, cachedEvent, markets.len);
                }
            } else {
                //handle new event
                const new_id = try snow_flake_generator.nextId();
                event_id = new_id;
                try buildCanonicalEventForCreate(arena_alloc, event, &canonical_events_to_create, markets.len, new_id);
            }

            for (markets) |market| {
                try seen_markets_set.put(market.id, 1);
                if (marketsCache.get(market.id)) |cachedMarket| {
                    const pulled_market_hash = hashParsedMarket(&market);
                    const marketHashesDifferent = try hashesEqual(cachedMarket.data_hash, pulled_market_hash);
                    if (!marketHashesDifferent) {
                        //market exists but needs an update
                        try buildCanonicalMarketForUpdate(arena_alloc, market, &canonical_markets_to_update, pulled_market_hash, cachedMarket, event_id);
                    }
                } else {
                    //handle new market
                    const new_id = try snow_flake_generator.nextId();
                    try buildCanonicalMarketForCreate(arena_alloc, market, &canonical_markets_to_create, new_id, event_id);
                }
            }
        }

        //TODO check if cache has events/markets that are not in the seen sets -> if so, need to update them as closed?

        // canonicalDB.updateEvents(canonical_events_to_update);
        // canonicalDB.createEvents(canonical_events_to_create);
        // canonicalDB.updateMarkets(canonical_markets_to_update);
        // canonicalDB.createMarkets(canonical_markets_to_create);

        total_events += canonical_events_to_create.items.len;
        total_markets += canonical_markets_to_create.items.len;

        if (events.value.len < EVENTS_PER_CALL) {
            break;
        }
        offset += EVENTS_PER_CALL;

        //TODO for testing remove
        // if (offset > 10_000) {
        //     break;
        // }

        // break if events comeback as empty

        // or if the number of events is less than our limit
        const parse_end = main_timer.read();
        parse_timer += parse_end - parse_start;
    }

    const api_ms = api_timer / 1_000_000;
    const parse_ms = parse_timer / 1_000_000;
    print("API time: {d} ms\n", .{api_ms});
    print("Parsing time: {d} ms\n", .{parse_ms});
    print("API/Parse: {d} ms\n", .{api_ms / parse_ms});
    print("ms per API Query: {d} ms\n", .{api_ms / api_queries});
    print("TOTAL: {d} events | {d} markets\n", .{ total_events, total_markets });
    print("Total time: {d} ms\n", .{main_timer.read() / 1_000_000});
}

pub fn buildCanonicalMarketForCreate(
    arena_alloc: std.mem.Allocator,
    market: pp.ParsedPolymarketMarket,
    canonical_markets: *ArrayList(canon.CanonicalMarket),
    new_id: u64,
    parent_event_id: u64,
) !void {
    const new_hash = hashParsedMarket(&market);
    const temp_market = try buildCanonicalMarket(
        arena_alloc,
        market,
        new_hash,
        std.time.milliTimestamp(),
        std.time.milliTimestamp(),
        new_id,
        parent_event_id,
    );
    try canonical_markets.append(arena_alloc, temp_market);
}

pub fn buildCanonicalMarketForUpdate(
    arena_alloc: std.mem.Allocator,
    market: pp.ParsedPolymarketMarket,
    canonical_markets: *ArrayList(canon.CanonicalMarket),
    pulled_market_hash: [32]u8,
    cachedMarket: canon.CanonicalMarketCacheField,
    parent_event_id: u64,
) !void {
    const temp_market = try buildCanonicalMarket(
        arena_alloc,
        market,
        pulled_market_hash,
        cachedMarket.created_at,
        std.time.milliTimestamp(),
        cachedMarket.market_id,
        parent_event_id,
    );
    try canonical_markets.append(arena_alloc, temp_market);
}

pub fn buildCanonicalEventForCreate(
    arena_alloc: std.mem.Allocator,
    event: pp.ParsedPolymarketEvent,
    canonical_events_to_create: *ArrayList(canon.CanonicalEvent),
    marketsLen: usize,
    new_id: u64,
) !void {
    const new_hash = hashParsedEvent(&event);
    const created_at = std.time.milliTimestamp();
    const updated_at = std.time.milliTimestamp();
    const internal_id = new_id;
    const temp_event = try buildCanonicalEvent(arena_alloc, event, new_hash, marketsLen, created_at, updated_at, internal_id);
    try canonical_events_to_create.append(arena_alloc, temp_event);
}

pub fn buildCanonicalEventForUpdate(
    arena_alloc: std.mem.Allocator,
    event: pp.ParsedPolymarketEvent,
    canonical_events_to_update: *ArrayList(canon.CanonicalEvent),
    newHash: [32]u8,
    cachedEvent: canon.CanonicalEventCacheField,
    marketsLen: usize,
) !void {
    const temp_event = try buildCanonicalEvent(
        arena_alloc,
        event,
        newHash,
        marketsLen,
        cachedEvent.created_at,
        std.time.milliTimestamp(),
        cachedEvent.event_id,
    );
    try canonical_events_to_update.append(arena_alloc, temp_event);
}

pub fn buildCanonicalEvent(
    arena_alloc: std.mem.Allocator,
    event: pp.ParsedPolymarketEvent,
    newHash: [32]u8,
    marketsLen: usize,
    created_at: i64,
    updated_at: i64,
    internal_id: u64,
) !canon.CanonicalEvent {
    const tags = event.tags;

    // Parse venue event ID
    const venue_event_id = try arena_alloc.dupe(u8, event.id);

    // Build persistent tags array
    const tag_arr = try arena_alloc.alloc([]const u8, tags.len);
    for (tags, 0..) |tag, i| {
        tag_arr[i] = try arena_alloc.dupe(u8, tag.label);
    }

    // Parse dates
    const start_date = try DateTime.ISO_8601_UTC_To_TimestampMs(event.startDate);
    const expiry_date = try DateTime.ISO_8601_UTC_To_TimestampMs(event.endDate);

    // Determine event type based on first market's outcomes
    const event_type = if (marketsLen > 1) canon.EventType.CATEGORICAL else canon.EventType.BINARY;

    // Create canonical event
    return canon.CanonicalEvent{
        .venue_id = canon.VenueID.POLYMARKET,
        .venue_event_id = venue_event_id,
        .event_id = internal_id,
        .event_name = try arena_alloc.dupe(u8, event.title),
        .event_description = try arena_alloc.dupe(u8, event.description),
        .event_type = event_type,
        .event_category = if (tags.len > 0) try arena_alloc.dupe(u8, tags[0].label) else try arena_alloc.dupe(u8, "Uncategorized"),
        .event_tags = tag_arr,
        .start_date = start_date,
        .expiry_date = expiry_date,
        .event_status = determineEventStatus(event.closed),
        .data_hash = newHash,
        .created_at = created_at,
        .updated_at = updated_at,
    };
}

pub fn buildCanonicalMarket(
    arena_alloc: std.mem.Allocator,
    market: pp.ParsedPolymarketMarket,
    new_hash: [32]u8,
    created_at: i64,
    updated_at: i64,
    internal_id: u64,
    parent_event_id: u64,
) !canon.CanonicalMarket {
    const start_date = try DateTime.ISO_8601_UTC_To_TimestampMs(market.startDate);
    const expiry_date = try DateTime.ISO_8601_UTC_To_TimestampMs(market.endDate);

    const status = try determineMarketStatus(arena_alloc, start_date, expiry_date, market);

    const market_type = canon.MarketType.BINARY;

    const outcomes = try parseOutcomes(arena_alloc, market.outcomes, market.clobTokenIds, internal_id);

    return canon.CanonicalMarket{
        .event_id = parent_event_id,
        .venue_market_id = market.id,
        .market_id = internal_id,
        .market_description = market.description,
        .market_status = status,
        .market_type = market_type,
        .outcomes = outcomes,
        .start_date = start_date,
        .expiry_date = expiry_date,
        .data_hash = new_hash,
        .created_at = created_at,
        .updated_at = updated_at,
    };
}

pub fn determineMarketStatus(
    arena_alloc: std.mem.Allocator,
    start_date_ts: i64,
    expiry_date_ts: i64,
    market: pp.ParsedPolymarketMarket,
) !canon.MarketStatus {
    if (std.mem.eql(u8, market.umaResolutionStatus, "resolved")) {
        return .RESOLVED;
    }

    if (std.time.milliTimestamp() < start_date_ts) {
        return .PRE_OPEN;
    }

    if (market.closed or std.time.milliTimestamp() > expiry_date_ts) {
        return .CLOSED;
    }
    const resolutionStates = try parseJsonStringArray(arena_alloc, market.umaResolutionStatuses);

    if (resolutionStates.len > 0) {
        return .PENDING_RESOLUTION;
    }

    return .ACTIVE;
}

pub fn fetchParsedForBatch(allocator: std.mem.Allocator, client: *http.Client, offset: u32) !std.json.Parsed(ParsedEvents) {
    var builder: qb.QueryBuilder = qb.QueryBuilder.init(allocator);
    defer builder.deinit();

    try builder.addInt("limit", EVENTS_PER_CALL);
    try builder.addString("order", "id");
    try builder.addBool("ascending", false);
    try builder.addBool("closed", false);
    try builder.addBool("active", true);
    try builder.addInt("offset", offset);

    var result_body = std.Io.Writer.Allocating.init(allocator);
    defer result_body.deinit();
    const builturl: []u8 = try builder.toUrl(constants.GAMMA_API_URL ++ "/events");
    defer allocator.free(builturl);
    // print("URL = {s}\n", .{builturl});
    const uri = try std.Uri.parse(builturl);
    var request = try client.fetch(.{
        .location = .{ .uri = uri },
        .response_writer = &result_body.writer,
    });
    if (request.status.class() != .success) {
        print("request failed: {?s}", .{request.status.phrase()});
    }
    const sliced_body = try result_body.toOwnedSlice();
    defer allocator.free(sliced_body);

    return try std.json.parseFromSlice(ParsedEvents, allocator, sliced_body, .{ .ignore_unknown_fields = true });
}

// Helper: Determine event status
fn determineEventStatus(closed: bool) canon.EventStatus {
    if (closed) return .CLOSED;
    return .ACTIVE;
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

    // Parse clob token IDs: '["123","456"]' -> ["123", "456"]
    const clob_ids = try parseJsonStringArray(allocator, clob_token_ids_str);

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

    var result = try std.ArrayList([]const u8).initCapacity(allocator, 10);

    var in_string = false;
    var start: usize = 0;

    for (json_str, 0..) |c, i| {
        if (c == '"') {
            if (in_string) {
                // End of string - extract it
                const str = try allocator.dupe(u8, json_str[start..i]);
                try result.append(allocator, str);
                in_string = false;
            } else {
                // Start of string
                start = i + 1;
                in_string = true;
            }
        }
    }

    return result.toOwnedSlice(allocator);
}

pub fn hashParsedEvent(event: *const pp.ParsedPolymarketEvent) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(event.title);
    hasher.update(&[_]u8{0});
    hasher.update(event.description);
    hasher.update(&[_]u8{0});
    for (event.tags) |tag| {
        hasher.update(tag.slug);
        hasher.update(&[_]u8{0});
    }
    hasher.update(event.startDate);
    hasher.update(&[_]u8{0});
    hasher.update(event.endDate);
    hasher.update(&[_]u8{0});
    hasher.update(event.resolutionSource);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    return hash;
}

pub fn hashParsedMarket(market: *const pp.ParsedPolymarketMarket) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(market.question);
    hasher.update(&[_]u8{0});
    hasher.update(market.description);
    hasher.update(&[_]u8{0});
    hasher.update(market.startDate);
    hasher.update(&[_]u8{0});
    hasher.update(market.endDate);
    hasher.update(&[_]u8{0});
    hasher.update(market.clobTokenIds);
    hasher.update(&[_]u8{0});
    hasher.update(market.outcomes);
    hasher.update(&[_]u8{0});
    hasher.update(market.umaResolutionStatus);
    hasher.update(&[_]u8{0});
    hasher.update(market.umaResolutionStatuses);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    return hash;
}

pub fn hashesEqual(hash_one: [32]u8, hash_two: [32]u8) !bool {
    for (hash_one, 0..) |v, i| {
        if (v != hash_two[i]) {
            return false;
        }
    }
    return true;
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
