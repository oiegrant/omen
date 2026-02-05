# Information model
Canonical facts (never change, or change rarely)
  - e.g. event_id, question being asked in market, 
Stateful facts (change, but have a single source of truth)
  - e.g. market status, order/transaction status, current best ask/bid, 
Derived metrics (change constantly, computed, recomputable)
  - e.g. volume, liquidity, spread, volatility

### All timestamps are in ms UTC

### unique internal ids are Snowflake-style u64 IDs : bit pattern : 41bits timestamp |10 bits sourceid | 12 bits sequence

# Entities
## Entity Descriptions
  - Venue
    - Polymarket, Kalshi, etc.
  - Event
    - A real-workd question that resolves to a single truth value
    - What price will bitcoin be at 1/1/2026 1PM ET?
    - Will it rain tomorrow?
  - Market
    - A binary tradeable market
    - There can be multiple markets per event (bitcoin example) : $10-$20, $20-$30, etc.
    - Or there can be a single market per event (rain example) : Yes, No
  - Outcome
    - Each side of a market is an Outcome
  - Order
    - an order places - as represented in the CLOB
  - Trade
    - a trade at market price
  - Resolution
    - final winning/losing outcome value ($1/$0)
  - MarketState
    - state to allow filtering of streaming, tracking, client-side rendering decisions
      
  - Transaction
    - venue-specific semantics wrapper
  - CLOB
    - derived - snapshot + deltas

## Entity Fields
  Final entity fields defined in canonical-entities.zig
