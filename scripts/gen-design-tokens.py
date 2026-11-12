#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
"""Generates the apps' design constants from the server's themes/tokens.json.

    python3 scripts/gen-design-tokens.py [--tokens PATH] [--check]

Reads themes/tokens.json (the single source, docs/plans/DESIGN-2.md section 2) from the server checkout next to this
repository, requires every key below (no defaults; a file lacking one is refused; a key this script does not know is ignored) and writes android/.../ui/DesignTokens.generated.kt. With --check it writes nothing and exits 1 when the
file on disk is not what the tokens would give, for CI.
"""
import argparse, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, "android/app/src/main/kotlin/com/wittywilla/wittymediaclient/ui/DesignTokens.generated.kt")
# The design branch's file where there is one (this repository's design worktree sits beside it), else the server's own.
CANDIDATES = [
    os.path.join(REPO, "../design-WittyMediaServer/themes/tokens.json"),
    os.path.join(REPO, "../WittyMediaServer/themes/tokens.json"),
    os.path.join(REPO, "../../WittyMediaServer/themes/tokens.json"),
]

# The shape of themes/tokens.json the apps require (docs/plans/DESIGN-2.md section 2); the values are W1's. Only its keys
# matter: a file lacking one is refused, there are no defaults.
DEFAULTS = {
    "type": {"role": {
        "display": {"size": 48, "weight": 650, "leading": 1.14, "tracking": -0.022},
        "pageTitle": {"size": 30, "weight": 650, "leading": 1.14, "tracking": -0.012},
        "heading": {"size": 20, "weight": 650, "leading": 1.32, "tracking": -0.012},
        "title": {"size": 17, "weight": 600, "leading": 1.32, "tracking": 0.0},
        "body": {"size": 15, "weight": 400, "leading": 1.55, "tracking": 0.0},
        "caption": {"size": 12, "weight": 400, "leading": 1.32, "tracking": 0.0},
        "label": {"size": 11, "weight": 600, "leading": 1.32, "tracking": 0.07},
    }},
    "space": {"none": 0, "xs": 4, "s": 8, "m": 16, "l": 24, "xl": 40},
    "elevation": {
        "0": {"fill": "bg", "line": "", "shadow": [{"y": 0, "blur": 0, "opacity": 0.0}]},
        "1": {"fill": "bg2", "line": "border", "shadow": [{"y": 0, "blur": 0, "opacity": 0.0}]},
        "2": {"fill": "bg3", "line": "border", "shadow": [{"y": 10, "blur": 24, "opacity": 0.5}]},
        "3": {"fill": "bg3", "line": "borderStrong", "shadow": [{"y": 10, "blur": 30, "opacity": 0.45}]},
    },
    "density": {"default": "comfortable", "tvDefault": "comfortable", "steps": {
        "compact": {"space": 0.75, "control": 0.875},
        "comfortable": {"space": 1.0, "control": 1.0},
        "spacious": {"space": 1.25, "control": 1.125},
    }},
    "focus": {
        "style": {"media": "ring-lift", "control": "fill", "field": "ring"},
        "input": {
            "pointer": {"width": 2, "offset": 2, "scale": 1.0},
            "keys": {"width": 3, "offset": 3, "scale": 1.0},
            "tv": {"width": 4, "offset": 4, "scale": 1.06},
        },
    },
    "nav": {
        "wrap": False, "rememberPerGroup": True, "enterFromOutside": "last-or-first",
        "zones": ["bar", "stage", "dock", "layer"],
        "backLadder": ["layer", "dock", "stage", "bar", "home", "exit"],
        "bumpers": {"prev": "LB", "next": "RB"},
        "weights": {
            "offLine": {"left": 4.0, "right": 4.0, "up": 1.2, "down": 1.2},
            "offCentre": {"left": 0.1, "right": 0.1, "up": 0.3, "down": 0.3},
            "leavesLine": {"left": 4000.0, "right": 4000.0, "up": 0.0, "down": 0.0},
        },
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
            "poster": {"w": 250, "h": 375}, "wide": {"w": 420, "h": 236}, "square": {"w": 300, "h": 300},
            "circle": 200, "channel": {"w": 280, "h": 158},
        },
        "dock": {"height": 112, "hintSize": 25},
    },
    "layout": {"breakpoints": {"compact": {"max": 600}, "medium": {"min": 600, "max": 840}, "expanded": {"min": 840, "max": 1200}, "large": {"min": 1200}}},
    "motion": {"focusMove": 120, "screen": 240, "hero": 600},
    "input": {
        "keyboard": {
            "move": ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"], "select": ["Enter", "Space"],
            "back": ["Escape", "Backspace", "Alt+ArrowLeft"], "options": ["Period", "Shift+F10", "ContextMenu"],
            "search": ["Slash", "Ctrl+K"], "tabPrev": ["Ctrl+BracketLeft", "PageUp"], "tabNext": ["Ctrl+BracketRight", "PageDown"],
            "pageUp": ["PageUp"], "pageDown": ["PageDown"], "top": ["Home"], "playPause": ["Space", "KeyK"],
            "seek": ["ArrowLeft", "ArrowRight", "KeyJ", "KeyL"], "dock": ["Tab"], "help": ["Shift+Slash"],
        },
        "gamepad": {
            "move": ["DPad", "LeftStick"], "select": ["A"], "back": ["B"], "options": ["X", "HoldA"], "search": ["Y"],
            "tabPrev": ["LB"], "tabNext": ["RB"], "pageUp": ["LT"], "pageDown": ["RT"], "top": ["RightStickClick"],
            "playPause": ["A"], "seek": ["LB", "RB"], "dock": ["Start"], "help": ["Back+Start"],
        },
        "remote": {
            "move": ["DPad"], "select": ["OK"], "back": ["Back"], "options": ["LongOK", "Menu", "Options"], "search": ["Search"],
            "tabPrev": ["ChannelUp"], "tabNext": ["ChannelDown"], "pageUp": ["ChannelUp"], "pageDown": ["ChannelDown"],
            "top": ["DoubleUp"], "playPause": ["PlayPause"], "seek": ["MediaRewind", "MediaFastForward"], "dock": ["Menu"], "help": ["HoldMenu"],
        },
    },
}

NAMES = {"keyboard": "KEYBOARD", "gamepad": "GAMEPAD", "remote": "REMOTE"}


def lacking(shape, got, path=""):
    """Dotted names of keys `shape` has that `got` does not (the file may carry more: those are ignored)."""
    out = []
    if not isinstance(shape, dict):
        return out
    if not isinstance(got, dict):
        return [path or "."]
    for k, v in shape.items():
        if k not in got:
            out.append((path + "." + k).lstrip("."))
        else:
            out += lacking(v, got[k], (path + "." + k).lstrip("."))
    return out


def merge(base, over):
    """`over` laid on `base`: only keys base knows are kept, so unknown keys are ignored; a missing key keeps its default."""
    if not isinstance(base, dict) or not isinstance(over, dict):
        if base is None or over is None:
            return base if over is None and base is not None else over
        if isinstance(base, (int, float)) and not isinstance(base, bool):
            return over if isinstance(over, (int, float)) and not isinstance(over, bool) else base
        return over if type(over) is type(base) else base
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
    w("    class Role(val size: Int, val weight: Int, val leading: Float, val tracking: Float)")
    w("    object TypeRole {")
    for k, r in t["type"]["role"].items():
        w("        val %s = Role(%s, %s, %s, %s)" % (k.upper(), i(r["size"]), i(r["weight"]), f(r["leading"]), f(r["tracking"])))
    w("    }")
    w("    object Space {")
    for k, v in t["space"].items():
        if k in DEFAULTS["space"]:
            w("        const val %s = %s" % (k.upper(), i(v)))
    w("    }")
    w("    class Shadow(val y: Int, val blur: Int, val opacity: Float)")
    w("    // fill and line are theme colour names (line empty for none); shadow is what platforms that draw one use.")
    w("    class Elevation(val fill: String, val line: String, val shadow: List<Shadow>)")
    w("    val ELEVATION = listOf(")
    for k in ("0", "1", "2", "3"):
        e = t["elevation"][k]
        sh = e["shadow"] if isinstance(e["shadow"], list) else []
        w("        Elevation(%s, %s, listOf(%s))," % (q(e["fill"]), q(e["line"] or ""), ", ".join("Shadow(%s, %s, %s)" % (i(x["y"]), i(x["blur"]), f(x["opacity"])) for x in sh if x.get("blur"))))
    w("    )")
    d = t["density"]
    w("    // Multiples of spacing and of control height; chosen per profile per device.")
    w("    class DensityStep(val space: Float, val control: Float)")
    w("    const val DENSITY_DEFAULT = %s" % q(d["default"]))
    w("    const val DENSITY_TV_DEFAULT = %s" % q(d["tvDefault"]))
    w("    val DENSITY = mapOf(%s)" % ", ".join("%s to DensityStep(%s, %s)" % (q(k), f(v["space"]), f(v["control"])) for k, v in d["steps"].items()))
    fo = t["focus"]
    w("    class FocusSpec(val width: Int, val offset: Int, val scale: Float)")
    for k in ("pointer", "keys", "tv"):
        x = fo["input"][k]
        w("    val FOCUS_%s = FocusSpec(%s, %s, %s)" % (k.upper(), i(x["width"]), i(x["offset"]), f(x["scale"])))
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
    w("        // Weights of the spatial search, per heading: the same numbers as web/src/spatial.ts, so no port drifts.")
    w("        class Weights(val left: Float, val right: Float, val up: Float, val down: Float)")
    for k, name in (("offLine", "OFF_LINE"), ("offCentre", "OFF_CENTRE"), ("leavesLine", "LEAVES_LINE")):
        x = n["weights"][k]
        w("        val %s = Weights(%s, %s, %s, %s)" % (name, f(x["left"]), f(x["right"]), f(x["up"]), f(x["down"])))
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
    for k, v in tv["card"].items():
        wh = (v["w"], v["h"]) if isinstance(v, dict) else (v, v)
        w("        const val CARD_%s_W = %s" % (k.upper(), i(wh[0])))
        w("        const val CARD_%s_H = %s" % (k.upper(), i(wh[1])))
    w("        const val DOCK_HEIGHT = %s" % i(tv["dock"]["height"]))
    w("        const val DOCK_HINT_SIZE = %s" % i(tv["dock"]["hintSize"]))
    w("    }")
    bp = t["layout"]["breakpoints"]
    w("    // Window width classes in dp: compact below COMPACT, medium below MEDIUM, expanded below EXPANDED, else large.")
    w("    object Breakpoints { const val COMPACT = %s; const val MEDIUM = %s; const val EXPANDED = %s }" % (i(bp["compact"]["max"]), i(bp["medium"]["max"]), i(bp["expanded"]["max"])))
    m = t["motion"]
    w("    object Motion { const val FOCUS_MOVE_MS = %s; const val SCREEN_MS = %s; const val HERO_MS = %s }" % (i(m["focusMove"]), i(m["screen"]), i(m["hero"])))
    w("    // The key map as data: action -> the keys that do it, per kind of input (docs/plans/DESIGN-2.md section 3), by the")
    w("    // names the web uses (KeyboardEvent.code, pad buttons, remote keys); ui/InputRules maps them to Android's.")
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
    # No fallbacks: the new schema is required. A file lacking a key the apps read is an error, not a default.
    missing = lacking(DEFAULTS, given)
    if not given or missing:
        print("tokens.json lacks: " + ", ".join(missing or ["(no file found)"]), file=sys.stderr)
        return 2
    t = given
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
