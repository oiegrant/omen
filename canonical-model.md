# Information model
Canonical facts (never change, or change rarely)
  - e.g. event_id, question being asked in market, 
Stateful facts (change, but have a single source of truth)
  - e.g. market status, order/transaction status, current best ask/bid, 
Derived metrics (change constantly, computed, recomputable)
  - e.g. volume, liquidity, spread, volatility

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
  - Venue
    - venue_id
    - price_scale ($0-$1, 0-100 cents)
    - currency / underlying token (USDC)
    - venue_type
    
  - Event
    - venue_id
    - event_id
    - event_name
    - event_description
    - event_type (binary, categorical)
    - event_category (sports, politics)
    - event_tags (bitcoin, trump, minnesota wild, etc.)
    - resolution_source
    - start_date
    - expiry_date
    - status (active/pending_resolution/resolved/cancelled)
  
  - Market
    - event_id
    - market_id
    - market_description
    - market_type (binary)
    - status (active/pending_resolution/resolved/cancelled/disputed)
      - This needs a seperate status since a categorical market can resolve while its parent remains tradeable
    - MarketState (enum)
      - PRE_OPEN
      - OPEN
      - HALTED
      - RESOLVED
      - DISPUTED

  - Outcome
    - market_id
    - outcome_id
    - outcome_name (YES/NO)
    - parent_market_id
    - token_id
    - clob_token_id
  
  - Order
    - order_id
    - market_id
    - outcome_id
    - side (bid/ask)
    - price
    - quantity
    - status (open/filled/partial/closed)
    - timestamp
  
  - Trade
    - outcome_id
    - trade_id
    - market_id
    - price
    - quantity
    - maker_order_id
    - taker_order_id
    - timestamp
  
  - Resolution
    - outcome_id
    - resolution_id
    - event_id
    - market_id
    - resolution_time
    - resolved_value
    - source
  
  - MarketState (enum)
    - PRE_OPEN
    - OPEN
    - HALTED
    - RESOLVED
    - DISPUTED
