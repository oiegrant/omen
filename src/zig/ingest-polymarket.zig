const std = @import("std");
const print = std.debug.print;
const http = std.http;
pub const constants = @import("consts.zig");

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

// message Market {
//   string market_type = 5; // binary, categorical, scalar
//   string settlement_rule = 8;
//   string initial_state = 9;
// }

// message MarketUpdated {
//   string market_id = 1;
//   string market_description = 2;
//   google.protobuf.Timestamp updated_at = 3;
// }

// message MarketStateUpdated {
//   string market_id = 1;
//   enum MarketState {
//     PRE_OPEN = 0;
//     OPEN = 1;
//     HALTED = 2;
//     RESOLVED = 3;
//     DISPUTED = 4;
//   }
//   MarketState previous_state = 2;
//   MarketState new_state = 3;
//   google.protobuf.Timestamp timestamp = 4;
//   string reason = 5;
// }

// message MarketResolved {
//   string market_id = 1;
//   string resolved_outcome_id = 2;
//   double payout_value = 3;
//   google.protobuf.Timestamp resolution_time = 4;
//   double confidence_level = 5;
// }

const ParsedEvents = []ParsedPolymarketEvent;

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
}
