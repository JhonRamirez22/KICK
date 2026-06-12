#!/usr/bin/env python3
"""
Token Server v17.1 — VPS + Tor
Por defecto usa Tor SOCKS5 (127.0.0.1:9050).
Si existe upstreams.txt, usa esos proxies rotando.
"""
import json, uuid, asyncio, random, logging, re, os, signal, sys
from fastapi import FastAPI
from fastapi.responses import JSONResponse
import uvicorn
from curl_cffi import requests as cffi_requests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("TokenServer")

app = FastAPI(title="Kick Token Server VPS", version="17.1")

CLIENT_TOKEN = os.environ.get("CLIENT_TOKEN", "e1393935a959b4020a4491574f6490129f678acdaa92760471263db43487f823")
CHROME_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36"
PROXY_LIST = []
PROXY_INDEX = 0

TOR_PROXY = "socks5://127.0.0.1:9050"
TOR_CONTROL_PASS = os.environ.get("TOR_CONTROL_PASS", "kickbot2024")

def load_proxies():
    global PROXY_LIST
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "upstreams.txt")
    if os.path.exists(path):
        with open(path) as f:
            proxies = [l.strip() for l in f if l.strip()]
            PROXY_LIST = [f"socks5://{p}" if not p.startswith('socks') else p for p in proxies]
            logger.info(f"Usando {len(PROXY_LIST)} proxies de upstreams.txt")
    else:
        PROXY_LIST = [TOR_PROXY]
        logger.info("Sin upstreams.txt — usando Tor proxy por defecto")

def get_next_proxy():
    global PROXY_INDEX
    if not PROXY_LIST:
        return TOR_PROXY
    p = PROXY_LIST[PROXY_INDEX % len(PROXY_LIST)]
    PROXY_INDEX += 1
    return p

async def fetch_token(channel_name, retries=5):
    for attempt in range(retries):
        try:
            prx = get_next_proxy()
            session = cffi_requests.Session(impersonate="chrome131", proxies={"http": prx, "https": prx})

            session.get(f"https://kick.com/{channel_name}", headers={
                "User-Agent": CHROME_UA, "Accept": "text/html,*/*"}, timeout=20)

            res = session.get("https://websockets.kick.com/viewer/v1/token", headers={
                "User-Agent": CHROME_UA, "Accept": "application/json",
                "Origin": "https://kick.com", "Referer": f"https://kick.com/{channel_name}",
                "X-CLIENT-TOKEN": CLIENT_TOKEN,
                "X-Device-ID": str(uuid.uuid4()),
                "X-Session-ID": str(uuid.uuid4()),
            }, timeout=25)

            if res.status_code == 200:
                data = res.json().get("data", {})
                token = data.get("token", "")
                if token and len(token) > 20:
                    return token
            elif res.status_code == 429:
                logger.warning(f"Rate limit (intento {attempt+1}) — esperando...")
                await asyncio.sleep(5 + attempt * 3)
            else:
                logger.warning(f"HTTP {res.status_code} (intento {attempt+1})")
                await asyncio.sleep(2)
        except Exception as e:
            logger.warning(f"Error intento {attempt+1}: {str(e)[:60]}")
            await asyncio.sleep(3 + attempt * 2)
    return None

async def get_channel_info(channel_name):
    try:
        prx = get_next_proxy()
        res = cffi_requests.get(f"https://kick.com/api/v1/channels/{channel_name}",
            impersonate="chrome131", proxies={"http": prx, "https": prx},
            headers={"User-Agent": CHROME_UA, "Accept": "application/json"}, timeout=20)

        if res.status_code == 200:
            d = res.json()
            ls = d.get("livestream") or {}
            return {"id": d.get("id"),
                    "chatroom_id": (d.get("chatroom") or {}).get("id"),
                    "live": d.get("livestream") is not None,
                    "viewers": ls.get("viewers", 0),
                    "title": ls.get("session_title", "")}
        return {"error": f"HTTP {res.status_code}"}
    except Exception as e:
        return {"error": str(e)}

# ── Endpoints ──────────────────────────────────────────────────────────────

@app.get("/batch-tokens")
async def batch_tokens(channel: str, count: int = 10):
    if count > 200: count = 200
    tasks = [fetch_token(channel) for _ in range(count)]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    valid = [t for t in results if isinstance(t, str) and len(t) > 20]
    logger.info(f"Batch: {len(valid)}/{count}")
    return {"tokens": valid, "count": len(valid)}

@app.get("/token")
async def token(channel: str):
    t = await fetch_token(channel)
    if t: return {"token": t}
    return JSONResponse(status_code=503, content={"error": "No token"})

@app.get("/discover")
async def discover(channel: str):
    info = await get_channel_info(channel)
    if info.get("error"):
        return JSONResponse(status_code=404, content=info)
    return info

@app.get("/health")
async def health():
    return {"status": "ok", "proxies": len(PROXY_LIST), "mode": "tor" if TOR_PROXY in PROXY_LIST else "file"}

@app.on_event("startup")
async def startup():
    load_proxies()
    logger.info(f"Token Server iniciado — {len(PROXY_LIST)} proxies disponibles")

if __name__ == "__main__":
    load_proxies()
    uvicorn.run(app, host="0.0.0.0", port=8765, log_level="warning", workers=1)
