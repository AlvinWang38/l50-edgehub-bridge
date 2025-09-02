import base64
import struct
from datetime import datetime, timezone

# 每筆資料長度（依 8.2/8.3）：4+4+4+2+1+1+1+1+1 = 19 bytes
BLOCK_SIZE = 19
PREFIX = 0xA5

def _iso_utc(ts: int) -> str:
    # 產生 2025-08-28T07:45:00Z 格式（timezone-aware）
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def decode_base64_payload(b64: str):
    """
    解析 data(Base64) → 回傳 list[dict]，每筆對應一個輸出 JSON。
    little-endian:
      <I timestamp
      <i latitude  (÷ 1e6)
      <i longitude (÷ 1e6)
      <h temp      (÷ 10)
      <b tilt_x
      <b tilt_y
      <b tilt_z
      <B core_v    (× 0.1)
      <B liion_v   (× 0.1)
    """
    out = []
    try:
        buf = base64.b64decode(b64)
    except Exception as e:
        print(f"[ERROR] base64 decode fail: {e}")
        return out

    print(f"[DEBUG] raw bytes len={len(buf)} head={buf[:16].hex()}")

    if len(buf) < 4:
        print(f"[ERROR] payload too short: {len(buf)}")
        return out

    # Header: 4 bytes，小端
    prefix, data_size, data_count, reserved = struct.unpack_from("<BBBB", buf, 0)
    print(f"[DEBUG] header prefix=0x{prefix:02x} size={data_size} count={data_count} reserved=0x{reserved:02x}")

    if prefix != PREFIX:
        print(f"[ERROR] invalid prefix: 0x{prefix:02x} (expect 0xa5)")
        return out
    if data_size != BLOCK_SIZE:
        print(f"[WARN] data_size={data_size} (expected {BLOCK_SIZE})")
    expected_len = 4 + data_count * data_size
    if len(buf) < expected_len:
        print(f"[ERROR] length mismatch len(buf)={len(buf)} expected>={expected_len}")
        return out

    base = 4
    for i in range(data_count):
        off = base + i * data_size

        ts   = struct.unpack_from('<I', buf, off)[0]; off += 4
        lat  = struct.unpack_from('<i', buf, off)[0]; off += 4
        lon  = struct.unpack_from('<i', buf, off)[0]; off += 4
        temp = struct.unpack_from('<h', buf, off)[0]; off += 2
        tx   = struct.unpack_from('<b', buf, off)[0]; off += 1
        ty   = struct.unpack_from('<b', buf, off)[0]; off += 1
        tz   = struct.unpack_from('<b', buf, off)[0]; off += 1
        core = struct.unpack_from('<B', buf, off)[0]; off += 1
        lio  = struct.unpack_from('<B', buf, off)[0]; off += 1

        rec = {
            "s": 1,
            "t": _iso_utc(ts),
            "q": 192,
            "c": 1,
            "Latitude":   lat / 1e6,
            "Longitude":  lon / 1e6,
            "Temperature": round(temp * 0.01, 2),
            "Tilt_X": int(tx),
            "Tilt_Y": int(ty),
            "Tilt_Z": int(tz),
            "Core_V":  round(core * 0.1, 1),
            "Liion_V": round(lio  * 0.1, 1),
        }
        print(f"[DEBUG] rec#{i+1}: ts={rec['t']} lat={rec['Latitude']} lon={rec['Longitude']} temp={rec['Temperature']} "
              f"tx={rec['Tilt_X']} ty={rec['Tilt_Y']} tz={rec['Tilt_Z']} core={rec['Core_V']} liion={rec['Liion_V']}")
        out.append(rec)

    return out
