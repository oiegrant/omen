# Streaming Architecture

This document defines the canonical event streams used to power discovery, real-time trading views, recovery, and lifecycle correctness across aggregated prediction markets.

Streams are designed to be:

* Single-purpose
* Replayable
* Idempotent
* Client-reconstructable

---

## Design Goals

The streaming layer must support:

1. **Market discovery**
2. **Real-time order book & trade views**
3. **Fast client recovery & replay**
4. **Correct market & event lifecycle handling**
5. **Cross-venue aggregation**

---

## Event-Level Streams

### `events.discovered`

**Purpose**

* Global directory of real-world events
* Cross-venue event linking

**Use cases**

* Search & browse all available events
* Link multiple venue markets to the same underlying question
* Bootstrap client state

**Carries**

* `Event`

  * `event_id`
  * `event_name`
  * `event_description`
  * `event_type`
  * `event_category`
  * `event_tags`
  * `start_date`
  * `expiry_date`
  * `resolution_source`

**Invariants**

* Emitted once per event (or on rare correction)
* Idempotent
* Canonical (no derived data)

---

### `events.resolved`

**Purpose**

* Final authoritative resolution of an event

**Use cases**

* Historical analysis
* Cross-market settlement consistency
* Post-resolution analytics

**Carries**

* `event_id`
* `resolution_time`
* `resolved_outcome`
* `resolution_source`
* `finality_status` (tentative / final / disputed)

**Invariants**

* Terminal event (except disputes)
* Immutable once final

---

## Market-Level Streams

### `markets.discovered`

**Purpose**

* Market directory
* Initial market metadata

**Use cases**

* Populate market lists
* Identify tradeable instruments
* Link markets to events & venues

**Carries**

* `Market`

  * `market_id`
  * `event_id`
  * `venue_id`
  * `market_description`
  * `market_type`
  * `open_time`
  * `close_time`
  * `settlement_rule`
  * `initial_state`

**Invariants**

* Emitted once per market
* Canonical metadata only

---

### `markets.snapshots`

**Purpose**

* Fast bootstrap and recovery
* Initial market state for clients

**Use cases**

* Client startup
* Reconnect recovery
* State reconciliation

**Carries**

* `market_id`
* `market_state`
* Optional:

  * last trade price/time
  * best bid / best ask

**Invariants**

* Represents full authoritative state at a point in time
* May be emitted periodically

---

### `markets.updated`

**Purpose**

* Non-state metadata changes

**Use cases**

* Description edits
* Schedule changes
* Settlement clarifications

**Carries**

* `market_id`
* Patch-style metadata updates

**Invariants**

* Rare
* Never used for lifecycle transitions

---

### `market.state.updated`

**Purpose**

* Explicit lifecycle transitions

**Use cases**

* Client rendering decisions
* Filtering tradeable markets
* Auditing market halts & disputes

**Carries**

* `market_id`
* `previous_state`
* `new_state`
* `timestamp`
* `reason`

**States**

* `PRE_OPEN`
* `OPEN`
* `HALTED`
* `RESOLVED`
* `DISPUTED`

**Invariants**

* Emitted for every state transition
* Totally ordered per market

---

### `markets.resolved`

**Purpose**

* Market-level settlement

**Use cases**

* Payout determination
* Historical replay
* Resolution verification

**Carries**

* `market_id`
* `resolved_outcome_id`
* `payout_value`
* `resolution_time`
* `confidence_level`

**Invariants**

* Terminal event (except dispute)
* Immutable once final

---

## Trading Streams (Hot Path)

### `orders.snapshot`

**Purpose**

* Authoritative order book reset

**Use cases**

* Initial order book load
* Recovery after dropped deltas
* Validation of client state

**Carries**

* `market_id`
* `outcome_id`
* Full order book depth
* `sequence_start`

**Invariants**

* Full replacement of local book
* Must precede deltas

---

### `orders.delta`

**Purpose**

* Live order book mutation

**Use cases**

* Real-time trading views
* Depth visualization
* Liquidity analysis

**Carries**

* `market_id`
* `outcome_id`
* One or more mutations:

  * add
  * modify
  * remove
* `sequence_number`

**Invariants**

* Strictly ordered per market + outcome
* No gaps without snapshot
* Idempotent

---

### `trades.executed`

**Purpose**

* Trade execution truth
* Time & sales tape

**Use cases**

* Price discovery
* Volume computation
* Historical replay

**Carries**

* `Trade`

  * `trade_id`
  * `market_id`
  * `outcome_id`
  * `price`
  * `quantity`
  * `maker_order_id`
  * `taker_order_id`
  * `timestamp`

**Invariants**

* Immutable
* Emitted once per execution

---

## Cross-Stream Invariants

The system enforces the following global rules:

1. Events outlive markets
2. Markets outlive order books
3. Order books reset only via snapshots
4. Trades never mutate
5. Resolution is terminal (except dispute handling)

---

## Notes

* Derived metrics (volume, spread, liquidity) are intentionally **not streamed** at this stage.
* All streams are designed to support full replay and deterministic reconstruction.
* Clients assemble order books locally from snapshots + deltas.
