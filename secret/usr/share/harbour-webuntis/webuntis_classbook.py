#!/usr/bin/env python3
"""
WebUntis Mobile API Backend für Sailfish OS
Secret-Only Version für Microsoft 365 Schulen
Verwendet ausschließlich die Mobile API (kein JSON-RPC Login nötig)
"""

VERSION = "v3.61-secret"

import pyotherside
import json
import os
import hmac
import hashlib
import struct
import base64
import time
import re
import urllib.parse
import untis_http as requests  # urllib-Ersatz, sandkastenfest
from pathlib import Path
from datetime import datetime, timedelta
from threading import Lock

# Import Sailfish Secrets
try:
    import sailfish_secrets
    HAS_SECRETS = True
except ImportError:
    HAS_SECRETS = False
    print("[WebUntis] Sailfish Secrets not available")

# Konfiguration - dynamisch pro Schule
SERVER = None  # z.B. "aoide.webuntis.com"
SCHOOL = None  # z.B. "polgargym"

# Globaler State
session = None
session_lock = Lock()
username = None
secret = None
user_id = None
user_type = None  # 2 = Teacher, 5 = Student

# Cache (aus getUserData2017 masterData)
cache = {
    'teachers': {},
    'subjects': {},
    'rooms': {},
    'classes': {},
    'students': {},
    'absence_reasons': [],
    'event_reasons': [],
    'time_grid': [],
    'lesson_ids': {}  # period_id -> lesson_id mapping
}


def log(msg):
    """Log to stdout for QML"""
    print(f"[WebUntis] {msg}")
    pyotherside.send('log', str(msg))


SCHOOLSEARCH_URL = "https://schoolsearch.webuntis.com/schoolquery2"

# Mindestlaenge: mit 2 Zeichen antwortet die Schulsuche fast immer
# mit -6003 ("too many results"), das sah nach einem Fehler aus.
MIN_SCHOOL_QUERY = 3

# Fehlercodes der Schulsuche in Klartext
SEARCH_ERRORS = {
    -6003: "Zu viele Treffer - bitte genauer eingeben",
}


def search_schools(query: str):
    """
    Schulsuche ueber die WebUntis-Schulsuche.
    Gibt {'schools': [...]} oder {'error': 'Klartext'} zurueck.
    """
    query = (query or '').strip()
    if len(query) < MIN_SCHOOL_QUERY:
        return {'error': f'Suchbegriff zu kurz (min. {MIN_SCHOOL_QUERY} Zeichen)'}

    payload = {
        "id": f"wu_schulsuche-{int(time.time())}",
        "method": "searchSchool",
        "params": [{"search": query}],
        "jsonrpc": "2.0"
    }

    try:
        response = requests.post(SCHOOLSEARCH_URL, json=payload, timeout=15)
        if response.status_code != 200:
            log(f"Schulsuche HTTP {response.status_code}")
            return {'error': f'Schulsuche nicht erreichbar (HTTP {response.status_code})'}
        data = response.json()
    except Exception as e:
        log(f"Schulsuche Fehler: {e}")
        return {'error': f'Schulsuche nicht erreichbar: {e}'}

    error = data.get('error')
    if error:
        code = error.get('code')
        message = SEARCH_ERRORS.get(code) or error.get('message') or 'Unbekannter Fehler'
        log(f"Schulsuche '{query}': Fehler {code} ({error.get('message')})")
        return {'error': message}

    schools = (data.get('result') or {}).get('schools') or []
    log(f"Schulsuche '{query}': {len(schools)} Ergebnisse")

    # Fuer QML aufbereiten (max. 20 Treffer)
    result = []
    for s in schools[:20]:
        server = s.get('server', '')
        login_name = s.get('loginName', '')
        if not server or not login_name:
            continue
        result.append({
            'displayName': s.get('displayName', '') or login_name,
            'address': s.get('address', ''),
            'server': server,
            'loginName': login_name,
            'schoolId': s.get('schoolId', 0)
        })
    return {'schools': result}


def set_school(server: str, login_name: str):
    """
    Set the active school for subsequent API calls
    """
    global SERVER, SCHOOL
    SERVER = server
    SCHOOL = login_name
    log(f"Schule gesetzt: {SCHOOL} @ {SERVER}")


def parse_school_url(text: str, login_name: str = ''):
    """
    Server und Schulkennung aus einer von Hand eingetippten WebUntis-Adresse
    holen - der Rueckfall, wenn die Schulsuche nichts findet (zu viele Treffer,
    Schule nicht gelistet, Suche nicht erreichbar).

    Versteht z.B.
      https://melpomene.webuntis.com/WebUntis/?school=meineschule
      melpomene.webuntis.com/WebUntis/index.do#/basic/login?school=meineschule
      melpomene.webuntis.com            (dann muss login_name dabei sein)
    """
    text = (text or '').strip()
    login_name = (login_name or '').strip()

    if not text:
        return {'error': 'Bitte die WebUntis-Adresse eintragen'}

    raw = text if '//' in text else 'https://' + text
    try:
        server = (urllib.parse.urlsplit(raw).hostname or '').strip().lower()
    except Exception:
        server = ''

    if not server or '.' not in server:
        return {'error': 'Das sieht nicht nach einer Adresse aus (z.B. xyz.webuntis.com)'}

    if not login_name:
        found = re.search(r'school=([^&#/?]+)', raw, re.IGNORECASE)
        if found:
            login_name = urllib.parse.unquote(found.group(1)).strip()

    if not login_name:
        return {'error': 'Schulkennung fehlt - sie steht in der Adresse als school=...'}

    set_school(server, login_name)
    return {'server': server, 'loginName': login_name}


def generate_otp(secret_b32: str) -> str:
    """Generate TOTP code from secret"""
    secret_padded = secret_b32.upper() + '=' * (-len(secret_b32) % 8)
    secret_bytes = base64.b32decode(secret_padded)
    counter = int(time.time()) // 30
    counter_bytes = struct.pack('>Q', counter)
    hmac_hash = hmac.new(secret_bytes, counter_bytes, hashlib.sha1).digest()
    offset = hmac_hash[-1] & 0x0F
    code = struct.unpack('>I', hmac_hash[offset:offset+4])[0]
    code = (code & 0x7FFFFFFF) % 1000000
    return str(code).zfill(6)


def mobile_call(method: str, extra_params: dict = None, retry: bool = True):
    """Mobile API call with OTP authentication"""
    global session, username, secret, SERVER, SCHOOL
    
    if not session:
        session = requests.Session()
        session.headers['User-Agent'] = 'Untis/6.3.2 (Linux; Mobile; SailfishOS)'
        session.headers['Content-Type'] = 'application/json'
    
    if not secret or not username:
        return {'error': {'message': 'Nicht authentifiziert'}}
    
    if not SERVER or not SCHOOL:
        return {'error': {'message': 'Server/Schule nicht konfiguriert'}}
    
    otp = generate_otp(secret)
    client_time = int(time.time() * 1000)
    
    params = {
        "auth": {
            "user": username,
            "otp": int(otp),
            "clientTime": client_time
        }
    }
    
    if extra_params:
        params.update(extra_params)
    
    payload = {
        "id": "1",
        "method": method,
        "params": [params],
        "jsonrpc": "2.0"
    }
    
    url = f"https://{SERVER}/WebUntis/jsonrpc_intern.do?school={SCHOOL}"
    
    # Log request for debugging (hide OTP)
    log_params = {k: v for k, v in params.items() if k != 'auth'}
    log(f"mobile_call: {method} params={log_params}")
    
    try:
        resp = session.post(url, json=payload, timeout=15)
        result = resp.json()
        
        # Log response
        if "error" in result:
            log(f"mobile_call response ERROR: {result.get('error')}")
        else:
            # Log success but truncate long responses
            result_str = str(result.get('result', ''))[:200]
            log(f"mobile_call response OK: {result_str}...")
        
        # Check for authentication errors
        if "error" in result:
            error_code = result.get('error', {}).get('code', 0)
            error_msg = result.get('error', {}).get('message', '')
            
            # Session/auth errors - try refresh session and retry
            if retry and (error_code in [-8504, -8520, 401] or 'auth' in error_msg.lower() or 'session' in error_msg.lower()):
                log(f"Auth error detected, refreshing session: {error_msg}")
                session.close()
                session = requests.Session()
                session.headers['User-Agent'] = 'Untis/6.3.2 (Linux; Mobile; SailfishOS)'
                session.headers['Content-Type'] = 'application/json'
                return mobile_call(method, extra_params, retry=False)  # Retry once
        
        return result
        
    except requests.exceptions.ConnectionError as e:
        log(f"Connection error, refreshing session: {e}")
        if retry:
            session.close()
            session = requests.Session()
            session.headers['User-Agent'] = 'Untis/6.3.2 (Linux; Mobile; SailfishOS)'
            session.headers['Content-Type'] = 'application/json'
            return mobile_call(method, extra_params, retry=False)
        return {'error': {'message': f'Verbindungsfehler: {e}'}}
        
    except requests.exceptions.Timeout as e:
        log(f"Timeout error: {e}")
        return {'error': {'message': 'Zeitüberschreitung - bitte erneut versuchen'}}
        
    except Exception as e:
        log(f"Mobile API Fehler: {e}")
        return {'error': {'message': str(e)}}


# ==================== Credentials ====================

def save_credentials(server: str, school: str, user: str, mobile_secret: str):
    """Save credentials to Sailfish Secrets"""
    if not HAS_SECRETS:
        log("Sailfish Secrets not available - credentials not saved")
        return False
    
    log(f"Saving credentials: server={server}, school={school}, user={user}")
    
    try:
        # Delete old credentials first to ensure clean overwrite
        try:
            sailfish_secrets.delete_user_credentials()
            log("Deleted old credentials from Sailfish Secrets")
        except:
            pass
        
        success = sailfish_secrets.save_user_credentials(server, school, user, mobile_secret)
        if success:
            log("Credentials saved to Sailfish Secrets")
            return True
        else:
            log("Sailfish Secrets save returned False")
            return False
    except Exception as e:
        log(f"Sailfish Secrets error: {e}")
        return False


def load_credentials():
    """Load credentials from Sailfish Secrets"""
    if not HAS_SECRETS:
        log("Sailfish Secrets not available")
        return None
    
    try:
        creds = sailfish_secrets.load_user_credentials()
        if creds:
            log(f"Credentials loaded from Sailfish Secrets: server={creds.get('server')}, school={creds.get('school')}, user={creds.get('username')}")
            return creds
        log("No credentials found in Sailfish Secrets")
    except Exception as e:
        log(f"Sailfish Secrets load error: {e}")
    
    return None


def clear_credentials():
    """Delete credentials from Sailfish Secrets"""
    if HAS_SECRETS:
        try:
            sailfish_secrets.delete_user_credentials()
            log("Credentials deleted from Sailfish Secrets")
        except Exception as e:
            log(f"Sailfish Secrets delete error: {e}")
    
    pyotherside.send('credentialsCleared')


# ==================== Login ====================

def login(server: str, school: str, user: str, mobile_secret: str, save: bool = True):
    """Login using Mobile API Secret"""
    global session, username, secret, cache, SERVER, SCHOOL
    
    with session_lock:
        try:
            SERVER = server
            SCHOOL = school
            username = user
            secret = mobile_secret
            session = requests.Session()
            session.headers['User-Agent'] = 'Untis/6.3.2 (Linux; Mobile; SailfishOS)'
            session.headers['Content-Type'] = 'application/json'
            
            log(f"Verbinde zu {SERVER} / {SCHOOL}...")
            
            # Test connection and load user data
            result = mobile_call("getUserData2017")
            
            if "error" in result:
                error_msg = result.get('error', {}).get('message', 'Unbekannter Fehler')
                raise Exception(f"API Fehler: {error_msg}")
            
            if "result" not in result:
                raise Exception("Ungültige Antwort")
            
            # Load all cache data from masterData
            _process_user_data(result["result"])
            
            if save:
                save_credentials(server, school, user, mobile_secret)
            
            log(f"Eingeloggt als {user} [{VERSION}]")
            log(f"Server: {SERVER}, Schule: {SCHOOL}")
            
            pyotherside.send('loginSuccess', user)
            return True
            
        except Exception as e:
            session = None
            username = None
            secret = None
            SERVER = None
            SCHOOL = None
            log(f"Login fehlgeschlagen: {e}")
            pyotherside.send('loginFailed', str(e))
            return False


def auto_login():
    """Try to login with saved credentials"""
    creds = load_credentials()
    if creds and all(k in creds for k in ['server', 'school', 'username', 'secret']):
        return login(
            creds['server'],
            creds['school'],
            creds['username'], 
            creds['secret'],
            save=False
        )
    return False


def logout():
    """Clear session"""
    global session, username, secret, SERVER, SCHOOL, user_id, user_type
    
    with session_lock:
        session = None
        username = None
        secret = None
        SERVER = None
        SCHOOL = None
        user_id = None
        user_type = None
    
    pyotherside.send('loggedOut')


def _process_user_data(user_data: dict):
    """Process getUserData2017 result and populate cache"""
    global cache, user_id, user_type
    
    # Debug: Log all keys in userData
    log(f"userData keys: {list(user_data.keys())}")
    
    # The user info is in nested 'userData' object
    inner = user_data.get("userData", {})
    if inner:
        log(f"inner userData keys: {list(inner.keys())}")
        # elemId = User ID, elemType = TEACHER/STUDENT/CLASS/ROOM
        user_id = inner.get("elemId")
        elem_type = inner.get("elemType", "TEACHER")
        
        # Keep as string for API calls, but also support number input
        if isinstance(elem_type, str):
            user_type = elem_type.upper()
        else:
            # Convert number to string
            type_str_map = {1: "CLASS", 2: "TEACHER", 3: "SUBJECT", 4: "ROOM", 5: "STUDENT"}
            user_type = type_str_map.get(elem_type, "TEACHER")
    
    log(f"User: ID={user_id}, Type={user_type}")
    
    master_data = user_data.get("masterData", {})
    
    # Teachers
    for t in master_data.get("teachers", []):
        cache['teachers'][t['id']] = t.get('name', t.get('longName', '?'))
    
    # Subjects
    for s in master_data.get("subjects", []):
        cache['subjects'][s['id']] = s.get('name', s.get('longName', '?'))
    
    # Rooms
    for r in master_data.get("rooms", []):
        cache['rooms'][r['id']] = r.get('name', r.get('longName', '?'))
    
    # Classes (klassen)
    for k in master_data.get("klassen", []):
        cache['classes'][k['id']] = k.get('name', '?')
    
    # Absence reasons
    cache['absence_reasons'] = master_data.get("absenceReasons", [])
    
    # Log ALL absence reasons for debugging
    log(f"=== ABSENCE REASONS ({len(cache['absence_reasons'])}) ===")
    for ar in cache['absence_reasons']:
        log(f"  ID={ar.get('id')}: {ar.get('name')} - {ar.get('longName')} (active={ar.get('active')})")
    
    # Event reasons
    cache['event_reasons'] = master_data.get("eventReasons", [])
    if not cache['event_reasons']:
        cache['event_reasons'] = master_data.get("eventReasonGroups", [])
    
    log(f"Event reasons loaded: {len(cache['event_reasons'])}")
    if cache['event_reasons']:
        log(f"First event reason: {cache['event_reasons'][0]}")
    
    # Time grid
    cache['time_grid'] = master_data.get("timeGrid", [])
    
    # Default reason IDs
    cache['default_lateness_reason_id'] = master_data.get("defaultLatenessReasonId")
    cache['default_absence_reason_id'] = master_data.get("defaultAbsenceReasonId")
    
    log(f"Cache: {len(cache['teachers'])} Lehrer, {len(cache['classes'])} Klassen, {len(cache['subjects'])} Fächer")


# ==================== Timetable ====================

def _get_timetable_jsonrpc(element_type: int, element_id: int, date_iso: str, retry: bool = True):
    """Get timetable using standard jsonrpc.do API (this works!)"""
    global session
    from datetime import datetime, timedelta
    
    log(f"jsonrpc.do getTimetable: type={element_type}, id={element_id}")
    
    # Parse date and get week range
    date_obj = datetime.strptime(date_iso, "%Y-%m-%d")
    
    # Monday of the week
    monday = date_obj - timedelta(days=date_obj.weekday())
    friday = monday + timedelta(days=4)
    
    start_int = int(monday.strftime("%Y%m%d"))
    end_int = int(friday.strftime("%Y%m%d"))
    
    log(f"Date range: {start_int} to {end_int}")
    
    url = f"https://{SERVER}/WebUntis/jsonrpc.do?school={SCHOOL}"
    
    payload = {
        "id": "1",
        "method": "getTimetable",
        "params": {
            "startDate": start_int,
            "endDate": end_int,
            "id": element_id,
            "type": element_type
        },
        "jsonrpc": "2.0"
    }
    
    try:
        resp = session.post(url, json=payload, timeout=30)
        log(f"Response status: {resp.status_code}")
        
        data = resp.json()
        
        if "error" in data:
            error_msg = str(data.get('error', ''))
            log(f"getTimetable error: {error_msg}")
            
            # Retry on auth/session errors
            if retry and ('auth' in error_msg.lower() or 'session' in error_msg.lower()):
                log("Refreshing session and retrying...")
                session.close()
                session = requests.Session()
                session.headers['User-Agent'] = 'Untis/6.3.2 (Linux; Mobile; SailfishOS)'
                session.headers['Content-Type'] = 'application/json'
                return _get_timetable_jsonrpc(element_type, element_id, date_iso, retry=False)
            return []
        
        periods_raw = data.get("result", [])
        log(f"Found {len(periods_raw)} periods")
        
        # Debug first period
        if periods_raw:
            log(f"First period raw: {json.dumps(periods_raw[0], default=str)}")
        
        # Convert to our format
        lessons = []
        for p in periods_raw:
            lstype = p.get('lstype', '')
            
            # Determine activity type based on lstype
            if lstype == 'bs':
                activity = 'Bereitschaft'
            elif lstype == 'oh':
                activity = 'Gangaufsicht'
            else:
                activity = p.get('activityType', 'Unterricht')
            
            lesson = {
                'id': p.get('id'),
                'lessonId': p.get('id'),
                'date': p.get('date'),  # Integer YYYYMMDD
                'startTime': p.get('startTime'),  # Integer HHMM
                'endTime': p.get('endTime'),
                'classes': [cache['classes'].get(k['id'], f"K{k['id']}") for k in p.get('kl', [])],
                'teachers': [cache['teachers'].get(t['id'], f"T{t['id']}") for t in p.get('te', [])],
                'subjects': [cache['subjects'].get(s['id'], f"S{s['id']}") for s in p.get('su', [])],
                'rooms': [cache['rooms'].get(r['id'], f"R{r['id']}") for r in p.get('ro', [])],
                'classIds': [k['id'] for k in p.get('kl', [])],
                'teacherIds': [t['id'] for t in p.get('te', [])],
                'subjectIds': [s['id'] for s in p.get('su', [])],
                'roomIds': [r['id'] for r in p.get('ro', [])],
                'code': p.get('code', ''),
                'cellState': p.get('cellState', 'STANDARD'),
                'activityType': activity,
                'lstype': lstype,
                'text': p.get('lstext', '')
            }
            
            # Include all lessons (including Bereitschaft, Gangaufsicht)
            # For display: use activityType if no subjects
            if not lesson['subjects'] and lstype:
                lesson['subjects'] = [activity]
            
            lessons.append(lesson)
        
        # Sort by date and startTime
        lessons.sort(key=lambda l: (l.get('date', 0), l.get('startTime', 0)))
        
        log(f"Parsed {len(lessons)} lessons")
        if lessons:
            log(f"First lesson converted: {json.dumps(lessons[0], default=str)}")
        
        return lessons
        
    except requests.exceptions.ConnectionError as e:
        log(f"Connection error in getTimetable: {e}")
        if retry:
            log("Refreshing session and retrying...")
            session.close()
            session = requests.Session()
            session.headers['User-Agent'] = 'Untis/6.3.2 (Linux; Mobile; SailfishOS)'
            session.headers['Content-Type'] = 'application/json'
            return _get_timetable_jsonrpc(element_type, element_id, date_iso, retry=False)
        return []
        
    except requests.exceptions.Timeout as e:
        log(f"Timeout in getTimetable: {e}")
        return []
        
    except Exception as e:
        log(f"getTimetable exception: {e}")
        return []


def _get_timetable_mobile_api(start_date: str, end_date: str):
    """Get timetable using Mobile API to get lessonIds
    
    Mobile API getTimetable returns UMPeriod with:
    - id: Period ID (ttId)
    - lessonId: Lesson ID (needed for homework)
    """
    global cache
    
    # Format: YYYY-MM-DD
    # Type is integer: 2 = TEACHER
    params = {
        "id": int(user_id),
        "type": 2,  # TEACHER as integer
        "startDate": start_date,
        "endDate": end_date,
        "masterDataTimestamp": 0,
        "timetableTimestamp": 0,
        "timetableTimestamps": []
    }
    
    log(f"Mobile API getTimetable: {start_date} to {end_date}")
    result = mobile_call("getTimetable", params)
    
    # Debug: Log FULL response
    log(f"Mobile API getTimetable FULL response: {json.dumps(result, default=str)[:1500]}")
    
    if "error" in result:
        log(f"Mobile API getTimetable error: {result.get('error')}")
        return []
    
    inner = result.get("result", {})
    log(f"Mobile API result keys: {list(inner.keys()) if isinstance(inner, dict) else type(inner)}")
    
    timetable = inner.get("timetable", {})
    log(f"Mobile API timetable type: {type(timetable)}")
    
    if isinstance(timetable, dict):
        log(f"Mobile API timetable keys: {list(timetable.keys())}")
    elif timetable is None:
        log("Mobile API timetable is None!")
    
    periods = []
    if isinstance(timetable, dict):
        periods = timetable.get("periods", [])
    
    log(f"Mobile API returned {len(periods)} periods")
    
    # Cache lessonIds
    for p in periods:
        period_id = p.get("id")
        lesson_id = p.get("lessonId")
        if period_id and lesson_id:
            cache['lesson_ids'][int(period_id)] = int(lesson_id)
    
    log(f"Cached {len(cache['lesson_ids'])} lessonIds")
    
    # Convert to our format
    lessons = []
    for p in periods:
        period_id = p.get("id")
        lesson_id = p.get("lessonId", period_id)
        
        # Parse datetime
        start_dt = p.get("startDateTime", "")  # "2025-11-28T10:50Z"
        end_dt = p.get("endDateTime", "")
        
        # Extract date and time
        if start_dt:
            date_part = start_dt[:10].replace("-", "")  # "20251128"
            time_part = start_dt[11:16].replace(":", "")  # "1050"
            date_int = int(date_part) if date_part else 0
            start_time = int(time_part) if time_part else 0
        else:
            date_int = 0
            start_time = 0
            
        if end_dt:
            end_time_part = end_dt[11:16].replace(":", "")
            end_time = int(end_time_part) if end_time_part else 0
        else:
            end_time = 0
        
        # Elements (classes, teachers, subjects, rooms)
        elements = p.get("elements", [])
        classes = []
        teachers = []
        subjects = []
        rooms = []
        class_ids = []
        teacher_ids = []
        subject_ids = []
        room_ids = []
        
        for elem in elements:
            elem_type = elem.get("type", "")
            elem_id = elem.get("id", 0)
            
            if elem_type == "CLASS":
                class_ids.append(elem_id)
                classes.append(cache['classes'].get(elem_id, f"K{elem_id}"))
            elif elem_type == "TEACHER":
                teacher_ids.append(elem_id)
                teachers.append(cache['teachers'].get(elem_id, f"T{elem_id}"))
            elif elem_type == "SUBJECT":
                subject_ids.append(elem_id)
                subjects.append(cache['subjects'].get(elem_id, f"S{elem_id}"))
            elif elem_type == "ROOM":
                room_ids.append(elem_id)
                rooms.append(cache['rooms'].get(elem_id, f"R{elem_id}"))
        
        # Period status
        status_list = p.get("is", [])
        cell_state = "STANDARD"
        if "CANCELLED" in status_list:
            cell_state = "CANCELLED"
        elif "IRREGULAR" in status_list:
            cell_state = "IRREGULAR"
        
        lesson = {
            'id': period_id,
            'lessonId': lesson_id,
            'date': date_int,
            'startTime': start_time,
            'endTime': end_time,
            'classes': classes,
            'teachers': teachers,
            'subjects': subjects,
            'rooms': rooms,
            'classIds': class_ids,
            'teacherIds': teacher_ids,
            'subjectIds': subject_ids,
            'roomIds': room_ids,
            'code': '',
            'cellState': cell_state,
            'activityType': 'Unterricht',
            'lstype': '',
            'text': ''
        }
        
        lessons.append(lesson)
    
    # Sort by date and startTime
    lessons.sort(key=lambda l: (l.get('date', 0), l.get('startTime', 0)))
    
    if lessons:
        log(f"First lesson: id={lessons[0]['id']}, lessonId={lessons[0]['lessonId']}")
    
    return lessons


def get_timetable(start_date: str, end_date: str):
    """Get timetable for date range (YYYYMMDD format)"""
    if not secret:
        return []
    
    # Convert YYYYMMDD to YYYY-MM-DD
    start_iso = f"{start_date[:4]}-{start_date[4:6]}-{start_date[6:8]}"
    
    log(f"getTimetable (own): {start_iso}")
    
    # Use legacy JSON-RPC API (Mobile API doesn't return timetable data for this school)
    return _get_timetable_jsonrpc(2, user_id, start_iso)  # 2 = TEACHER


def get_timetable_for(entity_type, entity_id: int, start_date: str, end_date: str):
    """Get timetable for specific entity"""
    if not secret:
        return []
    
    # Convert YYYYMMDD to YYYY-MM-DD
    start_iso = f"{start_date[:4]}-{start_date[4:6]}-{start_date[6:8]}"
    
    # entity_type: 1=class, 2=teacher, 3=subject, 4=room, 5=student
    etype = int(entity_type) if isinstance(entity_type, int) else 2
    
    log(f"getTimetable for: type={etype}, id={entity_id}")
    
    return _get_timetable_jsonrpc(etype, int(entity_id), start_iso)


def _process_timetable(data):
    """Process timetable response into lesson list"""
    # Debug: Was ist die Struktur?
    log(f"_process_timetable: data type = {type(data)}")
    
    periods = []
    
    if isinstance(data, dict):
        # Try 'timetable' key first
        timetable = data.get("timetable", {})
        log(f"timetable type = {type(timetable)}")
        
        if isinstance(timetable, dict):
            log(f"timetable keys: {list(timetable.keys())}")
            log(f"displayableStartDate: {timetable.get('displayableStartDate')}")
            log(f"displayableEndDate: {timetable.get('displayableEndDate')}")
            
            # timetable hat 'periods' direkt als Liste
            raw_periods = timetable.get("periods")
            log(f"raw periods type: {type(raw_periods)}, value: {raw_periods}")
            
            if isinstance(raw_periods, list):
                periods = raw_periods
            elif isinstance(raw_periods, dict):
                # Vielleicht ist periods ein Dict mit Datums-Keys?
                log(f"periods is dict with keys: {list(raw_periods.keys())[:5]}")
                for key, val in raw_periods.items():
                    if isinstance(val, list):
                        periods.extend(val)
                    elif isinstance(val, dict):
                        periods.append(val)
                        
        elif isinstance(timetable, list):
            periods = timetable
        
        # Fallback: periods direkt in data
        if not periods:
            periods = data.get("periods", [])
            log(f"periods from data.periods: {len(periods)}")
            
    elif isinstance(data, list):
        periods = data
    
    log(f"Total periods: {len(periods)}")
    if periods and len(periods) > 0:
        log(f"First period keys: {list(periods[0].keys()) if isinstance(periods[0], dict) else periods[0]}")
    
    lessons = []
    for p in periods:
        if not isinstance(p, dict):
            continue
            
        lesson = {
            'id': p.get('id') or p.get('ttId'),
            'date': p.get('date'),
            'startTime': p.get('startTime'),
            'endTime': p.get('endTime'),
            'type': p.get('type', 'ls'),
            'code': p.get('code', ''),
            'classes': _extract_names(p, 'kl', 'classes'),
            'subjects': _extract_names(p, 'su', 'subjects'),
            'rooms': _extract_names(p, 'ro', 'rooms'),
            'teachers': _extract_names(p, 'te', 'teachers'),
        }
        lessons.append(lesson)
    
    log(f"Parsed {len(lessons)} lessons")
    return sorted(lessons, key=lambda x: (x.get('date', 0), x.get('startTime', 0)))


def _extract_names(period, key1, key2):
    """Extract names from period data"""
    items = period.get(key1, period.get(key2, []))
    names = []
    for item in items:
        if isinstance(item, dict):
            names.append(item.get('name', item.get('longName', str(item.get('id', '?')))))
        else:
            names.append(str(item))
    return names


def get_today():
    """Get today's timetable"""
    today = datetime.now().strftime("%Y%m%d")
    return get_timetable(today, today)


def get_week():
    """Get this week's timetable"""
    today = datetime.now()
    monday = today - timedelta(days=today.weekday())
    friday = monday + timedelta(days=4)
    return get_timetable(monday.strftime("%Y%m%d"), friday.strftime("%Y%m%d"))


# ==================== Lists for Selection ====================

def get_classes_list():
    """Get list of all classes"""
    result = []
    for id, name in cache.get('classes', {}).items():
        result.append({'id': id, 'name': name, 'type': 1})
    return sorted(result, key=lambda x: x['name'])


def get_teachers_list():
    """Get list of all teachers"""
    result = []
    for id, name in cache.get('teachers', {}).items():
        result.append({'id': id, 'name': name, 'type': 2})
    return sorted(result, key=lambda x: x['name'])


def get_rooms_list():
    """Get list of all rooms"""
    result = []
    for id, name in cache.get('rooms', {}).items():
        result.append({'id': id, 'name': name, 'type': 4})
    return sorted(result, key=lambda x: x['name'])


def get_students_list():
    """Get list of all students - not available with Secret-Only auth"""
    # Legacy API getStudents() requires special permissions not available with Secret/OTP auth
    # The students are loaded from getPeriodData2017 when opening lessons
    
    # Check if we have any cached students from period data
    if cache.get('students'):
        result = []
        for id, data in cache['students'].items():
            if isinstance(data, dict):
                name = data.get('name', '')
            else:
                name = str(data)
            result.append({'id': id, 'name': name, 'type': 5})
        if result:
            log(f"Returning {len(result)} cached students from period data")
            return sorted(result, key=lambda x: x['name'])
    
    log("Students list not available - no permission for getStudents()")
    # Return empty list - UI has input field for student ID
    return []


# ==================== Period Data ====================

def get_period_data(period_id: int, load_images: bool = False):
    """Get detailed period data including students"""
    if not secret:
        return {'error': 'Nicht authentifiziert'}
    
    try:
        period_id = int(period_id)
        log(f"getPeriodData2017 for period {period_id}")
        result = mobile_call("getPeriodData2017", {"ttIds": [period_id]})
        
        if "error" in result:
            return {'error': result['error'].get('message', 'Fehler')}
        
        if "result" not in result:
            return {'error': 'Keine Daten'}
        
        data = result["result"]
        data_by_tt = data.get("dataByTTId", {})
        
        # Log available ttIds
        available_tt_ids = list(data_by_tt.keys())
        log(f"Requested ttId: {period_id}, Available ttIds: {available_tt_ids}")
        
        period_data = data_by_tt.get(str(period_id), {})
        
        log(f"period_data keys: {list(period_data.keys())}")
        
        # Process students - use referencedStudents from top level
        students = []
        referenced_students = data.get("referencedStudents", [])
        student_ids = period_data.get("studentIds", []) or []
        
        log(f"referencedStudents count: {len(referenced_students)}, studentIds count: {len(student_ids)}")
        
        if referenced_students:
            for s in referenced_students:
                student_id = s.get('id')
                first_name = s.get('foreName', s.get('firstName', ''))
                last_name = s.get('longName', s.get('lastName', ''))
                
                students.append({
                    'studId': student_id,
                    'firstName': first_name,
                    'lastName': last_name,
                    'className': s.get('className', ''),
                    'imageUrl': s.get('imageUrl', ''),
                })
                
                # Cache student for later use in timetable selection
                name = f"{last_name} {first_name}".strip() if last_name else first_name
                cache.setdefault('students', {})[student_id] = {'name': name}
                
            log(f"Loaded {len(students)} students from referencedStudents")
            if students:
                log(f"First student: {students[0]}")
        else:
            # Fallback to period_data students
            for s in period_data.get("students", []):
                students.append({
                    'studId': s.get('id'),
                    'firstName': s.get('firstName', s.get('foreName', '')),
                    'lastName': s.get('lastName', s.get('longName', '')),
                    'className': s.get('className', ''),
                })
        
        # Process topic and permissions
        topic = period_data.get('topic', {}) or {}
        can_field = period_data.get('can', []) or []
        
        # Process absences (handle None)
        absences = []
        absences_raw = period_data.get("absences") or []
        for a in absences_raw:
            absences.append({
                'id': a.get('id'),
                'studentId': a.get('studentId'),
                'reasonId': a.get('reasonId'),
                'startTime': a.get('startTime'),
                'endTime': a.get('endTime'),
                'text': a.get('text', ''),
            })
        
        # Process classreg events (handle None)
        classreg_events = []
        classreg_raw = period_data.get("classRegEvents") or []
        for e in classreg_raw:
            element_type = e.get('elementType', '')  # CLASS or STUDENT
            element_id = e.get('elementId')
            
            # Find name based on element type
            element_name = ""
            if element_type == 'STUDENT':
                for s in students:
                    if s.get('studId') == element_id:
                        element_name = f"{s.get('lastName', '')} {s.get('firstName', '')}"
                        break
                if not element_name:
                    element_name = f"Schüler ID {element_id}"
            elif element_type == 'CLASS':
                # Look up class name from cache (cache['classes'] is a dict: ID -> name)
                element_name = cache.get('classes', {}).get(element_id, f"Klasse ID {element_id}")
            
            # Find reason name from cache
            reason_name = ""
            reason_id = e.get('eventReasonId')
            if reason_id and reason_id > 0:
                for r in cache.get('event_reasons', []):
                    if r.get('id') == reason_id:
                        reason_name = r.get('longName') or r.get('name', '')
                        break
            
            classreg_events.append({
                'id': e.get('id'),
                'elementType': element_type,
                'elementId': element_id,
                'elementName': element_name,
                'reasonId': reason_id,
                'reason': reason_name,
                'text': e.get('text', ''),
                'dateTime': e.get('dateTime', ''),
            })
        
        # Extract text field (contains notes)
        # API returns: {"lesson": "", "substitution": "", "info": "...", "attachments": []}
        # "info" field is the notesAll (visible to all)
        # TODO: Find where notesStaff is stored - might need separate API call
        text_data = period_data.get('text') or {}
        
        # Map API field names to our internal names
        notes_all_text = text_data.get('info', '')  # 'info' = notesAll in API response
        notes_staff_text = text_data.get('staffInfo', '') or text_data.get('notesStaff', '')  # Try both possible names
        
        log(f"Notes extracted: notesAll='{notes_all_text}', notesStaff='{notes_staff_text}'")
        
        return {
            'ttId': period_data.get('ttId'),
            'students': sorted(students, key=lambda x: (x.get('lastName', ''), x.get('firstName', ''))),
            'studentIds': student_ids,
            'absences': absences,
            'classRegEvents': classreg_events,
            'topic': topic,
            'homeworks': period_data.get('homeWorks') or [],  # lowercase for QML
            'can': can_field,
            'notesAll': {'text': notes_all_text},
            'notesStaff': {'text': notes_staff_text},
            'text': text_data,  # Raw text field
        }
        
    except Exception as e:
        log(f"Period data error: {e}")
        return {'error': str(e)}


# ==================== Absences ====================

def get_absence_reasons():
    """Get list of absence reasons"""
    return cache.get('absence_reasons', [])


def create_absence(period_id: int, student_id: int, reason_id: int = None, text: str = ""):
    """Create absence for student in period using createAbsences2017
    
    NOTE: createImmediateAbsence2017 has a server-side bug with null text.
    Using createAbsences2017 instead (same as Android app and old version).
    """
    log(f"create_absence called: period_id={period_id}, student_id={student_id}, reason_id={reason_id}")
    
    if not secret:
        log("create_absence: Not authenticated")
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    try:
        # Validate and get reason ID
        valid_reasons = cache.get('absence_reasons', [])
        valid_reason_ids = [r.get('id') for r in valid_reasons if r.get('id')]
        
        # If provided reason is invalid, use ABSENZ_U (unentschuldigt) or server default
        if reason_id is None or reason_id == 0 or (valid_reason_ids and reason_id not in valid_reason_ids):
            # Prefer ABSENZ_U (ID 2) if available, otherwise use server default
            if 2 in valid_reason_ids:
                reason_id = 2  # ABSENZ_U = unentschuldigt
            else:
                default_id = cache.get('default_absence_reason_id')
                if default_id and (not valid_reason_ids or default_id in valid_reason_ids):
                    reason_id = default_id
                elif valid_reason_ids:
                    reason_id = valid_reason_ids[0]  # Use first available reason
                else:
                    reason_id = 2  # Fallback to 2 (ABSENZ_U)
            log(f"create_absence: Using reason_id={reason_id} (original was invalid or not provided)")
        
        # First get period data for times (required by createAbsences2017)
        period_check = mobile_call("getPeriodData2017", {"ttIds": [int(period_id)]})
        if "error" in period_check:
            error_msg = period_check.get('error', {}).get('message', 'Periode nicht gefunden')
            log(f"create_absence: getPeriodData2017 error: {error_msg}")
            return {'success': False, 'error': error_msg}
        
        if "result" not in period_check:
            return {'success': False, 'error': 'Stunde nicht gefunden'}
        
        data = period_check["result"]
        period_data = data.get("dataByTTId", {}).get(str(period_id), {})
        topic = period_data.get("topic", {}) or {}
        start_dt = topic.get("startDateTime", "")
        end_dt = topic.get("endDateTime", "")
        
        log(f"create_absence: start={start_dt}, end={end_dt}")
        
        if not start_dt or not end_dt:
            log("create_absence: Missing startDateTime or endDateTime")
            return {'success': False, 'error': 'Stundenzeiten nicht verfügbar'}
        
        # Build params for createAbsences2017 (like old version / Android app)
        params = {
            "periodId": int(period_id),
            "studentIds": [int(student_id)],
            "absenceReasonId": int(reason_id),
            "startDateTime": start_dt,
            "endDateTime": end_dt
        }
        
        # Only add text if not empty
        if text and text.strip():
            params["text"] = text.strip()
        
        log(f"create_absence params: {params}")
        
        result = mobile_call("createAbsences2017", params)
        log(f"create_absence result: {result}")
        
        if "error" in result:
            error_msg = result['error'].get('message', 'Fehler')
            log(f"create_absence error: {error_msg}")
            return {'success': False, 'error': error_msg}
        
        # Check result structure
        if "result" in result:
            result_data = result.get("result", {})
            student_result = result_data.get("resultPerStudent", {}).get(str(student_id), {})
            created_absences = student_result.get("absences", [])
            
            if created_absences:
                log(f"create_absence SUCCESS: absence_id={created_absences[0].get('id')}")
                return {'success': True, 'result': created_absences[0]}
            else:
                conflicts = student_result.get("conflicts", [])
                if conflicts:
                    log(f"create_absence: conflict detected")
                    return {'success': False, 'error': 'Konflikt mit bestehender Abwesenheit'}
                log(f"create_absence: no absence created (unknown reason)")
                return {'success': False, 'error': 'Abwesenheit nicht erstellt'}
        
        return {'success': True, 'result': result.get('result')}
        
    except Exception as e:
        log(f"create_absence exception: {e}")
        import traceback
        log(f"create_absence traceback: {traceback.format_exc()}")
        return {'success': False, 'error': str(e)}


def delete_absence(absence_id: int):
    """Delete an absence"""
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    try:
        result = mobile_call("deleteAbsence2017", {"absenceId": int(absence_id)})
        
        if "error" in result:
            return {'success': False, 'error': result['error'].get('message', 'Fehler')}
        
        return {'success': True}
        
    except Exception as e:
        return {'success': False, 'error': str(e)}


def create_lateness(period_id: int, student_id: int, reason_id: int = None):
    """Create lateness for student using createImmediateLateness2017"""
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    try:
        log(f"create_lateness: period={period_id}, student={student_id}, reason={reason_id}")
        
        # Build params - note: createImmediateLateness2017 does NOT take text param
        params = {
            "periodId": int(period_id),
            "studentId": int(student_id)
        }
        
        # Add reason if provided
        if reason_id and reason_id > 0:
            params["reasonId"] = int(reason_id)
        
        result = mobile_call("createImmediateLateness2017", params)
        log(f"create_lateness result: {result}")
        
        if "error" in result:
            return {'success': False, 'error': result['error'].get('message', 'Fehler')}
        
        if "result" in result:
            result_data = result.get("result", {})
            if result_data.get("absence"):
                return {'success': True, 'result': result_data.get("absence")}
        
        return {'success': True, 'result': result.get('result')}
        
    except Exception as e:
        log(f"create_lateness exception: {e}")
        return {'success': False, 'error': str(e)}


# ==================== Topic / Lehrstoff ====================

def submit_topic(period_id: int, text: str):
    """Submit lesson topic"""
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    try:
        log(f"=== SUBMIT_TOPIC ===")
        log(f"period_id: {period_id}")
        log(f"text: {text}")
        
        result = mobile_call("submitLessonTopic", {
            "ttId": int(period_id),
            "lessonTopic": text
        })
        
        log(f"submitLessonTopic result: {json.dumps(result, default=str)}")
        
        if "error" in result:
            return {'success': False, 'error': result['error'].get('message', 'Fehler')}
        
        # Verify by re-fetching
        log("Verifying topic was saved...")
        verify = mobile_call("getPeriodData2017", {"ttIds": [int(period_id)]})
        if "result" in verify:
            vdata = verify["result"].get("dataByTTId", {}).get(str(period_id), {})
            vtopic = vdata.get("topic", {})
            log(f"Verification - saved topic: '{vtopic.get('text', '')}'")
            if vtopic.get('text') == text:
                log("✓ Topic saved successfully!")
            else:
                log(f"!!! MISMATCH: expected '{text}', got '{vtopic.get('text', '')}'")
        
        return {'success': True}
        
    except Exception as e:
        return {'success': False, 'error': str(e)}


# ==================== Homework ====================

def submit_homework(period_id: int, text: str, due_date: str = None, remark: str = "", homework_id: int = None):
    """Submit or update homework
    
    APK Analysis shows SubmitHomeWorkRequest has:
    - ttId: Long (the period ID at top level!)
    - homeWork: JsonHomeWork object with:
        - id: Long (0 for new)
        - lessonId: Long (the LESSON ID, not period ID!)
        - text: String
        - remark: String
        - startDate: String
        - endDate: String
        - completed: boolean
    """
    log(f"=== SUBMIT_HOMEWORK ===")
    log(f"period_id: {period_id}, text: {text[:50]}..., due_date: {due_date}, remark: {remark}, homework_id: {homework_id}")
    
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    if not text or not text.strip():
        return {'success': False, 'error': 'Bitte Text eingeben'}
    
    # Get today's date for startDate
    today = datetime.now().strftime("%Y-%m-%d")
    
    try:
        # The correct format based on APK analysis:
        # SubmitHomeWorkRequest has ttId (Long) and homeWork (JsonHomeWork)
        # 
        # ISSUE: We don't have the correct lessonId because:
        # - Mobile API getTimetable doesn't work for this school
        # - Legacy API doesn't provide lessonId
        # 
        # Let's try without lessonId - server might derive it from ttId
        params = {
            "ttId": int(period_id),
            "homeWork": {
                "id": int(homework_id) if homework_id else 0,
                "text": text.strip(),
                "remark": remark or "",
                "startDate": today,
                "endDate": due_date or today,
                "completed": False
            }
        }
        log(f"Submitting without lessonId: {json.dumps(params, default=str)}")
        result = mobile_call("submitHomeWork", params)
        log(f"Result: {json.dumps(result, default=str)}")
        
        # Check for success
        if "error" not in result:
            inner = result.get("result", {})
            if isinstance(inner, dict):
                hw_id = inner.get("submittedHomeWorkId", 0)
                if hw_id > 0:
                    log(f"SUCCESS! HomeWork ID: {hw_id}")
                    return {'success': True, 'result': inner}
                if inner.get("success") == True:
                    log("SUCCESS (success=true)")
                    return {'success': True, 'result': inner}
        
        error_msg = result.get('error', {}).get('message', 'Hausübung konnte nicht gespeichert werden')
        return {'success': False, 'error': error_msg}
        
    except Exception as e:
        log(f"submit_homework exception: {e}")
        return {'success': False, 'error': str(e)}


def delete_homework(homework_id: int):
    """Delete homework"""
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    try:
        result = mobile_call("deleteHomeWork", {"id": int(homework_id)})
        
        if "error" in result:
            return {'success': False, 'error': result['error'].get('message', 'Fehler')}
        
        return {'success': True}
        
    except Exception as e:
        return {'success': False, 'error': str(e)}


# ==================== Class Register Events ====================

def get_event_reasons():
    """Get list of event reasons"""
    return cache.get('event_reasons', [])


def submit_classreg_event(period_id: int, element_ids, reason_id: int = None, text: str = "", element_type: str = "STUDENT"):
    """Submit class register event for students or classes
    
    APK Analysis shows SubmitClassRegEventsRequest has:
    - ttId: Long
    - event: JsonClassRegEvent (singular!) with:
        - id: Long (0 for new)
        - date: String
        - startTime: String
        - text: String
        - reasonId: Long
        - element: JsonTypedElement (type + id)
    
    Args:
        period_id: The period/lesson ID (ttId)
        element_ids: Single ID or list of IDs
        reason_id: Event reason ID
        text: Event text/note
        element_type: "STUDENT" or "CLASS"
    """
    log(f"=== SUBMIT_CLASSREG_EVENT ===")
    log(f"period_id: {period_id}, element_ids: {element_ids}, reason_id: {reason_id}, text: {text}, element_type: {element_type}")
    
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    if not text or not text.strip():
        return {'success': False, 'error': 'Bitte Text eingeben'}
    
    try:
        # Support single ID or list
        if isinstance(element_ids, (int, float)):
            element_ids = [int(element_ids)]
        elif isinstance(element_ids, list):
            element_ids = [int(eid) for eid in element_ids]
        else:
            element_ids = [int(element_ids)]
        
        # Determine reason value
        reason_val = int(reason_id) if reason_id and reason_id > 0 else -1
        
        # Element type mapping (from APK: STUDENT = 5, KLASSE = 1)
        type_map = {"STUDENT": 5, "CLASS": 1, "KLASSE": 1, "TEACHER": 2, "ROOM": 4}
        elem_type_num = type_map.get(element_type.upper(), 5)
        
        # Current date/time - API uses yyyy-MM-dd and HH:mm format
        now = datetime.now()
        date_str = now.strftime("%Y-%m-%d")  # e.g., "2025-11-28"
        time_str = now.strftime("%H:%M")     # e.g., "10:50"
        
        success_count = 0
        last_error = None
        
        # Submit one event per element (APK uses singular 'event')
        for elem_id in element_ids:
            # APK-based format: singular event
            params = {
                "ttId": int(period_id),
                "event": {
                    "id": 0,  # New event
                    "date": date_str,
                    "startTime": time_str,
                    "text": text.strip(),
                    "reasonId": reason_val,
                    "element": {
                        "type": elem_type_num,
                        "id": elem_id
                    }
                }
            }
            
            log(f"APK format for element {elem_id}: {json.dumps(params, default=str)}")
            result = mobile_call("submitClassRegEvents", params)
            log(f"Result: {json.dumps(result, default=str)}")
            
            if "error" not in result:
                inner = result.get("result", {})
                if isinstance(inner, dict) and inner.get("success") == True:
                    success_count += 1
                    continue
                # Check if classRegEvent was returned (also indicates success)
                if "classRegEvent" in inner:
                    success_count += 1
                    continue
            else:
                last_error = result.get('error', {}).get('message', 'Fehler')
        
        if success_count > 0:
            return {'success': True, 'count': success_count}
        
        # Fallback: try old format with classRegEvents array
        events = []
        for elem_id in element_ids:
            events.append({
                "elementType": element_type.upper(),
                "elementId": elem_id,
                "eventReasonId": reason_val,
                "text": text.strip()
            })
        
        log(f"Fallback format (classRegEvents array): {json.dumps(events, default=str)}")
        result = mobile_call("submitClassRegEvents", {
            "ttId": int(period_id),
            "classRegEvents": events
        })
        log(f"Fallback result: {json.dumps(result, default=str)}")
        
        if "error" not in result:
            return {'success': True, 'count': len(element_ids)}
        
        return {'success': False, 'error': last_error or 'Eintrag konnte nicht erstellt werden'}
        
    except Exception as e:
        log(f"submit_classreg_event exception: {e}")
        return {'success': False, 'error': str(e)}


# ==================== Helper for QML ====================

def load_absence_reasons():
    """Called by QML to ensure absence reasons are available"""
    pyotherside.send('absenceReasonsLoaded', cache.get('absence_reasons', []))


# ==================== Additional Functions ====================

def create_lateness_with_time(period_id: int, student_id: int, arrival_time: str, reason_id: int = None):
    """Create lateness with specific arrival time"""
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    try:
        if reason_id is None or reason_id == 0:
            reason_id = cache.get('default_lateness_reason_id', 1)
            
        params = {
            "ttId": int(period_id),
            "studentId": int(student_id),
            "reasonId": int(reason_id),
            "isLateness": True,
            "text": " "  # Single space required - server crashes on null/empty string!
        }
        
        if arrival_time:
            params["arrivalTime"] = arrival_time
        
        result = mobile_call("createImmediateAbsence2017", params)
        
        if "error" in result:
            return {'success': False, 'error': result['error'].get('message', 'Fehler')}
        
        return {'success': True, 'result': result.get('result')}
        
    except Exception as e:
        return {'success': False, 'error': str(e)}


def edit_absence(absence_id: int, reason_id: int, start_datetime: str, end_datetime: str, text: str = ""):
    """Edit an existing absence"""
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    try:
        # Convert empty text to single space - server crashes on null/empty
        actual_text = text if text else " "
        result = mobile_call("editAbsence2017", {
            "absenceId": int(absence_id),
            "reasonId": int(reason_id),
            "startDateTime": start_datetime,
            "endDateTime": end_datetime,
            "text": actual_text
        })
        
        if "error" in result:
            return {'success': False, 'error': result['error'].get('message', 'Fehler')}
        
        return {'success': True}
        
    except Exception as e:
        return {'success': False, 'error': str(e)}


def fetch_student_image(student_id: int):
    """Fetch student image - not available in Mobile-Only mode"""
    return {'success': False, 'error': 'Bilder nicht verfügbar'}


def get_classreg_events(period_id: int):
    """Get class register events for a period, including eventReasons"""
    log(f"get_classreg_events called for period {period_id}")
    
    period_data = get_period_data(period_id)
    if 'error' in period_data:
        log(f"get_classreg_events error: {period_data.get('error')}")
        return {'events': [], 'eventReasons': cache.get('event_reasons', [])}
    
    event_reasons = cache.get('event_reasons', [])
    log(f"Returning {len(event_reasons)} eventReasons")
    
    return {
        'events': period_data.get('classRegEvents', []),
        'eventReasons': event_reasons
    }


def get_homework(period_id: int):
    """Get homework for a period"""
    period_data = get_period_data(period_id)
    if 'error' in period_data:
        return []
    return period_data.get('homeWorks', [])


def get_homework_for_date_range(start_date: str = None, end_date: str = None):
    """Get homework using the getHomeWork endpoint with date range
    
    APK Analysis shows GetHomeWorkRequest has:
    - id: Long (teacher/element ID)
    - type: ElementType (TEACHER=2, STUDENT=5, CLASS=1)
    - startDate: String (yyyy-MM-dd)
    - endDate: String (yyyy-MM-dd)
    """
    global user_id, user_type
    
    if not secret:
        return {'homeworks': [], 'error': 'Nicht authentifiziert'}
    
    # Default to this week if no dates provided
    if not start_date:
        today = datetime.now()
        # Go back to Monday of this week
        monday = today - timedelta(days=today.weekday())
        start_date = monday.strftime("%Y-%m-%d")
    
    if not end_date:
        today = datetime.now()
        # Go to next month
        end_date = (today + timedelta(days=30)).strftime("%Y-%m-%d")
    
    try:
        # ElementType: TEACHER=2
        params = {
            "id": int(user_id),
            "type": 2,  # TEACHER
            "startDate": start_date,
            "endDate": end_date
        }
        log(f"getHomeWork request: {json.dumps(params)}")
        result = mobile_call("getHomeWork", params)
        log(f"getHomeWork result: {json.dumps(result, default=str)[:500]}")
        
        inner = result.get("result", {})
        if isinstance(inner, dict):
            homeworks = inner.get("homeWorks", [])
            log(f"getHomeWork returned {len(homeworks)} homework items")
            return {'homeworks': homeworks, 'lessonsById': inner.get('lessonsById', {})}
        
        return {'homeworks': [], 'error': 'Unerwartete API-Antwort'}
    except Exception as e:
        log(f"getHomeWork exception: {e}")
        return {'homeworks': [], 'error': str(e)}


def submit_absences(period_id: int, absences: list):
    """Submit multiple absences at once"""
    log(f"submit_absences called: period_id={period_id}, absences={absences}")
    
    if not secret:
        log("submit_absences: Not authenticated")
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    results = []
    for absence in absences:
        # Skip absences that already exist on server (have an id)
        if absence.get('id'):
            log(f"Skipping existing absence with id={absence.get('id')}")
            continue
        
        student_id = absence.get('studentId')
        if not student_id:
            log(f"Skipping absence without studentId: {absence}")
            continue
            
        result = create_absence(
            period_id,
            int(student_id),
            absence.get('reasonId')
        )
        results.append(result)
    
    log(f"submit_absences results: {results}")
    return {'success': True, 'results': results}


def sync_absences(period_id: int, absences: list):
    """Sync absences - create new ones"""
    return submit_absences(period_id, absences)


def submit_period_info(period_id: int, info_type: str, text: str):
    """Submit period info (notes for all or staff)
    
    APK Analysis shows SubmitPeriodInfoRequest has:
    - periodId: Long
    - periodInfo: String (just the text directly!)
    
    info_type: 'notesAll' (visible to all) or 'notesStaff' (staff only)
    """
    log(f"=== SUBMIT_PERIOD_INFO ===")
    log(f"period_id: {period_id}, info_type: {info_type}, text: {text[:50]}...")
    
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    try:
        # The correct format based on APK analysis:
        # SubmitPeriodInfoRequest has periodId (Long) and periodInfo (String)
        params = {
            "periodId": int(period_id),
            "periodInfo": text  # Just the text directly as a string!
        }
        log(f"APK-based format: {json.dumps(params, default=str)}")
        result = mobile_call("submitPeriodInfo2017", params)
        log(f"Result: {json.dumps(result, default=str)}")
        
        if "error" not in result:
            inner = result.get("result", {})
            if isinstance(inner, dict) and inner.get("success") == True:
                log("SUCCESS!")
                return {'success': True}
        
        # If that didn't work, the type might need to be specified differently
        # Try with type field
        params2 = {
            "periodId": int(period_id),
            "type": info_type,  # notesAll or notesStaff
            "periodInfo": text
        }
        log(f"With type field: {json.dumps(params2, default=str)}")
        result = mobile_call("submitPeriodInfo2017", params2)
        log(f"Result 2: {json.dumps(result, default=str)}")
        
        if "error" not in result:
            inner = result.get("result", {})
            if isinstance(inner, dict) and inner.get("success") == True:
                log("SUCCESS with type!")
                return {'success': True}
        
        error_msg = result.get('error', {}).get('message', 'Fehler')
        return {'success': False, 'error': error_msg}
        
    except Exception as e:
        log(f"submit_period_info exception: {e}")
        return {'success': False, 'error': str(e)}


def test_mobile_api():
    """Test if mobile API is working"""
    if not secret:
        return {'success': False, 'error': 'Nicht authentifiziert'}
    
    result = mobile_call("getUserData2017")
    if "error" in result:
        return {'success': False, 'error': result['error'].get('message', 'Fehler')}
    return {'success': True}
