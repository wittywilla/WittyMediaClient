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
retried = []
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
        xml = sh('rm -f /sdcard/u.xml; uiautomator dump /sdcard/u.xml 2>&1 | grep -v "dumped to" ; cat /sdcard/u.xml 2>/dev/null', check=False)
        if '<' not in xml:
            log('no screen dump:', xml.strip()[:120])
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
    hint = next((x for x in ns if x['text'] == 'Got it'), None)
    if hint and any('Viewing full screen' in x['text'] or 'Getting back to the app' in x['text'] for x in ns):
        b = hint['b']
        sh(f'input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}')
        log('hint closed:', next((x['text'] for x in ns if 'Viewing full screen' in x['text'] or 'Getting back' in x['text']), ''))
        time.sleep(1)
        return True
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
    # A web page often has the same words twice (a label and its button): the one that can be pressed, on screen.
    hits.sort(key=lambda x: (not x['clickable'], (x['b'][2] - x['b'][0]) * (x['b'][3] - x['b'][1]) <= 0))
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
    # In short pieces with pauses: a busy emulator's text field loses characters typed faster than it redraws.
    s = s.replace("'", '')
    for i in range(0, len(s), 8):
        sh("input text '" + s[i:i + 8].replace(' ', '%s') + "'")
        time.sleep(0.4)


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
    old = len(f['text'])
    for attempt in range(3):
        # Empty the field (one keyevent command can carry many presses), then type.
        sh('input keyevent KEYCODE_MOVE_END')
        sh('input keyevent ' + ' '.join(['KEYCODE_DEL'] * (old + 2)), check=False)
        type_text(s)
        old = len(s) + 20
        now = next((x['text'] for x in nodes() if 'EditText' in x['cls'] and abs(x['b'][1] - b[1]) < 40), '')
        log('typed', len(s), 'characters; the field holds', len(now))
        if len(s) <= 20 or now == s or not now:
            return
        log('NOT THE SAME as what was typed, again:', now[:80])


def launch(clear=False):
    sh(f'am force-stop {PKG}')
    if clear:
        sh(f'pm clear {PKG}')
    sh(f'monkey -p {PKG} -c android.intent.category.{"LEANBACK_LAUNCHER" if TV else "LAUNCHER"} 1', check=False)
    time.sleep(3)
    past_welcome()


def in_front():
    """This app's window has the focus (not the launcher, not a system dialog)."""
    return PKG in sh('dumpsys window | grep -E "mCurrentFocus|mFocusedApp"', check=False)


def p2p_connected(since):
    """The server's log: a device connected peer to peer since then."""
    logs = os.path.join(os.environ.get('SMOKE_OUT', 'smoke-out'), 'data', 'logs')
    stamp = time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(since))
    for name in sorted(os.listdir(logs)):
        for l in open(os.path.join(logs, name), errors='replace'):
            if 'peer-to-peer: device connected' in l and l[5:24] >= stamp:
                return l.strip()[:200]
    return None


def new_session(since):
    """A sign-in made on the server since then, by a device other than the test's own."""
    return next((x for x in api('GET', '/api/sessions') if (x.get('createdAt') or 0) >= since - 5 and x.get('device') != 'smoke'), None)


def signed_in(secs, what, since=None):
    """Waits for the server's home (its film shows), going through the welcome on the way. A phone's Home keeps
    moving, so uiautomator can go long without a picture of it: then the server's word that this device signed in,
    with the app in front and the welcome gone, is enough."""
    end = time.time() + secs
    since = since or (time.time() - 20)
    while not find('Smoke Film'):
        past_welcome()
        s = new_session(since) or p2p_connected(since)
        if s and in_front() and not on_welcome() and not find('digits entered|Choose a server'):
            log('signed in, says the server:', s)
            return
        if time.time() > end:
            raise RuntimeError(f'waited {secs}s for {what}; on screen: {texts()[:30]}')
        time.sleep(1)


def on_welcome():
    """The first-run look: its title, or (once that has scrolled away) its grid of two or more "… layout" tiles,
    which the colours page has too and Home never does."""
    tiles = sum(1 for x in nodes() if re.match(r'^[\w ]+ layout$', x['text'] or x['desc']))
    return tiles >= 2 or bool(find('Choose a layout|Choose colours|Your look is set'))


def past_welcome():
    """A new sign-in first asks for a layout, then colours: the first of each is fine. The colours page is a long
    list with its button at the end, so the phone flings."""
    for _ in range(40):
        if not on_welcome():
            return
        btn = find('^(Use this|Continue|Next|Done)$')
        if btn:
            b = btn['b']
            sh(f'input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}')
            log('welcome:', btn['text'])
        elif TV:
            sh('input keyevent KEYCODE_DPAD_DOWN')
        else:
            sh('input swipe 540 2000 540 300 120')
        time.sleep(1)


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


def game_started(since):
    logs = os.path.join(os.environ.get('SMOKE_OUT', 'smoke-out'), 'data', 'logs')
    return any('msg="game session started"' in l and l[5:24] >= since
               for name in os.listdir(logs) for l in open(os.path.join(logs, name), errors='replace'))


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
    except Exception as e:  # noqa: BLE001: tried once more, as an emulator on a busy runner has slow moments
        log('FIRST TRY FAILED:', e)
        try:
            with open(base + '-first-try.png', 'wb') as f:
                f.write(subprocess.run(['adb', 'exec-out', 'screencap', '-p'], capture_output=True, timeout=30).stdout)
        except Exception:  # noqa: BLE001
            pass
        print(f'android {kind}: {name}: failed once ({str(e)[:160]}); trying again', flush=True)
        try:
            fn()
            retried.append(name)
        except Exception as e2:  # noqa: BLE001: a failed step is reported, and the next runs
            err = e2
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
        tap('^(You|smoke|S)$', 30)
    # A TV's profile page is its settings (Account, Playback, Your devices…); a phone's You tab leads to them.
    if not find('^ACCOUNT$|^Account$'):
        tap('^Settings$', 30)
    wait('Server|Playback|Libraries|About|Account|ACCOUNT', 30, "settings' sections")
    launch()


def film():
    launch()
    play_film()
    log('playing:', until('the film playing', playing, 60))
    time.sleep(3)
    sh('input keyevent KEYCODE_BACK', check=False)


def wittytv():
    """Live TV on a phone (WittyMediaClient#160): the website's guide in the shell's web view, laid out round the app's
    bars, and its Watch full screen over them. Measured from the screen dump, in dp."""
    launch()
    tap('^Live TV$', 30)
    wait('^Watch full screen$', 90, "Live TV's guide")
    dp = int(re.findall(r'\d+', sh('wm density'))[-1]) / 160
    tall = int(re.findall(r'(\d+)x(\d+)', sh('wm size'))[-1][1])

    def page():
        webs = [x for x in nodes() if x['cls'] == 'android.webkit.WebView' and x['b'][3] > x['b'][1]]
        if not webs:
            raise RuntimeError('no web view on screen')
        return max(webs, key=lambda x: (x['b'][2] - x['b'][0]) * (x['b'][3] - x['b'][1]))['b']
    b = page()
    log('web view (dp):', [round(v / dp) for v in b], 'screen', round(tall / dp))
    # Right under the shell's bar or tabs (status bar, 52 and 8): no empty band, which was about 120 more.
    if b[1] / dp > 140:
        raise RuntimeError(f'the guide starts {b[1] / dp:.0f} dp down, an empty band under the bar')
    # Clear of the system's navigation bar at the foot.
    if b[3] >= tall - 8 * dp:
        raise RuntimeError('the guide runs under the navigation bar')
    # The programme's buttons wrap instead of scrolling out of sight.
    for label in ('Channel up', 'More about this programme', 'The whole day on this channel'):
        x = find('^' + label + '$')
        if not x or x['b'][2] - x['b'][0] < 40 * dp or x['b'][3] - x['b'][1] < 40 * dp:
            raise RuntimeError(f'{label!r} is not on screen at its full size: {x and x["b"]}')
    # Watch full screen has the whole screen, over the shell's top strip and floating bar.
    tap('^Watch full screen$', 30)
    time.sleep(4)
    if find('^Got it$'):
        tap('^Got it$', 10)
    # The screen can't be dumped while the picture plays (uiautomator never sees it idle), so the window says it: the
    # system's bars hidden for the player, and the phone turned to landscape for it (WatchOrientation.kt).
    def full_screen():
        win = sh('dumpsys window displays', check=False)
        bars = re.search(r'type=statusBars[^\n]*visible=(true|false)', win)
        turned = re.search(r'mRotation=ROTATION_(\d+)', win)
        return (bars and bars.group(1) == 'false') and turned and int(turned.group(1)) in (90, 270)
    until('the player over the whole screen, in landscape', full_screen, 30)
    log('full screen: system bars hidden, landscape')
    # Back comes back to the guide, not out of the app.
    sh('input keyevent KEYCODE_BACK', check=False)
    wait('^Watch full screen$', 30, 'the guide again after Back')


def rotation():
    """A phone turns to landscape for a film and back to portrait when the player closes; the player's Rotate button
    turns it either way, and none of it starts the film again (WittyMediaClient#160)."""
    def turned():
        m = re.search(r'mRotation=ROTATION_(\d+)', sh('dumpsys window displays', check=False))
        return int(m.group(1)) if m else -1

    def position():
        m = re.search(r'position=(\d+)', sh('dumpsys media_session', check=False))
        return int(m.group(1)) if m else -1
    sh('settings put system accelerometer_rotation 0', check=False)
    sh('settings put system user_rotation 0', check=False)
    launch()
    play_film()
    until('the film playing', playing, 60)
    until('landscape for the film', lambda: turned() in (90, 270), 20)
    start = position()

    def controls():
        # A short drag shows the player's controls without the tap that would pause the film.
        sh('input swipe 700 700 780 700 150', check=False)
        time.sleep(0.5)
    controls()
    tap('^Rotate to portrait$', 20)
    until('portrait when asked', lambda: turned() == 0, 20)
    controls()
    tap('^Rotate to landscape$', 20)
    until('landscape again when asked', lambda: turned() in (90, 270), 20)
    time.sleep(3)
    later = position()
    log('position before and after turning (ms):', start, later)
    if start >= 0 and later >= 0 and later < start:
        raise RuntimeError(f'the film went back from {start} to {later} ms while turning')
    sh('input keyevent KEYCODE_BACK', check=False)
    until('portrait after the player closes', lambda: turned() == 0, 20)


def away():
    # The device takes itself onto the server's list by itself while at home; wait for that.
    until("this device on the server's peer-to-peer list", lambda: api('GET', '/api/p2p/devices'), 90)
    # Away: the server's web port stops answering the emulator, at every address (its 10.0.2.2, and the address it
    # found the server at on the network). That's this machine's firewall (Android TV images don't allow adb root),
    # aimed at the emulator alone: its process goes in a cgroup of its own, and only that cgroup is refused. The
    # server, its modules' helpers (WittyPlay's restarts after a quiet spell, and talks to the server on that port)
    # and this test are left alone, as is the peer-to-peer port.
    # Every emulator process: qemu, and netsimd, which carries a newer emulator's network.
    pids = subprocess.run(['pgrep', '-f', 'qemu-system|netsimd|emulator/emulator'], capture_output=True, text=True).stdout.split()
    pids = [p for p in pids if p != str(os.getpid())]
    if not pids:
        raise RuntimeError('no emulator process to send away')
    cg = '/sys/fs/cgroup/smoke-emulator'
    subprocess.run(['sudo', '-n', 'mkdir', '-p', cg], check=True)
    for pid in pids:
        subprocess.run(['sudo', '-n', 'sh', '-c', f'echo {pid} > {cg}/cgroup.procs'], check=True)
    r = subprocess.run(['sudo', '-n', 'iptables', '-I', 'OUTPUT', '-p', 'tcp', '--dport', PORT, '-m', 'cgroup', '--path', 'smoke-emulator',
                        '-j', 'REJECT'], capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError('could not shut the address: ' + r.stderr)
    names = subprocess.run(['ps', '-o', 'pid=,comm=', '-p', ','.join(pids)], capture_output=True, text=True).stdout.split()
    log('away: port', PORT, 'refused to the emulator:', ' '.join(names))
    # From inside the emulator, the server's web port must not answer any more.
    probe = sh(f'nc -w 3 10.0.2.2 {PORT} </dev/null && echo REACHED || echo REFUSED', check=False)
    log('from the emulator:', probe.strip())
    if 'REACHED' in probe:
        raise RuntimeError("the emulator still reaches the server's web port: it isn't away")
    if subprocess.run(['curl', '-s', '-m', '3', '-o', '/dev/null', f'http://127.0.0.1:{PORT}/api/health']).returncode != 0:
        raise RuntimeError('the server stopped answering this machine too: the firewall caught more than the emulator')
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
    # WittyPlay's helper may be starting again after a quiet spell: wait for it before pressing again. No Enter on a
    # phone: the focus can be on the page's "How to get back to the app", whose help would cover Play.
    for again in range(2):
        if until('playing', lambda: game_started(since), 30):
            break
        log('the game has not started; pressing Play again')
        if find('^(Play|Resume)'):
            tap('^(Play|Resume)', 5)
        elif TV:
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
if not TV:
    step('wittytv: Live TV on a phone, round the app bars, and full screen over them', wittytv)
    step('rotation: a film turns to landscape, Rotate turns it, closing turns back to portrait', rotation)
step('away: from away, peer to peer, still signed in', away)
step('game: WittyPlay from away shows its frame', game)
if not TV:
    step('link: a fresh app joins with an invite link from away', link)
print(f"\nandroid {kind}: {'every step passed' if not failed else str(len(failed)) + ' failed: ' + ', '.join(failed)}")
if retried:
    print(f"android {kind}: passed on a second try: {', '.join(retried)}")
    print(f"::warning title=Smoke Android {kind}::passed on a second try: {', '.join(retried)}")
sys.exit(1 if failed else 0)
