#!/usr/bin/env python3
import json
import uuid
from curl_cffi import requests as r
import sys
import threading
import time

CLIENT_TOKEN = "e1393935a959b4020a4491574f6490129f678acdaa92760471263db43487f823"

def get_single_token(channel):
    try:
        s = r.Session(impersonate="chrome131")
        s.get(f"https://kick.com/{channel}", headers={"User-Agent":"Mozilla/5.0","Accept":"text/html,*/*"}, timeout=15)
        res = s.get("https://websockets.kick.com/viewer/v1/token", headers={
            "User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0",
            "Accept":"application/json",
            "Origin":"https://kick.com",
            "Referer":f"https://kick.com/{channel}",
            "X-CLIENT-TOKEN":CLIENT_TOKEN,
            "X-Device-ID":str(uuid.uuid4()),
            "X-Session-ID":str(uuid.uuid4())
        }, timeout=20)
        token = res.json().get("data",{}).get("token","") if res.status_code==200 else ""
        print(token)
    except:
        print("")

if __name__ == "__main__":
    channel = sys.argv[1] if len(sys.argv) > 1 else "test"
    get_single_token(channel)

