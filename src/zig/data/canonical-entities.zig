const std = @import("std");
pub const EventType = enum { BINARY, CATEGORICAL };
pub const MarketType = enum { BINARY };
pub const EventStatus = enum { ACTIVE, PENDING_RESOLUTION, RESOLVED, CANCELLED, CLOSED };
pub const MarketStatus = enum { PRE_OPEN, ACTIVE, PENDING_RESOLUTION, RESOLVED, DISPUTED, CANCELLED, CLOSED };
pub const VenueID = enum { POLYMARKET, KALSHI };
pub const OrderSide = enum { BID, ASK };
pub const OrderStatus = enum { OPEN, FILLED, PARTIAL, CANCELLED };

pub const CanonicalVenue = struct {
    name: []u8,
    underlying_asset: []u8, //USDC
};

pub const CanonicalEvent = struct {
    venue_id: VenueID,
    venue_event_id: u64,
    event_id: u64,
    event_name: []const u8,
    event_description: []const u8,
    event_type: EventType,
    event_category: []const u8,
    event_tags: []const []const u8,
    start_date: i64,
    expiry_date: i64,
    event_status: EventStatus,
};

pub const CanonicalMarket = struct {
    venue_market_id: u64,
    event_id: u64,
    market_id: u64,
    market_description: []const u8,
    market_type: MarketType,
    start_date: i64,
    expiry_date: i64,
    market_status: MarketStatus,
    outcomes: []CanonicalOutcome,
};

pub const CanonicalOutcome = struct {
    market_id: u64,
    outcome_id: u64,
    outcome_name: []const u8,
    token_id: []const u8,
    clob_token_id: []const u8,
};

pub const CanonicalOrder = struct {
    order_id: u64,
    market_id: u64,
    outcome_id: u64,
    side: OrderSide,
    price: f64,
    quantity: f64,
    status: OrderStatus,
    timestamp: i64,
};

pub const CanonicalTrade = struct {
    trade_id: u64,
    market_id: u64,
    outcome_id: u64,
    price: f64,
    quantity: f64,
    maker_order_id: u64,
    taker_order_id: u64,
    timestamp: i64,
};

pub const CanonicalResolution = struct {
    resolution_id: u64,
    event_id: u64,
    market_id: u64,
    outcome_id: u64,
    resolution_time: i64,
    resolved_value: []const u8,
    source: []const u8,
};
