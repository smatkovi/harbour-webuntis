#!/usr/bin/env python3
"""
WebUntis Backend für Sailfish OS
Theodor-Kramer-Straße Edition
Direkte JSON-RPC API (ohne webuntis Library)

Für PyOtherSide QML Integration
"""

import json
import os
import untis_http as requests  # urllib-Ersatz, sandkastenfest
from datetime import datetime, timedelta
from pathlib import Path

# Konfiguration
SERVER = "theodor-kramer.webuntis.com"
SCHOOL = "theodor-kramer"
API_URL = f"https://{SERVER}/WebUntis/jsonrpc.do?school={SCHOOL}"

CONFIG_DIR = Path.home() / ".config" / "webuntis-tks"
CRED_FILE = CONFIG_DIR / "credentials.json"
STUDENTS_DIR = CONFIG_DIR / "students"

# Globale Session und Cache
_session = None
_session_id = None
_person_id = None
_person_type = None
_request_id = 0
_cache = {'subjects': {}, 'classes': {}, 'rooms': {}, 'teachers': {}}


def _get_session():
    """Gibt die requests Session zurück (erstellt sie bei Bedarf)"""
    global _session
    if _session is None:
        _session = requests.Session()
        _session.headers.update({
            'User-Agent': 'SailfishOS-WebUntis/1.0',
            'Content-Type': 'application/json'
        })
    return _session


def _next_id():
    """Generiert eine eindeutige Request-ID"""
    global _request_id
    _request_id += 1
    return str(_request_id)


def _call(method: str, params: dict = None) -> dict:
    """JSON-RPC Aufruf an WebUntis API"""
    payload = {
        "id": _next_id(),
        "method": method,
        "params": params or {},
        "jsonrpc": "2.0"
    }
    
    try:
        response = _get_session().post(API_URL, json=payload, timeout=30)
        response.raise_for_status()
        data = response.json()
        
        if "error" in data:
            error = data["error"]
            raise Exception(f"API Error {error.get('code', '?')}: {error.get('message', 'Unknown')}")
        
        return data.get("result", {})
        
    except requests.exceptions.RequestException as e:
        raise Exception(f"Verbindungsfehler: {e}")


# === Credential Management ===

def save_credentials(username: str, password: str):
    """Speichert Zugangsdaten lokal"""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(CRED_FILE, 'w') as f:
        json.dump({'username': username, 'password': password}, f)
    os.chmod(CRED_FILE, 0o600)
    return True


def load_credentials():
    """Lädt gespeicherte Zugangsdaten"""
    if CRED_FILE.exists():
        with open(CRED_FILE, 'r') as f:
            return json.load(f)
    return None


def clear_credentials():
    """Löscht gespeicherte Zugangsdaten"""
    if CRED_FILE.exists():
        CRED_FILE.unlink()
    return True


def has_saved_credentials():
    """Prüft ob Credentials gespeichert sind"""
    return CRED_FILE.exists()


# === Login / Logout ===

def login(username: str = None, password: str = None, save: bool = False):
    """
    Login bei WebUntis
    Returns: {'success': bool, 'error': str, 'username': str}
    """
    global _session_id, _person_id, _person_type
    
    try:
        # Credentials laden falls nicht angegeben
        if not username or not password:
            creds = load_credentials()
            if creds:
                username = creds['username']
                password = creds['password']
            else:
                return {'success': False, 'error': 'Keine Zugangsdaten'}
        
        result = _call("authenticate", {
            "user": username,
            "password": password,
            "client": "SailfishOS-WebUntis-TKS"
        })
        
        _session_id = result.get("sessionId")
        _person_id = result.get("personId")
        _person_type = result.get("personType")
        
        # Session-Cookie setzen
        if _session_id:
            _get_session().cookies.set("JSESSIONID", _session_id, domain=SERVER)
        
        # Credentials speichern wenn gewünscht
        if save:
            save_credentials(username, password)
        
        # Cache laden
        _load_cache()
        
        return {
            'success': True,
            'error': None,
            'username': username,
            'personId': _person_id,
            'personType': _person_type
        }
        
    except Exception as e:
        error_msg = str(e)
        if "bad credentials" in error_msg.lower() or "-8504" in error_msg:
            return {'success': False, 'error': 'Falscher Benutzername oder Passwort'}
        return {'success': False, 'error': error_msg}


def logout():
    """Logout und Session beenden"""
    global _session_id, _person_id, _person_type
    try:
        _call("logout", {})
    except:
        pass
    _session_id = None
    _person_id = None
    _person_type = None
    return {'success': True}


def is_logged_in():
    """Prüft ob eingeloggt"""
    return _session_id is not None


# === Cache ===

def _load_cache():
    """Lädt Namen-Cache für Fächer, Klassen, Räume, Lehrer"""
    global _cache
    _cache = {'subjects': {}, 'classes': {}, 'rooms': {}, 'teachers': {}}
    
    try:
        for item in _call("getSubjects"):
            _cache['subjects'][item['id']] = item.get('name', '?')
    except:
        pass
    
    try:
        for item in _call("getKlassen"):
            _cache['classes'][item['id']] = item.get('name', '?')
    except:
        pass
    
    try:
        for item in _call("getRooms"):
            _cache['rooms'][item['id']] = item.get('name', '?')
    except:
        pass
    
    try:
        for item in _call("getTeachers"):
            _cache['teachers'][item['id']] = item.get('name', '?')
    except:
        pass


def _format_lesson(lesson: dict) -> dict:
    """Formatiert eine Stunde für die Anzeige"""
    date_str = str(lesson.get('date', ''))
    start_time = str(lesson.get('startTime', '')).zfill(4)
    end_time = str(lesson.get('endTime', '')).zfill(4)
    
    # Namen aus IDs
    subjects = [_cache['subjects'].get(s['id'], f"?{s['id']}") for s in lesson.get('su', [])]
    classes = [_cache['classes'].get(k['id'], f"?{k['id']}") for k in lesson.get('kl', [])]
    rooms = [_cache['rooms'].get(r['id'], f"?{r['id']}") for r in lesson.get('ro', [])]
    teachers = [_cache['teachers'].get(t['id'], f"?{t['id']}") for t in lesson.get('te', [])]
    
    return {
        'id': lesson.get('id', 0),
        'date': date_str[:4] + '-' + date_str[4:6] + '-' + date_str[6:] if len(date_str) == 8 else '',
        'start_time': f"{start_time[:2]}:{start_time[2:]}",
        'end_time': f"{end_time[:2]}:{end_time[2:]}",
        'subjects': subjects,
        'classes': classes,
        'rooms': rooms,
        'teachers': teachers,
        'code': lesson.get('code', ''),
        'lesson_topic': lesson.get('lstext', ''),
        'homework': lesson.get('homework', '')
    }


# === Timetable ===

def get_timetable(start_date: str = None, end_date: str = None):
    """
    Holt den Stundenplan
    start_date, end_date: Format 'YYYY-MM-DD' oder None für heute/diese Woche
    Returns: {'success': bool, 'lessons': list, 'error': str}
    """
    if not _person_id:
        return {'success': False, 'error': 'Nicht eingeloggt', 'lessons': []}
    
    try:
        # Defaults
        today = datetime.now()
        if not start_date:
            start = today
        else:
            start = datetime.strptime(start_date, '%Y-%m-%d')
        
        if not end_date:
            end = start
        else:
            end = datetime.strptime(end_date, '%Y-%m-%d')
        
        # API Aufruf
        result = _call("getTimetable", {
            "id": _person_id,
            "type": _person_type or 5,  # 5=Lehrer, 2=Schüler
            "startDate": start.strftime("%Y%m%d"),
            "endDate": end.strftime("%Y%m%d")
        })
        
        lessons = []
        if isinstance(result, list):
            for lesson in result:
                lessons.append(_format_lesson(lesson))
        
        # Sortieren
        lessons.sort(key=lambda x: (x['date'], x['start_time']))
        
        return {
            'success': True,
            'lessons': lessons,
            'start_date': start.strftime('%Y-%m-%d'),
            'end_date': end.strftime('%Y-%m-%d')
        }
        
    except Exception as e:
        return {'success': False, 'error': str(e), 'lessons': []}


def get_today():
    """Holt nur die heutigen Stunden"""
    today = datetime.now().strftime('%Y-%m-%d')
    return get_timetable(today, today)


def get_week():
    """Holt die Stunden der aktuellen Woche (Mo-Fr)"""
    today = datetime.now()
    monday = today - timedelta(days=today.weekday())
    friday = monday + timedelta(days=4)
    return get_timetable(monday.strftime('%Y-%m-%d'), friday.strftime('%Y-%m-%d'))


# === Stammdaten ===

def get_classes():
    """Holt alle Klassen"""
    try:
        result = _call("getKlassen")
        classes = [{'id': k['id'], 'name': k.get('name', '?'), 'long_name': k.get('longName', '')} 
                   for k in result]
        classes.sort(key=lambda x: x['name'])
        return {'success': True, 'classes': classes}
    except Exception as e:
        return {'success': False, 'error': str(e), 'classes': []}


def get_subjects():
    """Holt alle Fächer"""
    try:
        result = _call("getSubjects")
        subjects = [{'id': s['id'], 'name': s.get('name', '?'), 'long_name': s.get('longName', '')} 
                    for s in result]
        subjects.sort(key=lambda x: x['name'])
        return {'success': True, 'subjects': subjects}
    except Exception as e:
        return {'success': False, 'error': str(e), 'subjects': []}


def get_rooms():
    """Holt alle Räume"""
    try:
        result = _call("getRooms")
        rooms = [{'id': r['id'], 'name': r.get('name', '?'), 'long_name': r.get('longName', '')} 
                 for r in result]
        rooms.sort(key=lambda x: x['name'])
        return {'success': True, 'rooms': rooms}
    except Exception as e:
        return {'success': False, 'error': str(e), 'rooms': []}


def get_teachers():
    """Holt alle Lehrer"""
    try:
        result = _call("getTeachers")
        teachers = [{'id': t['id'], 'name': t.get('name', '?'), 'long_name': t.get('longName', '')} 
                    for t in result]
        teachers.sort(key=lambda x: x['name'])
        return {'success': True, 'teachers': teachers}
    except Exception as e:
        return {'success': False, 'error': str(e), 'teachers': []}


# === Für zukünftige Erweiterungen ===

def get_students():
    """Holt alle Schüler (benötigt Lehrer-Rechte)"""
    try:
        result = _call("getStudents")
        students = []
        for s in result:
            students.append({
                'id': s.get('id'),
                'key': s.get('key', ''),  # Schülernummer
                'name': s.get('name', ''),  # Nachname
                'foreName': s.get('foreName', ''),  # Vorname
                'longName': s.get('longName', ''),
                'gender': s.get('gender', '')
            })
        students.sort(key=lambda x: (x['name'], x['foreName']))
        return {'success': True, 'students': students}
    except Exception as e:
        return {'success': False, 'error': str(e), 'students': []}


def get_students_for_class(class_id: int):
    """Holt Schüler einer bestimmten Klasse"""
    try:
        # Versuche getStudents mit Klassen-Filter
        result = _call("getStudents")
        # Leider gibt die API keinen Klassen-Filter her
        # Wir müssten die Klassen-Zuordnung anders herausfinden
        students = []
        for s in result:
            students.append({
                'id': s.get('id'),
                'key': s.get('key', ''),
                'name': s.get('name', ''),
                'foreName': s.get('foreName', ''),
                'longName': s.get('longName', ''),
                'gender': s.get('gender', '')
            })
        students.sort(key=lambda x: (x['name'], x['foreName']))
        return {'success': True, 'students': students, 'note': 'Alle Schüler (kein Klassen-Filter verfügbar)'}
    except Exception as e:
        return {'success': False, 'error': str(e), 'students': []}


def get_timetable_with_absences(start_date: str = None, end_date: str = None):
    """
    Holt Stundenplan MIT Abwesenheiten
    Benötigt Klassenbuch-Modul
    """
    if not _person_id:
        return {'success': False, 'error': 'Nicht eingeloggt', 'lessons': []}
    
    try:
        today = datetime.now()
        if not start_date:
            start = today
        else:
            start = datetime.strptime(start_date, '%Y-%m-%d')
        
        if not end_date:
            end = start
        else:
            end = datetime.strptime(end_date, '%Y-%m-%d')
        
        # getTimetableWithAbsences benötigt erweiterte Parameter
        result = _call("getTimetableWithAbsences", {
            "options": {
                "id": _person_id,
                "type": _person_type or 5,
                "startDate": start.strftime("%Y%m%d"),
                "endDate": end.strftime("%Y%m%d")
            }
        })
        
        return {'success': True, 'data': result}
        
    except Exception as e:
        return {'success': False, 'error': str(e)}


def submit_lesson_topic(lesson_id: int, topic: str, homework: str = ""):
    """Trägt Lehrstoff ein (falls API es unterstützt)"""
    return {
        'success': False,
        'error': 'Stoffeintragung nicht über API unterstützt. Bitte WebUntis Webseite verwenden.'
    }


def submit_attendance(lesson_id: int, absences: list):
    """Erfasst Anwesenheit (falls API es unterstützt)"""
    return {
        'success': False,
        'error': 'Anwesenheitserfassung nicht über API unterstützt. Bitte WebUntis Webseite verwenden.'
    }


# === Lokale Schülerlisten ===

def save_students(class_name: str, students: list):
    """Speichert Schülerliste für eine Klasse lokal"""
    STUDENTS_DIR.mkdir(parents=True, exist_ok=True)
    
    # Dateiname sicher machen
    safe_name = "".join(c for c in class_name if c.isalnum() or c in "._-").strip()
    if not safe_name:
        safe_name = "unknown"
    
    file_path = STUDENTS_DIR / f"{safe_name}.json"
    
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump({
            'class': class_name,
            'students': students,
            'updated': datetime.now().isoformat()
        }, f, ensure_ascii=False, indent=2)
    
    return {'success': True, 'count': len(students)}


def load_students(class_name: str):
    """Lädt Schülerliste für eine Klasse"""
    if not class_name:
        return []
    
    # Dateiname sicher machen
    safe_name = "".join(c for c in class_name if c.isalnum() or c in "._-").strip()
    if not safe_name:
        return []
    
    file_path = STUDENTS_DIR / f"{safe_name}.json"
    
    if file_path.exists():
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                return data.get('students', [])
        except:
            return []
    
    return []


def get_all_student_lists():
    """Gibt alle gespeicherten Klassenlisten zurück"""
    if not STUDENTS_DIR.exists():
        return []
    
    result = []
    for file_path in STUDENTS_DIR.glob("*.json"):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                result.append({
                    'class': data.get('class', file_path.stem),
                    'count': len(data.get('students', [])),
                    'updated': data.get('updated', '')
                })
        except:
            pass
    
    return result


def delete_student_list(class_name: str):
    """Löscht eine Klassenliste"""
    safe_name = "".join(c for c in class_name if c.isalnum() or c in "._-").strip()
    file_path = STUDENTS_DIR / f"{safe_name}.json"
    
    if file_path.exists():
        file_path.unlink()
        return {'success': True}
    
    return {'success': False, 'error': 'Liste nicht gefunden'}


# === Test ===
if __name__ == '__main__':
    print("Testing WebUntis Backend...")
    
    creds = load_credentials()
    if creds:
        result = login(creds['username'], creds['password'])
        print(f"Login: {result}")
        
        if result['success']:
            today = get_today()
            print(f"Heute: {len(today.get('lessons', []))} Stunden")
            for l in today.get('lessons', []):
                print(f"  {l['start_time']} {l['subjects']} {l['classes']} {l['rooms']}")
            
            logout()
    else:
        print("Keine gespeicherten Credentials")
