# Prediction Market Terminal — Build Checklist


---

## PHASE 0 — Lock the spine (1–2 days)

**Goal:** Make irreversible decisions once.

### 0.1 Write the canonical data model

[x] Create a repo-level markdown doc: `CANONICAL_MODEL.md`

#### Core entities

[x] Venue
[x] Market
[x] Outcome
[x] OrderBook
[x] Trade

#### Message types

[x] MarketDiscovered
[x] MarketUpdated
[x] OrderBookSnapshot
[x] OrderBookDelta
[x] TradeExecuted
[x] MarketResolved

#### For **each entity + message**, define:

[x] Required fields
[x] Field types
[x] Units (price scale, quantity units)
[x] Timestamp source (venue / ingestor / bus)
[x] Idempotency key / natural key

---

### 0.2 Define ID strategy

[x] Decide ID format (ULID)
[x] Define venue ID prefixes

* `PMKT_01HZX...`
* `KAL_01HZY...`

**Decision (lock it):**
☑ ULIDs everywhere
☑ Venue prefix embedded

---

### 0.3 Tech stack

☑ Ingestors: zig
☑ Event bus: NATS JetStream
☑ Aggregation API: zig
☑ Search: Meilisearch
☑ DB: Postgres
☑ Client: Zig + raylib/raygui

---

## PHASE 1 — One venue, end to end (1–2 weeks)

**Goal:** “I can open a terminal and watch a real market stream.”

---

### 1. Ingest a single venue (Polymarket)

#### 1.1 Create `ingest-polymarket`

☐ Connect to websocket / REST API
  Get starting event/market list data
  - X get all active events
    - X get all active markets
      - X get the associated clobTokenIds
  - X parse above into pre-canonical representation (includes clobtokenIds at least, maybe more additional info if needed)
  - WIP method to parse pre-canonical into pure canonical
  
    -clobTokenIds -> all of these should be fed into the websocket which yields back messages over time
      - handles reconnect + backoffs
      - parses events into canonical events -> prints for now
    
☐ Handle reconnects + backoff
☐ Parse raw venue messages
☐ Map → canonical messages
☐ Log raw + canonical side-by-side

**Output:**
☐ Canonical messages printed to stdout

✅ Success = normalized data flowing locally

---

### 1.2 Stand up NATS locally

☐ Run single-node NATS
☐ Enable JetStream
☐ Create streams:

* `markets.*`
* `books.*`
* `trades.*`

☐ Verify persistence & replay

✅ Success = ingestor publishes, NATS stores

---

### 1.3 Publish canonical events

☐ Serialize messages (Protobuf / FlatBuffers)
☐ Publish to correct subjects
☐ Add per-market sequence numbers
☐ Validate idempotency

✅ Success = replayable streams

---

### 2. Snapshot + delta strategy

#### 2.1 Define snapshot cadence (WRITE THIS DOWN)

☐ Snapshot on reconnect
☐ Snapshot on market open
☐ Snapshot every N seconds (decide N)

---

#### 2.2 Implement book assembly in ingestor

☐ Maintain in-memory order book
☐ Emit full `OrderBookSnapshot`
☐ Emit incremental `OrderBookDelta`
☐ Sequence all updates

🚫 No aggregation yet

---

### 3. Aggregation API (thin layer)

#### 3.1 Skeleton service

☐ Connect to NATS
☐ Subscribe to canonical streams
☐ Cache latest book per market
☐ Cache market metadata

Expose endpoints:
☐ `GET /markets`
☐ `GET /markets/{id}/snapshot`
☐ `GET /stream/{market_id}` (SSE or WS)

☑ Keep it dumb

---

#### 3.2 Market directory

☐ Store market metadata in Postgres
☐ Sync updates from NATS
☐ Index into Meilisearch
☐ Test search latency

✅ Success = searchable markets

---

### 4. Desktop client (ugly but real)

#### 4.1 Dumb Zig client

☐ Connect to aggregation API
☐ Subscribe to single market
☐ Print:

* best bid
* best ask
* last trade
* spread

🚫 No UI polish

✅ Success = live data on screen

---

#### 4.2 Local book assembly (CORE IP)

☐ Apply deltas locally
☐ Validate sequence numbers
☐ Detect gaps
☐ Request snapshot on mismatch

---

## PHASE 2 — Make it feel like a terminal (1 week)

**Goal:** “This already feels addictive.”

---

### 5. TUI scaffolding

#### 5.1 Screen layout

☐ Market list pane
☐ Order book pane
☐ Trade tape pane

☐ Hardcode layout first

---

#### 5.2 Keyboard navigation

☐ Vim-like movement
☐ Pane switching
☐ Quick market jump

🎮 Lean on game dev instincts here

---

### 6. Latency & correctness pass

#### 6.1 Instrument everything

☐ Ingest lag
☐ Bus lag
☐ API lag
☐ Client lag

☐ Display latency in UI

---

#### 6.2 Kill bugs early

☐ Reconnect handling
☐ Snapshot mismatches
☐ Dropped deltas
☐ Duplicate messages

🚫 Do not proceed until solid

---

## PHASE 3 — Prep for monetization (later)

(Not now — just awareness)

☐ Auth hooks
☐ Feature flags
☐ Rate limiting
☐ Tier gating

---

## Deliverables Checklist (Non-Negotiable)

☐ One venue fully ingested
☐ Canonical event stream
☐ Searchable market directory
☐ Desktop client streaming live order book
☐ Replayable historical data

❗ If any box is unchecked, **stop and fix before adding features.**
