// Lists every file a Windows install holds, so that the uninstaller removes those and nothing
// else: anything someone else put in the folder stays where it is. build/installer.nsh reads it.
const fs = require('fs')
const path = require('path')

const LIST = 'resources\\installed-files.txt'

exports.default = async ({ appOutDir, electronPlatformName }) => {
  if (electronPlatformName !== 'win32') return
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
