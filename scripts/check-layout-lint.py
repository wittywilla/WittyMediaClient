# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
"""Single-line words end in an ellipsis rather than being cut mid-letter.

Fails on an Android (Kotlin, Compose) Text(...) call that has maxLines = 1 and no overflow = in the same call. Without
overflow, Compose clips the line at the edge of its box, which shows on narrow phones and at large text sizes.

Each Text( call is read to its matching close bracket, skipping strings (with their ${...} templates) and comments, so
an argument that spans lines or holds brackets of its own is read whole.

A call can say why it needs no ellipsis with a comment on its line: // layout-ok: <why>.

    python3 scripts/check-layout-lint.py            (exits 1 and lists each call)

No shebang on purpose: CI runs it with python3, and a new file from Windows would lose the executable bit.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'android', 'app', 'src')
SKIP_DIRS = {'build', '.gradle'}

# Calls left as they were in files another piece of work owns (the settings screens, the connect-from-anywhere panel):
# how many each may still have. A file over its number fails; take the number down as they are fixed, and the entry
# out at 0. Every other file has none.
KNOWN = {
    'ui/BrandEditorParts.kt': 2,
    'ui/Controls.kt': 1,  # GroupRowView, a settings row
}
KNOWN_BASE = 'android/app/src/main/kotlin/com/wittywilla/wittymediaclient/'

TEXT_CALL = re.compile(r'(?<![\w])Text\s*\(')
ONE_LINE = re.compile(r'\bmaxLines\s*=\s*1(?![\w.])')
OVERFLOW = re.compile(r'\boverflow\s*=')


def code_only(text):
    """The text with comments and string contents blanked (same length, line breaks kept), so their brackets don't count.

    Kotlin strings can hold ${...} templates with strings of their own ("${s["key"]}"), so this keeps a small stack:
    inside a template it is code again until the template's closing brace.
    """
    out = list(text)
    n = len(text)
    i = 0
    # Each entry: ('str', '"' or '\"\"\"') for a string, ('tpl', depth) for a ${...} template inside one.
    stack = []

    def blank(a, b):
        for k in range(a, b):
            if out[k] != '\n':
                out[k] = ' '

    while i < n:
        top = stack[-1] if stack else None
        if top is not None and top[0] == 'str':
            quote = top[1]
            if quote == '"' and text[i] == '\\':
                blank(i, min(i + 2, n))
                i += 2
                continue
            if text.startswith('${', i):
                stack.append(['tpl', 0])
                i += 2
                continue
            if text.startswith(quote, i):
                stack.pop()
                i += len(quote)
                continue
            if quote == '"' and text[i] == '\n':
                # An unclosed plain string: give up on it at the end of the line.
                stack.pop()
                i += 1
                continue
            blank(i, i + 1)
            i += 1
            continue
        # Code, at the top level or in a template.
        if text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            blank(i, j)
            i = j
        elif text.startswith('"""', i):
            stack.append(['str', '"""'])
            i += 3
        elif text[i] == '"':
            stack.append(['str', '"'])
            i += 1
        elif text[i] == "'":
            # A character: 'x', '\n', 'A'.
            j = i + 1
            while j < n and text[j] != "'" and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            blank(i + 1, min(j, n))
            i = j + 1
        elif top is not None and top[0] == 'tpl' and text[i] == '{':
            top[1] += 1
            i += 1
        elif top is not None and top[0] == 'tpl' and text[i] == '}':
            if top[1] == 0:
                stack.pop()
            else:
                top[1] -= 1
            i += 1
        else:
            i += 1
    return ''.join(out)


def close_of(code, i):
    """Index just past the bracket that closes the '(' at i."""
    depth = 0
    for j in range(i, len(code)):
        c = code[j]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return j + 1
    return len(code)


def problems(text):
    code = code_only(text)
    found = []
    for m in TEXT_CALL.finditer(code):
        before = code[max(0, m.start() - 4):m.start()]
        if before.endswith('fun '):
            continue
        args = code[m.end() - 1:close_of(code, m.end() - 1)]
        if ONE_LINE.search(args) and not OVERFLOW.search(args):
            found.append(m.start())
    return found


def main():
    bad = []
    known_left = 0
    files = 0
    for dirpath, dirs, names in os.walk(SOURCE):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith('.'))
        for name in sorted(names):
            if not name.endswith('.kt'):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding='utf-8') as f:
                text = f.read()
            files += 1
            lines = text.split('\n')
            rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
            here = []
            for at in problems(text):
                n = text.count('\n', 0, at) + 1
                if 'layout-ok' in lines[n - 1]:
                    continue
                here.append(f'{rel}:{n}: Text(...) has maxLines = 1 and no overflow (add overflow = TextOverflow.Ellipsis)')
            allowed = KNOWN.get(rel[len(KNOWN_BASE):], 0) if rel.startswith(KNOWN_BASE) else 0
            if len(here) > allowed:
                bad.extend(here)
            else:
                known_left += len(here)
    for line in bad:
        print(line)
    if bad:
        print(f'\n{len(bad)} single-line Text call(s) clip instead of ending in an ellipsis.')
        return 1
    left = f', {known_left} known in the files listed in KNOWN' if known_left else ''
    print(f'Checked {files} Kotlin files: every single-line Text has an overflow{left}.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
