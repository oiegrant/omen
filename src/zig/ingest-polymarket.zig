const std = @import("std");
const print = std.debug.print;
const http = std.http;
const constants = @import("consts.zig");
const canon = @import("data/canonical-entities.zig");
const ArrayList = std.ArrayList;

const ParsedPolymarketMarket = struct {
    id: []u8 = "",
    question: []u8 = "",
    description: []u8 = "",
    startDate: []u8 = "",
    endDate: []u8 = "",
    outcomes: []u8 = "",
    active: bool = false,
    closed: bool = false,
    createdAt: []u8 = "",
    clobTokenIds: []u8 = "",
    negRisk: bool = false,
    negRiskMarketID: []u8 = "",
    umaResolutionStatus: []u8 = "",
    umaResolutionStatuses: []u8 = "",
    holdingRewardsEnabled: bool = false,
    feesEnabled: bool = false,
    groupItemTitle: []u8 = "",
    conditionId: []u8 = "",
};

const ParsedPolymarketTag = struct {
    id: []u8,
    label: []u8,
    slug: []u8,
};

const ParsedPolymarketEvent = struct {
    id: []u8 = "",
    title: []u8 = "",
    description: []u8 = "",
    creationDate: []u8 = "",
    startDate: []u8 = "",
    endDate: []u8 = "",
    tags: []ParsedPolymarketTag = undefined,
    markets: []ParsedPolymarketMarket = undefined,
    negRisk: bool = false,
    resolutionSource: []u8 = "",
    active: bool,
    closed: bool,
    negRiskMarketID: []u8 = "",
};

const ParsedEvents = []ParsedPolymarketEvent;

const EVENTS_PER_CALL = 100;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

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

    //get polymarket event id and check for existance in db
    // SELECT event_id
    // FROM events
    // WHERE venue = "polymarket" AND venue_event_id = ?
    //
    // If already exists -> diff canonical fields
    //
    // If doesn't exist ->
    //

    for (events.value) |event| {

        const markets = event.markets;
        const tags = event.tags;
        const venue_event_id = try std.fmt.parseInt(u64, event.id, 10);

        const tag_arr = try gpa.allocator().alloc([]const u8, tags.len);
        defer gpa.allocator().free(tag_arr);
        for (tags, 0..) |tag, i| {
            tag_arr[i] = tag.label;
        }


        for (markets) |market| {



            const temp_market: canon.CanonicalMarket = canon.CanonicalMarket {
                .venue_market_id =
                .event_id = ,
                .market_id = ,
                .market_description = ,
                .start_date = ,
                .expiry_date = ,
                .market_status = ,
                .market_type = ,
                .outcomes = ,
            }
        }

        const temp_event: canon.CanonicalEvent = canon.CanonicalEvent{
            .venue_id = canon.VenueID.POLYMARKET,
            .venue_event_id = venue_event_id,
            .event_id = 123,
            .event_name = "name",
            .event_description = "desc",
            .event_type = canon.EventType.BINARY,
            .event_category = "cat",
            .event_tags = tag_arr,
            .start_date = 45678,
            .expiry_date = 98765,
            .event_status = canon.EventStatus.ACTIVE,
        };

        try canonical_events.append(gpa.allocator(), temp_event);
    }

    for (canonical_events.items) |cevent| {
        print("{}\n", .{cevent.event_id});
    }
}

pub fn
