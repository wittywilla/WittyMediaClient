const test = require('node:test')
const assert = require('node:assert')
const {
  CONNECT_PAGE, BAR_PAGE, isConnectUrl, pageFile, navigation, outsideAddress, budget, downloadAllowed, readJson, whyFailed, isCertificateCode,
  cleanName, cleanMessage, validCode, validToken, validPairCode, validDeviceSecret, serverPage, pollSeconds, menuPoint, MAX_ANSWER_BYTES,
} = require('../guards.js')

test('only the app\'s own connect page counts as the connect page', () => {
  assert.ok(isConnectUrl(CONNECT_PAGE))
  assert.ok(isConnectUrl(`${CONNECT_PAGE}?lost=1#top`), 'with a query it is still the same page')
  assert.ok(!isConnectUrl(BAR_PAGE))
  assert.ok(!isConnectUrl(CONNECT_PAGE.replace('index', 'other')))
  assert.ok(!isConnectUrl('file:///D:/anywhere/connect/index.html'), 'a file with the same names')
  assert.ok(!isConnectUrl('file://attacker/share/connect/index.html'), 'a network share')
  assert.ok(!isConnectUrl('http://192.168.1.5:9797/connect/index.html'))
  assert.ok(!isConnectUrl('http://connect/index.html'))
  assert.ok(!isConnectUrl('not a url'))
})

test('the app\'s scheme only reaches files in its two folders', () => {
  assert.deepStrictEqual(pageFile(CONNECT_PAGE), { folder: 'connect', name: 'index.html', type: 'text/html; charset=utf-8' })
  assert.strictEqual(pageFile(`${CONNECT_PAGE}?lost=1`).name, 'index.html')
  assert.strictEqual(pageFile('wittymedia-app://connect/connect.css').type, 'text/css; charset=utf-8')
  assert.strictEqual(pageFile('wittymedia-app://titlebar/titlebar.js').folder, 'titlebar')
  // Climbing out resolves before it gets here, and what's left is still looked for in that folder.
  assert.strictEqual(pageFile('wittymedia-app://connect/../main.js').folder, 'connect')
  assert.strictEqual(pageFile('wittymedia-app://connect/%2e%2e/main.js').folder, 'connect')
  for (const bad of [
    'wittymedia-app://connect/..%2fmain.js', 'wittymedia-app://connect/..%5cmain.js', 'wittymedia-app://connect/a/b.js', 'wittymedia-app://other/main.js', 'wittymedia-app://connect/secret.json',
    'wittymedia-app://connect/', 'wittymedia-app://main.js/', 'file:///connect/index.html', 'http://connect/index.html', 'not a url',
  ]) assert.strictEqual(pageFile(bad), null, bad)
})

test('only the server\'s own origin stays in the app', () => {
  const server = 'http://192.168.1.5:9797'
  const on = { server, lastServer: server }
  assert.strictEqual(navigation(`${server}/settings`, on), 'allow')
  assert.strictEqual(navigation('https://example.com/', on), 'outside')
  assert.strictEqual(navigation('http://192.168.1.5:9798/', on), 'outside', 'another port is another origin')
  assert.strictEqual(navigation(CONNECT_PAGE, on), 'outside', 'a page never goes to the connect page itself')
  assert.strictEqual(outsideAddress(CONNECT_PAGE), '', 'and that doesn\'t become a link to open')
})

test('a redirect never opens anything outside, and stays in the app only for the server', () => {
  const server = 'http://192.168.1.5:9797'
  const on = { server, lastServer: server, redirect: true }
  assert.strictEqual(navigation(`${server}/home`, on), 'allow')
  assert.strictEqual(navigation('https://example.com/', on), 'stop')
  assert.strictEqual(navigation('https://example.com/', { server: '', lastServer: server, redirect: true }), 'stop', 'with no server open')
})

test('a load still going when someone left that server is stopped, not opened', () => {
  const server = 'http://192.168.1.5:9797'
  assert.strictEqual(navigation(`${server}/home`, { server: '', lastServer: server }), 'stop')
  assert.strictEqual(navigation(`${server}/home`, { server: '', lastServer: '' }), 'outside')
})

test('only web and mail links can leave the app', () => {
  assert.strictEqual(outsideAddress('https://example.com/a?b=1'), 'https://example.com/a?b=1')
  assert.strictEqual(outsideAddress('mailto:someone@example.com'), 'mailto:someone@example.com')
  for (const bad of ['file:///C:/Windows/System32/calc.exe', 'javascript:alert(1)', 'ms-settings:', 'smb://host/share', 'not a url', '']) {
    assert.strictEqual(outsideAddress(bad), '', bad)
  }
  assert.strictEqual(outsideAddress(`https://example.com/${'a'.repeat(3000)}`), '', 'too long for a command line')
})

test('a page can only open so many things in a while', () => {
  let t = 1000
  const may = budget(2, 100, () => t)
  assert.ok(may())
  assert.ok(may())
  assert.ok(!may())
  t += 101
  assert.ok(may())
})

test('downloads come from the server that is open, and nowhere else', () => {
  const server = 'http://192.168.1.5:9797'
  assert.ok(downloadAllowed(`${server}/api/items/1/file`, server))
  assert.ok(downloadAllowed(`blob:${server}/3b1f`, server), 'a file its own script made')
  assert.ok(!downloadAllowed('https://example.com/setup.exe', server))
  assert.ok(!downloadAllowed('blob:https://example.com/3b1f', server))
  assert.ok(!downloadAllowed('data:text/plain,hello', server))
  assert.ok(!downloadAllowed('file:///C:/secret.txt', server))
  assert.ok(!downloadAllowed(`${server}/a`, ''), 'no server open')
  assert.ok(!downloadAllowed('not a url', server))
})

test('reads an answer up to its limit, and no further', async () => {
  assert.deepStrictEqual(await readJson(new Response('{"a":1}')), { a: 1 })
  await assert.rejects(readJson(new Response('not json')), SyntaxError)
  await assert.rejects(readJson(new Response('')), SyntaxError)
  const stated = new Response('{}', { headers: { 'content-length': String(MAX_ANSWER_BYTES + 1) } })
  await assert.rejects(readJson(stated), (err) => err.tooBig === true)
  // One that doesn't say how long it is, and doesn't stop.
  let chunks = 0
  const endless = new ReadableStream({
    pull(c) {
      chunks++
      c.enqueue(new Uint8Array(16 * 1024))
    },
  })
  await assert.rejects(readJson(new Response(endless)), (err) => err.tooBig === true)
  assert.ok(chunks < 50, 'stopped reading early')
})

test('says what went wrong in terms the connect screen knows', () => {
  assert.strictEqual(whyFailed(new SyntaxError('bad')), 'not-server')
  assert.strictEqual(whyFailed({ tooBig: true }), 'not-server')
  assert.strictEqual(whyFailed(new Error('net::ERR_CERT_AUTHORITY_INVALID')), 'certificate')
  assert.strictEqual(whyFailed(Object.assign(new Error('fetch failed'), { cause: new Error('net::ERR_SSL_PROTOCOL_ERROR') })), 'certificate')
  assert.strictEqual(whyFailed(new Error('net::ERR_CONNECTION_REFUSED')), 'unreachable')
  assert.strictEqual(whyFailed(undefined), 'unreachable')
  assert.ok(isCertificateCode(-202))
  assert.ok(!isCertificateCode(-3))
  assert.ok(!isCertificateCode(-106))
})

test('what comes from a server is cleaned before it is kept or shown', () => {
  assert.strictEqual(cleanName('A\u0007B\n'), 'AB')
  assert.strictEqual(cleanName(''), 'WittyMediaServer')
  assert.strictEqual(cleanName({ an: 'object' }), '[object Object]')
  assert.strictEqual(cleanName('x'.repeat(500)).length, 80)
  assert.strictEqual(cleanMessage('y'.repeat(5000)).length, 300)
  assert.strictEqual(cleanMessage(undefined), '')
})

test('a code is six digits and a token can\'t break out of its cookie', () => {
  assert.ok(validCode('012345'))
  for (const bad of ['12345', '1234567', '12345a', '١٢٣٤٥٦', 123456, null]) assert.ok(!validCode(bad), String(bad))
  assert.ok(validToken('abc123._-~='))
  for (const bad of ['', 'a;b', 'a b', 'a,b', 'a"b', 'a\nb', 'x'.repeat(513), 7, {}, null, undefined]) assert.ok(!validToken(bad), String(bad))
})

test('a code to show and the secret behind it are only ever what the server sends', () => {
  for (const good of ['BCDF-GHJK', 'BCDFGHJK', 'AB12-CD34']) assert.ok(validPairCode(good), good)
  for (const bad of ['', 'bcdf-ghjk', 'BCDF GHJK', 'BCDF-GHJK\n', '<b>BCDF</b>', 'A'.repeat(30), 7, null]) assert.ok(!validPairCode(bad), String(bad))
  assert.ok(validDeviceSecret('0123456789abcdef'.repeat(4)))
  for (const bad of ['', 'short', 'a'.repeat(129), 'a b'.repeat(20), 7, null]) assert.ok(!validDeviceSecret(bad), String(bad))
})

test('the page to approve a code at is on that server, whatever the server says', () => {
  const origin = 'http://10.0.0.2:9797'
  assert.strictEqual(serverPage(origin, '/pair?code=BCDF-GHJK', '/pair'), 'http://10.0.0.2:9797/pair?code=BCDF-GHJK')
  for (const away of ['//evil.example/pair', '/\\evil.example/pair', 'https://evil.example/pair', 'pair', '/a b', 7, null, `/${'x'.repeat(300)}`]) {
    assert.strictEqual(serverPage(origin, away, '/pair'), 'http://10.0.0.2:9797/pair', String(away))
  }
})

test('asking again waits as long as the server asks, within reason', () => {
  assert.strictEqual(pollSeconds(3), 3)
  assert.strictEqual(pollSeconds(600), 60)
  for (const odd of [0, -1, 1.5, '3', null, undefined]) assert.strictEqual(pollSeconds(odd), 3, String(odd))
  assert.strictEqual(pollSeconds(undefined, 0), 0)
})

test('a menu position is only used if it is in the window', () => {
  assert.deepStrictEqual(menuPoint({ x: 10, y: 32 }, 800, 600), { x: 10, y: 32 })
  for (const bad of [undefined, null, {}, { x: '1', y: 2 }, { x: 1.5, y: 2 }, { x: -1, y: 2 }, { x: 900, y: 2 }, { x: 1, y: 900 }]) {
    assert.deepStrictEqual(menuPoint(bad, 800, 600), {}, JSON.stringify(bad))
  }
})
