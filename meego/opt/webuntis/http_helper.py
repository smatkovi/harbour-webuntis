#!/opt/wunderw/bin/python3.11
# -*- coding: utf-8 -*-
"""
HTTP Helper for WebUntis MeeGo Harmattan
Args: METHOD URL DATA HEADERS_JSON [TIMEOUT]
Supports cookie persistence for session management
"""

import sys
import os
import json
import urllib.request
import urllib.parse
import ssl
import gzip
import http.cookiejar

sys.stdout = open(sys.stdout.fileno(), mode='w', encoding='utf-8', buffering=1)
sys.stderr = open(sys.stderr.fileno(), mode='w', encoding='utf-8', buffering=1)

COOKIE_FILE = os.path.expanduser("~/.config/webuntis/cookies.txt")

def ensure_cookie_dir():
    cookie_dir = os.path.dirname(COOKIE_FILE)
    if not os.path.exists(cookie_dir):
        os.makedirs(cookie_dir)

def decompress_response(data, headers):
    """Decompress gzip response if needed"""
    encoding = headers.get('Content-Encoding', '')
    if 'gzip' in encoding.lower():
        try:
            return gzip.decompress(data)
        except:
            pass
    return data

def make_request(url, method, data, headers, timeout):
    """Make HTTP request with cookie persistence"""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    # Cookie jar with file persistence
    ensure_cookie_dir()
    cookie_jar = http.cookiejar.MozillaCookieJar(COOKIE_FILE)
    
    # Load existing cookies
    try:
        if os.path.exists(COOKIE_FILE):
            cookie_jar.load(ignore_discard=True, ignore_expires=True)
            print(f"DEBUG: Loaded {len(cookie_jar)} cookies", file=sys.stderr)
    except Exception as e:
        print(f"DEBUG: Cookie load error: {e}", file=sys.stderr)
    
    # Create opener with cookie handler
    cookie_handler = urllib.request.HTTPCookieProcessor(cookie_jar)
    https_handler = urllib.request.HTTPSHandler(context=ctx)
    opener = urllib.request.build_opener(https_handler, cookie_handler)
    
    req = urllib.request.Request(url, method=method)
    
    # Add headers
    req.add_header('Accept-Encoding', 'gzip, deflate')
    req.add_header('User-Agent', 'Untis/6.3.2 (Linux; Mobile; MeeGo)')
    
    for k, v in headers.items():
        req.add_header(k, v)
    
    if method == "POST" and data:
        post_data = data.encode('utf-8')
        response = opener.open(req, post_data, timeout=timeout)
    else:
        response = opener.open(req, timeout=timeout)
    
    # Save cookies after request
    try:
        cookie_jar.save(ignore_discard=True, ignore_expires=True)
        print(f"DEBUG: Saved {len(cookie_jar)} cookies", file=sys.stderr)
    except Exception as e:
        print(f"DEBUG: Cookie save error: {e}", file=sys.stderr)
    
    raw_data = response.read()
    decompressed = decompress_response(raw_data, dict(response.headers))
    return decompressed.decode('utf-8')

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: http_helper.py METHOD URL [DATA] [HEADERS_JSON] [TIMEOUT]"}))
        return
    
    method = sys.argv[1]
    url = sys.argv[2]
    data = sys.argv[3] if len(sys.argv) > 3 else ""
    headers_json = sys.argv[4] if len(sys.argv) > 4 else "{}"
    timeout = int(sys.argv[5]) if len(sys.argv) > 5 else 30
    
    try:
        headers = json.loads(headers_json)
    except:
        headers = {}
    
    if data == "":
        data = None
    
    print(f"DEBUG: {method} {url[:60]}", file=sys.stderr)
    
    try:
        result = make_request(url, method, data, headers, timeout)
        print(result)
        
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode('utf-8')
            if body:
                print(body)
            else:
                print(json.dumps({"error": f"HTTP {e.code}"}))
        except:
            print(json.dumps({"error": f"HTTP {e.code}"}))
            
    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    main()
