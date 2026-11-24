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
  found      the server found on the network, chosen, then a security code: signed in
  address    Enter an address, then a security code from the server: signed in
  settings   Settings opens
  film       the film plays: the app's media session says so
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
    for _ in range(10):
        # The old picture goes first: a dump that fails (a screen still moving) must not leave it to be read.
        xml = sh('rm -f /sdcard/u.xml; uiautomator dump /sdcard/u.xml >/dev/null && cat /sdcard/u.xml', check=False)
        try:
            root = ET.fromstring(xml[xml.index('<'):])
            break
        except (ValueError, ET.ParseError):
            time.sleep(0.5)
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
    past_welcome()


def signed_in(secs, what):
    """Waits for the server's home (its film shows), going through the welcome on the way."""
    end = time.time() + secs
    while not find('Smoke Film'):
        past_welcome()
        if time.time() > end:
            raise RuntimeError(f'waited {secs}s for {what}; on screen: {texts()[:30]}')
        time.sleep(1)


def past_welcome():
    """A new sign-in first asks for a layout, then colours: the first of each is fine."""
    for _ in range(16):
        # Its title, or (once the title has scrolled away) its grid: two or more "… layout" tiles, which Home never has.
        tiles = sum(1 for x in nodes() if re.match(r'^[\w ]+ layout$', x['text'] or x['desc']))
        if tiles < 2 and not find('Choose a layout|Choose colours|Your look is set'):
            return
        btn = find('^(Use this|Continue|Next|Done)$')
        if btn:
            b = btn['b']
            sh(f'input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}')
            log('welcome:', btn['text'])
        elif TV:
            sh('input keyevent KEYCODE_DPAD_DOWN')
        else:
            sh('input swipe 540 1800 540 600 300')
        time.sleep(1.5)


def streaming(via=None):
    for s in api('GET', '/api/sessions'):
        if s.get('streaming') and 'smoke' not in (s.get('device') or '') and (via is None or s.get('via') == via):
            return s
    return None


def playing():
    """The app's player says it is playing (its media session), or the server sees it streaming."""
    out = sh('dumpsys media_session', check=False)
    if re.search(r'state=(PLAYING|3)\b', out):
        return 'media session playing'
    return streaming()


def play_film():
    tap('Smoke Film', 60)
    tap('^(Play|Resume)', 30)
    # A tap moves the focus on a TV; OK presses what has it.
    if TV and not until('playing', playing, 8):
        sh('input keyevent KEYCODE_DPAD_CENTER')


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
    if what == 'playing':
        return None
    raise RuntimeError(f'waited {secs}s for {what}; last: {last}')


def security_code():
    me = api('POST', '/api/login', {'name': env['WMS_NAME'], 'password': env['WMS_PASS']})
    r = api('POST', '/api/pair/invite', {'userId': me['user']['id'], 'password': env['WMS_PASS']}, token=me['token'])
    return re.sub(r'\D', '', str(r['code']))


def game_frames(since):
    """The newest game session started after since, and the server streaming it to this device: a viewer connected,
    the video being encoded, and the app's own reports of the network coming back (which only a player receiving
    the pictures sends). WittyPlay's stats for the session too, where it gives them."""
    logs = os.path.join(os.environ.get('SMOKE_OUT', 'smoke-out'), 'data', 'logs')
    lines = []
    for name in sorted(os.listdir(logs)):
        lines += [l for l in open(os.path.join(logs, name), errors='replace') if 'cat=games' in l and l[5:24] >= since]
    sid = None
    for l in lines:
        if 'msg="game session started"' in l or 'wittyplay: game started' in l:
            m = re.search(r'session=(\S+)', l)
            sid = m.group(1) if m else sid
    if not sid:
        return None
    mine = [l for l in lines if f'session={sid}' in l]
    seen = {k: any(k in l for l in mine) for k in ('viewer connected', 'encoding video', 'matching the video to the network')}
    try:
        st = api('GET', f'/api/v1/modules/wittyplay/play/{sid}/stats')
        log('stats', sid, json.dumps(st)[:300])
        if (st.get('sentFps') or 0) > 0:
            return st
    except Exception as e:  # noqa: BLE001: the log is enough
        log('no stats:', e)
    log('game', sid, seen)
    return seen if all(seen.values()) else None

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

def install():
    # This build, over whatever is there; a build signed with another key replaces it.
    if 'Success' not in adb('install', '-r', apk, check=False):
        adb('uninstall', PKG, check=False)
        adb('install', apk)


def enter_code():
    wait('Enter the security code|Security code|Sign in with a code', 60, 'the code screen')
    code = security_code()
    if any('EditText' in x['cls'] for x in nodes()):
        type_into('Security code|code', code)
        sh('input keyevent KEYCODE_ENTER', check=False)
    else:
        # The app's own number pad. The digits typed so far show above it with the same text: press the pad's key.
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
    signed_in(90, 'the signed-in app')


def found():
    install()
    launch(clear=True)
    # The server announces itself on this machine's network, which the emulator's network reaches.
    for _ in range(3):
        tap('Found on your network', 60)
        if find('Enter the security code|Security code|Sign in with a code|digits entered'):
            break
        time.sleep(2)
    enter_code()


def address():
    install()
    launch(clear=True)
    # The list moves when a server is found: if the tap landed on something else, try again.
    for _ in range(3):
        tap('^Enter an address$', 60)
        if find("Enter your server's address|Server address"):
            break
        sh('input keyevent KEYCODE_BACK', check=False)
        time.sleep(2)
    wait("Enter your server's address|Server address", 20)
    type_into('address', EMU_URL.replace('http://', ''))
    sh('input keyevent KEYCODE_ENTER', check=False)
    if find('^Connect$'):
        tap('^Connect$')
    enter_code()


def settings():
    launch()
    if not find('^Settings$'):
        # The phone's You tab; on a TV, the profile at the end of the top bar.
        tap('^You$' if not TV else '^smoke$', 30)
    # A TV's profile page is its settings (Account, Playback, Your devices…); a phone's You tab leads to them.
    if not (TV and find('^ACCOUNT$|^Account$')):
        tap('^Settings$', 30)
    wait('Server|Playback|Libraries|About|Account|ACCOUNT', 30, "settings' sections")
    launch()


def film():
    launch()
    play_film()
    log('playing:', until('the film playing', playing, 60))
    time.sleep(3)
    sh('input keyevent KEYCODE_BACK', check=False)


def away():
    global URL
    # The device takes itself onto the server's list by itself while at home; wait for that.
    until("this device on the server's peer-to-peer list", lambda: api('GET', '/api/p2p/devices'), 90)
    # Away: the server's web port stops answering every program on this machine but root's, at every address
    # (the emulator's 10.0.2.2, and the address it found the server at on the network). That's this machine's
    # firewall, as Android TV images don't allow adb root. The test itself goes on through a forwarder run as
    # root. The peer-to-peer port is left alone.
    side = str(int(PORT) + 7)
    subprocess.Popen(['sudo', '-n', 'socat', f'TCP-LISTEN:{side},bind=127.0.0.1,fork,reuseaddr', f'TCP:127.0.0.1:{PORT}'],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    r = subprocess.run(['sudo', '-n', 'iptables', '-I', 'OUTPUT', '-p', 'tcp', '--dport', PORT, '-m', 'owner', '!', '--uid-owner', '0',
                        '-j', 'REJECT'], capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError('could not shut the address: ' + r.stderr)
    URL = f'http://127.0.0.1:{side}'
    log('away: port', PORT, 'refused to everyone but root; the test now asks', URL)
    if subprocess.run(['curl', '-s', '-m', '3', '-o', '/dev/null', f'http://127.0.0.1:{PORT}/api/health']).returncode == 0:
        raise RuntimeError('the server still answers at home')
    launch()
    signed_in(120, 'the app signed in from away')
    play_film()
    log('playing:', until('the film playing from away', playing, 90))
    p2p = until('the server seeing this device come peer to peer',
                lambda: next((x for x in api('GET', '/api/sessions') if x.get('via', '').startswith('p2p')), None), 30)
    log('session:', p2p)
    sh('input keyevent KEYCODE_BACK', check=False)


def game():
    launch()
    tap('^Games$', 60)
    if find('Which buttons should we show'):
        tap('Continue')
    tap('adjustris', 60)
    since = time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime(time.time() - 5))
    tap('^(Play|Resume)', 30)
    if TV and not game_frames(since):
        time.sleep(3)
        sh('input keyevent KEYCODE_DPAD_CENTER')
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
    signed_in(180, 'signed in with the link, from away')


# Peer to peer on, straight to this machine: the emulator reaches it, and nothing else is needed.
api('PUT', '/api/p2p/settings', {'accept': True, 'enabled': True, 'port': int(PORT) + 2, 'devicesOnly': True,
                                 'layers': {'dht': False, 'relay': False, 'holePunch': False, 'portMap': False, 'ipv6': False}})
step('found: the server found on the network, and its security code', found)
step('address: Enter an address and a security code', address)
step('settings: Settings opens', settings)
step('film: the film plays', film)
step('away: from away, peer to peer, still signed in', away)
step('game: WittyPlay from away shows its frame', game)
if not TV:
    step('link: a fresh app joins with an invite link from away', link)
print(f"\nandroid {kind}: {'every step passed' if not failed else str(len(failed)) + ' failed: ' + ', '.join(failed)}")
sys.exit(1 if failed else 0)
