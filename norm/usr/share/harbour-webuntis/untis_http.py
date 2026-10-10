"""
Kleiner Ersatz fuer die benutzten Teile von "requests" - nur mit der
Standardbibliothek (urllib).

Warum: Sailjail laesst der App vom Heimverzeichnis nur
~/.local/share/<app> & Co. sehen. Ein mit "pip --user" installiertes
requests liegt in ~/.local/lib/pythonX.Y/site-packages und ist im
Sandkasten unsichtbar - "import requests" scheitert, damit stirbt das
ganze Python-Modul und in der App bleiben Schulsuche und Anmeldung
stumm. urllib ist Teil von python3-base und immer da.

Benutzung: "import untis_http as requests" - die Aufrufstellen bleiben.
"""

import http.cookiejar
import json as _json
import socket
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_USER_AGENT = 'Untis/6.3.2 (Linux; Mobile; SailfishOS)'


class exceptions:
    """Nachbau von requests.exceptions (nur was gebraucht wird)"""

    class RequestException(Exception):
        pass

    class ConnectionError(RequestException):
        pass

    class Timeout(RequestException):
        pass

    class HTTPError(RequestException):
        pass


# Damit "except requests.exceptions.Timeout" auch bei direkt
# geworfenen Standardfehlern greift, werfen wir ausschliesslich
# die Klassen oben.
RequestException = exceptions.RequestException
ConnectionError = exceptions.ConnectionError
Timeout = exceptions.Timeout
HTTPError = exceptions.HTTPError


class Response:
    """Antwort mit der Teilmenge der requests-Schnittstelle"""

    def __init__(self, status_code, headers, content, url):
        self.status_code = status_code
        self.headers = headers
        self.content = content
        self.url = url

    @property
    def ok(self):
        return self.status_code < 400

    @property
    def text(self):
        charset = None
        try:
            charset = self.headers.get_content_charset()
        except AttributeError:
            pass
        return self.content.decode(charset or 'utf-8', 'replace')

    def json(self):
        return _json.loads(self.text)

    def raise_for_status(self):
        if not self.ok:
            raise exceptions.HTTPError(
                "HTTP %s fuer %s" % (self.status_code, self.url))

    def close(self):
        pass

    def __repr__(self):
        return "<Response [%s]>" % self.status_code


class _Cookies:
    """Minimaler Zugang zum CookieJar (set/get, wie requests.cookies)"""

    def __init__(self, jar):
        self._jar = jar

    def set(self, name, value, domain=None, path='/'):
        cookie = http.cookiejar.Cookie(
            version=0, name=name, value=value,
            port=None, port_specified=False,
            domain=domain or '', domain_specified=bool(domain),
            domain_initial_dot=False,
            path=path, path_specified=True,
            secure=True, expires=None, discard=True,
            comment=None, comment_url=None, rest={}, rfc2109=False)
        self._jar.set_cookie(cookie)

    def get(self, name, default=None):
        for cookie in self._jar:
            if cookie.name == name:
                return cookie.value
        return default

    def clear(self):
        self._jar.clear()

    def __iter__(self):
        return iter(self._jar)


class Session:
    """requests.Session-Ersatz: haelt Kopfzeilen und die Kekse"""

    def __init__(self):
        self.headers = {'User-Agent': DEFAULT_USER_AGENT}
        self._jar = http.cookiejar.CookieJar()
        self._opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self._jar))
        self.cookies = _Cookies(self._jar)

    # --- intern ---

    def request(self, method, url, json=None, data=None, headers=None,
                timeout=30):
        body = data
        send_headers = dict(self.headers)
        if json is not None:
            body = _json.dumps(json).encode('utf-8')
            send_headers.setdefault('Content-Type', 'application/json')
        if isinstance(body, str):
            body = body.encode('utf-8')
        if headers:
            send_headers.update(headers)
        # urllib setzt ohne Body kein Content-Length, das stoert hier nicht
        request = urllib.request.Request(url, data=body, method=method)
        for key, value in send_headers.items():
            if value is None:
                continue
            request.add_header(key, value)

        try:
            answer = self._opener.open(request, timeout=timeout)
            with answer:
                content = answer.read()
            status, headers, url = answer.status, answer.headers, answer.geturl()
        except urllib.error.HTTPError as error:
            # Fehlerseiten liefern oft den eigentlichen JSON-RPC-Fehler,
            # darum wie requests: kein Wurf, sondern Antwort zurueck.
            content = b''
            try:
                content = error.read()
            except Exception:
                pass
            return Response(error.code, error.headers, content, url)
        except urllib.error.URLError as error:
            reason = getattr(error, 'reason', error)
            if isinstance(reason, (socket.timeout, TimeoutError)):
                raise exceptions.Timeout(str(reason))
            raise exceptions.ConnectionError(str(reason))
        except (socket.timeout, TimeoutError) as error:
            raise exceptions.Timeout(str(error))
        except OSError as error:
            raise exceptions.ConnectionError(str(error))

        return Response(status, headers, content, url)

    # --- oeffentlich ---

    def post(self, url, json=None, data=None, headers=None, timeout=30):
        return self.request('POST', url, json=json, data=data,
                            headers=headers, timeout=timeout)

    def get(self, url, headers=None, timeout=30):
        return self.request('GET', url, headers=headers, timeout=timeout)

    def close(self):
        pass


# --- Abkuerzungen ohne eigene Sitzung ---

def post(url, json=None, data=None, headers=None, timeout=30):
    return Session().post(url, json=json, data=data, headers=headers,
                          timeout=timeout)


def get(url, headers=None, timeout=30):
    return Session().get(url, headers=headers, timeout=timeout)
