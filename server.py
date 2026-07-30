import http.server
import os
import socket
import json
import hashlib
import secrets
import time
import urllib.parse
import mimetypes
from datetime import datetime
from http.cookies import SimpleCookie

PORT = int(os.environ.get('PANEL_PORT', '8080'))
HOST = os.environ.get('PANEL_HOST', 'N/A')
IP   = os.environ.get('PANEL_IP', 'N/A')
APP_DIR = '/opt/simple-panel'
STATIC_DIR = os.path.join(APP_DIR, 'static')
CREDS_FILE = os.path.join(APP_DIR, '.credentials')
START_TIME = datetime.now()

sessions = {}
SESSION_TTL = 86400

# ---------- credentials ----------
def load_credentials():
    try:
        with open(CREDS_FILE) as f:
            line = f.readline().strip()
            if ':' in line:
                u, p = line.split(':', 1)
                return u, p
    except Exception:
        pass
    return ('admin', 'admin123')

def hash_password(pwd):
    return hashlib.sha256(pwd.encode()).hexdigest()

def check_password(pwd):
    _, stored = load_credentials()
    return hash_password(pwd) == hash_password(stored)

def create_session():
    token = secrets.token_hex(32)
    sessions[token] = time.time() + SESSION_TTL
    return token

def validate_session(token):
    if token in sessions:
        if sessions[token] > time.time():
            sessions[token] = time.time() + SESSION_TTL
            return True
        del sessions[token]
    return False

def get_cookie(req):
    cookie_header = req.headers.get('Cookie', '')
    c = SimpleCookie()
    c.load(cookie_header)
    session = c.get('kmpanel_session')
    return session.value if session else None

# ---------- HTML ----------

LOGIN_HTML = r"""<!DOCTYPE html>
<html lang="en" dir="ltr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>KMPanel — Login</title>
<link href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css" rel="stylesheet" type="text/css" />
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{
  font-family:'Vazirmatn',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  min-height:100vh;display:flex;align-items:center;justify-content:center;
  color:#e0e0e0;overflow:hidden;
}
.bg-layer{position:fixed;inset:0;z-index:0}
.bg-gradient{
  position:absolute;inset:0;
  background:linear-gradient(135deg,#060610,#0f0f2e,#0a0a20,#060610);
  background-size:400% 400%;animation:gradientShift 12s ease infinite;
  z-index:2;
}
@keyframes gradientShift{
  0%{background-position:0% 50%}50%{background-position:100% 50%}100%{background-position:0% 50%}
}
.bg-video{
  position:absolute;inset:0;width:100%;height:100%;object-fit:cover;
  z-index:1;opacity:0.35;
}
.overlay{position:fixed;inset:0;z-index:3;display:flex;align-items:center;justify-content:center}
.card{
  background:rgba(10,10,30,0.75);
  backdrop-filter:blur(32px);-webkit-backdrop-filter:blur(32px);
  border-radius:24px;padding:44px 38px;text-align:center;
  border:1px solid rgba(255,255,255,0.08);
  box-shadow:0 30px 80px rgba(0,0,0,0.7),0 0 100px rgba(124,58,237,0.08);
  max-width:420px;width:90%;position:relative;
}
.logo{width:80px;height:80px;margin-bottom:16px;border-radius:18px;object-fit:contain}
h1{
  font-size:22px;font-weight:700;margin-bottom:4px;letter-spacing:1px;
  background:linear-gradient(90deg,#a78bfa,#c4b5fd,#a78bfa);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;
}
.sub{font-size:13px;color:#666;margin-bottom:28px;font-weight:300}
.input-group{margin-bottom:16px;text-align:left}
.input-group label{display:block;font-size:11px;color:#777;margin-bottom:6px;text-transform:uppercase;letter-spacing:0.6px}
.input-group input{
  width:100%;padding:13px 16px;border-radius:12px;
  background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.1);
  color:#e0e0e0;font-size:14px;outline:none;transition:border .25s,box-shadow .25s;
  font-family:'Vazirmatn',-apple-system,BlinkMacSystemFont,sans-serif;
}
.input-group input:focus{
  border-color:#7c3aed;box-shadow:0 0 0 3px rgba(124,58,237,0.15);
}
.btn{
  width:100%;padding:13px;border-radius:12px;border:none;
  background:linear-gradient(135deg,#7c3aed,#5b21b6);
  color:#fff;font-size:15px;font-weight:600;cursor:pointer;
  margin-top:6px;transition:all .2s;
  font-family:'Vazirmatn',-apple-system,BlinkMacSystemFont,sans-serif;
}
.btn:hover{opacity:.9;transform:translateY(-1px);box-shadow:0 8px 25px rgba(124,58,237,0.3)}
.btn:active{transform:translateY(0)}
.error{
  background:rgba(239,68,68,0.1);border:1px solid rgba(239,68,68,0.25);
  color:#f87171;padding:10px 16px;border-radius:10px;font-size:13px;margin-bottom:16px;
}
.foot{position:fixed;bottom:20px;z-index:4;font-size:11px;color:#333;text-align:center;width:100%}
</style>
</head>
<body>
<div class="bg-layer">
  <div class="bg-gradient"></div>
  <video autoplay muted loop playsinline class="bg-video">
    <source src="/static/bg.mp4" type="video/mp4">
  </video>
</div>
<div class="overlay">
  <div class="card">
    <img src="/static/logo.png" alt="KMPanel" class="logo" onerror="this.style.display='none'">
    <h1>KMPanel</h1>
    <div class="sub">Sign in to continue</div>
    {{ERROR}}
    <form method="POST" action="/login">
      <div class="input-group">
        <label>Username</label>
        <input type="text" name="username" placeholder="Enter username" required autofocus>
      </div>
      <div class="input-group">
        <label>Password</label>
        <input type="password" name="password" placeholder="Enter password" required>
      </div>
      <button type="submit" class="btn">Sign In</button>
    </form>
  </div>
</div>
<div class="foot">KMPanel v4 &middot; Secure Access</div>
</body>
</html>"""

DASH_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Dashboard — KMPanel</title>
<link href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css" rel="stylesheet" type="text/css" />
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{
  font-family:'Vazirmatn',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  background:linear-gradient(135deg,#060610,#0f0f2e,#0a0a20,#060610);
  background-size:400% 400%;animation:gradientShift 12s ease infinite;
  min-height:100vh;display:flex;align-items:center;justify-content:center;
  color:#e0e0e0;
}
@keyframes gradientShift{
  0%{background-position:0% 50%}50%{background-position:100% 50%}100%{background-position:0% 50%}
}
.card{
  background:rgba(10,10,30,0.75);
  backdrop-filter:blur(32px);-webkit-backdrop-filter:blur(32px);
  border-radius:24px;padding:44px 40px;text-align:center;
  border:1px solid rgba(255,255,255,0.08);
  box-shadow:0 30px 80px rgba(0,0,0,0.7),0 0 100px rgba(124,58,237,0.06);
  max-width:540px;width:90%;
}
.header{display:flex;justify-content:space-between;align-items:center;margin-bottom:24px}
.header-left{display:flex;align-items:center;gap:12px}
.logo-sm{width:36px;height:36px;border-radius:10px;object-fit:contain}
.header h1{
  font-size:18px;font-weight:700;
  background:linear-gradient(90deg,#a78bfa,#c4b5fd);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;
}
.logout-btn{
  padding:7px 16px;border-radius:8px;
  background:rgba(239,68,68,0.08);border:1px solid rgba(239,68,68,0.2);
  color:#f87171;font-size:12px;cursor:pointer;text-decoration:none;
  transition:all .2s;font-family:'Vazirmatn',sans-serif;
}
.logout-btn:hover{background:rgba(239,68,68,0.18);border-color:rgba(239,68,68,0.4)}
.icon-big{font-size:56px;margin-bottom:12px}
.badge{
  display:inline-flex;align-items:center;gap:10px;
  background:rgba(34,197,94,0.08);
  border:1px solid rgba(34,197,94,0.2);
  border-radius:30px;padding:10px 26px;margin-bottom:24px;
  font-size:14px;color:#4ade80;font-weight:500;
}
.pulse{width:9px;height:9px;background:#22c55e;border-radius:50%;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1;box-shadow:0 0 10px #22c55e}50%{opacity:.3;box-shadow:0 0 3px #22c55e}}
.url-box{
  background:rgba(124,58,237,0.06);border:1px solid rgba(124,58,237,0.15);
  border-radius:12px;padding:14px 18px;margin-bottom:18px;text-align:left;
  font-size:13px;color:#a78bfa;word-break:break-all;
  font-family:'SF Mono','Fira Code',monospace;
}
.url-box .lbl{font-size:10px;color:#555;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;font-family:'Vazirmatn',sans-serif}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;text-align:left;margin-bottom:12px}
.cell{
  background:rgba(255,255,255,0.02);border-radius:14px;padding:15px 18px;
  border:1px solid rgba(255,255,255,0.04);
}
.cell .lbl{font-size:10px;color:#555;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:5px}
.cell .val{font-size:15px;color:#bbb;font-weight:500;word-break:break-all}
.foot{margin-top:18px;font-size:11px;color:#444}
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <div class="header-left">
      <img src="/static/logo.png" alt="" class="logo-sm" onerror="this.style.display='none'">
      <h1>KMPanel</h1>
    </div>
    <a href="/logout" class="logout-btn">Logout</a>
  </div>
  <div class="icon-big">🚀</div>
  <div class="badge"><span class="pulse"></span> System Online</div>
  <div class="url-box">
    <div class="lbl">Panel URL</div>
    http://{{HOST}}:{{PORT}}
  </div>
  <div class="grid">
    <div class="cell"><div class="lbl">Hostname</div><div class="val">{{HOSTNAME}}</div></div>
    <div class="cell"><div class="lbl">IP Address</div><div class="val">{{IP}}</div></div>
    <div class="cell"><div class="lbl">Port</div><div class="val">{{PORT}}</div></div>
    <div class="cell"><div class="lbl">Uptime</div><div class="val">{{UPTIME}}</div></div>
  </div>
  <div class="foot">KMPanel v4 &middot; {{DATE}}</div>
</div>
</body>
</html>"""

# ---------- Handlers ----------

class Handler(http.server.BaseHTTPRequestHandler):

    def serve_html(self, code, html):
        body = html.encode()
        self.send_response(code)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def serve_static(self, filepath):
        if not os.path.isfile(filepath):
            self.send_response(404)
            self.end_headers()
            return
        try:
            with open(filepath, 'rb') as f:
                data = f.read()
            ctype, _ = mimetypes.guess_type(filepath)
            if ctype is None:
                ctype = 'application/octet-stream'
            self.send_response(200)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'public, max-age=86400')
            self.end_headers()
            self.wfile.write(data)
        except Exception:
            self.send_response(500)
            self.end_headers()

    def serve_json(self, data):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def redirect(self, location):
        self.send_response(302)
        self.send_header('Location', location)
        self.end_headers()

    def set_session_cookie(self, token):
        c = SimpleCookie()
        c['kmpanel_session'] = token
        c['kmpanel_session']['path'] = '/'
        c['kmpanel_session']['httponly'] = True
        c['kmpanel_session']['max-age'] = SESSION_TTL
        c['kmpanel_session']['samesite'] = 'Lax'
        self.send_header('Set-Cookie', c['kmpanel_session'].OutputString())

    def clear_session_cookie(self):
        c = SimpleCookie()
        c['kmpanel_session'] = ''
        c['kmpanel_session']['path'] = '/'
        c['kmpanel_session']['max-age'] = 0
        self.send_header('Set-Cookie', c['kmpanel_session'].OutputString())

    def is_authenticated(self):
        token = get_cookie(self)
        return validate_session(token) if token else False

    def dash_vars(self):
        uptime = datetime.now() - START_TIME
        h, r = divmod(int(uptime.total_seconds()), 3600)
        m, s = divmod(r, 60)
        return {
            '{{HOST}}': HOST,
            '{{HOSTNAME}}': socket.gethostname(),
            '{{IP}}': IP,
            '{{PORT}}': str(PORT),
            '{{UPTIME}}': f"{h}h {m}m {s}s",
            '{{DATE}}': datetime.now().strftime('%Y-%m-%d %H:%M UTC'),
        }

    def do_GET(self):
        path = self.path.split('?')[0]

        if path == '/health':
            uptime = str(datetime.now() - START_TIME)
            self.serve_json({"status": "ok", "uptime": uptime})
            return

        if path.startswith('/static/'):
            filename = path[8:]
            if '..' in filename or '/' in filename.lstrip('/'):
                self.send_response(403)
                self.end_headers()
                return
            filepath = os.path.join(STATIC_DIR, filename)
            self.serve_static(filepath)
            return

        if path == '/logout':
            self.clear_session_cookie()
            self.redirect('/login')
            return

        if path == '/login':
            if self.is_authenticated():
                self.redirect('/')
                return
            html = LOGIN_HTML.replace('{{ERROR}}', '')
            self.serve_html(200, html)
            return

        if not self.is_authenticated():
            self.redirect('/login')
            return

        html = DASH_HTML
        for k, v in self.dash_vars().items():
            html = html.replace(k, v)
        self.serve_html(200, html)

    def do_POST(self):
        path = self.path.split('?')[0]

        if path == '/login':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode()
            data = urllib.parse.parse_qs(body)
            username = data.get('username', [''])[0]
            password = data.get('password', [''])[0]

            user, _ = load_credentials()

            if username == user and check_password(password):
                token = create_session()
                self.set_session_cookie(token)
                self.redirect('/')
                return

            html = LOGIN_HTML.replace(
                '{{ERROR}}',
                '<div class="error">Invalid username or password</div>'
            )
            self.serve_html(200, html)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass


if __name__ == '__main__':
    httpd = http.server.HTTPServer(('0.0.0.0', PORT), Handler)
    print(f"KMPanel server started on port {PORT}", flush=True)
    httpd.serve_forever()
