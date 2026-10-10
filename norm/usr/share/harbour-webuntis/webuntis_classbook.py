#!/usr/bin/env python3
"""
WebUntis Klassenbuch Backend für Sailfish OS
Mit Mobile-API für Anwesenheitserfassung
"""

VERSION = "v1.8.7"

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
SERVER = None
SCHOOL = None

# Globaler State
session = None
session_lock = Lock()
person_id = None
person_type = None
username = None
password = None  # For re-authentication if needed
secret = None    # Mobile API secret from QR code

# Cache
cache = {
    'teachers': {},
    'subjects': {},
    'rooms': {},
    'classes': {},
    'students': {},
    'absence_reasons': []
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


def api_call(method: str, params: dict = None):
    """Standard WebUntis API call"""
    global session
    if not session:
        raise Exception("Nicht eingeloggt")
    
    url = f"https://{SERVER}/WebUntis/jsonrpc.do?school={SCHOOL}"
    payload = {
        "id": "1",
        "method": method,
        "params": params or {},
        "jsonrpc": "2.0"
    }
    
    resp = session.post(url, json=payload, timeout=15)
    data = resp.json()
    
    if "error" in data:
        raise Exception(data["error"].get("message", "API Fehler"))
    
    return data.get("result")


def mobile_call(method: str, extra_params: dict = None):
    """Mobile API call with OTP authentication"""
    global session, username, secret
    
    if not session or not secret:
        raise Exception("Mobile API nicht verfügbar")
    
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
    
    # Log full request for debugging
    log(f"mobile_call REQUEST: method={method}, params={params}")
    
    url = f"https://{SERVER}/WebUntis/jsonrpc_intern.do?school={SCHOOL}"
    resp = session.post(url, json=payload, timeout=15)
    return resp.json()


def save_credentials(server: str, school: str, user: str, pwd: str, mobile_secret: str = None):
    """Save credentials to Sailfish Secrets"""
    if not HAS_SECRETS:
        log("Sailfish Secrets not available - credentials not saved")
        return False
    
    log(f"Saving credentials: server={server}, school={school}, user={user}")
    
    try:
        # Delete old credentials first to ensure clean overwrite
        try:
            sailfish_secrets.get_secrets().delete_secret('user-credentials')
            log("Deleted old credentials from Sailfish Secrets")
        except:
            pass
        
        success = sailfish_secrets.get_secrets().store_secret('user-credentials', {
            'server': server,
            'school': school,
            'username': user,
            'password': pwd,
            'secret': mobile_secret or ''
        })
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
        creds = sailfish_secrets.get_secrets().retrieve_secret('user-credentials')
        if creds:
            log(f"Credentials loaded from Sailfish Secrets: server={creds.get('server')}, school={creds.get('school')}, user={creds.get('username')}")
            return {
                'server': creds.get('server'),
                'school': creds.get('school'),
                'username': creds.get('username'),
                'password': creds.get('password'),
                'secret': creds.get('secret')
            }
        log("No credentials found in Sailfish Secrets")
    except Exception as e:
        log(f"Sailfish Secrets load error: {e}")
    
    return None


def login(server: str, school: str, user: str, pwd: str, mobile_secret: str = None, save: bool = True):
    """Login to WebUntis using JSON-RPC"""
    global session, person_id, person_type, username, password, secret, cache, SERVER, SCHOOL
    
    with session_lock:
        try:
            SERVER = server
            SCHOOL = school
            username = user
            password = pwd
            secret = mobile_secret  # Set mobile API secret
            
            session = requests.Session()
            session.headers['User-Agent'] = 'Untis/6.3.2 (Linux; Mobile; SailfishOS)'
            session.headers['Content-Type'] = 'application/json'
            
            log(f"Verbinde zu {SERVER} / {SCHOOL}...")
            
            result = api_call("authenticate", {
                "user": user,
                "password": pwd,
                "client": "harbour-webuntis"
            })
            
            person_id = result.get("personId")
            person_type = result.get("personType")
            
            if save:
                save_credentials(server, school, user, pwd, mobile_secret)
            
            # Load cache
            _load_cache()
            
            log(f"Eingeloggt als {user} (ID: {person_id}) [{VERSION}]")
            log(f"Server: {SERVER}, Schule: {SCHOOL}")
            if secret:
                log(f"Mobile API Secret: vorhanden ({len(secret)} Zeichen)")
            else:
                log("Kein Mobile API Secret - Klassenbuch eingeschränkt")
            
            pyotherside.send('loginSuccess', user)
            return True
            
        except Exception as e:
            session = None
            SERVER = None
            SCHOOL = None
            log(f"Login fehlgeschlagen: {e}")
            pyotherside.send('loginFailed', str(e))
            return False


def auto_login():
    """Try to login with saved credentials"""
    creds = load_credentials()
    if creds and all(k in creds for k in ['server', 'school', 'username', 'password']):
        return login(
            creds['server'],
            creds['school'],
            creds['username'], 
            creds['password'],
            creds.get('secret'),  # Load secret if available
            save=False
        )
    return False


def logout():
    """Logout and clear session"""
    global session, person_id, username, password, SERVER, SCHOOL
    
    with session_lock:
        if session:
            try:
                api_call("logout")
            except:
                pass
            session = None
        
        person_id = None
        username = None
        password = None
        SERVER = None
        SCHOOL = None
    
    pyotherside.send('loggedOut')


def clear_credentials():
    """Delete saved credentials"""
    if HAS_SECRETS:
        sailfish_secrets.delete_user_credentials()
    log("Credentials cleared from Sailfish Secrets")
    logout()


def _load_cache():
    """Load reference data into cache"""
    global cache
    
    try:
        # Teachers
        for t in api_call("getTeachers") or []:
            cache['teachers'][t['id']] = t.get('name', t.get('foreName', '?'))
        
        # Subjects
        for s in api_call("getSubjects") or []:
            cache['subjects'][s['id']] = s.get('name', s.get('longName', '?'))
        
        # Rooms
        for r in api_call("getRooms") or []:
            cache['rooms'][r['id']] = r.get('name', '?')
        
        # Classes
        for k in api_call("getKlassen") or []:
            cache['classes'][k['id']] = k.get('name', '?')
        
        # Students
        for s in api_call("getStudents") or []:
            cache['students'][s['id']] = {
                'name': f"{s.get('foreName', '')} {s.get('longName', '')}".strip(),
                'key': s.get('key', ''),
                'klasse': s.get('klasseId')
            }
        
        # Absence reasons and event reasons from mobile API
        if secret:
            result = mobile_call("getUserData2017")
            if "result" in result:
                master_data = result["result"].get("masterData", {})
                log(f"MasterData keys: {list(master_data.keys())}")
                
                # Debug: absenceReasons zum Vergleich
                raw_absence_reasons = master_data.get("absenceReasons")
                log(f"Raw absenceReasons type: {type(raw_absence_reasons)}, count: {len(raw_absence_reasons) if isinstance(raw_absence_reasons, list) else 'N/A'}")
                cache['absence_reasons'] = raw_absence_reasons if isinstance(raw_absence_reasons, list) else []
                
                # Log ALL absence reasons for debugging
                log(f"=== ABSENCE REASONS ({len(cache['absence_reasons'])}) ===")
                for ar in cache['absence_reasons']:
                    log(f"  ID={ar.get('id')}: {ar.get('name')} - {ar.get('longName')} (active={ar.get('active')})")
                
                # Debug: eventReasons
                raw_event_reasons = master_data.get("eventReasons")
                log(f"Raw eventReasons type: {type(raw_event_reasons)}, value: {raw_event_reasons}")
                
                # Debug: eventReasonGroups - diese könnten die Kategorien sein!
                raw_event_reason_groups = master_data.get("eventReasonGroups")
                log(f"Raw eventReasonGroups type: {type(raw_event_reason_groups)}, value: {raw_event_reason_groups}")
                
                # eventReasons oder eventReasonGroups verwenden
                if isinstance(raw_event_reasons, list) and raw_event_reasons:
                    cache['event_reasons'] = raw_event_reasons
                elif isinstance(raw_event_reason_groups, list) and raw_event_reason_groups:
                    # eventReasonGroups als Fallback verwenden
                    cache['event_reasons'] = raw_event_reason_groups
                    log(f"Using eventReasonGroups as event_reasons")
                else:
                    cache['event_reasons'] = []
                
                cache['default_lateness_reason_id'] = master_data.get("defaultLatenessReasonId")
                cache['default_absence_reason_id'] = master_data.get("defaultAbsenceReasonId")
                log(f"Lateness Reason ID: {cache.get('default_lateness_reason_id')}")
                log(f"Event Reasons: {len(cache.get('event_reasons', []))} geladen")
                if cache.get('event_reasons'):
                    log(f"First event reason: {cache['event_reasons'][0]}")
        
        log(f"Cache geladen: {len(cache['teachers'])} Lehrer, {len(cache['students'])} Schüler")
        
    except Exception as e:
        log(f"Cache-Fehler: {e}")


def get_timetable(start_date: str, end_date: str):
    """Get timetable for date range (YYYYMMDD format)"""
    if not person_id:
        return []
    
    return get_timetable_for(person_type or 5, person_id, start_date, end_date)


def get_timetable_for(entity_type: int, entity_id: int, start_date: str, end_date: str):
    """Get timetable for any entity (class, teacher, student, room)
    
    entity_type: 1=Klasse, 2=Lehrer, 3=Fach, 4=Raum, 5=Schüler
    entity_id: ID der Entität
    start_date, end_date: YYYYMMDD format
    """
    try:
        lessons = api_call("getTimetable", {
            "id": int(entity_id),
            "type": int(entity_type),
            "startDate": start_date,
            "endDate": end_date
        })
        
        # Enrich with names
        result = []
        for l in (lessons or []):
            lesson = {
                'id': l['id'],
                'date': l['date'],
                'startTime': l['startTime'],
                'endTime': l['endTime'],
                'type': l.get('lstype', 'ls'),
                'code': l.get('code', ''),
                'classes': [cache['classes'].get(k['id'], '?') for k in l.get('kl', [])],
                'subjects': [cache['subjects'].get(s['id'], '?') for s in l.get('su', [])],
                'rooms': [cache['rooms'].get(r['id'], '?') for r in l.get('ro', [])],
                'teachers': [cache['teachers'].get(t['id'], '?') for t in l.get('te', [])],
            }
            result.append(lesson)
        
        return sorted(result, key=lambda x: (x['date'], x['startTime']))
        
    except Exception as e:
        log(f"Stundenplan-Fehler: {e}")
        return []


def get_classes_list():
    """Get list of all classes for selection"""
    result = []
    for id, name in cache.get('classes', {}).items():
        result.append({'id': id, 'name': name, 'type': 1})
    return sorted(result, key=lambda x: x['name'])


def get_teachers_list():
    """Get list of all teachers for selection"""
    result = []
    for id, name in cache.get('teachers', {}).items():
        result.append({'id': id, 'name': name, 'type': 2})
    return sorted(result, key=lambda x: x['name'])


def get_rooms_list():
    """Get list of all rooms for selection"""
    result = []
    for id, name in cache.get('rooms', {}).items():
        result.append({'id': id, 'name': name, 'type': 4})
    return sorted(result, key=lambda x: x['name'])


def get_students_list():
    """Get list of all students for selection"""
    result = []
    for id, data in cache.get('students', {}).items():
        if isinstance(data, dict):
            # Cache speichert 'name', nicht 'lastName'/'firstName'
            name = data.get('name', '')
        else:
            name = str(data)
        result.append({'id': id, 'name': name, 'type': 5})
    return sorted(result, key=lambda x: x['name'])


def get_today():
    """Get today's timetable"""
    today = datetime.now().strftime("%Y%m%d")
    return get_timetable(today, today)


def get_week():
    """Get this week's timetable"""
    today = datetime.now()
    # Start from Monday
    monday = today - timedelta(days=today.weekday())
    friday = monday + timedelta(days=4)
    return get_timetable(monday.strftime("%Y%m%d"), friday.strftime("%Y%m%d"))


def get_period_data(period_id: int, load_images: bool = False):
    """Get detailed period data including students (Mobile API)
    
    period_id: The timetable period ID
    load_images: If True, fetch student images as base64 data URLs
    """
    if not session:
        return {'error': 'Nicht eingeloggt'}
    
    try:
        # Ensure period_id is an integer (QML sometimes passes floats)
        log(f"get_period_data: raw period_id = {period_id} (type: {type(period_id).__name__})")
        period_id = int(period_id)
        log(f"get_period_data: converted period_id = {period_id}")
        result = mobile_call("getPeriodData2017", {"ttIds": [period_id]})
        
        if "result" in result:
            data = result["result"]
            # Log all available keys in dataByTTId
            data_by_tt = data.get("dataByTTId", {})
            log(f"get_period_data: dataByTTId keys = {list(data_by_tt.keys())}")
            period_data = data_by_tt.get(str(period_id), {})
            
            # Debug: log all keys to understand structure
            log(f"get_period_data: period_data keys = {list(period_data.keys())}")
            
            # Process absences - check multiple possible field names
            raw_absences = period_data.get("absences") or period_data.get("studentAbsences") or []
            
            # Also check if there's an 'attendances' field with absence info
            attendances = period_data.get("attendances", [])
            if attendances:
                log(f"get_period_data: found attendances field with {len(attendances)} entries")
            
            absences = []
            for a in raw_absences:
                absence = dict(a)  # Copy
                # Ensure absenceId is available (for delete_absence)
                if 'id' in absence:
                    absence['absenceId'] = absence['id']
                absences.append(absence)
            
            log(f"get_period_data: found {len(absences)} absences")
            if absences:
                log(f"get_period_data: absences = {absences}")
            
            # Rename 'id' to 'studId' to avoid QML reserved keyword issues
            # Also preserve imageUrl if present
            students = []
            for s in data.get("referencedStudents", []):
                student = dict(s)  # Copy
                student['studId'] = student.pop('id', 0)  # Rename id -> studId
                
                # Image URL handling:
                # 1. If imageUrl is already a full URL, use it
                # 2. Otherwise construct one (but note: this may not work without auth)
                if 'imageUrl' in student and student['imageUrl']:
                    # Check if it's a relative or absolute URL
                    if not student['imageUrl'].startswith('http'):
                        student['imageUrl'] = f"https://{SERVER}{student['imageUrl']}"
                else:
                    # No imageUrl provided - set empty (fallback avatar will be shown)
                    student['imageUrl'] = ""
                
                students.append(student)
            
            log(f"get_period_data: found {len(students)} students")
            if students:
                log(f"get_period_data: first student = {students[0]}")
            
            # Get topic from period_data (already contains text field)
            topic = period_data.get("topic", {})
            log(f"get_period_data: topic = {topic}")
            
            # Get additional period info: notes, homeworks, classreg events
            notes_all = period_data.get("notesAll", {})
            notes_staff = period_data.get("notesStaff", {})
            homeworks = period_data.get("homeWorks", []) or period_data.get("homeworks", [])
            classreg_events = period_data.get("classRegEvents", [])
            lesson_info = period_data.get("lessonInfo", {})
            
            log(f"get_period_data: notesAll = {notes_all}")
            log(f"get_period_data: notesStaff = {notes_staff}")
            log(f"get_period_data: homeworks = {len(homeworks) if homeworks else 0}")
            log(f"get_period_data: classRegEvents = {len(classreg_events) if classreg_events else 0}")
            log(f"get_period_data: lessonInfo = {lesson_info}")
            
            # Log permissions
            can = period_data.get("can", [])
            log(f"get_period_data: PERMISSIONS (can) = {can}")
            
            return {
                'students': students,
                'studentIds': period_data.get("studentIds", []),
                'absenceChecked': period_data.get("absenceChecked", False),
                'absences': absences,
                'topic': topic,
                'can': can,
                # New fields
                'notesAll': notes_all,
                'notesStaff': notes_staff,
                'homeworks': homeworks,
                'classRegEvents': classreg_events,
                'lessonInfo': lesson_info,
                'ttId': period_id
            }
        else:
            error = result.get('error', {}).get('message', 'Unbekannter Fehler')
            log(f"get_period_data error: {error}")
            return {'error': error}
            
    except Exception as e:
        log(f"get_period_data exception: {e}")
        return {'error': str(e)}


def get_absence_reasons():
    """Get list of absence reasons"""
    return cache.get('absence_reasons', [])


def submit_absences(period_id: int, absences: list):
    """
    Submit absences for a period using createAbsences2017
    (discovered via Android app reverse engineering)
    
    absences: list of dicts with:
        - studentId: int (required)
        - reasonId: int (optional, default 75 = Fehlt)
        - startTime: int (optional, for late arrivals, e.g. 1105)
        - endTime: int (optional)
        - text: str (optional, note)
    """
    if not session:
        log("submit_absences: Kein Secret!")
        return {'success': False, 'error': 'Mobile API nicht verfügbar - kein Secret'}
    
    # Ensure period_id is int
    period_id = int(period_id)
    
    log(f"submit_absences: period={period_id}, absences={absences}")
    
    try:
        # First get period data for times and permissions
        period_check = mobile_call("getPeriodData2017", {"ttIds": [period_id]})
        if "result" not in period_check:
            return {'success': False, 'error': 'Stunde nicht gefunden'}
        
        period_data = period_check["result"].get("dataByTTId", {}).get(str(period_id), {})
        can = period_data.get("can", [])
        topic = period_data.get("topic", {})
        start_dt = topic.get("startDateTime", "")
        end_dt = topic.get("endDateTime", "")
        
        log(f"submit_absences: can={can}, start={start_dt}, end={end_dt}")
        
        if "WRITE_STUD_ABSENCE" not in can:
            log("submit_absences: KEINE SCHREIBBERECHTIGUNG!")
            return {
                'success': False, 
                'error': 'Keine Schreibberechtigung für diese Stunde'
            }
        
        if not absences:
            log("submit_absences: Keine Abwesenheiten zu speichern")
            return {'success': True}
        
        # Use createAbsences2017 for each absence (works even on checked periods!)
        success_count = 0
        errors = []
        
        # Get valid absence reason IDs for validation
        valid_reasons = cache.get('absence_reasons', [])
        valid_reason_ids = [r.get('id') for r in valid_reasons if r.get('id')]
        
        for a in absences:
            student_id = int(a.get("studentId", 0))
            reason_id = int(a.get("reasonId", 0))
            
            # Validate reason ID - use ABSENZ_U (ID 2) if invalid
            if reason_id == 0 or (valid_reason_ids and reason_id not in valid_reason_ids):
                if 2 in valid_reason_ids:
                    reason_id = 2  # ABSENZ_U = unentschuldigt
                elif valid_reason_ids:
                    reason_id = valid_reason_ids[0]
                else:
                    reason_id = 2  # Fallback
                log(f"submit_absences: Using reason_id={reason_id} (original was invalid)")
            
            # Build request params
            params = {
                "periodId": period_id,
                "studentIds": [student_id],
                "absenceReasonId": reason_id,
                "startDateTime": start_dt,
                "endDateTime": end_dt
            }
            
            # Add optional text
            if "text" in a and a["text"]:
                params["text"] = str(a["text"])
            
            log(f"submit_absences: createAbsences2017 for student {student_id}")
            
            result = mobile_call("createAbsences2017", params)
            
            if "error" in result:
                error = result.get('error', {})
                error_msg = error.get('message', 'Unbekannter Fehler')
                log(f"submit_absences: error for student {student_id}: {error_msg}")
                errors.append(f"Student {student_id}: {error_msg}")
            elif "result" in result:
                result_data = result.get("result", {})
                student_result = result_data.get("resultPerStudent", {}).get(str(student_id), {})
                created_absences = student_result.get("absences", [])
                
                if created_absences:
                    log(f"submit_absences: SUCCESS for student {student_id}, absence_id={created_absences[0].get('id')}")
                    success_count += 1
                else:
                    conflicts = student_result.get("conflicts", [])
                    if conflicts:
                        log(f"submit_absences: conflict for student {student_id}")
                        errors.append(f"Student {student_id}: Konflikt mit bestehender Abwesenheit")
                    else:
                        log(f"submit_absences: no absences created for student {student_id}")
                        errors.append(f"Student {student_id}: Nicht gespeichert")
        
        if errors:
            if success_count > 0:
                return {
                    'success': True,
                    'warning': f'{success_count} gespeichert, {len(errors)} Fehler: {"; ".join(errors)}'
                }
            else:
                return {
                    'success': False,
                    'error': '; '.join(errors)
                }
        
        log(f"submit_absences: ALL {success_count} absences saved successfully")
        return {'success': True}
            
    except Exception as e:
        log(f"submit_absences exception: {e}")
        import traceback
        log(f"submit_absences traceback: {traceback.format_exc()}")
        return {'success': False, 'error': str(e)}


def sync_absences(period_id: int, new_absences: list):
    """
    Synchronize absences for a period - handles both creation AND deletion.
    This compares the new_absences list with what's currently on the server
    and creates/deletes as needed.
    
    new_absences: list of dicts with:
        - studentId: int (required)
        - reasonId: int (optional, default 75 = Fehlt)
        - startTime: int (optional, for late arrivals, e.g. 1105)
        - endTime: int (optional)
        - text: str (optional, note)
        
    Returns: {'success': bool, 'created': int, 'deleted': int, 'error': str}
    """
    log(f">>> sync_absences called (NOT submit_absences)")
    
    if not session:
        log("sync_absences: Kein Secret!")
        return {'success': False, 'error': 'Mobile API nicht verfügbar - kein Secret'}
    
    period_id = int(period_id)
    log(f"sync_absences: period={period_id}, new_count={len(new_absences)}")
    log(f"sync_absences: new_absences={new_absences}")
    
    try:
        # Get current server state
        period_check = mobile_call("getPeriodData2017", {"ttIds": [period_id]})
        if "result" not in period_check:
            return {'success': False, 'error': 'Stunde nicht gefunden'}
        
        period_data = period_check["result"].get("dataByTTId", {}).get(str(period_id), {})
        can = period_data.get("can", [])
        topic = period_data.get("topic", {})
        start_dt = topic.get("startDateTime", "")
        end_dt = topic.get("endDateTime", "")
        
        if "WRITE_STUD_ABSENCE" not in can:
            log("sync_absences: KEINE SCHREIBBERECHTIGUNG!")
            return {'success': False, 'error': 'Keine Schreibberechtigung für diese Stunde'}
        
        # Current absences on server (map by studentId for comparison)
        server_absences = period_data.get("absences", []) or []
        server_by_student = {}
        for a in server_absences:
            student_id = a.get("studentId")
            if student_id:
                server_by_student[student_id] = a
        
        # New absences (map by studentId)
        new_by_student = {}
        for a in new_absences:
            student_id = int(a.get("studentId", 0))
            if student_id:
                new_by_student[student_id] = a
        
        log(f"sync_absences: server has {len(server_by_student)} absences, new has {len(new_by_student)}")
        
        deleted_count = 0
        created_count = 0
        errors = []
        
        # Delete absences that are on server but not in new list
        for student_id, server_absence in server_by_student.items():
            if student_id not in new_by_student:
                # Try both 'id' and 'absenceId' as the key
                absence_id = server_absence.get("id") or server_absence.get("absenceId")
                if absence_id:
                    log(f"sync_absences: deleting absence {absence_id} for student {student_id}")
                    result = delete_absence(absence_id)
                    if result.get('success'):
                        deleted_count += 1
                    else:
                        error_msg = result.get('error', 'Fehler')
                        log(f"sync_absences: delete failed: {error_msg}")
                        errors.append(f"Löschen Student {student_id}: {error_msg}")
                else:
                    log(f"sync_absences: no absence ID found for student {student_id}")
                    errors.append(f"Student {student_id}: Keine Absence-ID")
        
        # Create absences that are in new list but not on server
        # Get valid absence reason IDs for validation
        valid_reasons = cache.get('absence_reasons', [])
        valid_reason_ids = [r.get('id') for r in valid_reasons if r.get('id')]
        
        for student_id, new_absence in new_by_student.items():
            if student_id not in server_by_student:
                # Check if this is a lateness (has startTime and endTime)
                is_lateness = "startTime" in new_absence and "endTime" in new_absence
                
                if is_lateness:
                    # Use createImmediateLateness2017 for late arrivals
                    log(f"sync_absences: creating LATENESS for student {student_id}")
                    result = mobile_call("createImmediateLateness2017", {
                        "periodId": period_id,
                        "studentId": student_id
                    })
                    
                    if "error" in result:
                        error_msg = result.get('error', {}).get('message', 'Fehler')
                        log(f"sync_absences: lateness error: {error_msg}")
                        errors.append(f"Verspätung Student {student_id}: {error_msg}")
                    elif "result" in result:
                        result_data = result.get("result", {})
                        if result_data.get("absence"):
                            created_count += 1
                            log(f"sync_absences: lateness SUCCESS for student {student_id}")
                        else:
                            errors.append(f"Verspätung Student {student_id}: Nicht erstellt")
                else:
                    # Regular absence - use createAbsences2017
                    reason_id = int(new_absence.get("reasonId", 0))
                    
                    # Validate reason ID - use ABSENZ_U (ID 2) if invalid
                    if reason_id == 0 or (valid_reason_ids and reason_id not in valid_reason_ids):
                        if 2 in valid_reason_ids:
                            reason_id = 2  # ABSENZ_U = unentschuldigt
                        elif valid_reason_ids:
                            reason_id = valid_reason_ids[0]
                        else:
                            reason_id = 2  # Fallback
                        log(f"sync_absences: Using reason_id={reason_id} (original was invalid)")
                    
                    params = {
                        "periodId": period_id,
                        "studentIds": [student_id],
                        "absenceReasonId": reason_id,
                        "startDateTime": start_dt,
                        "endDateTime": end_dt
                    }
                    
                    if "text" in new_absence and new_absence["text"]:
                        params["text"] = str(new_absence["text"])
                    
                    log(f"sync_absences: creating ABSENCE for student {student_id}")
                    result = mobile_call("createAbsences2017", params)
                    
                    if "error" in result:
                        error_msg = result.get('error', {}).get('message', 'Fehler')
                        log(f"sync_absences: absence error: {error_msg}")
                        errors.append(f"Abwesenheit Student {student_id}: {error_msg}")
                    elif "result" in result:
                        result_data = result.get("result", {})
                        student_result = result_data.get("resultPerStudent", {}).get(str(student_id), {})
                        if student_result.get("absences"):
                            created_count += 1
                            log(f"sync_absences: absence SUCCESS for student {student_id}")
                        elif student_result.get("conflicts"):
                            errors.append(f"Student {student_id}: Konflikt")
                        else:
                            errors.append(f"Student {student_id}: Nicht erstellt")
        
        log(f"sync_absences: done - created={created_count}, deleted={deleted_count}, errors={len(errors)}")
        
        if errors:
            return {
                'success': len(errors) < (created_count + deleted_count),
                'created': created_count,
                'deleted': deleted_count,
                'warning': '; '.join(errors)
            }
        
        return {
            'success': True,
            'created': created_count,
            'deleted': deleted_count
        }
        
    except Exception as e:
        log(f"sync_absences exception: {e}")
        import traceback
        log(f"sync_absences traceback: {traceback.format_exc()}")
        return {'success': False, 'error': str(e)}


def submit_topic(period_id: int, text: str):
    """Submit lesson topic"""
    log(f"submit_topic called: period_id={period_id}, text='{text}'")
    
    if not session:
        log("submit_topic: no secret available")
        return {'success': False, 'error': 'Mobile API nicht verfügbar'}
    
    try:
        # Android App verwendet "lessonTopic", nicht "text"
        params = {
            "ttId": int(period_id),
            "lessonTopic": text
        }
        log(f"submit_topic: calling submitLessonTopic with params={params}")
        result = mobile_call("submitLessonTopic", params)
        log(f"submit_topic: result={result}")
        
        if "result" in result and result["result"].get("success"):
            log(f"Lehrstoff gespeichert für Period {period_id}")
            return {'success': True}
        else:
            error = result.get('error', {}).get('message', 'Unbekannter Fehler')
            log(f"submit_topic error: {error}")
            return {'success': False, 'error': error}
            
    except Exception as e:
        log(f"submit_topic exception: {e}")
        return {'success': False, 'error': str(e)}


def delete_absence(absence_id: int):
    """
    Delete an absence by its ID using deleteAbsence2017
    (discovered via Android app reverse engineering)
    
    absence_id: The ID of the absence to delete (from absence object)
    """
    if not session:
        log("delete_absence: Kein Secret!")
        return {'success': False, 'error': 'Mobile API nicht verfügbar - kein Secret'}
    
    absence_id = int(absence_id)
    log(f"delete_absence: absenceId={absence_id}")
    
    try:
        result = mobile_call("deleteAbsence2017", {
            "absenceId": absence_id
        })
        
        if "error" in result:
            error = result.get('error', {})
            error_msg = error.get('message', 'Unbekannter Fehler')
            log(f"delete_absence: error: {error_msg}")
            return {'success': False, 'error': error_msg}
        
        if "result" in result:
            log(f"delete_absence: SUCCESS for absenceId={absence_id}")
            return {'success': True}
        
        return {'success': False, 'error': 'Keine Antwort vom Server'}
            
    except Exception as e:
        log(f"delete_absence exception: {e}")
        return {'success': False, 'error': str(e)}


def edit_absence(absence_id: int, reason_id: int = None, start_datetime: str = None, 
                 end_datetime: str = None, text: str = None):
    """
    Edit an existing absence using editAbsence2017
    (discovered via Android app reverse engineering)
    
    absence_id: The ID of the absence to edit
    reason_id: New absence reason ID (optional)
    start_datetime: New start datetime ISO format (optional)
    end_datetime: New end datetime ISO format (optional)
    text: New note text (optional)
    """
    if not session:
        log("edit_absence: Kein Secret!")
        return {'success': False, 'error': 'Mobile API nicht verfügbar - kein Secret'}
    
    absence_id = int(absence_id)
    log(f"edit_absence: absenceId={absence_id}")
    
    try:
        params = {"absenceId": absence_id}
        
        if reason_id is not None:
            params["absenceReasonId"] = int(reason_id)
        if start_datetime:
            params["startDateTime"] = start_datetime
        if end_datetime:
            params["endDateTime"] = end_datetime
        if text is not None:
            params["text"] = str(text)
        
        log(f"edit_absence: params={params}")
        result = mobile_call("editAbsence2017", params)
        
        if "error" in result:
            error = result.get('error', {})
            error_msg = error.get('message', 'Unbekannter Fehler')
            log(f"edit_absence: error: {error_msg}")
            return {'success': False, 'error': error_msg}
        
        if "result" in result:
            log(f"edit_absence: SUCCESS for absenceId={absence_id}")
            return {'success': True, 'result': result.get('result')}
        
        return {'success': False, 'error': 'Keine Antwort vom Server'}
            
    except Exception as e:
        log(f"edit_absence exception: {e}")
        return {'success': False, 'error': str(e)}


def create_lateness(period_id: int, student_id: int, reason_id: int = None):
    """
    Create an immediate lateness entry using createImmediateLateness2017
    (discovered via Android app reverse engineering)
    
    This creates a lateness for a student who arrived late - 
    the arrival time is set to NOW (server time).
    
    period_id: The timetable period ID (ttId)
    student_id: The student ID
    reason_id: Optional lateness reason ID (uses default if not provided)
    """
    if not session:
        log("create_lateness: Kein Secret!")
        return {'success': False, 'error': 'Mobile API nicht verfügbar - kein Secret'}
    
    period_id = int(period_id)
    student_id = int(student_id)
    
    log(f"create_lateness: period={period_id}, student={student_id}, reason={reason_id}")
    
    try:
        params = {
            "periodId": period_id,
            "studentId": student_id
        }
        
        if reason_id is not None:
            params["absenceReasonId"] = int(reason_id)
        
        result = mobile_call("createImmediateLateness2017", params)
        
        if "error" in result:
            error = result.get('error', {})
            error_msg = error.get('message', 'Unbekannter Fehler')
            log(f"create_lateness: error: {error_msg}")
            return {'success': False, 'error': error_msg}
        
        if "result" in result:
            result_data = result.get("result", {})
            absence = result_data.get("absence")
            log(f"create_lateness: SUCCESS, absence={absence}")
            return {'success': True, 'absence': absence}
        
        return {'success': False, 'error': 'Keine Antwort vom Server'}
            
    except Exception as e:
        log(f"create_lateness exception: {e}")
        return {'success': False, 'error': str(e)}


def get_student_image_url(student_id: int) -> str:
    """
    Get the image URL for a student.
    The URL is typically provided in the referencedStudents data from getPeriodData2017.
    
    Returns the image URL or empty string if not available.
    """
    # Images are typically accessed via the WebUntis web interface
    # The URL format is usually: https://SERVER/WebUntis/api/public/person/STUDENT_ID/image
    # But this requires proper authentication
    if not session:
        return ""
    
    # The image URL is usually included in the student data from getPeriodData2017
    # as 'imageUrl' field. We return a constructed URL that can be used with
    # the current session cookies.
    return f"https://{SERVER}/WebUntis/api/public/person/{student_id}/image"


def fetch_student_image(student_id: int):
    """
    Fetch a student's image from WebUntis.
    Returns the image as base64-encoded data or None if not available.
    
    This function uses the authenticated session to download the image.
    """
    if not session:
        log("fetch_student_image: Nicht eingeloggt")
        return {'success': False, 'error': 'Nicht eingeloggt'}
    
    student_id = int(student_id)
    url = f"https://{SERVER}/WebUntis/api/public/person/{student_id}/image"
    
    try:
        log(f"fetch_student_image: fetching {url}")
        resp = session.get(url, timeout=10)
        
        if resp.status_code == 200:
            content_type = resp.headers.get('Content-Type', 'image/jpeg')
            import base64
            image_data = base64.b64encode(resp.content).decode('utf-8')
            log(f"fetch_student_image: success, {len(resp.content)} bytes")
            return {
                'success': True,
                'data': image_data,
                'contentType': content_type,
                'dataUrl': f"data:{content_type};base64,{image_data}"
            }
        elif resp.status_code == 404:
            log(f"fetch_student_image: no image for student {student_id}")
            return {'success': False, 'error': 'Kein Bild vorhanden'}
        else:
            log(f"fetch_student_image: HTTP {resp.status_code}")
            return {'success': False, 'error': f'HTTP {resp.status_code}'}
            
    except Exception as e:
        log(f"fetch_student_image exception: {e}")
        return {'success': False, 'error': str(e)}


def create_lateness_with_time(period_id: int, student_id: int, arrival_time: int, reason_id: int = None):
    """
    Create a lateness entry with a specific arrival time.
    
    This creates a partial absence from period start until arrival time.
    
    period_id: The timetable period ID (ttId)
    student_id: The student ID  
    arrival_time: Arrival time as integer (e.g. 815 for 08:15)
    reason_id: Optional lateness reason ID (uses default if not provided)
    """
    if not session:
        log("create_lateness_with_time: Kein Secret!")
        return {'success': False, 'error': 'Mobile API nicht verfügbar - kein Secret'}
    
    period_id = int(period_id)
    student_id = int(student_id)
    arrival_time = int(arrival_time)
    
    log(f"create_lateness_with_time: period={period_id}, student={student_id}, arrival={arrival_time}")
    
    try:
        # Get period data for start time and datetime info
        period_check = mobile_call("getPeriodData2017", {"ttIds": [period_id]})
        if "result" not in period_check:
            return {'success': False, 'error': 'Stunde nicht gefunden'}
        
        period_data = period_check["result"].get("dataByTTId", {}).get(str(period_id), {})
        can = period_data.get("can", [])
        topic = period_data.get("topic", {})
        start_dt = topic.get("startDateTime", "")  # ISO format e.g. "2025-01-15T08:00:00"
        
        if "WRITE_STUD_ABSENCE" not in can:
            return {'success': False, 'error': 'Keine Schreibberechtigung'}
        
        if not start_dt:
            return {'success': False, 'error': 'Keine Startzeit verfügbar'}
        
        # Get default lateness reason if not provided
        if reason_id is None:
            # First try cached value
            reason_id = cache.get('default_lateness_reason_id')
            
            if not reason_id:
                # Fallback: get from API
                user_data = mobile_call("getUserData2017")
                if "result" in user_data:
                    master_data = user_data["result"].get("masterData", {})
                    reason_id = master_data.get("defaultLatenessReasonId")
                    if not reason_id:
                        # Fallback: use first absence reason that looks like lateness
                        reasons = master_data.get("absenceReasons", [])
                        for r in reasons:
                            name_lower = r.get("name", "").lower()
                            if "spät" in name_lower or "verspät" in name_lower or "late" in name_lower:
                                reason_id = r.get("id")
                                break
            if not reason_id:
                reason_id = 75  # Final fallback
        
        # Build arrival datetime - must include Z suffix for UTC
        arr_hours = arrival_time // 100
        arr_mins = arrival_time % 100
        date_part = start_dt.split('T')[0]
        arrival_dt = f"{date_part}T{arr_hours:02d}:{arr_mins:02d}Z"
        
        # For lateness: startDateTime = period start, endDateTime = arrival time
        # This means: student was absent from start until arrival (= late)
        params = {
            "periodId": period_id,
            "studentIds": [student_id],
            "absenceReasonId": int(reason_id),
            "startDateTime": start_dt,
            "endDateTime": arrival_dt
        }
        
        log(f"create_lateness_with_time: params={params}")
        result = mobile_call("createAbsences2017", params)
        
        if "error" in result:
            error_msg = result.get('error', {}).get('message', 'Fehler')
            log(f"create_lateness_with_time: error: {error_msg}")
            return {'success': False, 'error': error_msg}
        
        if "result" in result:
            result_data = result.get("result", {})
            student_result = result_data.get("resultPerStudent", {}).get(str(student_id), {})
            created = student_result.get("absences", [])
            if created:
                log(f"create_lateness_with_time: SUCCESS, id={created[0].get('id')}")
                return {'success': True, 'absence': created[0]}
            elif student_result.get("conflicts"):
                log("create_lateness_with_time: conflict with existing absence")
                return {'success': False, 'error': 'Konflikt mit bestehender Abwesenheit'}
        
        return {'success': False, 'error': 'Nicht erstellt'}
        
    except Exception as e:
        log(f"create_lateness_with_time exception: {e}")
        return {'success': False, 'error': str(e)}


def format_time(time_int: int) -> str:
    """Format time integer to HH:MM"""
    hours = time_int // 100
    minutes = time_int % 100
    return f"{hours:02d}:{minutes:02d}"


def parse_time(time_str: str) -> int:
    """Parse HH:MM to time integer"""
    parts = time_str.split(':')
    return int(parts[0]) * 100 + int(parts[1])


def submit_period_info(period_id: int, info_type: str, text: str):
    """
    Submit/update period info (notes, etc.) using submitPeriodInfo2017
    
    period_id: The timetable period ID
    info_type: One of 'notesAll', 'notesStaff', 'topic' (teaching content)
    text: The text content to save
    
    Returns: {'success': True/False, 'error': optional error message}
    """
    if not session:
        return {'success': False, 'error': 'Mobile API nicht verfügbar'}
    
    try:
        period_id = int(period_id)
        log(f"submit_period_info: period={period_id}, type={info_type}, text={text[:50] if text else ''}...")
        
        # Build the request based on info_type
        # periodId is the correct parameter name (confirmed by "no right" error vs "no period found")
        update_data = {}
        
        if info_type == 'notesAll':
            update_data['notesAll'] = {'text': text}
        elif info_type == 'notesStaff':
            update_data['notesStaff'] = {'text': text}
        elif info_type == 'topic':
            update_data['teachingContent'] = {'text': text}
        else:
            return {'success': False, 'error': f'Unbekannter Typ: {info_type}'}
        
        # Use periodId - this is correct, "no right" means permission issue, not wrong parameter
        result = mobile_call("submitPeriodInfo2017", {
            "periodId": period_id,
            **update_data
        })
        
        log(f"submit_period_info: result = {result}")
        
        if "error" in result:
            error_msg = result.get('error', {}).get('message', 'Fehler beim Speichern')
            log(f"submit_period_info: error: {error_msg}")
            
            # Provide helpful error messages
            if error_msg == "no right":
                return {'success': False, 'error': 'Keine Berechtigung (Stunde evtl. in der Vergangenheit?)'}
            elif error_msg == "no period found":
                return {'success': False, 'error': 'Stunde nicht gefunden'}
            
            return {'success': False, 'error': error_msg}
        
        if "result" in result:
            return {'success': True}
        
        return {'success': False, 'error': 'Unbekannte Antwort'}
        
    except Exception as e:
        log(f"submit_period_info exception: {e}")
        return {'success': False, 'error': str(e)}


def get_classreg_events(period_id: int):
    """
    Get class register events for a period
    Events kommen aus getPeriodData2017, eventReasons aus dem Cache
    """
    try:
        period_id = int(period_id)
        
        # Events sind bereits in periodData enthalten
        result = mobile_call("getPeriodData2017", {"ttIds": [period_id]})
        
        events = []
        if "result" in result:
            period_data = result["result"].get("dataByTTId", {}).get(str(period_id), {})
            events = period_data.get("classRegEvents", [])
        
        # EventReasons aus Cache
        event_reasons = cache.get('event_reasons', [])
        
        log(f"get_classreg_events: {len(events)} events, {len(event_reasons)} reasons from cache")
        
        return {
            'events': events,
            'eventReasons': event_reasons
        }
        
    except Exception as e:
        log(f"get_classreg_events exception: {e}")
        return {'events': [], 'eventReasons': cache.get('event_reasons', []), 'error': str(e)}


def get_event_reasons():
    """Get cached event reasons for class register entries"""
    return cache.get('event_reasons', [])


def submit_classreg_event(period_id: int, student_ids, reason_id: int = None, text: str = ""):
    """
    Submit a class register event (Klassenbucheintrag) for one or more students
    
    period_id: The timetable period ID
    student_ids: Single student ID (int) or list of student IDs
    reason_id: The event reason ID (optional - can be None or 0 if no categories configured)
    text: The event text/note
    """
    if not session:
        return {'success': False, 'error': 'Mobile API nicht verfügbar'}
    
    try:
        period_id = int(period_id)
        
        # Support both single ID and list of IDs
        if isinstance(student_ids, (int, float)):
            student_ids = [int(student_ids)]
        elif isinstance(student_ids, list):
            student_ids = [int(sid) for sid in student_ids]
        else:
            return {'success': False, 'error': 'Ungültige Schüler-IDs'}
        
        log(f"submit_classreg_event: period={period_id}, students={student_ids}, reason={reason_id}, text={text}")
        
        # First get period data for times and permissions
        period_check = mobile_call("getPeriodData2017", {"ttIds": [period_id]})
        if "result" not in period_check:
            return {'success': False, 'error': 'Stunde nicht gefunden'}
        
        period_data = period_check["result"].get("dataByTTId", {}).get(str(period_id), {})
        can = period_data.get("can", [])
        
        if "WRITE_CLASSREGEVENT" not in can:
            log("submit_classreg_event: no WRITE_CLASSREGEVENT permission")
            return {'success': False, 'error': 'Keine Berechtigung für Klassenbucheinträge'}
        
        topic = period_data.get("topic", {})
        start_dt = topic.get("startDateTime", "")
        
        # Build events list for all students
        events = []
        for student_id in student_ids:
            event = {
                "studentId": student_id,
                "text": text,
                "dateTime": start_dt
            }
            # Only include reasonId if it's set (not None and not 0)
            if reason_id and int(reason_id) > 0:
                event["reasonId"] = int(reason_id)
            events.append(event)
        
        # Try submitClassRegEvents (Mobile API)
        result = mobile_call("submitClassRegEvents", {
            "ttId": period_id,
            "events": events
        })
        
        log(f"submit_classreg_event: result = {result}")
        
        if "error" in result:
            error_msg = result.get('error', {}).get('message', 'Fehler')
            return {'success': False, 'error': error_msg}
        
        if "result" in result:
            return {'success': True, 'count': len(student_ids)}
        
        return {'success': False, 'error': 'Unbekannte Antwort'}
        
    except Exception as e:
        log(f"submit_classreg_event exception: {e}")
        return {'success': False, 'error': str(e)}


def get_homework(period_id: int):
    """
    Get homework for a period using getHomeWork2017
    """
    if not session:
        return {'error': 'Mobile API nicht verfügbar'}
    
    try:
        period_id = int(period_id)
        result = mobile_call("getHomeWork2017", {"ttId": period_id})
        
        log(f"get_homework: result = {result}")
        
        if "result" in result:
            homework = result["result"]
            return {'homework': homework}
        
        return {'homework': None}
        
    except Exception as e:
        log(f"get_homework exception: {e}")
        return {'error': str(e)}


def submit_homework(period_id: int, text: str, due_date: str = None, remark: str = "", homework_id: int = None):
    """
    Submit or update homework for a period
    
    period_id: The timetable period ID
    text: Homework text/description
    due_date: Due date in format YYYY-MM-DD (optional, defaults to next lesson)
    remark: Additional remark (optional)
    homework_id: If provided, update existing homework instead of creating new
    """
    if not session:
        return {'success': False, 'error': 'Mobile API nicht verfügbar'}
    
    try:
        period_id = int(period_id)
        
        log(f"submit_homework: period={period_id}, text={text[:50] if text else ''}..., due={due_date}, hwId={homework_id}")
        
        # First get period data for permissions and times
        period_check = mobile_call("getPeriodData2017", {"ttIds": [period_id]})
        if "result" not in period_check:
            return {'success': False, 'error': 'Stunde nicht gefunden'}
        
        period_data = period_check["result"].get("dataByTTId", {}).get(str(period_id), {})
        can = period_data.get("can", [])
        
        if "WRITE_HOMEWORK" not in can:
            log("submit_homework: no WRITE_HOMEWORK permission")
            return {'success': False, 'error': 'Keine Berechtigung für Hausübungen'}
        
        topic = period_data.get("topic", {})
        end_dt = topic.get("endDateTime", "")
        
        # Format due date if provided
        due_datetime = None
        if due_date:
            due_datetime = f"{due_date}T08:00Z"
        
        # Try submitHomeWork (Mobile API)
        hw_data = {
            "ttId": period_id,
            "text": text,
            "remark": remark or ""
        }
        if due_datetime:
            hw_data["endDateTime"] = due_datetime
        
        # If homework_id provided, this is an update
        if homework_id:
            hw_data["id"] = int(homework_id)
        
        result = mobile_call("submitHomeWork", hw_data)
        
        log(f"submit_homework: result = {result}")
        
        if "error" in result:
            error_msg = result.get('error', {}).get('message', 'Fehler')
            return {'success': False, 'error': error_msg}
        
        if "result" in result:
            return {'success': True}
        
        return {'success': False, 'error': 'Unbekannte Antwort'}
        
    except Exception as e:
        log(f"submit_homework exception: {e}")
        return {'success': False, 'error': str(e)}


def delete_homework(homework_id: int):
    """
    Delete a homework entry
    """
    if not session:
        return {'success': False, 'error': 'Mobile API nicht verfügbar'}
    
    try:
        homework_id = int(homework_id)
        
        log(f"delete_homework: id={homework_id}")
        
        result = mobile_call("deleteHomeWork", {"id": homework_id})
        
        log(f"delete_homework: result = {result}")
        
        if "error" in result:
            error_msg = result.get('error', {}).get('message', 'Fehler')
            return {'success': False, 'error': error_msg}
        
        return {'success': True}
        
    except Exception as e:
        log(f"delete_homework exception: {e}")
        return {'success': False, 'error': str(e)}


# Test functions
def test_mobile_api():
    """Test if mobile API is working"""
    if not session:
        return {'success': False, 'error': 'Kein Secret konfiguriert'}
    
    try:
        result = mobile_call("getUserData2017")
        if "result" in result:
            user_data = result["result"].get("userData", {})
            return {
                'success': True,
                'elemId': user_data.get("elemId"),
                'displayName': user_data.get("displayName"),
                'rights': user_data.get("rights", [])
            }
        else:
            return {'success': False, 'error': result.get('error', {}).get('message', '?')}
    except Exception as e:
        return {'success': False, 'error': str(e)}
