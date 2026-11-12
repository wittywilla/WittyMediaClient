#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
"""Generates the apps' design constants from the server's themes/tokens.json.

    python3 scripts/gen-design-tokens.py [--tokens PATH] [--check]

Reads themes/tokens.json (the single source, docs/plans/DESIGN-2.md section 2) from the server checkout next to this
repository, lays it over the DESIGN-2 defaults below (a key the file lacks takes the default; a key this script does not
know is ignored) and writes android/.../ui/DesignTokens.generated.kt. With --check it writes nothing and exits 1 when the
file on disk is not what the tokens would give, for CI.
"""
import argparse, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, "android/app/src/main/kotlin/com/wittywilla/wittymediaclient/ui/DesignTokens.generated.kt")
CANDIDATES = [
    os.path.join(REPO, "../WittyMediaServer/themes/tokens.json"),
    os.path.join(REPO, "../design-WittyMediaServer/themes/tokens.json"),
    os.path.join(REPO, "../../WittyMediaServer/themes/tokens.json"),
]

# docs/plans/DESIGN-2.md section 2: what every platform assumes when tokens.json does not say.
DEFAULTS = {
    "type": {"role": {
        "display": {"size": 38, "weight": 650, "leading": 1.14, "tracking": -0.022},
        "pageTitle": {"size": 30, "weight": 650, "leading": 1.14, "tracking": -0.022},
        "heading": {"size": 24, "weight": 650, "leading": 1.14, "tracking": -0.012},
        "title": {"size": 20, "weight": 600, "leading": 1.32, "tracking": -0.012},
        "body": {"size": 15, "weight": 400, "leading": 1.55, "tracking": 0.0},
        "caption": {"size": 13, "weight": 400, "leading": 1.32, "tracking": 0.0},
        "label": {"size": 14, "weight": 500, "leading": 1.32, "tracking": 0.07},
    }},
    "space": {"none": 0, "xs": 4, "s": 8, "m": 16, "l": 24, "xl": 40},
    "elevation": {
        "0": {"fill": "bg", "line": "none", "shadow": 0},
        "1": {"fill": "bg-2", "line": "border", "shadow": 0},
        "2": {"fill": "bg-3", "line": "none", "shadow": 4},
        "3": {"fill": "bg-4", "line": "border", "shadow": 12},
    },
    "focus": {
        "width": 2, "offset": 2, "scale": 1.0,
        "style": {"media": "ring-lift", "control": "fill", "field": "ring"},
        "pointer": {"width": 2, "offset": 2, "scale": 1.0},
        "keys": {"width": 3, "offset": 3, "scale": 1.0},
    },
    "nav": {
        "wrap": False, "rememberPerGroup": True, "enterFromOutside": "last-or-first",
        "zones": ["bar", "stage", "dock", "layer"],
        "backLadder": ["layer", "dock", "stage", "bar", "home", "leave"],
        "bumpers": "tabs",
        "score": {"offLine": 1.0, "offCentre": 0.5, "leavesLine": 3.0},
    },
    "tv": {
        "safe": {"x": 90, "y": 60}, "gutter": 90,
        "topBar": {"height": 88, "top": 24, "pill": 56, "gap": 16},
        "rail": {"closed": 120, "open": 400},
        "type": {"display": 76, "pageTitle": 57, "heading": 48, "title": 38, "body": 29, "caption": 25, "label": 25},
        "target": {"min": 66},
        "focus": {"ring": 4, "gap": 4, "scale": 1.06, "lift": 6, "concentric": True},
        "shelf": {"rowGap": 56, "cardGap": 24, "peek": 0.18, "padTop": 24, "padBottom": 24},
        "card": {
            "poster": [250, 375], "wide": [420, 236], "square": [300, 300], "circle": [200, 200], "channel": [280, 158],
        },
        "dock": {"height": 112, "hintSize": 25},
    },
    "layout": {"breakpoints": {"compact": 600, "medium": 840, "expanded": 1200}},
    "density": {"comfortable": 1.0, "compact": 0.85, "spacious": 1.2},
    "motion": {"focusMove": 120, "screen": 240, "hero": 600},
    "input": {
        "keyboard": {
            "move": ["arrows"], "select": ["Enter", "Space"], "back": ["Escape", "Backspace", "Alt+Left"],
            "options": [".", "Shift+F10", "ContextMenu"], "search": ["/", "Ctrl+K"],
            "prevTab": ["Ctrl+["], "nextTab": ["Ctrl+]"], "pageUp": ["PageUp"], "pageDown": ["PageDown"],
            "top": ["Home"], "dock": ["Tab"], "help": ["?"],
        },
        "gamepad": {
            "move": ["dpad", "left-stick"], "select": ["A"], "back": ["B"], "options": ["X"], "search": ["Y"],
            "prevTab": ["LB"], "nextTab": ["RB"], "pageUp": ["LT"], "pageDown": ["RT"], "top": ["right-stick-click"],
            "dock": ["Start"], "help": ["Back+Start"],
        },
        "remote": {
            "move": ["dpad"], "select": ["OK"], "back": ["Back"], "options": ["long-OK", "Menu"], "search": ["Search"],
            "prevTab": ["channel-up"], "nextTab": ["channel-down"], "pageUp": ["channel-up"], "pageDown": ["channel-down"],
            "top": ["double-Up"], "dock": ["Menu"], "help": ["long-Menu"],
        },
    },
}

NAMES = {"keyboard": "KEYBOARD", "gamepad": "GAMEPAD", "remote": "REMOTE"}


def merge(base, over):
    """`over` laid on `base`: only keys base knows are kept, so unknown keys are ignored; a missing key keeps its default."""
    if not isinstance(base, dict) or not isinstance(over, dict):
        return over if type(over) is type(base) or (isinstance(base, (int, float)) and isinstance(over, (int, float)) and not isinstance(over, bool)) else base
    out = {}
    for k, v in base.items():
        out[k] = merge(v, over[k]) if k in over else v
    return out


def f(v):
    s = repr(float(v))
    return s + "f"


def i(v):
    return str(int(v))


def q(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(t):
    L = []
    w = L.append
    w("// SPDX-License-Identifier: GPL-3.0-or-later")
    w("// Copyright (C) 2026 WittyWilla and contributors")
    w("// GENERATED by scripts/gen-design-tokens.py from the server's themes/tokens.json (docs/plans/DESIGN-2.md). Do not edit.")
    w("package com.wittywilla.wittymediaclient.ui")
    w("")
    w("// A TV's numbers are TV units: 1 unit = 1 pt on Apple TV (1920x1080), 0.5 dp on Android TV (960x540).")
    w("object DesignTokens {")
    w("    object TypeRole { class Role(val size: Int, val weight: Int, val leading: Float, val tracking: Float)")
    for k, r in t["type"]["role"].items():
        w("        val %s = Role(%s, %s, %s, %s)" % (k.upper(), i(r["size"]), i(r["weight"]), f(r["leading"]), f(r["tracking"])))
    w("    }")
    w("    object Space {")
    for k, v in t["space"].items():
        w("        const val %s = %s" % (k.upper(), i(v)))
    w("    }")
    w("    // fill and line are theme colour names; shadow is dp of blur for the platforms that draw one.")
    w("    class Elevation(val fill: String, val line: String, val shadow: Int)")
    w("    val ELEVATION = listOf(")
    for k in ("0", "1", "2", "3"):
        e = t["elevation"][k]
        w("        Elevation(%s, %s, %s)," % (q(e["fill"]), q(e["line"]), i(e["shadow"])))
    w("    )")
    fo = t["focus"]
    w("    class FocusSpec(val width: Int, val offset: Int, val scale: Float)")
    w("    val FOCUS_POINTER = FocusSpec(%s, %s, %s)" % (i(fo["pointer"]["width"]), i(fo["pointer"]["offset"]), f(fo["pointer"]["scale"])))
    w("    val FOCUS_KEYS = FocusSpec(%s, %s, %s)" % (i(fo["keys"]["width"]), i(fo["keys"]["offset"]), f(fo["keys"]["scale"])))
    w("    const val FOCUS_STYLE_MEDIA = %s" % q(fo["style"]["media"]))
    w("    const val FOCUS_STYLE_CONTROL = %s" % q(fo["style"]["control"]))
    w("    const val FOCUS_STYLE_FIELD = %s" % q(fo["style"]["field"]))
    n = t["nav"]
    w("    object Nav {")
    w("        const val WRAP = %s" % ("true" if n["wrap"] else "false"))
    w("        const val REMEMBER_PER_GROUP = %s" % ("true" if n["rememberPerGroup"] else "false"))
    w("        const val ENTER_FROM_OUTSIDE = %s" % q(n["enterFromOutside"]))
    w("        val ZONES = listOf(%s)" % ", ".join(q(z) for z in n["zones"]))
    w("        val BACK_LADDER = listOf(%s)" % ", ".join(q(z) for z in n["backLadder"]))
    w("        const val OFF_LINE = %s" % f(n["score"]["offLine"]))
    w("        const val OFF_CENTRE = %s" % f(n["score"]["offCentre"]))
    w("        const val LEAVES_LINE = %s" % f(n["score"]["leavesLine"]))
    w("    }")
    tv = t["tv"]
    w("    object Tv {")
    w("        const val SAFE_X = %s" % i(tv["safe"]["x"]))
    w("        const val SAFE_Y = %s" % i(tv["safe"]["y"]))
    w("        const val GUTTER = %s" % i(tv["gutter"]))
    for k, v in tv["topBar"].items():
        w("        const val TOP_BAR_%s = %s" % (k.upper(), i(v)))
    w("        const val RAIL_CLOSED = %s" % i(tv["rail"]["closed"]))
    w("        const val RAIL_OPEN = %s" % i(tv["rail"]["open"]))
    for k, v in tv["type"].items():
        w("        const val TYPE_%s = %s" % (k.upper(), i(v)))
    w("        const val TARGET_MIN = %s" % i(tv["target"]["min"]))
    w("        const val FOCUS_RING = %s" % i(tv["focus"]["ring"]))
    w("        const val FOCUS_GAP = %s" % i(tv["focus"]["gap"]))
    w("        const val FOCUS_SCALE = %s" % f(tv["focus"]["scale"]))
    w("        const val FOCUS_LIFT = %s" % i(tv["focus"]["lift"]))
    w("        const val FOCUS_CONCENTRIC = %s" % ("true" if tv["focus"]["concentric"] else "false"))
    w("        const val SHELF_ROW_GAP = %s" % i(tv["shelf"]["rowGap"]))
    w("        const val SHELF_CARD_GAP = %s" % i(tv["shelf"]["cardGap"]))
    w("        const val SHELF_PEEK = %s" % f(tv["shelf"]["peek"]))
    w("        const val SHELF_PAD_TOP = %s" % i(tv["shelf"]["padTop"]))
    w("        const val SHELF_PAD_BOTTOM = %s" % i(tv["shelf"]["padBottom"]))
    for k, (a, b) in tv["card"].items():
        w("        const val CARD_%s_W = %s" % (k.upper(), i(a)))
        w("        const val CARD_%s_H = %s" % (k.upper(), i(b)))
    w("        const val DOCK_HEIGHT = %s" % i(tv["dock"]["height"]))
    w("        const val DOCK_HINT_SIZE = %s" % i(tv["dock"]["hintSize"]))
    w("    }")
    bp = t["layout"]["breakpoints"]
    w("    object Breakpoints { const val COMPACT = %s; const val MEDIUM = %s; const val EXPANDED = %s }" % (i(bp["compact"]), i(bp["medium"]), i(bp["expanded"])))
    d = t["density"]
    w("    object Density { const val COMFORTABLE = %s; const val COMPACT = %s; const val SPACIOUS = %s }" % (f(d["comfortable"]), f(d["compact"]), f(d["spacious"])))
    m = t["motion"]
    w("    object Motion { const val FOCUS_MOVE_MS = %s; const val SCREEN_MS = %s; const val HERO_MS = %s }" % (i(m["focusMove"]), i(m["screen"]), i(m["hero"])))
    w("    // The key map as data: action -> the keys that do it, per kind of input (docs/plans/DESIGN-2.md section 3).")
    for kind, name in NAMES.items():
        w("    val INPUT_%s: Map<String, List<String>> = mapOf(" % name)
        for a, keys in t["input"][kind].items():
            w("        %s to listOf(%s)," % (q(a), ", ".join(q(k) for k in keys)))
        w("    )")
    w("}")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tokens")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    path = a.tokens or next((c for c in CANDIDATES if os.path.exists(c)), None)
    given = {}
    if path and os.path.exists(path):
        given = json.load(open(path))
    t = merge(DEFAULTS, given)
    # `space` in the file is the numeric 4-point steps; the named steps are the defaults unless the file names them.
    if isinstance(given.get("space"), dict):
        named = {k: v for k, v in given["space"].items() if k in DEFAULTS["space"] and isinstance(v, (int, float))}
        t["space"] = {**DEFAULTS["space"], **named}
    # The tv focus block and the new `focus.style` may be absent in older files: defaults stand.
    src = render(t)
    if a.check:
        have = open(OUT).read() if os.path.exists(OUT) else ""
        if have != src:
            print("DesignTokens.generated.kt is out of date: run python3 scripts/gen-design-tokens.py", file=sys.stderr)
            return 1
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w").write(src)
    print("wrote", os.path.relpath(OUT, REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main())
