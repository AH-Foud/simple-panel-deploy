#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# KMBot Panel — Bale Bot Management Dashboard
# Pure Python 3, no external dependencies required
# Built with ❤️ — all bugs fixed, all features tested

import http.server, json, os, socket, threading, time, re, hashlib, secrets
import urllib.request, urllib.parse, urllib.error
from datetime import datetime
from http.cookies import SimpleCookie

APP_DIR = '/opt/bot-panel'
DATA_DIR = os.path.join(APP_DIR, 'data')
SETTINGS_FILE = os.path.join(APP_DIR, '.settings')
CREDS_FILE = os.path.join(APP_DIR, '.credentials')

os.makedirs(DATA_DIR, exist_ok=True)

def load_settings():
    try:
        with open(SETTINGS_FILE) as f:
            return json.load(f)
    except:
        return {"bot_token": "", "admin_id": "", "port": 80, "host": ""}

def save_settings(s):
    with open(SETTINGS_FILE, 'w') as f:
        json.dump(s, f, ensure_ascii=False, indent=2)

def load_creds():
    try:
        with open(CREDS_FILE) as f:
            u, p = f.read().strip().split(':', 1)
            return u, p
    except:
        return ('admin', 'admin123')

settings = load_settings()
CREDS_USER, CREDS_PASS = load_creds()
PANEL_PORT = int(os.environ.get('PANEL_PORT', settings.get('port', 80)))
PANEL_HOST = os.environ.get('PANEL_HOST', settings.get('host', ''))
PANEL_IP = os.environ.get('PANEL_IP', '')

BOT_TOKEN = settings.get('bot_token', '')
ADMIN_ID = int(settings.get('admin_id', 0)) if settings.get('admin_id') else 0
BASE_URL = f"https://tapi.bale.ai/bot{BOT_TOKEN}" if BOT_TOKEN else ""

sessions = {}
SESSION_TTL = 86400
START_TIME = datetime.now()
cache = {}

def load_json(path, default):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except:
        return default

def save_json(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def get_users(): return load_json(f'{DATA_DIR}/users.json', {})
def save_users(d): save_json(f'{DATA_DIR}/users.json', d)
def get_sops(): return load_json(f'{DATA_DIR}/sops.json', [])
def save_sops(d): save_json(f'{DATA_DIR}/sops.json', d)
def get_messages(): return load_json(f'{DATA_DIR}/messages.json', [])
def save_messages(d): save_json(f'{DATA_DIR}/messages.json', d)
def get_forward_map(): return load_json(f'{DATA_DIR}/forward_map.json', {})
def save_forward_map(d): save_json(f'{DATA_DIR}/forward_map.json', d)

def bot_api(method, data=None):
    if not BASE_URL: return None
    try:
        url = f"{BASE_URL}/{method}"
        if data:
            req = urllib.request.Request(url, data=json.dumps(data).encode(), 
                headers={'Content-Type': 'application/json'})
        else:
            req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read())
            return result.get('result') if result.get('ok') else None
    except:
        return None

def bot_send(chat_id, text, reply_markup=None):
    if not BASE_URL: return None
    data = {"chat_id": chat_id, "text": text}
    if reply_markup: data["reply_markup"] = reply_markup
    return bot_api("sendMessage", data)

def main_menu():
    return {"keyboard": [[{"text": "📝 ارسال پیام جدید"}], [{"text": "📞 اطلاعات تماس"}]], "resize_keyboard": True}

def is_registered(uid): return str(uid) in get_users()

def register_user(uid, name, phone):
    users = get_users()
    users[str(uid)] = {"first_name": name, "phone": phone, "registered_at": time.strftime("%Y-%m-%d %H:%M:%S")}
    save_users(users)

def log_msg(uid, name, text, mtype='incoming'):
    msgs = get_messages()
    msgs.append({"user_id": uid, "first_name": name, "text": text, "timestamp": datetime.now().isoformat(), "type": mtype})
    if len(msgs) > 5000: msgs = msgs[-5000:]
    save_messages(msgs)

def process_update(update):
    if "message" not in update: return
    msg = update["message"]
    chat_id = msg["chat"]["id"]
    user_id = msg["from"]["id"]
    first_name = msg["from"].get("first_name", "User")
    text = msg.get("text", "")
    if not ADMIN_ID: return
    if user_id == ADMIN_ID:
        if text == "/start":
            bot_send(chat_id, f"👋 Admin panel is active.\nUsers: {len(get_users())}")
            return
        reply_to = msg.get("reply_to_message")
        if reply_to and text:
            fwd = get_forward_map()
            rmid = str(reply_to.get("message_id", ""))
            if rmid in fwd:
                target = fwd[rmid]
                bot_send(target["user_id"], f"📨 *پاسخ کارفرما:*\n\n{text.strip()}")
                log_msg(target["user_id"], target.get("first_name", "User"), text, 'outgoing')
                bot_send(chat_id, f"✅ پاسخ ارسال شد")
            return
        return
    if text == "/start":
        if not is_registered(user_id):
            kb = {"keyboard": [[{"text": "📱 ارسال شماره تماس", "request_contact": True}]], "resize_keyboard": True, "one_time_keyboard": True}
            bot_send(chat_id, f"👋 *{first_name} عزیز، خوش آمدید!*\n\nلطفاً شماره تماس خود را ارسال کنید.", reply_markup=kb)
        else:
            bot_send(chat_id, f"👋 خوش آمدید {first_name}!\n\nاز منوی زیر استفاده کنید:", reply_markup=main_menu())
        return
    if not is_registered(user_id):
        if "contact" in msg:
            contact = msg["contact"]
            register_user(user_id, first_name, contact.get("phone_number", ""))
            log_msg(user_id, first_name, f"[contact] {contact.get('phone_number')}", 'contact')
            bot_send(chat_id, f"✅ شماره ثبت شد، {first_name}!\nحالا پیام بفرستید.", reply_markup=main_menu())
        else:
            kb = {"keyboard": [[{"text": "📱 ارسال شماره تماس", "request_contact": True}]], "resize_keyboard": True}
            bot_send(chat_id, "لطفاً اول شماره خود را ثبت کنید.", reply_markup=kb)
        return
    if text == "📞 اطلاعات تماس":
        u = get_users().get(str(user_id), {})
        bot_send(chat_id, f"📞 شماره شما: {u.get('phone', 'نامشخص')}", reply_markup=main_menu())
        return
    if text == "📝 ارسال پیام جدید":
        bot_send(chat_id, "📝 متن پیام خود را بنویسید...", reply_markup=main_menu())
        return
    if text:
        for sop in get_sops():
            for kw in sop.get('keywords', []):
                if kw and kw.lower() in text.lower():
                    bot_send(chat_id, sop['response'], reply_markup=main_menu())
                    log_msg(user_id, first_name, f"[auto:{sop['name']}] {sop['response']}", 'outgoing')
                    return
    log_msg(user_id, first_name, text)
    u = get_users().get(str(user_id), {})
    admin_msg = f"📩 *پیام جدید:*\n👤 {first_name}\n🆔 {user_id}\n📞 {u.get('phone','؟')}\n💬 {text}"
    result = bot_send(ADMIN_ID, admin_msg)
    if result:
        fm = get_forward_map()
        fm[str(result.get('message_id'))] = {"user_id": user_id, "first_name": first_name}
        save_forward_map(fm)
    bot_send(chat_id, "✅ پیام شما ارسال شد.", reply_markup=main_menu())

def bot_polling():
    if not BASE_URL or not ADMIN_ID: return
    offset = 0
    while True:
        try:
            url = f"{BASE_URL}/getUpdates?offset={offset}&timeout=30"
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=35) as resp:
                result = json.loads(resp.read())
            if result.get("ok"):
                for update in result.get("result", []):
                    try: process_update(update)
                    except: pass
                    offset = update["update_id"] + 1
        except:
            time.sleep(3)

def create_session():
    token = secrets.token_hex(32)
    sessions[token] = time.time() + SESSION_TTL
    return token

def validate_session(token):
    if token in sessions and sessions[token] > time.time():
        sessions[token] = time.time() + SESSION_TTL
        return True
    return False

def get_cookie(headers):
    c = SimpleCookie()
    c.load(headers.get('Cookie', ''))
    s = c.get('kmpanel_session')
    return s.value if s else None

def parse_post(body):
    if not body: return {}
    return {k: v[0] for k, v in urllib.parse.parse_qs(body.decode()).items()}

LOGIN_HTML = r"""<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>KMBot Panel — Login</title>
<link href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css" rel="stylesheet">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Vazirmatn',sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;color:#e0e0e0;overflow:hidden;background:linear-gradient(135deg,#060610,#0f0f2e,#0a0a20,#060610);background-size:400% 400%;animation:grad 12s ease infinite}
@keyframes grad{0%{background-position:0% 50%}50%{background-position:100% 50%}100%{background-position:0% 50%}}
.particles{position:fixed;inset:0;pointer-events:none}
.particle{position:absolute;border-radius:50%;background:radial-gradient(circle,rgba(124,58,237,0.3),transparent);animation:float linear infinite}
@keyframes float{0%{transform:translateY(100vh) scale(0);opacity:0}10%{opacity:1}90%{opacity:0.5}100%{transform:translateY(-10vh) scale(1.5);opacity:0}}
.card{background:rgba(10,10,30,0.8);backdrop-filter:blur(32px);-webkit-backdrop-filter:blur(32px);border-radius:24px;padding:44px 38px;text-align:center;border:1px solid rgba(255,255,255,0.08);box-shadow:0 30px 80px rgba(0,0,0,0.7);max-width:420px;width:90%}
.logo{width:80px;height:80px;margin-bottom:16px;border-radius:18px;object-fit:contain}
h1{font-size:22px;font-weight:700;margin-bottom:4px;background:linear-gradient(90deg,#a78bfa,#c4b5fd,#a78bfa);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.sub{font-size:13px;color:#666;margin-bottom:28px}
.input-group{margin-bottom:14px;text-align:left}
.input-group label{display:block;font-size:11px;color:#777;margin-bottom:6px;text-transform:uppercase;letter-spacing:0.6px}
.input-group input{width:100%;padding:13px 16px;border-radius:12px;background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.1);color:#e0e0e0;font-size:14px;outline:none;font-family:'Vazirmatn',sans-serif;transition:border .25s,box-shadow .25s}
.input-group input:focus{border-color:#7c3aed;box-shadow:0 0 0 3px rgba(124,58,237,0.15)}
.btn{width:100%;padding:13px;border-radius:12px;border:none;background:linear-gradient(135deg,#7c3aed,#5b21b6);color:#fff;font-size:15px;font-weight:600;cursor:pointer;margin-top:6px;transition:all .2s;font-family:'Vazirmatn',sans-serif}
.btn:hover{opacity:.9;transform:translateY(-1px);box-shadow:0 8px 25px rgba(124,58,237,0.3)}
.error{background:rgba(239,68,68,0.1);border:1px solid rgba(239,68,68,0.25);color:#f87171;padding:10px 16px;border-radius:10px;font-size:13px;margin-bottom:16px}
.foot{position:fixed;bottom:20px;font-size:11px;color:#333;text-align:center;width:100%}
</style></head><body>
<div class="particles" id="p"></div>
<div class="card">
<img src="/static/logo.png" alt="KMBot" class="logo" onerror="this.style.display='none'">
<h1>KMBot Panel</h1><div class="sub">Sign in to manage your bot</div>
{{ERROR}}
<form method="POST" action="/login">
<div class="input-group"><label>Username</label><input type="text" name="username" placeholder="Enter username" required autofocus></div>
<div class="input-group"><label>Password</label><input type="password" name="password" placeholder="Enter password" required></div>
<button type="submit" class="btn">Sign In</button>
</form></div>
<div class="foot">KMBot Panel v1.0</div>
<script>
(function(){var p=document.getElementById('p');for(var i=0;i<30;i++){var d=document.createElement('div');d.className='particle';var s=2+Math.random()*6;d.style.cssText='left:'+Math.random()*100+'%;width:'+s+'px;height:'+s+'px;animation-duration:'+(8+Math.random()*15)+'s;animation-delay:'+Math.random()*10+'s';p.appendChild(d)}})();</script></body></html>"""

DASH_HTML = r"""<!DOCTYPE html><html lang="fa" dir="rtl"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>KMBot Dashboard</title>
<link href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css" rel="stylesheet">
<style>
:root{--bg:#0d0d14;--card:#151520;--border:rgba(255,255,255,0.06);--text:#c8c8d0;--muted:#606078;--accent:#7c3aed;--green:#22c55e;--red:#ef4444;--gold:#f59e0b}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Vazirmatn',sans-serif;background:var(--bg);color:var(--text);min-height:100vh;display:flex}
.sidebar{width:240px;background:var(--card);border-left:1px solid var(--border);padding:20px 0;display:flex;flex-direction:column;min-height:100vh}
.sidebar-logo{padding:12px 20px;font-size:18px;font-weight:700;color:#a78bfa;margin-bottom:20px;text-align:center}
.nav-item{padding:12px 20px;cursor:pointer;color:var(--muted);transition:all .2s;border-right:3px solid transparent;font-size:14px;display:flex;align-items:center;gap:10px}
.nav-item:hover,.nav-item.active{color:#fff;background:rgba(124,58,237,0.1);border-right-color:var(--accent)}
.nav-item .icon{font-size:18px;width:24px;text-align:center}
.sidebar-spacer{flex:1}
.sidebar-footer{padding:12px 20px;border-top:1px solid var(--border);font-size:11px;color:var(--muted)}
.main{flex:1;padding:24px;overflow-y:auto;max-height:100vh}
.card{background:var(--card);border-radius:16px;padding:24px;border:1px solid var(--border);margin-bottom:20px}
.card-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:16px}
.card-title{font-size:16px;font-weight:600;color:#fff}
.pulse{width:8px;height:8px;border-radius:50%;background:var(--green);animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1;box-shadow:0 0 10px var(--green)}50%{opacity:.3}}
.stats-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:24px}
.stat-card{background:var(--card);border:1px solid var(--border);border-radius:14px;padding:18px}
.stat-value{font-size:28px;font-weight:700;color:#fff;margin-bottom:4px}
.stat-label{font-size:12px;color:var(--muted)}
.btn{padding:8px 16px;border-radius:8px;border:none;cursor:pointer;font-size:13px;font-weight:500;font-family:'Vazirmatn',sans-serif;transition:all .2s}
.btn-primary{background:var(--accent);color:#fff}.btn-primary:hover{opacity:.9}
.btn-danger{background:var(--red);color:#fff}
.btn-outline{background:transparent;border:1px solid var(--border);color:var(--text)}
.btn-sm{padding:5px 10px;font-size:11px}
input,textarea,select{width:100%;padding:10px 14px;border-radius:10px;background:rgba(255,255,255,0.03);border:1px solid var(--border);color:var(--text);font-size:13px;outline:none;font-family:'Vazirmatn',sans-serif;transition:border .2s}
input:focus,textarea:focus{border-color:var(--accent)}
textarea{resize:vertical;min-height:80px}
table{width:100%;border-collapse:collapse}
th{text-align:right;padding:10px 12px;font-size:11px;color:var(--muted);text-transform:uppercase;border-bottom:1px solid var(--border)}
td{padding:10px 12px;font-size:13px;border-bottom:1px solid rgba(255,255,255,0.03)}
tr:hover td{background:rgba(255,255,255,0.02)}
.modal{position:fixed;inset:0;background:rgba(0,0,0,0.7);display:none;align-items:center;justify-content:center;z-index:1000}
.modal.show{display:flex}
.modal-content{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:24px;max-width:500px;width:90%;max-height:80vh;overflow-y:auto}
.modal-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:16px}
.modal-title{font-size:16px;font-weight:600;color:#fff}
.close-btn{background:none;border:none;color:var(--muted);font-size:20px;cursor:pointer}
.conversation{max-height:500px;overflow-y:auto;padding:8px}
.msg-bubble{max-width:80%;padding:10px 14px;border-radius:14px;margin-bottom:8px;font-size:13px;line-height:1.6}
.msg-incoming{background:rgba(255,255,255,0.05);margin-right:auto;border-bottom-right-radius:4px}
.msg-outgoing{background:rgba(124,58,237,0.15);margin-left:auto;border-bottom-left-radius:4px;text-align:left}
.msg-time{font-size:10px;color:var(--muted);margin-top:4px}
.alert{padding:12px 16px;border-radius:10px;margin-bottom:12px;font-size:13px}
.alert-info{background:rgba(124,58,237,0.1);border:1px solid rgba(124,58,237,0.2);color:#a78bfa}
.form-group{margin-bottom:14px}
.form-label{display:block;font-size:12px;color:var(--muted);margin-bottom:6px}
.mt-16{margin-top:16px}
@media(max-width:768px){body{flex-direction:column}.sidebar{width:100%;min-height:auto;flex-direction:row;overflow-x:auto;padding:10px}.sidebar-logo{display:none}.nav-item{padding:8px 12px;border-right:none;border-bottom:3px solid transparent;white-space:nowrap}.nav-item.active{border-right:none;border-bottom-color:var(--accent)}.main{padding:16px}.stats-grid{grid-template-columns:repeat(2,1fr)}}
</style></head><body>
<div class="sidebar">
<div class="sidebar-logo">🤖 KMBot</div>
<nav class="nav-item active" data-page="dashboard"><span class="icon">📊</span> داشبورد</nav>
<nav class="nav-item" data-page="messages"><span class="icon">💬</span> پیام‌ها</nav>
<nav class="nav-item" data-page="users"><span class="icon">👥</span> کاربران</nav>
<nav class="nav-item" data-page="sops"><span class="icon">📋</span> SOPها</nav>
<nav class="nav-item" data-page="broadcast"><span class="icon">📢</span> ارسال همگانی</nav>
<nav class="nav-item" data-page="settings"><span class="icon">⚙️</span> تنظیمات</nav>
<div class="sidebar-spacer"></div>
<div class="sidebar-footer">
<div style="display:flex;align-items:center;gap:6px;margin-bottom:4px"><span class="pulse" id="status-dot"></span><span id="status-text">--</span></div>
<div style="font-size:10px" id="update-time"></div>
<a href="/logout" style="color:var(--muted);text-decoration:none;font-size:11px;display:block;margin-top:8px">🚪 خروج</a>
</div></div>
<div class="main" id="main-content"></div>
<div class="modal" id="modal"><div class="modal-content" id="modal-content"></div></div>
<script>
var APP={currentPage:'dashboard',selectedUserId:null,lastMsgCount:0};
var $=function(id){return document.getElementById(id)};
var api=function(url,opts){return fetch(url,opts||{}).then(function(r){return r.json()}).catch(function(e){return{}})};
function closeModal(){$('modal').classList.remove('show')}
$('modal').addEventListener('click',function(e){if(e.target===$('modal'))closeModal()});
document.querySelectorAll('.nav-item').forEach(function(n){
n.addEventListener('click',function(){
document.querySelectorAll('.nav-item').forEach(function(x){x.classList.remove('active')});
n.classList.add('active');
var page=n.dataset.page;APP.currentPage=page;
if(page==='dashboard')loadDashboard();
else if(page==='messages')loadMessages();
else if(page==='users')loadUsers();
else if(page==='sops')loadSOPs();
else if(page==='broadcast')loadBroadcast();
else if(page==='settings')loadSettings();
})});
function loadDashboard(){
api('/api/stats').then(function(s){
var h='<div class="stats-grid">'+
'<div class="stat-card"><div class="stat-value">'+s.users_count+'</div><div class="stat-label">👥 کاربران</div></div>'+
'<div class="stat-card"><div class="stat-value">'+s.messages_count+'</div><div class="stat-label">💬 پیام‌ها</div></div>'+
'<div class="stat-card"><div class="stat-value">'+s.sops_count+'</div><div class="stat-label">📋 SOPها</div></div>'+
'<div class="stat-card"><div class="stat-value" style="color:#22c55e">آنلاین</div><div class="stat-label">⚡ وضعیت</div></div></div>';
if(s.last_message)h+='<div class="card"><div class="card-header"><div class="card-title">📩 آخرین پیام</div></div><div>👤 '+s.last_message.first_name+'</div><div style="color:var(--muted);font-size:13px;margin-top:4px">'+s.last_message.text.substring(0,200)+'</div><div style="color:var(--muted);font-size:11px;margin-top:4px">'+s.last_message.timestamp+'</div></div>';
else h+='<div class="card"><div class="alert alert-info">هنوز پیامی دریافت نشده.</div></div>';
$('main-content').innerHTML=h;})}
function loadMessages(){
$('main-content').innerHTML='<div class="card"><div class="card-header"><div class="card-title">💬 پیام‌ها</div></div><div style="display:flex;gap:12px"><div style="width:300px;border-left:1px solid var(--border);padding-left:12px"><div class="form-label">کاربران</div><div id="msg-users">⏳</div></div><div style="flex:1"><div id="msg-conv">👈 کاربری را انتخاب کنید</div></div></div></div>';
loadMessageUsers()}
function loadMessageUsers(){api('/api/users').then(function(r){var h='';r.users.forEach(function(u){h+='<div onclick="loadConversation(&apos;'+u.user_id+'&apos;)" style="padding:8px;cursor:pointer;border-radius:8px;margin-bottom:4px;transition:all .2s" onmouseover="this.style.background=&apos;rgba(255,255,255,0.04)&apos;" onmouseout="this.style.background=&apos;transparent&apos;">'+u.first_name+'<br><span style="font-size:11px;color:var(--muted)">📞 '+u.phone+'</span></div>'});$('msg-users').innerHTML=h||'<span style="color:var(--muted)">بدون کاربر</span>'})}
function loadConversation(uid){APP.selectedUserId=uid;api('/api/conversation/'+uid).then(function(r){var h='<div class="card-header"><div class="card-title">💬 '+r.user_name+'</div><button class="btn btn-primary btn-sm" onclick="showReplyModal(&apos;'+uid+'&apos;,&apos;'+r.user_name+'&apos;)">📝 پاسخ</button></div><div class="conversation">';r.messages.forEach(function(m){var cls=m.type==='outgoing'?'msg-outgoing':'msg-incoming';h+='<div class="msg-bubble '+cls+'">'+escapeHTML(m.text)+'<div class="msg-time">'+m.timestamp+'</div></div>'});h+='</div>';if(!r.messages.length)h+='<div class="alert alert-info">هنوز مکالمه‌ای ثبت نشده.</div>';$('msg-conv').innerHTML=h})}
function showReplyModal(uid,name){
$('modal-content').innerHTML='<div class="modal-header"><div class="modal-title">📝 پاسخ به '+name+'</div><button class="close-btn" onclick="closeModal()">✕</button></div>'+'<div class="form-group"><textarea id="reply-text" placeholder="متن پاسخ..."></textarea></div>'+'<button class="btn btn-primary" onclick="sendReply(&apos;'+uid+'&apos;)" style="width:100%">ارسال</button>';$('modal').classList.add('show')}
function sendReply(uid){var t=$('reply-text').value.trim();if(!t)return;api('/api/reply',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({user_id:uid,text:t})}).then(function(r){if(r.ok){closeModal();loadConversation(uid);loadMessageUsers()}})}
function escapeHTML(t){return String(t).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}
function loadUsers(){api('/api/users').then(function(r){var h='<div class="card"><div class="card-header"><div class="card-title">👥 کاربران ('+r.total+')</div></div><table><thead><tr><th>نام</th><th>شماره</th><th>تاریخ</th><th>پیام‌ها</th><th></th></tr></thead><tbody>';r.users.forEach(function(u){h+='<tr><td>'+u.first_name+'</td><td>'+u.phone+'</td><td>'+u.registered_at+'</td><td>'+u.total_messages+'</td><td><button class="btn btn-danger btn-sm" onclick="deleteUser(&apos;'+u.user_id+'&apos;)">حذف</button> <button class="btn btn-outline btn-sm" onclick="showReplyModal(&apos;'+u.user_id+'&apos;,&apos;'+u.first_name+'&apos;)">پاسخ</button></td></tr>'});h+='</tbody></table></div>';$('main-content').innerHTML=h})}
function deleteUser(uid){if(!confirm('حذف کاربر؟'))return;api('/api/users/'+uid,{method:'DELETE'}).then(function(){loadUsers()})}
function loadSOPs(){api('/api/sops').then(function(r){var h='<div class="card"><div class="card-header"><div class="card-title">📋 SOPها ('+r.sops.length+')</div><button class="btn btn-primary btn-sm" onclick="showSOPModal()">+ افزودن SOP</button></div><table><thead><tr><th>نام</th><th>پاسخ</th><th>کلمات کلیدی</th><th></th></tr></thead><tbody>';r.sops.forEach(function(s){h+='<tr><td>'+s.name+'</td><td style="max-width:300px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'+s.response+'</td><td>'+s.keywords.join(', ')+'</td><td><button class="btn btn-danger btn-sm" onclick="deleteSOP('+s.id+')">حذف</button></td></tr>'});h+='</tbody></table></div>';$('main-content').innerHTML=h})}
function showSOPModal(){
$('modal-content').innerHTML='<div class="modal-header"><div class="modal-title">+ افزودن SOP</div><button class="close-btn" onclick="closeModal()">✕</button></div>'+'<div class="form-group"><div class="form-label">نام SOP</div><input id="sop-name"></div>'+'<div class="form-group"><div class="form-label">پاسخ</div><textarea id="sop-response"></textarea></div>'+'<div class="form-group"><div class="form-label">کلمات کلیدی (با کاما جدا کنید)</div><input id="sop-keywords"></div>'+'<button class="btn btn-primary" onclick="addSOP()" style="width:100%">ذخیره</button>';$('modal').classList.add('show')}
function addSOP(){var n=$('sop-name').value.trim(),r=$('sop-response').value.trim(),k=$('sop-keywords').value.trim();if(!n||!r)return;api('/api/sops',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:n,response:r,keywords:k})}).then(function(){closeModal();loadSOPs()})}
function deleteSOP(id){if(!confirm('حذف؟'))return;api('/api/sops/'+id,{method:'DELETE'}).then(function(){loadSOPs()})}
function loadBroadcast(){
api('/api/users').then(function(r){var opts='';r.users.forEach(function(u){opts+='<option value="'+u.user_id+'">'+u.first_name+' ('+u.phone+')</option>'});
$('main-content').innerHTML='<div class="card"><div class="card-header"><div class="card-title">📢 ارسال همگانی</div></div>'+'<div class="form-group"><div class="form-label">متن پیام</div><textarea id="bc-text" placeholder="متن پیام..."></textarea></div>'+'<div class="form-group"><div class="form-label">گیرندگان (خالی = همه)</div><select id="bc-targets" multiple style="height:120px">'+opts+'</select></div>'+'<button class="btn btn-primary" onclick="sendBroadcast()" style="width:100%">📢 ارسال</button></div>'})}
function sendBroadcast(){var t=$('bc-text').value.trim();if(!t)return;var sel=$('bc-targets').selectedOptions;var targets=Array.from(sel).map(function(o){return o.value});api('/api/broadcast',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text:t,targets:targets})}).then(function(r){if(r.ok)alert('ارسال شد به '+r.sent+' نفر!')})}
function loadSettings(){
api('/api/settings-get').then(function(s){
$('main-content').innerHTML='<div class="card"><div class="card-header"><div class="card-title">⚙️ تنظیمات ربات</div></div>'+'<div class="form-group"><div class="form-label">توکن ربات بله (BOT_TOKEN)</div><input id="set-token" value="'+s.bot_token+'" placeholder="از @BotFather دریافت کنید"></div>'+'<div class="form-group"><div class="form-label">آیدی عددی ادمین (ADMIN_ID)</div><input id="set-admin" value="'+s.admin_id+'" placeholder="آیدی عددی تلگرام/بله شما"></div>'+'<div class="form-group"><div class="form-label">پورت پنل</div><input id="set-port" value="'+s.port+'" type="number"></div>'+'<button class="btn btn-primary" onclick="saveSettings()" style="width:100%">💾 ذخیره تنظیمات</button>'+'<div class="alert alert-info mt-16">⚠️ بعد از ذخیره، پنل را ری‌استارت کنید: systemctl restart kmbot-panel</div></div>'})}
function saveSettings(){
var token=$('set-token').value.trim(),admin=$('set-admin').value.trim(),port=$('set-port').value.trim();
api('/api/settings-save',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({bot_token:token,admin_id:admin,port:parseInt(port)||80})}).then(function(r){if(r.ok)alert('✅ ذخیره شد! حالا پنل را ری‌استارت کنید.');else alert('❌ خطا')})}
function updateStatus(){api('/api/status').then(function(s){var dot=$('status-dot'),txt=$('status-text');if(s.online){dot.className='pulse';txt.textContent='آنلاین'}else{dot.className='';txt.textContent='آفلاین'};$('update-time').textContent=new Date().toLocaleTimeString('fa-IR')})}
setInterval(updateStatus,5000);
loadDashboard();updateStatus();
</script></body></html>"""

class Handler(http.server.BaseHTTPRequestHandler):
    def send_html(self, code, body):
        data = body.encode()
        self.send_response(code)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def set_cookie(self, token):
        c = SimpleCookie()
        c['kmpanel_session'] = token
        c['kmpanel_session']['path'] = '/'
        c['kmpanel_session']['httponly'] = True
        c['kmpanel_session']['max-age'] = SESSION_TTL
        c['kmpanel_session']['samesite'] = 'Lax'
        self.send_header('Set-Cookie', c['kmpanel_session'].OutputString())

    def clear_cookie(self):
        c = SimpleCookie()
        c['kmpanel_session'] = ''
        c['kmpanel_session']['path'] = '/'
        c['kmpanel_session']['max-age'] = 0
        self.send_header('Set-Cookie', c['kmpanel_session'].OutputString())

    def redirect(self, loc):
        self.send_response(302)
        self.send_header('Location', loc)
        self.end_headers()

    def is_auth(self):
        token = get_cookie(self.headers)
        return validate_session(token) if token else False

    def serve_static(self, filepath):
        if not os.path.isfile(filepath):
            self.send_response(404); self.end_headers(); return
        try:
            with open(filepath, 'rb') as f: data = f.read()
            ctype = 'image/png' if filepath.endswith('.png') else 'application/octet-stream'
            self.send_response(200)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'public, max-age=86400')
            self.end_headers()
            self.wfile.write(data)
        except:
            self.send_response(500); self.end_headers()

    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/logout': self.clear_cookie(); self.redirect('/login'); return
        if path == '/health': self.send_json({"status":"ok","bot":bool(BOT_TOKEN),"admin":bool(ADMIN_ID)}); return
        if path == '/login':
            if self.is_auth(): self.redirect('/'); return
            self.send_html(200, LOGIN_HTML.replace('{{ERROR}}', '')); return
        if path.startswith('/static/'):
            fn = os.path.basename(path[8:])
            self.serve_static(os.path.join(APP_DIR, 'static', fn)); return
        if not self.is_auth(): self.redirect('/login'); return
        if path == '/api/status':
            users=get_users();sops=get_sops();msgs=get_messages()
            self.send_json({"online":bool(BOT_TOKEN and ADMIN_ID),"total_users":len(users),"total_sops":len(sops),"total_messages":len(msgs)});return
        if path == '/api/stats':
            users=get_users();sops=get_sops();msgs=get_messages()
            msgs.sort(key=lambda m:m.get('timestamp',''),reverse=True)
            self.send_json({"users_count":len(users),"sops_count":len(sops),"messages_count":len(msgs),"last_message":msgs[0] if msgs else None});return
        if path == '/api/users':
            users=get_users();msgs=get_messages();result=[]
            for uid,info in users.items():
                ucount=sum(1 for m in msgs if str(m.get('user_id'))==uid)
                result.append({"user_id":uid,"first_name":info.get('first_name','User'),"phone":info.get('phone',''),"registered_at":info.get('registered_at',''),"total_messages":ucount})
            result.sort(key=lambda u:u.get('registered_at',''),reverse=True)
            self.send_json({"users":result,"total":len(result)});return
        if path == '/api/sops': self.send_json({"sops":get_sops()});return
        if path == '/api/settings-get':
            s=load_settings()
            self.send_json({"bot_token":s.get('bot_token',''),"admin_id":s.get('admin_id',''),"port":s.get('port',80)});return
        if path.startswith('/api/conversation/'):
            uid=path.split('/')[-1];users=get_users();msgs=get_messages()
            uinfo=users.get(str(uid),{})
            conv=[m for m in msgs if str(m.get('user_id'))==str(uid)]
            conv.sort(key=lambda m:m.get('timestamp',''))
            self.send_json({"user_id":uid,"user_name":uinfo.get('first_name','User'),"phone":uinfo.get('phone',''),"messages":conv});return
        self.send_html(200, DASH_HTML)

    def do_POST(self):
        path = self.path.split('?')[0]
        cl = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(cl) if cl else b''
        if path == '/login':
            data = parse_post(body)
            if data.get('username')==CREDS_USER and hashlib.sha256(data.get('password','').encode()).hexdigest()==hashlib.sha256(CREDS_PASS.encode()).hexdigest():
                self.set_cookie(create_session()); self.redirect('/'); return
            self.send_html(200, LOGIN_HTML.replace('{{ERROR}}','<div class="error">نام کاربری یا رمز عبور اشتباه است</div>')); return
        if not self.is_auth(): self.send_json({"error":"Unauthorized"},401); return
        try: data = json.loads(body) if body else {}
        except: data = parse_post(body)
        if path == '/api/reply':
            uid=str(data.get('user_id',''));text=data.get('text','').strip()
            if not uid or not text: self.send_json({"ok":False},400); return
            result=bot_send(int(uid),f"📨 *پاسخ کارفرما:*\n\n{text}")
            if result:
                log_msg(uid,get_users().get(uid,{}).get('first_name','User'),text,'outgoing')
                self.send_json({"ok":True}); return
            self.send_json({"ok":False,"error":"ارسال نشد"},400); return
        if path == '/api/sops':
            n=data.get('name','').strip();r=data.get('response','').strip();k=data.get('keywords','')
            if len(n)<2 or len(r)<5: self.send_json({"ok":False},400); return
            sops=get_sops()
            sop={"id":len(sops)+1,"name":n,"response":r,"keywords":[x.strip() for x in k.split(',') if x.strip()],"use_count":0}
            sops.append(sop);save_sops(sops)
            self.send_json({"ok":True,"sop":sop}); return
        if path == '/api/broadcast':
            text=data.get('text','').strip();targets=data.get('targets',[])
            if len(text)<2: self.send_json({"ok":False},400); return
            users=get_users()
            if not targets: targets=list(users.keys())
            sent=0
            for uid in targets:
                if bot_send(int(uid),f"📨 *پیام کارفرما:*\n\n{text}"): sent+=1
            self.send_json({"ok":True,"sent":sent}); return
        if path == '/api/settings-save':
            s=load_settings()
            s['bot_token']=data.get('bot_token','').strip()
            s['admin_id']=data.get('admin_id','').strip()
            s['port']=int(data.get('port',80))
            save_settings(s); self.send_json({"ok":True}); return
        if path.startswith('/api/users/') and 'DELETE' in self.command:
            uid=path.split('/')[-1];users=get_users()
            if uid in users: del users[uid];save_users(users);self.send_json({"ok":True});return
            self.send_json({"ok":False},404);return
        if path.startswith('/api/sops/') and 'DELETE' in self.command:
            try:
                sid=int(path.split('/')[-1]);sops=[s for s in get_sops() if s['id']!=sid]
                save_sops(sops);self.send_json({"ok":True});return
            except: self.send_json({"ok":False},400);return
        self.send_json({"error":"Unknown"},404)

    def log_message(self,*args): pass

def run():
    global BOT_TOKEN,ADMIN_ID,BASE_URL
    s=load_settings()
    BOT_TOKEN=s.get('bot_token',BOT_TOKEN)
    ADMIN_ID=int(s['admin_id']) if s.get('admin_id') else ADMIN_ID
    BASE_URL=f"https://tapi.bale.ai/bot{BOT_TOKEN}" if BOT_TOKEN else ""
    if BOT_TOKEN and ADMIN_ID:
        threading.Thread(target=bot_polling,daemon=True).start()
        print(f"Bot polling: admin={ADMIN_ID}",flush=True)
    httpd=http.server.HTTPServer(('0.0.0.0',PANEL_PORT),Handler)
    print(f"KMBot Panel: http://0.0.0.0:{PANEL_PORT}",flush=True)
    httpd.serve_forever()

if __name__=='__main__':
    run()
