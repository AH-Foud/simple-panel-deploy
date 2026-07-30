import http.server
import os
import socket
import json
import hashlib
import secrets
import time
import urllib.parse
from datetime import datetime
from http.cookies import SimpleCookie

PORT = int(os.environ.get('PANEL_PORT', '8080'))
HOST = os.environ.get('PANEL_HOST', 'N/A')
IP   = os.environ.get('PANEL_IP', 'N/A')
APP_DIR = '/opt/simple-panel'
CREDS_FILE = os.path.join(APP_DIR, '.credentials')
CONFIG_FILE = os.path.join(APP_DIR, '.config')
START_TIME = datetime.now()

# ---------- sessions ----------
sessions = {}
SESSION_TTL = 86400  # 24h

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

def save_credentials(user, pwd):
    with open(CREDS_FILE, 'w') as f:
        f.write(f"{user}:{pwd}\n")
    os.chmod(CREDS_FILE, 0o600)

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
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Login — KMPanel</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  background:linear-gradient(135deg,#0a0a1a,#121240,#0a0a1a);
  min-height:100vh;display:flex;align-items:center;justify-content:center;
  color:#e0e0e0;
}
.card{
  background:rgba(255,255,255,0.03);
  backdrop-filter:blur(28px);-webkit-backdrop-filter:blur(28px);
  border-radius:24px;padding:48px 40px;text-align:center;
  border:1px solid rgba(255,255,255,0.06);
  box-shadow:0 30px 80px rgba(0,0,0,0.6);
  max-width:420px;width:90%;
}
.icon{font-size:56px;margin-bottom:12px}
h1{
  font-size:24px;font-weight:700;margin-bottom:4px;
  background:linear-gradient(90deg,#7c3aed,#a78bfa);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;
}
.sub{font-size:13px;color:#666;margin-bottom:32px}
.input-group{margin-bottom:18px;text-align:left}
.input-group label{display:block;font-size:12px;color:#777;margin-bottom:6px;text-transform:uppercase;letter-spacing:0.5px}
.input-group input{
  width:100%;padding:14px 16px;border-radius:12px;
  background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.1);
  color:#e0e0e0;font-size:15px;outline:none;transition:border .2s;
}
.input-group input:focus{border-color:#7c3aed}
.btn{
  width:100%;padding:14px;border-radius:12px;border:none;
  background:linear-gradient(135deg,#7c3aed,#5b21b6);
  color:#fff;font-size:16px;font-weight:600;cursor:pointer;
  margin-top:8px;transition:opacity .2s;
}
.btn:hover{opacity:.9}
.error{
  background:rgba(239,68,68,0.12);border:1px solid rgba(239,68,68,0.3);
  color:#f87171;padding:10px 16px;border-radius:10px;font-size:13px;
  margin-bottom:16px;
}
</style>
</head>
<body>
<div class="card">
  <div class="icon">🔐</div>
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
</body>
</html>"""

DASH_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Dashboard — KMPanel</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  background:linear-gradient(135deg,#0a0a1a,#121240,#0a0a1a);
  min-height:100vh;display:flex;align-items:center;justify-content:center;
  color:#e0e0e0;
}
.card{
  background:rgba(255,255,255,0.03);
  backdrop-filter:blur(28px);-webkit-backdrop-filter:blur(28px);
  border-radius:24px;padding:48px 44px;text-align:center;
  border:1px solid rgba(255,255,255,0.06);
  box-shadow:0 30px 80px rgba(0,0,0,0.6);
  max-width:540px;width:90%;
}
.header{display:flex;justify-content:space-between;align-items:center;margin-bottom:28px}
.header h1{
  font-size:20px;font-weight:700;
  background:linear-gradient(90deg,#7c3aed,#a78bfa);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;
}
.logout-btn{
  padding:8px 18px;border-radius:8px;
  background:rgba(239,68,68,0.1);border:1px solid rgba(239,68,68,0.3);
  color:#f87171;font-size:13px;cursor:pointer;text-decoration:none;
  transition:background .2s;
}
.logout-btn:hover{background:rgba(239,68,68,0.2)}
.icon-big{font-size:60px;margin-bottom:16px}
.badge{
  display:inline-flex;align-items:center;gap:10px;
  background:rgba(34,197,94,0.1);
  border:1px solid rgba(34,197,94,0.25);
  border-radius:30px;padding:12px 28px;margin-bottom:28px;
  font-size:15px;color:#4ade80;font-weight:500;
}
.pulse{width:10px;height:10px;background:#22c55e;border-radius:50%;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1;box-shadow:0 0 10px #22c55e}50%{opacity:.3;box-shadow:0 0 3px #22c55e}}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;text-align:left;margin-bottom:20px}
.cell{
  background:rgba(255,255,255,0.02);border-radius:14px;padding:16px 18px;
  border:1px solid rgba(255,255,255,0.04);
}
.cell .lbl{font-size:10px;color:#555;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:5px}
.cell .val{font-size:15px;color:#bbb;font-weight:500;word-break:break-all}
.url-box{
  background:rgba(124,58,237,0.08);border:1px solid rgba(124,58,237,0.2);
  border-radius:12px;padding:14px 18px;margin-bottom:6px;text-align:left;
  font-size:14px;color:#a78bfa;word-break:break-all;font-family:'SF Mono',monospace;
}
.url-box .lbl{font-size:10px;color:#666;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px}
.foot{margin-top:20px;font-size:11px;color:#444}
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <h1>⚡ KMPanel</h1>
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
  <div class="foot">KMPanel v3.0 &middot; {{DATE}}</div>
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

        # Dashboard ( / ) — requires auth
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
            # Read form body
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

            # Login failed
            html = LOGIN_HTML.replace(
                '{{ERROR}}',
                '<div class="error">Invalid username or password</div>'
            )
            self.serve_html(200, html)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass  # silent


if __name__ == '__main__':
    httpd = http.server.HTTPServer(('0.0.0.0', PORT), Handler)
    print(f"KMPanel server started on port {PORT}", flush=True)
    httpd.serve_forever()
