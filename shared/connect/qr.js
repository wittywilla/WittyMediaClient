// A QR code for an address, so a phone can open it: which squares are dark. Byte mode and
// the middle level of error correction (M), versions 1 to 10, which is up to 213 bytes and far
// more than an address here needs. Written from the standard (ISO/IEC 18004) because the
// connect screen loads nothing from outside itself. Loaded as a plain script and by Node's tests.
(function (root) {
  const MAX_VERSION = 10
  // For level M: error correction codewords in each block, and how many blocks, by version.
  const ECC_PER_BLOCK = [10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
  const BLOCKS = [1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
  const LEVEL_M = 0 // its two bits in the format information

  // Multiplication in GF(256), modulo x^8 + x^4 + x^3 + x^2 + 1.
  function multiply(a, b) {
    let product = 0
    for (let bit = 7; bit >= 0; bit--) {
      product = (product << 1) ^ ((product >>> 7) * 0x11d)
      if ((b >>> bit) & 1) product ^= a
    }
    return product & 0xff
  }

  // The generator polynomial for so many error correction codewords, highest power left out.
  function generator(degree) {
    const poly = new Array(degree).fill(0)
    poly[degree - 1] = 1
    let root = 1
    for (let i = 0; i < degree; i++) {
      for (let j = 0; j < degree; j++) {
        poly[j] = multiply(poly[j], root)
        if (j + 1 < degree) poly[j] ^= poly[j + 1]
      }
      root = multiply(root, 2)
    }
    return poly
  }

  function errorCorrection(data, poly) {
    const rest = poly.map(() => 0)
    for (const byte of data) {
      const factor = byte ^ rest.shift()
      rest.push(0)
      for (let i = 0; i < poly.length; i++) rest[i] ^= multiply(poly[i], factor)
    }
    return rest
  }

  // How many modules carry data and error correction, once the fixed patterns are placed.
  function dataModules(version) {
    let n = (16 * version + 128) * version + 64
    if (version >= 2) {
      const aligns = Math.floor(version / 7) + 2
      n -= (25 * aligns - 10) * aligns - 55
      if (version >= 7) n -= 36
    }
    return n
  }

  const capacity = (version) => Math.floor(dataModules(version) / 8) - ECC_PER_BLOCK[version - 1] * BLOCKS[version - 1]

  function alignmentCentres(version) {
    if (version === 1) return []
    const size = version * 4 + 17
    const count = Math.floor(version / 7) + 2
    const step = Math.ceil((version * 4 + 4) / (count * 2 - 2)) * 2
    const centres = [6]
    for (let at = size - 7; centres.length < count; at -= step) centres.splice(1, 0, at)
    return centres
  }

  function utf8(text) {
    const bytes = []
    const encoded = unescape(encodeURIComponent(text)) // one character per byte, in old browsers too
    for (let i = 0; i < encoded.length; i++) bytes.push(encoded.charCodeAt(i))
    return bytes
  }

  // The data codewords: mode, length, the bytes, then the standard padding.
  function codewords(bytes, version) {
    const bits = []
    const put = (value, length) => { for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1) }
    put(4, 4)
    put(bytes.length, version < 10 ? 8 : 16)
    for (const b of bytes) put(b, 8)
    const room = capacity(version) * 8
    put(0, Math.min(4, room - bits.length))
    while (bits.length % 8) bits.push(0)
    const out = []
    for (let i = 0; i < bits.length; i += 8) out.push(bits.slice(i, i + 8).reduce((v, b) => (v << 1) | b, 0))
    for (let pad = 0xec; out.length < capacity(version); pad ^= 0xec ^ 0x11) out.push(pad)
    return out
  }

  // Splits the data into blocks, adds each block's error correction, and interleaves them.
  function interleave(data, version) {
    const blocks = BLOCKS[version - 1]
    const ecc = ECC_PER_BLOCK[version - 1]
    const total = Math.floor(dataModules(version) / 8)
    const short = blocks - (total % blocks)
    const shortLength = Math.floor(total / blocks) - ecc
    const poly = generator(ecc)
    const parts = []
    let at = 0
    for (let i = 0; i < blocks; i++) {
      const length = shortLength + (i < short ? 0 : 1)
      const block = data.slice(at, at + length)
      at += length
      parts.push({ data: block, ecc: errorCorrection(block, poly) })
    }
    const out = []
    for (let i = 0; i <= shortLength; i++) for (const p of parts) if (i < p.data.length) out.push(p.data[i])
    for (let i = 0; i < ecc; i++) for (const p of parts) out.push(p.ecc[i])
    return out
  }

  const MASKS = [
    (x, y) => (x + y) % 2 === 0,
    (x, y) => y % 2 === 0,
    (x) => x % 3 === 0,
    (x, y) => (x + y) % 3 === 0,
    (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
    (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
    (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
    (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0,
  ]

  function bch(value, poly, length) {
    let rest = value << length
    const top = Math.floor(Math.log2(poly))
    for (let bit = top + length - 1; bit >= length; bit--) if ((rest >>> bit) & 1) rest ^= poly << (bit - top)
    return (value << length) | rest
  }

  // A symbol with every fixed pattern in place, and which modules they are.
  function frame(version) {
    const size = version * 4 + 17
    const dark = Array.from({ length: size }, () => new Array(size).fill(false))
    const fixed = Array.from({ length: size }, () => new Array(size).fill(false))
    const set = (x, y, on) => {
      if (x < 0 || y < 0 || x >= size || y >= size) return
      dark[y][x] = on
      fixed[y][x] = true
    }
    for (let i = 0; i < size; i++) {
      set(6, i, i % 2 === 0)
      set(i, 6, i % 2 === 0)
    }
    for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]]) {
      for (let dy = -4; dy <= 4; dy++) {
        for (let dx = -4; dx <= 4; dx++) {
          const ring = Math.max(Math.abs(dx), Math.abs(dy))
          set(cx + dx, cy + dy, ring !== 2 && ring !== 4)
        }
      }
    }
    const centres = alignmentCentres(version)
    for (const cy of centres) {
      for (const cx of centres) {
        if ((cx === 6 && cy === 6) || (cx === 6 && cy === size - 7) || (cx === size - 7 && cy === 6)) continue
        for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(cx + dx, cy + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1)
      }
    }
    if (version >= 7) {
      const bits = bch(version, 0x1f25, 12)
      for (let i = 0; i < 18; i++) {
        const on = ((bits >>> i) & 1) === 1
        const a = size - 11 + (i % 3)
        const b = Math.floor(i / 3)
        set(a, b, on)
        set(b, a, on)
      }
    }
    placeFormat(set, size, 0) // reserves the places; the real bits go in once the mask is chosen
    return { size, dark, fixed, set }
  }

  function placeFormat(set, size, mask) {
    const bits = bch((LEVEL_M << 3) | mask, 0x537, 10) ^ 0x5412
    const bit = (i) => ((bits >>> i) & 1) === 1
    for (let i = 0; i <= 5; i++) set(8, i, bit(i))
    set(8, 7, bit(6))
    set(8, 8, bit(7))
    set(7, 8, bit(8))
    for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i))
    for (let i = 0; i < 8; i++) set(size - 1 - i, 8, bit(i))
    for (let i = 8; i < 15; i++) set(8, size - 15 + i, bit(i))
    set(8, size - 8, true)
  }

  // Up and down two columns at a time from the bottom right, round everything fixed.
  function placeData(symbol, data) {
    const { size, dark, fixed } = symbol
    let i = 0
    for (let right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5
      const upward = ((right + 1) & 2) === 0
      for (let step = 0; step < size; step++) {
        const y = upward ? size - 1 - step : step
        for (let j = 0; j < 2; j++) {
          const x = right - j
          if (fixed[y][x]) continue
          if (i < data.length * 8) dark[y][x] = ((data[i >>> 3] >>> (7 - (i & 7))) & 1) === 1
          i++
        }
      }
    }
  }

  // How hard a symbol is to read, by the standard's four rules: lower is better.
  function penalty(dark) {
    const size = dark.length
    let score = 0
    const lines = []
    for (let y = 0; y < size; y++) lines.push(dark[y])
    for (let x = 0; x < size; x++) lines.push(dark.map((row) => row[x]))
    const finderLike = [true, false, true, true, true, false, true]
    for (const line of lines) {
      let run = 1
      for (let i = 1; i <= size; i++) {
        if (i < size && line[i] === line[i - 1]) { run++; continue }
        if (run >= 5) score += run - 2
        run = 1
      }
      for (let i = 0; i + 7 <= size; i++) {
        if (!finderLike.every((on, k) => line[i + k] === on)) continue
        const lightBefore = i >= 4 && [1, 2, 3, 4].every((k) => !line[i - k])
        const lightAfter = i + 11 <= size && [7, 8, 9, 10].every((k) => !line[i + k])
        if (lightBefore || lightAfter) score += 40
      }
    }
    let darkCount = 0
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        if (dark[y][x]) darkCount++
        if (x + 1 < size && y + 1 < size && dark[y][x] === dark[y][x + 1] && dark[y][x] === dark[y + 1][x] && dark[y][x] === dark[y + 1][x + 1]) score += 3
      }
    }
    const total = size * size
    score += Math.max(0, Math.ceil(Math.abs(darkCount * 20 - total * 10) / total) - 1) * 10
    return score
  }

  // The rows of the symbol, true for dark, without the quiet margin round it. Null when
  // the text is too long for a code a phone would read from across a room.
  function encode(text, forceMask) {
    const bytes = utf8(String(text))
    let version = 1
    while (version <= MAX_VERSION && capacity(version) < bytes.length + (version < 10 ? 2 : 3)) version++
    if (version > MAX_VERSION) return null
    const data = interleave(codewords(bytes, version), version)
    let best = null
    for (let mask = 0; mask < MASKS.length; mask++) {
      if (forceMask !== undefined && mask !== forceMask) continue
      const symbol = frame(version)
      placeData(symbol, data)
      for (let y = 0; y < symbol.size; y++) {
        for (let x = 0; x < symbol.size; x++) if (!symbol.fixed[y][x] && MASKS[mask](x, y)) symbol.dark[y][x] = !symbol.dark[y][x]
      }
      placeFormat(symbol.set, symbol.size, mask)
      const score = penalty(symbol.dark)
      if (!best || score < best.score) best = { score, rows: symbol.dark, version, mask }
    }
    return { rows: best.rows, version: best.version, mask: best.mask }
  }

  const api = { encode, MAX_VERSION }
  if (typeof module !== 'undefined' && module.exports) module.exports = api
  else root.WittyQR = api
})(typeof self !== 'undefined' ? self : this)
