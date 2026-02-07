pub const ParsedPolymarketMarket = struct {
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

pub const ParsedPolymarketTag = struct {
    id: []u8,
    label: []u8,
    slug: []u8,
};

pub const ParsedPolymarketEvent = struct {
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
