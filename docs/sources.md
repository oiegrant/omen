#Polymarket Sources
Gamma API
  The Gamma API provides market metadata and indexing. Use it for:
  Market titles, slugs, categories
  Event/condition mapping
  Volume and liquidity data
  Outcome token metadata

Websocket
- There are two available channels user and market.
- Subscription
    To subscribe send a message including the following authentication and intent information upon opening the connection.
    Field	Type	Description
    auth	Auth	see next page for auth information
    markets	string[]	array of markets (condition IDs) to receive events for (for user channel)
    assets_ids	string[]	array of asset ids (token IDs) to receive events for (for market channel)
    type	string	id of channel to subscribe to (USER or MARKET)
    custom_feature_enabled	bool	enabling / disabling custom features
    
    Once connected, the client can subscribe and unsubscribe to asset_ids by sending the following message:
    Field	Type	Description
    assets_ids	string[]	array of asset ids (token IDs) to receive events for (for market channel)
    markets	string[]	array of market ids (condition IDs) to receive events for (for user channel)
    operation	string	”subscribe” or “unsubscribe”
    custom_feature_enabled	bool	enabling / disabling custom features

  Market Channel
    Public channel for updates related to market updates (level 2 price data).
    Messages (emitted when...)

      book Message
        First subscribed to a market
        When there is a trade that affects the book

      example
      {'market': '0xede5bd35327ea3d3c4ec164df7dd85de41a6c7de5419457281b6ad2d98d15086', 'asset_id': '92578288188432979359071261963415339111880931964393842646101434005006460761534', 'timestamp': '1769916676919', 'hash': '257b74b37d69da561633a6ec90888ad3815d746e', 'bids': [{'price': '0.001', 'size': '2413958.76'}], 'asks': [{'price': '0.999', 'size': '21003654'}, {'price': '0.998', 'size': '250'}, {'price': '0.997', 'size': '60406.62'}, {'price': '0.996', 'size': '250'}, {'price': '0.994', 'size': '200'}, {'price': '0.993', 'size': '15.51'}, {'price': '0.99', 'size': '10'}, {'price': '0.989', 'size': '9.09'}, {'price': '0.97', 'size': '8764'}, {'price': '0.969', 'size': '50700'}, {'price': '0.968', 'size': '1401'}, {'price': '0.967', 'size': '400'}, {'price': '0.95', 'size': '30'}, {'price': '0.949', 'size': '5.02'}, {'price': '0.94', 'size': '900'}, {'price': '0.89', 'size': '300'}, {'price': '0.889', 'size': '13.55'}, {'price': '0.777', 'size': '44'}, {'price': '0.5', 'size': '600'}, {'price': '0.477', 'size': '239'}, {'price': '0.47', 'size': '1565'}, {'price': '0.458', 'size': '6000'}, {'price': '0.457', 'size': '12000'}, {'price': '0.4', 'size': '100'}, {'price': '0.399', 'size': '999.97'}, {'price': '0.398', 'size': '3961'}, {'price': '0.397', 'size': '5'}, {'price': '0.277', 'size': '32'}, {'price': '0.196', 'size': '444'}, {'price': '0.177', 'size': '61'}, {'price': '0.1', 'size': '5577.35'}, {'price': '0.08', 'size': '4850'}, {'price': '0.079', 'size': '1100'}, {'price': '0.077', 'size': '30'}, {'price': '0.076', 'size': '30'}, {'price': '0.058', 'size': '29.66'}, {'price': '0.049', 'size': '40'}, {'price': '0.043', 'size': '52.73'}, {'price': '0.042', 'size': '20'}, {'price': '0.035', 'size': '59.33'}, {'price': '0.033', 'size': '300'}, {'price': '0.028', 'size': '70.31'}, {'price': '0.023', 'size': '93.75'}, {'price': '0.02', 'size': '39.55'}, {'price': '0.014', 'size': '200'}, {'price': '0.011', 'size': '300'}, {'price': '0.008', 'size': '100'}, {'price': '0.007', 'size': '179.99'}, {'price': '0.006', 'size': '1000'}, {'price': '0.004', 'size': '61103.59'}, {'price': '0.003', 'size': '75282'}, {'price': '0.002', 'size': '88759.05'}], 'event_type': 'book', 'last_trade_price': '0.002'}
      
      price_change Message
        A new order is placed
        An order is cancelled
        
        {'market': '0xede5bd35327ea3d3c4ec164df7dd85de41a6c7de5419457281b6ad2d98d15086', 'price_changes': [{'asset_id': '92578288188432979359071261963415339111880931964393842646101434005006460761534', 'price': '0.001', 'size': '2413938.74', 'side': 'BUY', 'hash': '1622d8e1208ce568b3f485ff85229285012e5a0c', 'best_bid': '0.001', 'best_ask': '0.002'}, {'asset_id': '93889421969336142745558340143509705147769228903969346254516362084783696296524', 'price': '0.999', 'size': '2413938.74', 'side': 'SELL', 'hash': '84e3997b1439e084e03d48114714f00b010810a0', 'best_bid': '0.998', 'best_ask': '0.999'}], 'timestamp': '1769916998865', 'event_type': 'price_change'}
      
      tick_size_change Message
        price goes out of the bounds 0.04>x>0.96
      
      last_trade_price Message
        when a maker and taker complete a trade
        
        {'market': '0xede5bd35327ea3d3c4ec164df7dd85de41a6c7de5419457281b6ad2d98d15086', 'asset_id': '93889421969336142745558340143509705147769228903969346254516362084783696296524', 'price': '0.999', 'size': '20.02', 'fee_rate_bps': '0', 'side': 'BUY', 'timestamp': '1769916998893', 'event_type': 'last_trade_price', 'transaction_hash': '0x6408bb70eb6e5047772cd0289c82bcd24240abd3c1d84d59a60fb16dbe1e0bb4'}

      best_bid_ask Message
        when best bid/ask change

      new_market Message
      
      market_resolved Message
