#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
"""The Android app's smoke test, on an emulator, against a real server that the server
repository's scripts/smoke/server.sh set up on this machine (the emulator reaches it as 10.0.2.2).
Every step leaves a screenshot and a log in $SMOKE_OUT/android-<kind>/.

  SMOKE_OUT=... python3 scripts/smoke/android.py <app.apk> [--tv] [step ...]

Installing over the previous release is ci.yml's android-update job (android/scripts/check-upgrade.sh and
upgrade-test.sh), not repeated here.

Steps, in order (name some to run only those):
  address    Enter an address, then a security code from the server: signed in
  settings   Settings opens
  film       the film plays: the server sees this device streaming
  away       the server's address stops answering (the emulator's firewall): the app comes back
             peer to peer, still signed in
  game       from away, WittyPlay's Adjustris starts and the server sends this device its frames
  link       a fresh app, still away: Join with a link or code, the invite link pasted, signed in

Only the standard library; adb must be on PATH.
"""
import json, os, re, subprocess, sys, time, urllib.request, xml.etree.ElementTree as ET

PKG = 'com.wittywilla.wittymediaclient'
args = sys.argv[1:]
apk = args.pop(0)
TV = '--tv' in args
only = [a for a in args if not a.startswith('--')]
kind = 'tv' if TV else 'phone'
OUT = os.path.join(os.environ.get('SMOKE_OUT', 'smoke-out'), 'android-' + kind)
os.makedirs(OUT, exist_ok=True)
env = {}
for line in open(os.path.join(os.environ.get('SMOKE_OUT', 'smoke-out'), 'server.env')):
    k, _, v = line.strip().partition('=')
    env[k] = v
URL = env['WMS_URL']
PORT = URL.rsplit(':', 1)[1]
EMU_URL = 'http://10.0.2.2:' + PORT
HERE = os.path.dirname(os.path.abspath(__file__))
n = 0
failed = []
log_file = None


def log(*a):
    s = ' '.join(str(x) for x in a)
    if log_file:
        log_file.write(s + '\n'); log_file.flush()


def adb(*a, check=True, timeout=120):
    r = subprocess.run(['adb', *a], capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"adb {' '.join(a)}: {r.stdout.strip()} {r.stderr.strip()}")
    return r.stdout


def sh(cmd, **k):
    return adb('shell', cmd, **k)


def api(method, path, body=None, token=None):
    req = urllib.request.Request(URL + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + (token or env['WMS_TOKEN'])})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or b'null')


def nodes():
    for _ in range(3):
        sh('uiautomator dump /sdcard/u.xml', check=False)
        xml = sh('cat /sdcard/u.xml', check=False)
        try:
            root = ET.fromstring(xml[xml.index('<'):])
            break
        except (ValueError, ET.ParseError):
            time.sleep(1)
    else:
        return []
    out = []
    for e in root.iter('node'):
        b = [int(x) for x in re.findall(r'\d+', e.get('bounds', '[0,0][0,0]'))]
        out.append({'text': e.get('text', ''), 'desc': e.get('content-desc', ''), 'cls': e.get('class', ''),
                    'focused': e.get('focused') == 'true', 'clickable': e.get('clickable') == 'true', 'b': b})
    return out


def texts():
    return [x['text'] or x['desc'] for x in nodes() if x['text'] or x['desc']]


def dismiss(ns):
    """A system "isn't responding" dialog over everything (the emulator's launcher, on a busy runner): closed,
    and logged. One about this app is waited out instead, and logged, as it would be a fault of ours."""
    msg = next((x['text'] for x in ns if "isn't responding" in x['text']), None)
    if not msg:
        return False
    ours = 'WittyMediaClient' in msg or 'Witty' in msg
    log('system dialog:', msg, '(waiting)' if ours else '(closing it)')
    btn = next((x for x in ns if x['text'] == ('Wait' if ours else 'Close app')), None)
    if btn:
        b = btn['b']
        sh(f'input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}')
        time.sleep(1)
    return True


def find(pattern):
    re_ = re.compile(pattern, re.I)
    ns = nodes()
    if dismiss(ns):
        ns = nodes()
    hits = [x for x in ns if re_.search(x['text']) or re_.search(x['desc'])]
    return hits[0] if hits else None


def wait(pattern, secs=30, what=None):
    end = time.time() + secs
    while True:
        x = find(pattern)
        if x:
            return x
        if time.time() > end:
            raise RuntimeError(f"waited {secs}s for {what or pattern}; on screen: {texts()[:30]}")
        time.sleep(1)


def tap(pattern, secs=30):
    x = wait(pattern, secs)
    b = x['b']
    sh(f'input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}')
    log('tapped', repr(x['text'] or x['desc']))
    time.sleep(1)


def type_text(s):
    # In short pieces: a long input text can lose characters on a busy emulator.
    s = s.replace("'", '')
    for i in range(0, len(s), 40):
        sh("input text '" + s[i:i + 40].replace(' ', '%s') + "'")
        time.sleep(0.2)


def type_into(pattern, s):
    """Taps the field labelled pattern (or the first text field) and types."""
    fields = [x for x in nodes() if 'EditText' in x['cls']]
    re_ = re.compile(pattern, re.I)
    f = next((x for x in fields if re_.search(x['text']) or re_.search(x['desc'])), fields[0] if fields else None)
    if not f:
        raise RuntimeError(f'no text field; on screen: {texts()[:30]}')
    b = f['b']
    sh(f'input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}')
    time.sleep(0.5)
    sh('input keyevent KEYCODE_MOVE_END')
    for _ in range(len(f['text']) + 2):
        sh('input keyevent KEYCODE_DEL', check=False)
    type_text(s)
    now = next((x['text'] for x in nodes() if 'EditText' in x['cls'] and x['b'] == b), '')
    log('typed', len(s), 'characters; the field holds', len(now), ':', now[:60], '…', now[-60:])
    if now and now != s and len(s) > 20:
        log('NOT THE SAME as what was typed:', s[:60], '…', s[-60:])


def launch(clear=False):
    sh(f'am force-stop {PKG}')
    if clear:
        sh(f'pm clear {PKG}')
    sh(f'monkey -p {PKG} -c android.intent.category.{"LEANBACK_LAUNCHER" if TV else "LAUNCHER"} 1', check=False)
    time.sleep(3)


def streaming(via=None):
    for s in api('GET', '/api/sessions'):
        if s.get('streaming') and 'smoke' not in (s.get('device') or '') and (via is None or s.get('via') == via):
            return s
    return None


def until(what, fn, secs=60):
    end = time.time() + secs
    last = None
    while time.time() < end:
        try:
            last = fn()
            if last:
                return last
        except Exception as e:  # noqa: BLE001: tried again until the time is up
            last = e
        time.sleep(2)
    raise RuntimeError(f'waited {secs}s for {what}; last: {last}')


def security_code():
    me = api('POST', '/api/login', {'name': env['WMS_NAME'], 'password': env['WMS_PASS']})
    r = api('POST', '/api/pair/invite', {'userId': me['user']['id'], 'password': env['WMS_PASS']}, token=me['token'])
    return re.sub(r'\D', '', str(r['code']))


def game_frames(since):
    """The newest game session started after since, and frames the server has sent from it (its stats)."""
    logs = os.path.join(os.environ.get('SMOKE_OUT', 'smoke-out'), 'data', 'logs')
    sid = None
    for f in sorted(os.listdir(logs)):
        for line in open(os.path.join(logs, f), errors='replace'):
            if 'wittyplay: game started' in line and line[5:24] >= since:
                m = re.search(r'session=(\S+)', line)
                sid = m.group(1) if m else sid
    if not sid:
        return None
    st = api('GET', f'/api/v1/modules/wittyplay/play/{sid}/stats')
    log('stats', sid, json.dumps(st)[:400])
    return st if (st.get('sentFps') or 0) > 0 and (st.get('width') or 0) > 0 else None


def step(name, fn):
    global n, log_file
    if only and name.split(':')[0] not in only:
        return
    n += 1
    base = os.path.join(OUT, f'{n:02d}-{re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")}')
    log_file = open(base + '.log', 'w')
    log('---', name)
    print(f'::group::android {kind}: {name}', flush=True)
    t = time.time()
    err = None
    try:
        fn()
    except Exception as e:  # noqa: BLE001: a failed step is reported, and the next runs
        err = e
    try:
        with open(base + '.png', 'wb') as f:
            f.write(subprocess.run(['adb', 'exec-out', 'screencap', '-p'], capture_output=True, timeout=30).stdout)
    except Exception as e:  # noqa: BLE001
        log('no picture:', e)
    log('on screen:', texts()[:40])
    print('::endgroup::', flush=True)
    if err:
        log('FAILED:', err)
        print(f'FAIL  android {kind}: {name}: {err}', flush=True)
        print(f'::error title=Smoke Android {kind}: {name}::{str(err)[:300]} (picture: {os.path.basename(base)}.png)', flush=True)
        failed.append(name)
    else:
        print(f'ok    android {kind}: {name} ({time.time() - t:.0f}s)', flush=True)
    log_file.close()
    log_file = None


# ---------------------------------------------------------------- the steps

def address():
    # This build, over whatever is there; a build signed with another key replaces it.
    if 'Success' not in adb('install', '-r', apk, check=False):
        adb('uninstall', PKG, check=False)
        adb('install', apk)
    launch(clear=True)
    tap('^Enter an address$', 60)
    wait("Enter your server's address|Server address", 20)
    type_into('address', EMU_URL.replace('http://', ''))
    sh('input keyevent KEYCODE_ENTER', check=False)
    if find('^Connect$'):
        tap('^Connect$')
    wait('Enter the security code|Security code|Sign in with a code', 60, 'the code screen')
    code = security_code()
    if any('EditText' in x['cls'] for x in nodes()):
        type_into('Security code|code', code)
        sh('input keyevent KEYCODE_ENTER', check=False)
    else:
        # The app's own number pad, as on a TV.
        # The digits typed so far show above the pad with the same text: press the pad's own key.
        for d in code:
            keys = [x for x in nodes() if x['text'] == d or x['desc'] == d]
            key = next((x for x in keys if x['clickable']), keys[-1] if keys else None)
            if not key:
                raise RuntimeError(f'no key {d} on the pad; on screen: {texts()[:30]}')
            b = key['b']
            sh(f'input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}')
            time.sleep(0.6)
        log('entered:', [t for t in texts() if 'digits entered' in t])
    if find('^Sign in$'):
        tap('^Sign in$')
    wait('Smoke Films|Smoke Film|Home', 90, 'the signed-in app')


def settings():
    if not find('^Settings$'):
        if TV:
            sh('input keyevent KEYCODE_MENU', check=False)
        else:
            tap('^You$', 20)
    tap('^Settings$', 20)
    wait('Settings', 20)
    wait('Server|Playback|Libraries|About|Account', 30, "settings' sections")
    launch()


def film():
    launch()
    tap('Smoke Film', 60)
    tap('^(Play|Resume)', 30)
    s = until('the server seeing this device stream the film', lambda: streaming(), 60)
    log('session:', s)
    time.sleep(3)
    sh('input keyevent KEYCODE_BACK', check=False)


def away():
    adb('root', check=False)
    time.sleep(3)
    adb('wait-for-device')
    # The device takes itself onto the server's list by itself while at home; wait for that.
    until("this device on the server's peer-to-peer list", lambda: api('GET', '/api/p2p/devices'), 90)
    sh(f'iptables -A OUTPUT -p tcp -d 10.0.2.2 --dport {PORT} -j REJECT')
    log(sh('iptables -S OUTPUT', check=False))
    launch()
    wait('Smoke Films|Smoke Film|Home', 120, 'the app signed in from away')
    tap('Smoke Film', 30)
    tap('^(Play|Resume)', 30)
    s = until('the server seeing this device stream from away (peer to peer)', lambda: streaming('p2p'), 90)
    log('session:', s)
    sh('input keyevent KEYCODE_BACK', check=False)


def game():
    launch()
    tap('^Games$', 60)
    if find('Which buttons should we show'):
        tap('Continue')
    tap('adjustris', 60)
    since = time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(time.time() - 5))
    tap('^(Play|Resume)', 30)
    until('the server sending this device frames of the game', lambda: game_frames(since), 120)
    time.sleep(3)  # for the picture


def link():
    inv = api('POST', '/api/v1/p2p/invite', {'password': env['WMS_PASS']})
    link = inv['link']
    log('link for', link.split('?')[0])
    launch(clear=True)
    tap('Join with a link or code|Connect from anywhere', 60)
    if find('Connect from anywhere') and not find('Invite link'):
        tap('Join with a link or code')
    type_into('Invite link|link', link)
    sh('input keyevent KEYCODE_ENTER', check=False)
    if find('^(Join|Connect)$'):
        tap('^(Join|Connect)$')
    wait('Smoke Films|Smoke Film|Home', 180, 'signed in with the link, from away')


# Peer to peer on, straight to this machine: the emulator reaches it, and nothing else is needed.
api('PUT', '/api/p2p/settings', {'accept': True, 'enabled': True, 'port': int(PORT) + 2, 'devicesOnly': True,
                                 'layers': {'dht': False, 'relay': False, 'holePunch': False, 'portMap': False, 'ipv6': False}})
step('address: Enter an address and a security code', address)
step('settings: Settings opens', settings)
step('film: the film plays', film)
step('away: from away, peer to peer, still signed in', away)
step('game: WittyPlay from away shows its frame', game)
if not TV:
    step('link: a fresh app joins with an invite link from away', link)
print(f"\nandroid {kind}: {'every step passed' if not failed else str(len(failed)) + ' failed: ' + ', '.join(failed)}")
sys.exit(1 if failed else 0)
