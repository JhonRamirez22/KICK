#!/usr/bin/env python3
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from curl_cffi import requests as r
import uvicorn
import uuid
import threading
import time
import json

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

CLIENT_TOKEN = "e1393935a959b4020a4491574f6490129f678acdaa92760471263db43487f823"

@app.get("/tokens")
async def get_tokens(channel: str = Query(...), count: int = Query(1)):
    tokens = []
    
    def get_token():
        try:
            s = r.Session(impersonate="chrome131")
            s.get(f"https://kick.com/{channel}", headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0",
                "Accept": "text/html,*/*"
            }, timeout=15)
            
            res = s.get("https://websockets.kick.com/viewer/v1/token", headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0",
                "Accept": "application/json",
                "Origin": "https://kick.com",
                "Referer": f"https://kick.com/{channel}",
                "X-CLIENT-TOKEN": CLIENT_TOKEN,
                "X-Device-ID": str(uuid.uuid4()),
                "X-Session-ID": str(uuid.uuid4())
            }, timeout=20)
            
            if res.status_code == 200:
                token = res.json().get("data", {}).get("token", "")
                return token if len(token) > 20 else None
        except Exception as e:
            print(f"Token error: {e}")
        return None
    
    threads = []
    for _ in range(count):
        t = threading.Thread(target=lambda: tokens.append(get_token()))
        threads.append(t)
        t.start()
        time.sleep(0.1)
    
    for t in threads:
        t.join(timeout=30)
    
    tokens = [t for t in tokens if t]
    return {"tokens": tokens[:count]}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=3000)
