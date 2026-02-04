import json
import threading
import time

from py_clob_client.client import ClobClient
from websocket import WebSocketApp

MARKET_CHANNEL = "market"
USER_CHANNEL = "user"

host: str = "https://clob.polymarket.com"
key: str = "0x3a643f6081c21fd503ce768081b4e95580b1984e2634d3afd07e4783c426211a"  # This is your Private Key. If using email login export from https://reveal.magic.link/polymarket otherwise export from your Web3 Application
chain_id: int = 137  # No need to adjust this
POLYMARKET_PROXY_ADDRESS: str = "0xd112527e752627d6132AB00766fd662933CC4D1a"  # This is the address you deposit/send USDC to to FUND your Polymarket account.


class WebSocketOrderBook:
    def __init__(self, channel_type, url, data, auth, message_callback, verbose):
        self.channel_type = channel_type
        self.url = url
        self.data = data
        self.auth = auth
        self.message_callback = message_callback
        self.verbose = verbose
        furl = url + "/ws/" + channel_type
        self.ws = WebSocketApp(
            furl,
            on_message=self.on_message,
            on_error=self.on_error,
            on_close=self.on_close,
            on_open=self.on_open,
        )
        self.orderbooks = {}

    def on_message(self, ws, message):
        jsonM = json.loads(message)
        if isinstance(jsonM, list):
            for m in jsonM:
                event_type = m.get("event_type")
                print(event_type)
                print(m)
        else:
            event_type = jsonM.get("event_type")
            print(event_type)
            print(jsonM)

    def on_error(self, ws, error):
        print("Error: ", error)
        exit(1)

    def on_close(self, ws, close_status_code, close_msg):
        print("closing")
        exit(0)

    def on_open(self, ws):
        if self.channel_type == MARKET_CHANNEL:
            print("opening")
            ws.send(
                json.dumps(
                    {
                        "assets_ids": self.data,
                        "type": "MARKET",
                        "custom_feature_enabled": False,
                    }
                )
            )
        elif self.channel_type == USER_CHANNEL and self.auth:
            ws.send(
                json.dumps(
                    {"markets": self.data, "type": USER_CHANNEL, "auth": self.auth}
                )
            )
        else:
            exit(1)

    def subscribe_to_tokens_ids(self, assets_ids):
        if self.channel_type == MARKET_CHANNEL:
            self.ws.send(
                json.dumps({"assets_ids": assets_ids, "operation": "subscribe"})
            )

    def unsubscribe_to_tokens_ids(self, assets_ids):
        if self.channel_type == MARKET_CHANNEL:
            self.ws.send(
                json.dumps({"assets_ids": assets_ids, "operation": "unsubscribe"})
            )

    def ping(self, ws):
        while True:
            ws.send("PING")
            time.sleep(10)

    def run(self):
        self.ws.run_forever()


if __name__ == "__main__":
    client = ClobClient(
        host,
        key=key,
        chain_id=chain_id,
        signature_type=1,
        funder=POLYMARKET_PROXY_ADDRESS,
    )
    apiccred = client.derive_api_key()
    url = "wss://ws-subscriptions-clob.polymarket.com"
    api_key = apiccred.api_key
    api_secret = apiccred.api_secret
    api_passphrase = apiccred.api_passphrase

    asset_ids = [
        "42965146259929605797806965560632904263752338454817822438029661385790791701585",
        "114444125124122303566399993657146184596008541183155111894675512718735990103370",
        "92578288188432979359071261963415339111880931964393842646101434005006460761534",
        "93889421969336142745558340143509705147769228903969346254516362084783696296524",
        "10408531163541906469889697916972765618976044104637646008373727590266756953460",
        "34101402955691468281703248273660445311979856091562672407547570608033515729819",
    ]
    condition_ids = []  # no really need to filter by this one

    auth = {"apiKey": api_key, "secret": api_secret, "passphrase": api_passphrase}

    market_connection = WebSocketOrderBook(
        MARKET_CHANNEL, url, asset_ids, auth, None, True
    )
    # user_connection = WebSocketOrderBook(
    #     USER_CHANNEL, url, condition_ids, auth, None, True
    # )
    # market_connection.unsubscribe_to_tokens_ids(["123"])
    # market_connection.subscribe_to_tokens_ids(
    #     ["1620153095795063040639794950231973479413962044351079573320587222509914112081"]
    # )

    market_connection.run()
    # user_connection.run()
