import json
import re
import sys
from pathlib import Path
from typing import Optional
import paho.mqtt.client as mqtt

import payload_parser as parser
from version import __appname__, __version__

DEVICE_FROM_TOPIC = re.compile(r"^adv/([^/]+)/data$")  # {imei}

def load_config(path: str = "config.json") -> dict:
    with open(Path(path), "r", encoding="utf-8") as f:
        return json.load(f)

def make_client(name: str, host: str, port: int, username: Optional[str], password: Optional[str], tls: bool = False) -> mqtt.Client:
    client = mqtt.Client(client_id=name, clean_session=True, protocol=mqtt.MQTTv311)
    if username:
        client.username_pw_set(username, password or "")
    if tls:
        client.tls_set()  # 如需CA/證書可再擴充
    client.connect(host, port or 1883, keepalive=60)
    client.loop_start()
    return client

def main():
    # 顯示版本
    if len(sys.argv) >= 2 and sys.argv[1] in ("--version", "-v"):
        print(f"{__appname__} {__version__}")
        return

    config = load_config()
    src_cfg = config["brokers"]["source"]
    tgt_cfg = config["brokers"]["target"]
    subs = config["subscriptions"][0]
    to_template = config["routing"][0]["to"]
    skip_unknown = bool(config.get("skip_unknown", True))

    # 1) 準備 IMEI → 認證的索引
    device_creds_map: dict[str, dict] = {d["imei"]: d for d in config.get("devices", [])}

    # 2) 針對每個 IMEI 動態建立/快取 publisher client
    publishers: dict[str, mqtt.Client] = {}

    # 來源 broker（只負責訂閱）
    sub = mqtt.Client(client_id=src_cfg.get("client_id", "bridge-source"), clean_session=True, protocol=mqtt.MQTTv311)
    if src_cfg.get("username"):
        sub.username_pw_set(src_cfg["username"], src_cfg.get("password", ""))
    if src_cfg.get("tls", False):
        sub.tls_set()
    sub.connect(src_cfg["host"], src_cfg.get("port", 1883), keepalive=60)

    def on_connect(client, userdata, flags, rc):
        print(f"[SUB] Connected rc={rc}, subscribing {subs['topic']} (qos={subs.get('qos', 1)})")
        client.subscribe(subs["topic"], qos=subs.get("qos", 1))

    def get_publisher_for(imei: str) -> Optional[mqtt.Client]:
        # 白名單檢查
        creds = device_creds_map.get(imei)
        if creds is None:
            if skip_unknown:
                print(f"[SKIP] imei={imei} not in whitelist")
                return None
            else:
                print(f"[WARN] imei={imei} not in whitelist, but skip_unknown=false → 將使用匿名連線")
        # 已存在就直接用
        if imei in publishers:
            return publishers[imei]
        # 建立新的 publisher（每個 IMEI 有不同帳密）
        username = creds.get("username") if creds else None
        password = creds.get("password") if creds else None
        client_id = (creds.get("client_id") if creds else None) or f"pub-{imei}"
        pub = make_client(
            name=client_id,
            host=tgt_cfg["host"],
            port=tgt_cfg.get("port", 1883),
            username=username,
            password=password,
            tls=bool(tgt_cfg.get("tls", False)),
        )
        publishers[imei] = pub
        print(f"[PUB-READY] imei={imei} connected to target as user={username}")
        return pub

    def on_message(client, userdata, msg: mqtt.MQTTMessage):
        print(f"[DEBUG] incoming topic={msg.topic}")
        m = DEVICE_FROM_TOPIC.match(msg.topic)
        if not m:
            print(f"[WARN] skip topic={msg.topic}")
            return
        imei = m.group(1)

        # 取 publisher（若不在白名單、且 skip_unknown=true → 直接 None）
        pub = get_publisher_for(imei)
        if pub is None:
            return

        # 來源 payload 是 JSON，取出 data(Base64)
        try:
            src_obj = json.loads(msg.payload.decode("utf-8", errors="replace"))
        except Exception as e:
            print(f"[ERROR] invalid JSON: {e}")
            return

        b64 = src_obj.get("data")
        if not b64:
            print("[WARN] no 'data' field, skip")
            return

        records = parser.decode_base64_payload(b64)
        if not records:
            print("[WARN] no decoded records")
            return

        dst_topic = to_template.format(device=imei)
        for idx, rec in enumerate(records):
            payload = json.dumps(rec, ensure_ascii=False, separators=(",", ":"))
            result = pub.publish(dst_topic, payload=payload, qos=1, retain=False)
            if result.rc == mqtt.MQTT_ERR_SUCCESS:
                print(f"[PUB] {msg.topic} -> {dst_topic} #{idx+1}/{len(records)} bytes={len(payload)}")
            else:
                print(f"[ERROR] publish rc={result.rc} to {dst_topic}")

    sub.on_connect = on_connect
    sub.on_message = on_message

    try:
        sub.loop_forever()
    except KeyboardInterrupt:
        print("Stopping...")
    finally:
        for imei, pub in publishers.items():
            try:
                pub.loop_stop()
                pub.disconnect()
            except Exception:
                pass
        sub.disconnect()

if __name__ == "__main__":
    main()
