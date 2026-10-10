#!/opt/wunderw/bin/python3.11
# -*- coding: utf-8 -*-
"""
Image Helper for WebUntis MeeGo Harmattan
Downloads images with cookie authentication
Args: URL OUTPUT_PATH [COOKIE_FILE]
"""

import sys
import os
import urllib.request
import ssl
import http.cookiejar

COOKIE_FILE = os.path.expanduser("~/.config/webuntis/cookies.txt")

def download_image(url, output_path, cookie_file=None):
    """Download image with cookie authentication"""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    # Cookie jar
    cfile = cookie_file or COOKIE_FILE
    cookie_jar = http.cookiejar.MozillaCookieJar(cfile)
    
    try:
        if os.path.exists(cfile):
            cookie_jar.load(ignore_discard=True, ignore_expires=True)
    except:
        pass
    
    cookie_handler = urllib.request.HTTPCookieProcessor(cookie_jar)
    https_handler = urllib.request.HTTPSHandler(context=ctx)
    opener = urllib.request.build_opener(https_handler, cookie_handler)
    
    req = urllib.request.Request(url)
    req.add_header('User-Agent', 'Untis/6.3.2 (Linux; Mobile; MeeGo)')
    
    try:
        response = opener.open(req, timeout=15)
        data = response.read()
        
        content_type = response.headers.get('Content-Type', '')
        if 'image' in content_type or len(data) > 100:
            # Ensure directory exists
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            
            with open(output_path, 'wb') as f:
                f.write(data)
            
            print(f"OK:{len(data)}")
            return True
        else:
            print(f"ERROR:Not an image ({content_type})")
            return False
            
    except Exception as e:
        print(f"ERROR:{e}")
        return False

def main():
    if len(sys.argv) < 3:
        print("Usage: image_helper.py URL OUTPUT_PATH [COOKIE_FILE]")
        return 1
    
    url = sys.argv[1]
    output_path = sys.argv[2]
    cookie_file = sys.argv[3] if len(sys.argv) > 3 else None
    
    success = download_image(url, output_path, cookie_file)
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
