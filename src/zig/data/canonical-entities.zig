const std = @import("std");
const EventType = enum { BINARY, CATEGORICAL };
const MarketType = enum { BINARY };
const EventStatus = enum { ACTIVE, PENDING_RESOLUTION, RESOLVED, CANCELLED, CLOSED };
const MarketStatus = enum { PRE_OPEN, ACTIVE, PENDING_RESOLUTION, RESOLVED, DISPUTED, CANCELLED, CLOSED };
const VenueID = enum { POLYMARKET, KALSHI };
const OrderSide = enum { BID, ASK };
const OrderStatus = enum { OPEN, FILLED, PARTIAL, CANCELLED };

const Venue = struct {
    venue_id: VenueID,
    underlying_asset: []u8, //USDC
};

const CanonicalEvent = struct {
    venue_id: VenueID,
    venue_event_id: u64,
    event_id: u64,
    event_name: []u8,
    event_description: []u8,
    event_type: EventType,
    event_category: []u8,
    event_tags: [][]u8,
    start_date: i64,
    expiry_date: i64,
    event_status: EventStatus,
};

const CanonicalMarket = struct {
    venue_market_id: u64,
    event_id: u64,
    market_id: u64,
    market_description: []u8,
    market_type: MarketType,
    start_date: i64,
    expiry_date: i64,
    market_status: MarketStatus,
    outcomes: []Outcome,
};

const Outcome = struct {
    market_id: u64,
    outcome_id: u64,
    outcome_name: []u8,
    token_id: []u8,
    clob_token_id: []u8,
};

const CanonicalOrder = struct {
    order_id: u64,
    market_id: u64,
    outcome_id: u64,
    side: OrderSide,
    price: f64,
    quantity: f64,
    status: OrderStatus,
    timestamp: i64,
};

const CanonicalTrade = struct {
    trade_id: u64,
    market_id: u64,
    outcome_id: u64,
    price: f64,
    quantity: f64,
    maker_order_id: u64,
    taker_order_id: u64,
    timestamp: i64,
};

const CanonicalResolution = struct {
    resolution_id: u64,
    event_id: u64,
    market_id: u64,
    outcome_id: u64,
    resolution_time: i64,
    resolved_value: []u8,
    source: []u8,
};
