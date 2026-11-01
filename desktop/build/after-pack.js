// Runs on what's about to be packed. Two jobs:
//  - On Windows, lists every file an install holds, so that the uninstaller removes those and
//    nothing else: anything someone else put in the folder stays. build/installer.nsh reads it.
//  - Elsewhere, makes sure nothing is writable by everyone. Electron's download unpacks that way,
//    and a package would install it that way, so anyone on the computer could change the program.
const fs = require('fs')
const path = require('path')

const LIST = 'resources\\installed-files.txt'

function listForWindows(appOutDir) {
  const files = []
  const dirs = []
  const walk = (rel) => {
    for (const entry of fs.readdirSync(path.join(appOutDir, rel), { withFileTypes: true })) {
      const name = rel ? `${rel}\\${entry.name}` : entry.name
      if (entry.isDirectory()) { dirs.push(name); walk(name) } else files.push(name)
    }
  }
  walk('')
  // Folders last and deepest first, because a folder can only go once it's empty.
  dirs.sort((a, b) => b.length - a.length)
  // The setup adds elevate.exe itself, after this has run.
  const lines = [...files, LIST, 'resources\\elevate.exe', ...dirs.map((d) => `${d}\\`)]
  fs.writeFileSync(path.join(appOutDir, ...LIST.split('\\')), `${lines.join('\n')}\n`)
}

function removeWriteForOthers(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isSymbolicLink()) continue
    fs.chmodSync(full, fs.statSync(full).mode & 0o755)
    if (entry.isDirectory()) removeWriteForOthers(full)
  }
}

exports.default = async ({ appOutDir, electronPlatformName }) => {
  if (electronPlatformName === 'win32') listForWindows(appOutDir)
  else removeWriteForOthers(appOutDir)
}
