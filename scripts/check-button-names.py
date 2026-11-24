#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
"""Every button has a name a screen reader can say: TalkBack on Android, VoiceOver on iPhone, iPad and Apple TV.

Fails on a button whose only content is an icon, with no words and no label:

  Android (Kotlin, Compose)  Pressable(...), IconButton(...), Modifier.clickable(...) and .combinedClickable(...) whose
                             content is an Icon(..., null) or Image(..., null) with no Text, and with no label =,
                             contentDescription or onClickLabel on the call or in a .semantics { } on it.
  Apple (Swift, SwiftUI)     Button { ... } whose label is only an Image, with no Text or Label inside and no
                             .accessibilityLabel(...) on it.
  Desktop (HTML)             <button> with no words inside and no aria-label, aria-labelledby or title.

A call can say why it needs no name with a comment on its line: // a11y-ok: <why> (decoration a screen reader skips,
a duplicate of a named control beside it).

    python3 scripts/check-button-names.py            (exits 1 and lists each unnamed button)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = [('android', '.kt'), ('apple', '.swift'), ('desktop', '.html')]
SKIP_DIRS = {'build', '.gradle', 'DerivedData', '.build', 'Pods', 'node_modules'}


def strip_comments_and_strings(text):
    """Blanks out comments and string contents (keeping their length and line breaks) so braces in them don't count."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if text[k] != '\n':
                    out[k] = ' '
            i = j
        elif text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j < 0 else j + 3
            for k in range(i + 3, j - 3):
                if text[k] != '\n':
                    out[k] = 'x'
            i = j
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            for k in range(i + 1, min(j, n)):
                out[k] = 'x'
            i = j + 1
        else:
            i += 1
    return ''.join(out)


def match(code, i, open_ch, close_ch):
    """Index just past the bracket that closes the one at i."""
    depth = 0
    for j in range(i, len(code)):
        if code[j] == open_ch:
            depth += 1
        elif code[j] == close_ch:
            depth -= 1
            if depth == 0:
                return j + 1
    return len(code)


def call_extent(code, start):
    """From the start of a call's name: its (arguments) and any trailing { content } lambdas, as (args, body, end)."""
    i = start
    while i < len(code) and code[i] not in '({\n':
        i += 1
    args = ''
    if i < len(code) and code[i] == '(':
        e = match(code, i, '(', ')')
        args, i = code[i:e], e
    body = ''
    # Trailing lambdas, Swift's "label:" one included.
    while True:
        m = re.match(r'\s*(?:[A-Za-z]+:\s*)?\{', code[i:])
        if not m or (args and '\n' in code[i:i + m.end()].strip(' \t')[:1]):
            break
        b = i + m.end() - 1
        e = match(code, b, '{', '}')
        body += code[b:e]
        i = e
    return args, body, i


def line_of(text, i):
    return text.count('\n', 0, i) + 1


KT_CALL = re.compile(r'(?<![\w.])(Pressable|IconButton|FilledIconButton|OutlinedIconButton|FilledTonalIconButton)\s*[({]')
KT_CLICK = re.compile(r'\.(clickable|combinedClickable)\s*[({]')
KT_NAMED = re.compile(r'\blabel\s*=|contentDescription\s*=\s*(?!null)|onClickLabel\s*=|\bsemantics\b|clearAndSetSemantics|stateDescription')
KT_ICON_ONLY = re.compile(r'\b(Icon|Image|AsyncImage|TvIcon)\s*\(')
KT_WORDS = re.compile(r'\b(Text|BasicText|Label|BrandText|[A-Z]\w*Text)\s*\(|\btext\s*=|\btitle\s*=')


def kotlin_problems(path, text):
    code = strip_comments_and_strings(text)
    found = []
    for m in KT_CALL.finditer(code):
        if code[max(0, m.start() - 4):m.start()].endswith('fun '):
            continue
        args, body, end = call_extent(code, m.start())
        if KT_NAMED.search(args) or KT_NAMED.search(body) or not KT_ICON_ONLY.search(body) or KT_WORDS.search(body):
            continue
        found.append((m.start(), m.group(1)))
    for m in KT_CLICK.finditer(code):
        # The element the modifier is on: the call the Modifier chain is an argument of, from the line it starts.
        line_start = code.rfind('\n', 0, m.start()) + 1
        owner = re.search(r'(Icon|Image|TvIcon|Box|Row|Column|Surface)\s*\(', code[line_start:m.start()])
        if not owner:
            continue
        o = line_start + owner.start()
        args, body, end = call_extent(code, o)
        chain = code[o:end]
        if KT_NAMED.search(chain) or KT_WORDS.search(chain):
            continue
        if owner.group(1) in ('Icon', 'Image', 'TvIcon') or KT_ICON_ONLY.search(body):
            found.append((m.start(), owner.group(1) + '.' + m.group(1)))
    return found


SW_BUTTON = re.compile(r'(?<![\w.])Button\s*[({]')
# Words: Text, Label (either form), the app's own rows and texts that take a title (RowLabel(title:), BusyText("…")).
SW_WORDS = re.compile(r'\b(Text|Label|LabeledContent|[A-Z]\w*Text)\s*[({]|\btitle\s*:')
SW_IMAGE = re.compile(r'\b(Image|AsyncImage)\s*\(')
SW_NAMED = re.compile(r'\.accessibilityLabel\s*\(|\.accessibilityElement\s*\(\s*children:\s*\.combine|\.help\s*\(')


def swift_problems(path, text):
    code = strip_comments_and_strings(text)
    found = []
    for m in SW_BUTTON.finditer(code):
        start = m.start()
        args, body, end = call_extent(code, start)
        # Button("Title", ...) and Button(title, ...) carry their words in the first argument. Strings are blanked to x.
        if re.match(r'\(\s*("|[a-z_]\w*\s*[,)]|role:)', args) and not re.match(r'\(\s*action\s*:', args):
            continue
        if SW_WORDS.search(body) or SW_WORDS.search(args) or not SW_IMAGE.search(body):
            continue
        # The modifiers chained after the button, up to the next line that isn't one.
        tail = code[end:end + 600]
        chain = re.match(r'(?:[ \t\r\n]*\.[^\n]*)*', tail).group(0)
        if SW_NAMED.search(chain) or SW_NAMED.search(body):
            continue
        found.append((start, 'Button'))
    return found


HTML_BUTTON = re.compile(r'<button([^>]*)>(.*?)</button>', re.S | re.I)


def html_problems(path, text):
    found = []
    for m in HTML_BUTTON.finditer(text):
        attrs, inner = m.group(1), m.group(2)
        if re.search(r'(aria-label|aria-labelledby|title)\s*=', attrs) or re.search(r'hidden', attrs):
            continue
        if re.sub(r'<[^>]*>|&nbsp;|\s', '', inner):
            continue
        found.append((m.start(), 'button'))
    return found


def main():
    problems = []
    files = 0
    for folder, ext in SOURCES:
        for dirpath, dirs, names in os.walk(os.path.join(ROOT, folder)):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith('.')]
            for name in names:
                if not name.endswith(ext):
                    continue
                path = os.path.join(dirpath, name)
                with open(path, encoding='utf-8') as f:
                    text = f.read()
                files += 1
                lines = text.split('\n')
                check = {'.kt': kotlin_problems, '.swift': swift_problems, '.html': html_problems}[ext]
                for at, what in check(path, text):
                    n = line_of(text, at)
                    if 'a11y-ok' in lines[n - 1]:
                        continue
                    rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
                    problems.append(f'{rel}:{n}  {what}: {lines[n - 1].strip()[:110]}')
    if problems:
        print(f'{len(problems)} button(s) with no name. Give each a label (label =, contentDescription, '
              f'.accessibilityLabel) a screen reader can say:')
        for p in problems:
            print('  ' + p)
        return 1
    print(f'every button in {files} files has a name')
    return 0


if __name__ == '__main__':
    sys.exit(main())
