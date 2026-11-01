// Checks that an address is answered by the server we think it is: it has to
// sign a fresh random value with its Ed25519 key (docs/CLIENT-API.md, "Server identity").
const crypto = require('crypto')

// The fixed DER header that turns a raw 32-byte Ed25519 public key into a key object.
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex')
const KEY_BYTES = 32
const SIGNATURE_BYTES = 64
const MAX_SERVER_ID = 128

function signedBytes(serverId, nonce) {
  return Buffer.from(`WittyMediaServer identity v1\n${serverId}\n${nonce}`, 'utf8')
}

// Is this answer really signed by the key it names? An answer comes from an address
// nobody has proved yet, so each part has to be what it should be before it is used.
function signatureValid(answer, nonce) {
  if (!answer || answer.algorithm !== 'ed25519') return false
  if (typeof answer.serverId !== 'string' || !answer.serverId || answer.serverId.length > MAX_SERVER_ID) return false
  if (typeof answer.publicKey !== 'string' || typeof answer.signature !== 'string') return false
  try {
    const raw = Buffer.from(answer.publicKey, 'base64')
    const signature = Buffer.from(answer.signature, 'base64')
    if (raw.length !== KEY_BYTES || signature.length !== SIGNATURE_BYTES) return false
    const key = crypto.createPublicKey({ key: Buffer.concat([ED25519_SPKI_PREFIX, raw]), format: 'der', type: 'spki' })
    return crypto.verify(null, signedBytes(answer.serverId, nonce), key, signature)
  } catch {
    return false
  }
}

// What an identity answer means, given the saved servers:
//   bad        the signature doesn't hold: nothing about it can be believed
//   new        never seen before
//   same       a key we remembered: that proves who it is, wherever it answers
//   different  we remembered another key at this address or for this ID: possibly a look-alike
function judge(answer, nonce, url, saved) {
  if (!signatureValid(answer, nonce)) return 'bad'
  const pinned = (saved || []).filter((s) => s.publicKey)
  if (pinned.some((s) => s.publicKey === answer.publicKey)) return 'same'
  return pinned.some((s) => s.url === url || s.serverId === answer.serverId) ? 'different' : 'new'
}

// A short form of the key for people to compare, worked out here rather than
// believed from the answer: a look-alike could claim any fingerprint it liked.
function fingerprintOf(publicKey) {
  const hash = crypto.createHash('sha256').update(Buffer.from(String(publicKey), 'base64')).digest('hex').toUpperCase()
  return `${hash.slice(0, 4)}-${hash.slice(4, 8)}-${hash.slice(8, 12)}`
}

// A server with no identity route. Only a server we hold no key for can be an
// older one; for a known server this may be something avoiding the check.
function judgeMissing(url, saved) {
  return (saved || []).some((s) => s.publicKey && s.url === url) ? 'bad' : 'none'
}

// May a sign-in kept for this address go to the server that just gave this proof?
// A remembered key is only good for the sign-in made with it: another remembered
// server turning up at this address is still not the one who was signed in here.
function signInFits(url, proof, saved) {
  const here = (saved || []).find((s) => s.url === url)
  if (!here) return false
  if (here.publicKey) return proof.state === 'same' && proof.publicKey === here.publicKey
  return proof.state === 'new' || proof.state === 'none'
}

// May the app carry on with this server now? `shown` is what the person last saw for
// it. Each check asks the server again, and the answer has to be the one they were
// looking at when they typed a code or said to trust it. Otherwise, they look again.
//   ok, unreachable, refused, changed
function admit(url, proof, shown, trust = false) {
  if (proof.state === 'unreachable') return 'unreachable'
  if (proof.state === 'bad') return 'refused'
  if (!shown || shown.url !== url || shown.state !== proof.state || shown.publicKey !== (proof.publicKey || '')) return 'changed'
  // Another key at a known server is only ever accepted because the person said so.
  if (proof.state === 'different' && trust !== true) return 'refused'
  return 'ok'
}

function newNonce() {
  return crypto.randomBytes(32).toString('base64')
}

module.exports = { signatureValid, judge, judgeMissing, signInFits, admit, fingerprintOf, newNonce, signedBytes }
