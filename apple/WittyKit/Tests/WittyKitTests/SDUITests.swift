// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// Server-driven pages without the server's fixtures: reading what's sent, patches, the router, focus,
/// "Customise", the cache and the requests. Everything here is made up.
final class SDUITests: XCTestCase {
    static let page = #"""
    {"version":1,"catalog":8,"futureField":{"x":1},
     "page":{"id":"home","kind":"home","title":"Home","route":"/","params":{"tab":"a","n":3}},
     "layout":{"formFactor":"tv","class":"hd","canvas":{"width":1920,"height":1080},"scale":1,"breakpoint":"large",
       "safeArea":{"top":60,"right":80,"bottom":60,"left":80},"focusEngine":true,"density":"comfortable",
       "spacing":{"none":0,"xs":10,"s":20,"m":40,"l":60,"xl":100},"text":{"pageTitle":76,"heading":57,"title":48,"body":29,"caption":25},
       "cards":{"poster":{"shape":"poster","aspect":"2/3","width":{"s":200,"m":250,"l":312},"columns":6}},
       "imageWidths":[120,160,240,320,480,640,960,1280,1920,2560,3840],"budget":{"shelfItems":12},"somethingNew":true},
     "root":{"type":"Page","id":"page","props":{"title":"Home"},"children":[
       {"type":"Hero","id":"hero","focus":{"order":1,"default":true},"props":{"size":{"width":1920,"height":620}},"children":[
         {"type":"Card","id":"hero:1","props":{"style":"hero","title":"Film 1","facts":[{"id":"year","value":"1991"}],
           "actions":[{"id":"play","label":"Play","primary":true,"action":{"type":"play","item":"1","params":{"resume":true}}},
                      {"id":"details","label":"More info","action":{"type":"navigate","to":"/item/1"}}]}}]},
       {"type":"Shelf","id":"jump","props":{"title":"Jump back in","cardStyle":"progress","card":{"width":420,"height":236},
          "seeAll":{"label":"See all","route":"/library/1"},"more":{"url":"/api/v1/sdui/pages/home/sections/jump/items?cursor=2"}},"children":[
         {"type":"Card","id":"jump:3","focus":{"order":2,"group":"jump"},"action":{"type":"navigate","to":"/item/3"},
          "props":{"style":"progress","shape":"landscape","title":"Film 3","subtitle":"1993","progress":0.42,"remaining":"1 hr 1 min left",
                   "image":{"url":"/api/items/3/backdrop?w=480","width":480,"height":270,"aspect":"16/9","kind":"backdrop"}}},
         {"type":"Card","id":"jump:4","focus":{"order":3,"group":"jump"},"action":{"type":"frobnicate","to":"/x"},
          "props":{"style":"hologram","shape":"poster","title":"Film 4","subtitle":"1994","sparkle":[1,2,3]}}]},
       {"type":"Marquee","id":"future","props":{"speed":3},"children":[
         {"type":"Button","id":"b","focus":{"order":4},"action":{"type":"native","to":"settings"},"props":{"label":"Settings"}}]},
       {"type":"Shelf","id":"recent-2","state":"deferred","props":{"title":"Recently added","cardStyle":"poster","card":{"width":250,"height":375},
          "more":{"url":"/api/v1/sdui/pages/home/sections/recent-2/items?cursor=0"}}},
       {"type":"Shelf","id":"odd","state":"quantum","props":{"title":"Odd"}}
     ]},
     "personal":{"editable":true,"allow":["reorder","hide","pin","density","cardSize","defaultTab"],
       "sections":[{"id":"hero","title":"Featured"},{"id":"jump","title":"Jump back in"},{"id":"future","title":"Notice","locked":true},
                   {"id":"recent-2","title":"Recently added"},{"id":"onnow","title":"On TV now","empty":true},{"id":"gone","title":"Hidden one","hidden":true}],
       "url":"/api/v1/sdui/pages/home/personal"},
     "meta":{"etag":"W/\"sha256-abc\"","ttlSeconds":60}}
    """#

    static func document() throws -> SDUIDocument { try JSONDecoder().decode(SDUIDocument.self, from: Data(page.utf8)) }

    // MARK: Reading

    func testAPageIsReadWithWhatItDoesNotKnowLeftAlone() throws {
        let document = try Self.document()
        XCTAssertEqual(document.page.params, ["tab": "a", "n": "3"])
        XCTAssertEqual(document.layout.deviceClass, "hd")
        XCTAssertEqual(document.root.kids.map(\.type), ["Hero", "Shelf", "Marquee", "Shelf", "Shelf"])
        let screen = SDUIScreen(document: document)
        // A type this app doesn't know is drawn as a column of its children, which are still there.
        let future = try XCTUnwrap(screen.root.find("future"))
        XCTAssertEqual(future.type, "Stack")
        XCTAssertEqual(future.children.map(\.label), ["Settings"])
        // An unknown card style is drawn as its shape: the title and subtitle under the picture.
        let odd = try XCTUnwrap(screen.root.find("jump:4"))
        XCTAssertEqual(odd.shows, ["title", "subtitle"])
        XCTAssertEqual(odd.label, "Film 4, 1994")
        // An unknown state is ready; an unknown action does nothing.
        XCTAssertEqual(screen.root.find("odd")?.state, .ready)
        XCTAssertEqual(SDUIRouter().resolve(odd.action), SDUIDestination.none)
        let card = try XCTUnwrap(screen.root.find("jump:3"))
        XCTAssertEqual(card.label, "Film 3, 1993, 42 percent watched, 1 hr 1 min left")
        XCTAssertEqual(card.progress, 42)
        XCTAssertEqual(card.picture?.width, 480)
        XCTAssertEqual(screen.root.find("recent-2")?.placeholders, 7)
        XCTAssertEqual(screen.root.find("hero:1")?.buttons.map(\.label), ["Play", "More info"])
    }

    func testAVersionThisAppDoesNotKnowIsRefused() {
        XCTAssertThrowsError(try JSONDecoder().decode(SDUIDocument.self, from: Data(#"{"version":2,"root":{"type":"Page","id":"page"}}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(SDUIDocument.self, from: Data(#"{"root":{"type":"Page","id":"page"}}"#.utf8)))
    }

    func testAChildThatCannotBeReadIsLeftOutAndTheRestStays() throws {
        let text = #"{"version":1,"root":{"type":"Page","id":"page","children":[7,{"type":"Text","id":"t","props":{"text":"Hello"}},"x"]}}"#
        let document = try JSONDecoder().decode(SDUIDocument.self, from: Data(text.utf8))
        XCTAssertEqual(document.root.kids.map(\.id), ["t"])
        XCTAssertEqual(document.layout, SDUILayout.fallback)
    }

    func testTheCatalogueKeepsItsOwnTablesWhereTheServersAreMissing() throws {
        let catalog = try JSONDecoder().decode(SDUICatalog.self, from: Data(#"{"revision":3,"routes":[{"pattern":"/x/{id}","page":"{id}"},7],"components":[{"type":"Page"}]}"#.utf8))
        XCTAssertEqual(catalog.routes.count, 1)
        XCTAssertEqual(catalog.cardStyles.count, 17)
        XCTAssertEqual(catalog.cardStyle("photo")?.shows, [])
        XCTAssertNotNil(catalog.command("watched.set"))
    }

    func testNavigationKeepsTheEntriesItCanRead() throws {
        let text = #"{"version":1,"formFactor":"tv","etag":"W/\"nav-1\"","items":[{"id":"home","label":"Home","icon":"home","kind":"page","page":"home","route":"/","placement":"primary"},{"nope":1},{"id":"settings","label":"Settings","kind":"native","screen":"settings","route":"/settings","placement":"end"},{"id":"lib-3","label":"Films","kind":"page","page":"library","params":{"library":"3"},"route":"/library/3","placement":"more"}]}"#
        let menu = try JSONDecoder().decode(SDUINavigation.self, from: Data(text.utf8))
        XCTAssertEqual(menu.items.map(\.id), ["home", "settings", "lib-3"])
        XCTAssertEqual(menu.placed("more").map(\.id), ["lib-3"])
        XCTAssertTrue(menu.items[1].isSettings)
        let router = SDUIRouter()
        XCTAssertEqual(router.resolve(menu.items[0]), .page("home", params: [:]))
        XCTAssertEqual(router.resolve(menu.items[1]), .native("settings", params: [:]))
        XCTAssertEqual(router.resolve(menu.items[2]), .page("library", params: ["library": "3"]))
    }

    // MARK: The router

    func testRoutesAreShownByWhatTheTableSays() {
        let router = SDUIRouter()
        XCTAssertEqual(router.resolve(route: "/"), .page("home", params: [:]))
        XCTAssertEqual(router.resolve(route: "/item/103"), .page("detail", params: ["item": "103"]))
        XCTAssertEqual(router.resolve(route: "/show/7"), .page("detail", params: ["show": "7"]))
        XCTAssertEqual(router.resolve(route: "/album/5?artist=The+Examples&album=A%20%26%20B"),
                       .page("detail", params: ["library": "5", "artist": "The Examples", "album": "A & B"]))
        XCTAssertEqual(router.resolve(route: "/library/3?genre=Drama&sort=rating"), .page("library", params: ["library": "3", "genre": "Drama", "sort": "rating"]))
        XCTAssertEqual(router.resolve(route: "/collections/12"), .page("detail", params: ["collection": "12"]))
        XCTAssertEqual(router.resolve(route: "/collections"), .page("collections", params: [:]))
        XCTAssertEqual(router.resolve(route: "/search?q=exam"), .page("search", params: ["q": "exam"]))
        XCTAssertEqual(router.resolve(route: "/page/family-night"), .page("family-night", params: [:]))
        XCTAssertEqual(router.resolve(route: "/settings/playback"), .native("settings", params: ["section": "playback", "route": "/settings/playback"]))
        XCTAssertEqual(router.resolve(route: "/tv/watch/bbc.one"), .native("livePlayer", params: ["key": "bbc.one", "route": "/tv/watch/bbc.one"]))
        XCTAssertEqual(router.resolve(route: "/watch/12"), .native("player", params: ["item": "12", "route": "/watch/12"]))
        XCTAssertEqual(router.resolve(route: "/you"), .native("profiles", params: ["route": "/you"]))
        XCTAssertEqual(router.resolve(route: "/tv/recordings"), .native("guide", params: ["route": "/tv/recordings"]))
        for bad in ["", "item/3", "//evil.example/x", "/nowhere", "/item/3/extra", "/page/../etc", "https://example.com/"] {
            XCTAssertEqual(router.resolve(route: bad), SDUIDestination.none, bad)
        }
        // A newer server's table is the one used: nothing about a route is written into the app.
        let newer = SDUIRouter(rules: [SDUIRouteRule("/film/{item}", page: "detail", params: ["item": "{item}", "from": "films"])])
        XCTAssertEqual(newer.resolve(route: "/film/9"), .page("detail", params: ["item": "9", "from": "films"]))
        XCTAssertEqual(newer.resolve(route: "/item/9"), SDUIDestination.none)
    }

    func testActionsBecomeWhatTheAppDoes() {
        let router = SDUIRouter()
        XCTAssertEqual(router.resolve(SDUIAction(type: "play", item: "3")), .play(item: "3", resume: true))
        XCTAssertEqual(router.resolve(SDUIAction(type: "play", item: "3", params: ["resume": .bool(false)])), .play(item: "3", resume: false))
        XCTAssertEqual(router.resolve(SDUIAction(type: "native", to: "share", params: ["item": .string("3")])), .native("share", params: ["item": "3"]))
        XCTAssertEqual(router.resolve(SDUIAction(type: "command", item: "3", op: "watched.set")), .command(op: "watched.set", item: "3", params: [:]))
        XCTAssertEqual(router.resolve(SDUIAction(type: "command", op: "selectTab", params: ["tab": .string("artists")])), .command(op: "selectTab", item: "", params: ["tab": "artists"]))
        XCTAssertEqual(router.resolve(SDUIAction(type: "back")), .back)
        XCTAssertEqual(router.resolve(SDUIAction(type: "external", url: "https://example.com/a")), .external(URL(string: "https://example.com/a")!))
        for bad in [SDUIAction(type: "external", url: "javascript:alert(1)"), SDUIAction(type: "external", url: "file:///etc/passwd"),
                    SDUIAction(type: "play"), SDUIAction(type: "teleport", to: "/"), SDUIAction(type: "command")] {
            XCTAssertEqual(router.resolve(bad), SDUIDestination.none, bad.type)
        }
        XCTAssertEqual(router.resolve(nil), SDUIDestination.none)
    }

    func testACommandIsTheCataloguesRequestWithTheItemFilledIn() throws {
        let catalog = SDUICatalog.builtIn
        let later = try XCTUnwrap(SDUIRouter.request(for: catalog.command("watchLater.add"), item: "12"))
        XCTAssertEqual(later.method, "POST")
        XCTAssertEqual(later.path, "/api/v1/collections/watch-later/items")
        XCTAssertEqual(later.body.map { String(decoding: $0, as: UTF8.self) }, #"{"items":[12]}"#)
        let clear = try XCTUnwrap(SDUIRouter.request(for: catalog.command("watched.clear"), item: "12"))
        XCTAssertEqual(clear.method, "DELETE")
        XCTAssertEqual(clear.path, "/api/v1/items/12/progress")
        XCTAssertNil(clear.body)
        XCTAssertNil(SDUIRouter.request(for: catalog.command("refresh"), item: "12"))
        XCTAssertNil(SDUIRouter.request(for: catalog.command("watched.set"), item: "12/../../users"))
        XCTAssertNil(SDUIRouter.request(for: catalog.command("watched.set"), item: #"1"}"#))
        XCTAssertNil(SDUIRouter.request(for: SDUICommand("x", method: "POST", path: "https://example.com/"), item: "1"))
        // A newer catalogue puts the ID in a JSON string: a show's ID goes in as it is, and so does a number.
        let quoted = SDUICommand("watchLater.add", method: "POST", path: "/api/v1/collections/watch-later/items", body: #"{"items":["{item}"]}"#)
        XCTAssertEqual(SDUIRouter.request(for: quoted, item: "show-5")?.body.map { String(decoding: $0, as: UTF8.self) }, #"{"items":["show-5"]}"#)
        XCTAssertEqual(SDUIRouter.request(for: quoted, item: "12")?.body.map { String(decoding: $0, as: UTF8.self) }, #"{"items":["12"]}"#)
        XCTAssertEqual(SDUIRouter.request(for: catalog.command("watched.set"), item: "show-5")?.path, "/api/v1/items/show-5/progress")
    }

    // MARK: Patches

    func testPatchesApplyInOrder() throws {
        let document = try Self.document()
        let added = SDUINode(type: "Card", id: "jump:9", props: ["title": .string("Film 9")], action: SDUIAction(type: "navigate", to: "/item/9"))
        var replaced = try XCTUnwrap(document.root.find("jump"))
        replaced.children = nil
        replaced.props?["title"] = .string("Keep watching")
        let patched = try document.applying([
            SDUIPatch(op: "add", path: "#jump/children/0", node: added),
            SDUIPatch(op: "move", path: "#jump/children/0", from: "#jump:4"),
            SDUIPatch(op: "remove", path: "#jump:3"),
            SDUIPatch(op: "replace", path: "#jump", node: replaced),
            SDUIPatch(op: "move", path: "#page/children/0", from: "#recent-2"),
            SDUIPatch(op: "replace", path: "/screenTime", value: .object(["reason": .string("limit"), "message": .string("That's all for today.")])),
            SDUIPatch(op: "replace", path: "/personal", value: .null),
            SDUIPatch(op: "replace", path: "/meta", value: .object(["ttlSeconds": .number(0), "etag": .string("ignored")])),
        ])
        XCTAssertEqual(patched.root.kids.map(\.id), ["recent-2", "hero", "jump", "future", "odd"])
        let jump = try XCTUnwrap(patched.root.find("jump"))
        // Replace changes every field but the children.
        XCTAssertEqual(jump.properties.text("title"), "Keep watching")
        XCTAssertEqual(jump.kids.map(\.id), ["jump:4", "jump:9"])
        XCTAssertEqual(patched.screenTime?.message, "That's all for today.")
        XCTAssertNil(patched.personal)
        XCTAssertEqual(patched.meta?.ttlSeconds, 0)
        XCTAssertEqual(patched.meta?.etag, document.meta?.etag, "the ETag is never in a patch")
        // The one before is untouched.
        XCTAssertEqual(document.root.kids.map(\.id), ["hero", "jump", "future", "recent-2", "odd"])

        let whole = try document.applying([SDUIPatch(op: "replace", path: "/root", node: SDUINode(type: "Page", id: "page2"))])
        XCTAssertEqual(whole.root.id, "page2")
    }

    func testAPatchThatCannotBeAppliedThrowsAndNothingIsHalfDone() throws {
        let document = try Self.document()
        let node = SDUINode(type: "Text", id: "t")
        let bad: [[SDUIPatch]] = [
            [SDUIPatch(op: "remove", path: "#nobody")],
            [SDUIPatch(op: "remove", path: "#page")],
            [SDUIPatch(op: "add", path: "#jump/children/9", node: node)],
            [SDUIPatch(op: "add", path: "#jump", node: node)],
            [SDUIPatch(op: "add", path: "#jump/children/0")],
            [SDUIPatch(op: "replace", path: "#jump")],
            [SDUIPatch(op: "move", path: "#hero/children/0", from: "#jump:3")],
            [SDUIPatch(op: "move", path: "#jump/children/5", from: "#jump:3")],
            [SDUIPatch(op: "explode", path: "#jump")],
            [SDUIPatch(op: "add", path: "/root", node: node)],
            [SDUIPatch(op: "replace", path: "/nothing", value: .null)],
            [SDUIPatch(op: "replace", path: "/layout", value: .null)],
            [SDUIPatch(op: "remove", path: "jump:3")],
            [SDUIPatch(op: "remove", path: "#jump:3"), SDUIPatch(op: "remove", path: "#jump:3")],
        ]
        for patches in bad {
            XCTAssertThrowsError(try document.applying(patches), patches.last?.path ?? "")
        }
    }

    func testADeferredRowIsFilledAndAnEmptyOneLeaves() throws {
        let document = try Self.document()
        let answer = try JSONDecoder().decode(SDUISectionItems.self, from: Data(#"""
        {"version":1,"section":"recent-2","props":{"title":"Recently added in Shows","total":40},
         "items":[{"type":"Card","id":"recent-2:1","action":{"type":"navigate","to":"/show/1"},"props":{"title":"Show 1"}},
                  {"type":"Card","id":"recent-2:2","action":{"type":"navigate","to":"/show/2"},"props":{"title":"Show 2"}}],
         "next":"/api/v1/sdui/pages/home/sections/recent-2/items?cursor=2"}
        """#.utf8))
        let filled = document.applying(answer, to: "recent-2")
        let row = try XCTUnwrap(filled.root.find("recent-2"))
        XCTAssertNil(row.state)
        XCTAssertEqual(row.properties.text("title"), "Recently added in Shows")
        XCTAssertEqual(row.properties.text("cardStyle"), "poster", "props are merged, not replaced")
        XCTAssertEqual(row.properties.fields("more")?.text("url"), "/api/v1/sdui/pages/home/sections/recent-2/items?cursor=2")
        let plan = SDUIFocusPlan(root: filled.root)
        XCTAssertEqual(plan.groups["recent-2"], ["recent-2:1", "recent-2:2"])
        XCTAssertEqual(plan.order, ["hero", "jump:3", "jump:4", "b", "recent-2:1", "recent-2:2"])
        XCTAssertEqual(plan.start, "hero")

        // The next page is appended, and with no `next` that's the end.
        let last = SDUISectionItems(items: [SDUINode(type: "Card", id: "recent-2:3", action: SDUIAction(type: "navigate", to: "/show/3"))])
        let more = filled.applying(last, to: "recent-2")
        XCTAssertEqual(more.root.find("recent-2")?.kids.map(\.id), ["recent-2:1", "recent-2:2", "recent-2:3"])
        XCTAssertNil(more.root.find("recent-2")?.properties["more"])
        XCTAssertFalse(SDUIScreen(document: more).root.find("recent-2")?.hasMore ?? true)

        // Asked for again, the page keeps what was fetched for it where it still fits.
        let again = document.keepingLoaded(from: more)
        XCTAssertEqual(again.root.find("recent-2")?.kids.count, 3, "a row that arrives waiting keeps the cards it had")
        XCTAssertNil(again.root.find("recent-2")?.state)
        XCTAssertEqual(SDUIFocusPlan(root: again.root).groups["recent-2"]?.count, 3)
        let paged = document.applying(SDUISectionItems(items: [SDUINode(type: "Card", id: "jump:5")], next: "/api/v1/sdui/pages/home/sections/jump/items?cursor=3"), to: "jump")
        XCTAssertEqual(document.keepingLoaded(from: paged).root.find("jump")?.kids.map(\.id), ["jump:3", "jump:4", "jump:5"])
        XCTAssertEqual(document.keepingLoaded(from: paged).root.find("jump")?.properties.fields("more")?.text("url"), "/api/v1/sdui/pages/home/sections/jump/items?cursor=3")
        var reordered = paged
        reordered.root.change(at: [1]) { $0.children?.reverse() }
        XCTAssertEqual(document.keepingLoaded(from: reordered), document, "a row that no longer starts the same is the server's own")

        let gone = document.applying(SDUISectionItems(state: "empty"), to: "recent-2")
        XCTAssertNil(gone.root.find("recent-2"))
        XCTAssertEqual(document.failing(section: "recent-2").root.find("recent-2")?.state, "error")
        XCTAssertEqual(document.applying(answer, to: "nobody"), document)
        // Focus started on the hero; when that goes, it starts on the first thing left.
        let heroless = try document.applying([SDUIPatch(op: "remove", path: "#hero")])
        var settled = heroless
        settled.renumberFocus()
        XCTAssertEqual(SDUIFocusPlan(root: settled.root).start, "jump:3")
        XCTAssertEqual(SDUIFocusPlan(root: settled.root).order, ["jump:3", "jump:4", "b"])
    }

    // MARK: Focus

    func testFocusFollowsThePagesOrderAndEachGroupRemembersItsMember() throws {
        let plan = SDUIFocusPlan(root: try Self.document().root)
        XCTAssertEqual(plan.order, ["hero", "jump:3", "jump:4", "b"])
        XCTAssertEqual(plan.start, "hero")
        XCTAssertEqual(plan.groups, ["jump": ["jump:3", "jump:4"]])
        XCTAssertEqual(plan.stops, ["hero", "jump", "b"])
        XCTAssertEqual(plan.stop(of: "jump:4"), "jump")
        XCTAssertEqual(plan.stop(from: "jump", by: 1), "b")
        XCTAssertEqual(plan.stop(from: "jump", by: -1), "hero")
        XCTAssertNil(plan.stop(from: "hero", by: -1))
        XCTAssertEqual(plan.neighbour(of: "jump:4", by: 1), "b")
        XCTAssertNil(plan.neighbour(of: "b", by: 1))

        var memory = SDUIFocusMemory()
        XCTAssertNil(memory.moved(to: "hero", in: plan))
        XCTAssertEqual(memory.landing(in: "jump", plan: plan), "jump:3", "a group nobody has been in lands on its first")
        XCTAssertNil(memory.moved(to: "jump:3", in: plan))
        XCTAssertNil(memory.moved(to: "jump:4", in: plan), "moving inside a group is just moving")
        XCTAssertNil(memory.moved(to: "b", in: plan))
        // Coming back up, geometry picked the nearest card; the group remembers the one that had focus.
        XCTAssertEqual(memory.moved(to: "jump:3", in: plan), "jump:4")
        XCTAssertEqual(memory.current, "jump:4")
        XCTAssertNil(memory.moved(to: "jump:3", in: plan), "and from there left is left")
        XCTAssertEqual(memory.landing(in: "jump", plan: plan), "jump:3")
        XCTAssertEqual(memory.landing(in: "hero", plan: plan), "hero")
        // A remembered card that has left the page is forgotten.
        var smaller = try Self.document()
        smaller = try smaller.applying([SDUIPatch(op: "remove", path: "#jump:3")])
        let after = SDUIFocusPlan(root: smaller.root)
        memory.prune(to: after)
        XCTAssertEqual(memory.landing(in: "jump", plan: after), "jump:4")
        XCTAssertNil(memory.moved(to: nil, in: after))
    }

    // MARK: Layout

    func testLayoutNumbersFollowTheSpecsRules() throws {
        let tv = try Self.document().layout
        XCTAssertEqual(tv.contentWidth(), 1760)
        XCTAssertEqual(tv.sectionGap, 60)
        XCTAssertEqual(tv.cardGap, 40)
        XCTAssertEqual(tv.sideMargin, 80)
        XCTAssertEqual(tv.placeholders(cardWidth: 250), 7)
        XCTAssertEqual(tv.placeholders(cardWidth: 60), 12, "no more than the row's first page")
        XCTAssertEqual(tv.gridColumns(cardWidth: 250, sent: 6, window: 1920), 6, "a television keeps the count it was sent")
        XCTAssertEqual(tv.imageWidth(points: 250), 320)
        let phone = SDUILayout.fallback
        XCTAssertEqual(phone.contentWidth(), 358)
        XCTAssertEqual(phone.sectionGap, 16)
        XCTAssertEqual(phone.cardGap, 12)
        XCTAssertEqual(phone.gridColumns(cardWidth: 120, sent: 3, window: nil), 3)
        // The window changed without crossing a breakpoint: max(minimum, floor((content + gap) / (card + gap))).
        XCTAssertEqual(phone.gridColumns(cardWidth: 120, sent: 3, window: 430), 3)
        XCTAssertEqual(phone.gridColumns(cardWidth: 120, sent: 3, window: 590), 4)
        XCTAssertEqual(phone.gridColumns(cardWidth: 120, sent: 3, window: 200), 3, "at least 3 for cards under 130")
        XCTAssertEqual(phone.gridColumns(cardWidth: 224, sent: 2, window: 320), 2)
        XCTAssertEqual(phone.imageWidth(points: 120), 480)
        XCTAssertEqual(phone.imageWidth(points: 5000), 3840)
        XCTAssertEqual(["compact", "compact", "medium", "expanded", "large"], [320, 599, 600, 840, 1200].map { SDUILayout.breakpoint(width: $0) })
        XCTAssertEqual(SDUILayout.ratio("16/9"), 16.0 / 9.0)
        XCTAssertNil(SDUILayout.ratio("wide"))
        XCTAssertEqual(SDUILayout.truncate("A small crew sets out to find film number 3", limit: 20), "A small crew sets…")
        XCTAssertEqual(SDUILayout.truncate("Short", limit: 20), "Short")
        XCTAssertEqual(SDUILayout.truncate("Supercalifragilisticexpialidocious", limit: 10), "Supercali…")
    }

    func testWhatADeviceSaysAboutItself() {
        let hd = SDUIDevice.appleTV(pixelsWide: 1920, reducedMotion: false, views: ["guide"])
        XCTAssertEqual(SDUIQuery.encode(hd.query), "catalog=8&platform=tvos&formFactor=tv&deviceClass=hd&views=guide")
        let uhd = SDUIDevice.appleTV(pixelsWide: 3840, reducedMotion: true, hdr: true, views: [])
        XCTAssertEqual(SDUIQuery.encode(uhd.query), "catalog=8&platform=tvos&formFactor=tv&deviceClass=4k&capabilities=reducedMotion%2Chdr")
        let phone = SDUIDevice.touch(pad: false, width: 393, height: 852, reducedMotion: false, locale: "en-GB", views: ["guide"])
        XCTAssertEqual(SDUIQuery.encode(phone.query), "catalog=8&platform=ios&formFactor=phone&viewport=393x852&views=guide&capabilities=touch&locale=en-GB")
        // An iPad sharing its screen is still a tablet, with the part of the screen it has.
        let split = SDUIDevice.touch(pad: true, width: 507, height: 1024, reducedMotion: false, views: [])
        let full = SDUIDevice.touch(pad: true, width: 1366, height: 1024, reducedMotion: false, views: [])
        let wider = SDUIDevice.touch(pad: true, width: 1210, height: 1024, reducedMotion: false, views: [])
        XCTAssertEqual(split.formFactor, "tablet")
        XCTAssertEqual(split.breakpoint, "compact")
        XCTAssertTrue(split.needsNewPage(after: full), "the window crossed a breakpoint")
        XCTAssertFalse(wider.needsNewPage(after: full), "the window changed inside one")
        XCTAssertEqual(wider.cacheName, full.cacheName)
        XCTAssertNotEqual(split.cacheName, full.cacheName)
        var few = phone
        few.components = []
        XCTAssertTrue(SDUIQuery.encode(few.query).contains("components=none"))
        XCTAssertEqual(SDUIQuery.page(["q": "a b&c", "tab": ""], hd), "q=a%20b%26c&catalog=8&platform=tvos&formFactor=tv&deviceClass=hd&views=guide")
    }

    func testOnlyTheServersOwnAddressesAreAskedFor() {
        let device = SDUIDevice.appleTV(pixelsWide: 1920, reducedMotion: false, views: [])
        XCTAssertEqual(SDUIQuery.path(fromServer: "/api/v1/sdui/pages/home/sections/jump/items?cursor=12", device: device),
                       "/sdui/pages/home/sections/jump/items?cursor=12&catalog=8&platform=tvos&formFactor=tv&deviceClass=hd")
        XCTAssertEqual(SDUIQuery.path(fromServer: "/api/sdui/pages/home/personal", device: nil), "/sdui/pages/home/personal")
        XCTAssertEqual(SDUIQuery.path(fromServer: "/api/v1/sdui/pages/x/sections/y/items?cursor=0&platform=web", device: device),
                       "/sdui/pages/x/sections/y/items?cursor=0&platform=web&catalog=8&formFactor=tv&deviceClass=hd")
        for bad in ["https://example.com/api/v1/sdui/x", "/api/v1/users", "/api/v1/sdui/../users", "//example.com/api/v1/sdui/x", "/api/v1/sdui/x y", ""] {
            XCTAssertNil(SDUIQuery.path(fromServer: bad, device: device), bad)
        }
    }

    // MARK: Customise

    func testCustomiseSendsTheOrderHiddenAndPinnedRows() throws {
        let document = try Self.document()
        var edit = SDUICustomise(document: document, stored: SDUIPersonal(order: ["old-row"], cardSize: ["old-row": "l"]))
        XCTAssertTrue(edit.offersAnything)
        XCTAssertEqual(edit.rows.map(\.id), ["hero", "jump", "future", "recent-2", "onnow", "gone"])
        XCTAssertEqual(edit.rows.map(\.cardSize), [nil, nil, nil, nil, nil, nil], "none of these rows says its size")
        XCTAssertFalse(edit.changed)
        edit.move(from: 3, to: 0)            // recent-2 to the top
        edit.setHidden("hero", true)
        edit.setPinned("jump", true)
        edit.setHidden("gone", false)
        edit.setDensity("compact")
        edit.setHidden("future", true)       // locked: never hidden
        edit.move(from: edit.rows.firstIndex { $0.id == "future" } ?? 0, to: 0) // locked: never moves
        XCTAssertEqual(edit.rows.map(\.id), ["jump", "recent-2", "hero", "future", "onnow", "gone"])
        let sent = edit.personal
        XCTAssertEqual(sent.pinned, ["jump"])
        XCTAssertEqual(sent.order, ["recent-2", "hero", "future", "onnow", "gone", "old-row"], "what this page doesn't show is kept")
        XCTAssertEqual(sent.hidden, ["hero"])
        XCTAssertEqual(sent.density, "compact")
        XCTAssertEqual(sent.cardSize, ["old-row": "l"])
        XCTAssertTrue(edit.changed)
        // A remote: one place at a time, never past a locked row or out of the pinned ones.
        XCTAssertFalse(edit.canMove("jump", by: 1), "the only pinned row stays first")
        XCTAssertTrue(edit.canMove("recent-2", by: 1))
        XCTAssertFalse(edit.canMove("hero", by: 1), "not past a locked row")
        XCTAssertFalse(edit.canMove("future", by: -1))
        edit.move("recent-2", by: 1)
        XCTAssertEqual(edit.rows.map(\.id).prefix(3), ["jump", "hero", "recent-2"])
        edit.setPinned("jump", false)
        XCTAssertNil(edit.personal.pinned)
        let body = try JSONEncoder().encode(edit.personal)
        XCTAssertLessThan(body.count, 8192)
    }

    func testCustomiseOffersOnlyWhatThePageAllows() throws {
        var document = try Self.document()
        document.personal?.allow = ["hide"]
        var edit = SDUICustomise(document: document, stored: SDUIPersonal(order: ["jump", "hero"], density: "spacious"))
        XCTAssertFalse(edit.canReorder)
        edit.move(from: 0, to: 2)
        edit.setDensity("compact")
        edit.setPinned("jump", true)
        edit.setHidden("jump", true)
        XCTAssertEqual(edit.personal, SDUIPersonal(order: ["jump", "hero"], hidden: ["jump", "gone"], density: "spacious"))
        // The `editLayout` switch is off: nothing is offered, and nothing changes.
        document.personal?.editable = false
        var none = SDUICustomise(document: document, stored: SDUIPersonal())
        XCTAssertFalse(none.offersAnything)
        none.setHidden("jump", true)
        XCTAssertFalse(none.changed)
        document.personal = nil
        XCTAssertFalse(SDUICustomise(document: document, stored: SDUIPersonal()).offersAnything)
    }

    func testCardSizesAndTheTabThatOpensFirst() throws {
        let text = #"""
        {"version":1,"page":{"id":"library-music","kind":"library","title":"Music"},
         "root":{"type":"Page","id":"page","children":[
           {"type":"Shelf","id":"played","props":{"title":"Recently played","cardSize":"m","cardStyle":"album"}},
           {"type":"Tabs","id":"views","props":{"selected":"albums","default":"albums"},"children":[
             {"type":"Tab","id":"albums","props":{"label":"Albums","selected":true},"children":[{"type":"Grid","id":"albums-grid","props":{"cardSize":"m"}}]},
             {"type":"Tab","id":"artists","props":{"label":"Artists"}}]}]},
         "personal":{"editable":true,"allow":["cardSize","defaultTab"],"sections":[{"id":"played","title":"Recently played"},{"id":"views","title":"Tabs"}],"url":"/api/v1/sdui/pages/library-music/personal"}}
        """#
        let document = try JSONDecoder().decode(SDUIDocument.self, from: Data(text.utf8))
        var edit = SDUICustomise(document: document, stored: SDUIPersonal())
        XCTAssertEqual(edit.rows.map(\.cardSize), ["m", nil])
        XCTAssertEqual(edit.tabs.map(\.chosen), ["albums"])
        XCTAssertFalse(edit.changed)
        edit.setCardSize("played", "l")
        edit.setCardSize("views", "l")
        edit.setCardSize("played", "xxl")
        edit.setDefaultTab("views", "artists")
        edit.setDefaultTab("views", "nobody")
        XCTAssertEqual(edit.personal, SDUIPersonal(cardSize: ["played": "l"], defaultTab: ["views": "artists"]))
    }

    func testTheMenusOwnOrderNeverHidesSettings() {
        let shown = [SDUINavItem(id: "home", label: "Home", kind: "page", page: "home"),
                     SDUINavItem(id: "search", label: "Search", kind: "page", page: "search"),
                     SDUINavItem(id: "settings", label: "Settings", kind: "native", screen: "settings")]
        var edit = SDUINavCustomise(shown: shown, stored: SDUIPersonal(hidden: ["livetv"]), names: ["livetv": "Live TV"])
        XCTAssertEqual(edit.rows.map(\.label), ["Home", "Search", "Settings", "Live TV"])
        XCTAssertFalse(edit.changed == false && edit.personal.order == nil)
        edit.setHidden("settings", true)
        edit.setHidden("search", true)
        edit.setHidden("livetv", false)
        edit.move("settings", by: -1)
        XCTAssertEqual(edit.personal, SDUIPersonal(order: ["home", "settings", "search", "livetv"], hidden: ["search"]))
    }

    func testTheMenuListsWhatTheServerSaysTheProfileCouldHave() throws {
        let json = #"""
        {"version":1,"items":[{"id":"home","label":"Home","kind":"page","page":"home","icon":"home"},
          {"id":"settings","label":"Settings","kind":"native","screen":"settings"}],
          "personal":{"editable":true,"allow":["reorder","hide"],"url":"/api/v1/sdui/navigation/personal",
          "sections":[{"id":"home","title":"Home"},{"id":"livetv","title":"Live TV","hidden":true},{"id":"settings","title":"Settings"}]}}
        """#
        let navigation = try JSONDecoder().decode(SDUINavigation.self, from: Data(json.utf8))
        XCTAssertEqual(navigation.personal?.sections?.count, 3)
        var edit = SDUINavCustomise(shown: navigation.items, stored: SDUIPersonal(hidden: ["livetv"]), listed: navigation.personal)
        XCTAssertEqual(edit.rows.map(\.label), ["Home", "Live TV", "Settings"], "a hidden entry has its name and its place")
        XCTAssertEqual(edit.rows.map(\.hidden), [false, true, false])
        XCTAssertEqual(edit.rows.first?.icon, "home")
        XCTAssertTrue(edit.rows.last?.fixed == true)
        edit.setHidden("livetv", false)
        edit.setHidden("settings", true)
        XCTAssertEqual(edit.personal, SDUIPersonal(order: ["home", "livetv", "settings"]))
    }

    func testAPageWrittenForAnotherRevisionIsRefusedAndTheCountIsTheServersWords() throws {
        var old = try JSONDecoder().decode(SDUIDocument.self, from: Data(Self.page.utf8))
        XCTAssertTrue(SDUI.accepts(old))
        old.catalog = 4
        XCTAssertFalse(SDUI.accepts(old), "a client built for revision 4 refuses another revision's tree")
        old.catalog = nil
        XCTAssertTrue(SDUI.accepts(old))
        let bar = #"{"version":1,"catalog":8,"page":{"id":"l","kind":"library","title":"L"},"layout":{"formFactor":"phone"},"root":{"type":"Page","id":"page","children":[{"type":"FilterBar","id":"f","props":{"count":1,"countText":"1 title"}},{"type":"DetailHeader","id":"h","props":{"title":"T","actions":[{"id":"watchLater","label":"In Watch later","icon":"check","pressed":true,"action":{"type":"command","op":"watchLater.remove","item":"5"}}]}}]}}"#
        let screen = SDUIScreen(document: try JSONDecoder().decode(SDUIDocument.self, from: Data(bar.utf8)))
        XCTAssertEqual(screen.root.find("f")?.shown("count"), "1 title")
        XCTAssertEqual(screen.root.find("h")?.buttons.first?.pressed, true)
    }

    // MARK: Theme scopes

    func testAScopesTokensGoOnTopOfTheTheme() {
        let theme = ThemeTranslator.translate(ThemeTokens(id: "t", colors: ThemeTranslator.witty))
        let scoped = SDUITheme.apply(["accent": "#2A6FDB", "bg3": "#101820", "nonsense": "#fff", "fg": "url(x)"], to: theme)
        XCTAssertEqual(scoped.accent, ThemeColour(hex: "#2A6FDB"))
        XCTAssertEqual(scoped.accentText, ThemeColour(hex: "#2A6FDB"))
        XCTAssertEqual(scoped.onAccent, .white)
        XCTAssertEqual(scoped.card, ThemeColour(hex: "#101820"))
        XCTAssertEqual(scoped.text, theme.text, "something that isn't a colour changes nothing")
        XCTAssertEqual(scoped.background, theme.background)
        XCTAssertEqual(SDUITheme.apply(["accent": "#ffee00", "accentFg": "#000000"], to: theme).onAccent, ThemeColour(hex: "#000000"))
        XCTAssertEqual(SDUITheme.apply(nil, to: theme), theme)
        XCTAssertEqual(SDUITheme.apply([:], to: theme), theme)
        // A node's tokens go on top of the page's.
        let page = SDUITheme.apply(["accent": "#ff0000", "bg": "#ffffff"], to: theme)
        let node = SDUITheme.apply(["accent": "#00ff00"], to: page)
        XCTAssertEqual(node.accent, ThemeColour(hex: "#00ff00"))
        XCTAssertEqual(node.background, ThemeColour(hex: "#ffffff"))
        XCTAssertTrue(node.isLight)
        XCTAssertEqual(SDUITheme.onImage(["onImage": "#ffeecc"]), ThemeColour(hex: "#ffeecc"))
        XCTAssertEqual(SDUITheme.onImage(nil), .white)
    }

    // MARK: Markdown

    func testTheMarkdownSubset() {
        let blocks = SDUIMarkdown.blocks("## Friday, 7 o'clock\nPick **one** each. The [full list](/collections/12) is *longer*.\n\n- `a`\n1. b\n<b>not html</b> [x](javascript:alert(1))")
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0], .heading(2, [.plain("Friday, 7 o'clock")]))
        XCTAssertEqual(blocks[1], .paragraph([.plain("Pick "), .bold("one"), .plain(" each. The "), .link("full list", to: "/collections/12"), .plain(" is "), .italic("longer"), .plain(".")]))
        XCTAssertEqual(blocks[2], .item(number: nil, [.code("a")]))
        XCTAssertEqual(blocks[3], .item(number: 1, [.plain("b")]))
        guard case .paragraph(let last) = blocks[4] else { return XCTFail("a paragraph") }
        XCTAssertEqual(last.first, .plain("<b>not html</b> "))
        XCTAssertFalse(last.contains { if case .link = $0 { return true } else { return false } }, "only a route or a web address is a link")
        XCTAssertEqual(SDUIMarkdown.spans("2 * 3 = 6"), [.plain("2 * 3 = 6")])
        XCTAssertEqual(SDUIMarkdown.plainText("## Friday\nPick **one**. The [full list](/collections/12) is longer."), "Friday Pick one. The full list is longer.")
    }

    // MARK: Top Shelf and links

    func testTheTopShelfIsTheServersWithLinksIntoTheApp() throws {
        let text = #"""
        {"version":1,"style":"sectioned","expiresInSec":900,"sections":[
          {"title":"Continue watching","items":[
            {"id":"12","title":"Film 3","shape":"wide","progress":0.4,"image":{"url":"/api/items/12/backdrop?w=908","width":908,"height":512},"displayRoute":"/item/12","playRoute":"/watch/12"},
            {"id":"bad","title":"Elsewhere","displayRoute":"https://example.com/"},
            {"id":"12","title":"Twice","displayRoute":"/item/12"}]},
          {"title":"New in Music","items":[{"id":"album-5-817","title":"An Album","shape":"square","image":{"url":"https://example.com/x.jpg"},"displayRoute":"/album/5?artist=The+Examples&album=An+Album"}]},
          {"title":"Nothing","items":[]}]}
        """#
        let made = Shelf.from(topShelf: try JSONDecoder().decode(SDUITopShelf.self, from: Data(text.utf8)))
        XCTAssertEqual(made.shelf.sections.map(\.title), ["Continue watching", "New in Music"])
        let film = try XCTUnwrap(made.shelf.sections.first?.entries.first)
        XCTAssertEqual(made.shelf.sections.first?.entries.count, 1)
        XCTAssertEqual(film.shape, "wide")
        XCTAssertEqual(film.progress, 0.4)
        XCTAssertEqual(DeepLink.parse(try XCTUnwrap(URL(string: film.link))), .route("/item/12"))
        XCTAssertEqual(DeepLink.parse(try XCTUnwrap(URL(string: try XCTUnwrap(film.play)))), .route("/watch/12"))
        XCTAssertEqual(made.pictures.map(\.url), ["/api/items/12/backdrop?w=908"], "only this server's pictures")
        XCTAssertTrue(Shelf.isPosterName(try XCTUnwrap(film.poster)))
        let album = try XCTUnwrap(made.shelf.sections.last?.entries.first)
        XCTAssertNil(album.poster)
        XCTAssertEqual(DeepLink.parse(try XCTUnwrap(URL(string: album.link))), .route("/album/5?artist=The+Examples&album=An+Album"))

        // Written and read back, as the extension reads it.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sdui-shelf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try made.shelf.write(to: folder)
        XCTAssertEqual(Shelf.read(from: folder), made.shelf)
    }

    func testALinkFromOutsideOnlyChoosesAScreen() throws {
        func parse(_ text: String) -> DeepLink? { URL(string: text).flatMap(DeepLink.parse) }
        XCTAssertEqual(parse(DeepLink.route("/show/6").address), .route("/show/6"))
        XCTAssertEqual(parse("wittymedia://item/42"), .item(42))
        for bad in ["/settings", "/you", "/pair", "/tv/watch/x", "/watch/abc", "/nowhere", "//example.com", "/page/../x"] {
            XCTAssertNil(parse(DeepLink.route(bad).address), bad)
            XCTAssertFalse(DeepLink.isOpenable(bad), bad)
        }
        XCTAssertNil(parse("wittymedia://route/" + String(repeating: "a", count: 2000)))
    }

    // MARK: The cache

    func testTheCacheKeepsTheLastAnswersAndNoMore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sdui-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = SDUICache(folder: folder, maxEntries: 3, maxBytes: 64)
        XCTAssertNil(cache.read("a"))
        cache.write("a", etag: "1", body: Data("one".utf8))
        XCTAssertEqual(cache.read("a")?.etag, "1")
        XCTAssertEqual(cache.read("a")?.body, Data("one".utf8))
        cache.write("a", etag: "2", body: Data("two".utf8))
        XCTAssertEqual(cache.read("a")?.etag, "2")
        cache.write("big", etag: "x", body: Data(repeating: 0, count: 65))
        XCTAssertNil(cache.read("big"), "too big to keep")
        for name in ["b", "c", "d", "e"] {
            cache.write(name, etag: name, body: Data(name.utf8))
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual(cache.count, 3)
        XCTAssertNil(cache.read("a"), "the oldest goes first")
        XCTAssertNotNil(cache.read("e"))
        cache.remove("e")
        XCTAssertNil(cache.read("e"))
        // A key can't name a file outside the folder.
        cache.write("../../escape", etag: "1", body: Data("x".utf8))
        XCTAssertEqual(cache.read("../../escape")?.etag, "1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("escape.json").path))
        cache.clear()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNotEqual(SDUICache.fileName("a|1"), SDUICache.fileName("a|2"))
    }

    // MARK: The requests

    private var stands: [StandInServer] = []
    override func tearDown() {
        stands.forEach { $0.stop() }
        stands = []
    }

    private func stand(_ respond: @escaping @Sendable (StandInServer.Request) -> Data) throws -> StandInServer {
        let made = try StandInServer(respond: respond)
        stands.append(made)
        return made
    }

    private func tempCache() -> SDUICache {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sdui-loader-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return SDUICache(folder: folder)
    }

    func testAPageIsAskedForWithTheDeviceAndKeptWithItsETag() async throws {
        let body = Self.page.replacingOccurrences(of: "\n", with: " ")
        let server = try stand { request in
            if request.head.lowercased().contains("if-none-match: w/\"sha256-abc\"") { return StandInServer.answer(status: "304 Not Modified") }
            return StandInServer.answer(headers: [#"ETag: W/"sha256-abc""#], body: body)
        }
        let device = SDUIDevice.appleTV(pixelsWide: 1920, reducedMotion: false, views: ["guide"])
        let loader = SDUIPageLoader(client: WittyClient(base: server.address, token: "t"), cache: tempCache())
        XCTAssertNil(loader.kept("home", params: [:], device: device))
        let first = try await loader.load("home", params: ["tab": "a"], device: device)
        XCTAssertEqual(first.etag, #"W/"sha256-abc""#)
        XCTAssertFalse(first.offline)
        let second = try await loader.load("home", params: ["tab": "a"], device: device)
        XCTAssertEqual(second.document, first.document, "a 304 is the page that was kept")
        XCTAssertEqual(server.requests.map(\.path), Array(repeating: "/api/v1/sdui/pages/home?tab=a&catalog=8&platform=tvos&formFactor=tv&deviceClass=hd&views=guide", count: 2))
        XCTAssertNotNil(loader.kept("home", params: ["tab": "a"], device: device))
        XCTAssertNil(loader.kept("home", params: ["tab": "b"], device: device))
    }

    func testWithNoNetworkTheLastGoodPageIsShown() async throws {
        let body = Self.page.replacingOccurrences(of: "\n", with: " ")
        let server = try stand { _ in StandInServer.answer(headers: [#"ETag: W/"sha256-abc""#], body: body) }
        let device = SDUIDevice.touch(pad: false, width: 393, height: 852, reducedMotion: false, views: [])
        let cache = tempCache()
        _ = try await SDUIPageLoader(client: WittyClient(base: server.address, token: "t"), cache: cache).load("home", params: [:], device: device)
        server.stop()
        // Nothing listens there any more.
        let away = SDUIPageLoader(client: WittyClient(base: server.address, token: "t", quick: true), cache: cache)
        let kept = try await away.load("home", params: [:], device: device)
        XCTAssertTrue(kept.offline)
        XCTAssertEqual(kept.document.page.id, "home")
        do {
            _ = try await away.load("library", params: ["library": "1"], device: device)
            XCTFail("nothing was kept for that page")
        } catch {}
    }

    func testAPageThatIsNoLongerTheProfilesIsForgotten() async throws {
        let body = Self.page.replacingOccurrences(of: "\n", with: " ")
        final class Flag: @unchecked Sendable { var gone = false }
        let flag = Flag()
        let server = try stand { _ in
            flag.gone ? StandInServer.answer(status: "404 Not Found", body: #"{"error":"not found"}"#) : StandInServer.answer(headers: [#"ETag: "e1""#], body: body)
        }
        let device = SDUIDevice.appleTV(pixelsWide: 3840, reducedMotion: false, views: [])
        let loader = SDUIPageLoader(client: WittyClient(base: server.address, token: "t"), cache: tempCache())
        _ = try await loader.load("detail", params: ["item": "3"], device: device)
        flag.gone = true
        do {
            _ = try await loader.load("detail", params: ["item": "3"], device: device)
            XCTFail("a 404 is a 404")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 404)
        }
        XCTAssertNil(loader.kept("detail", params: ["item": "3"], device: device))
    }

    func testAskingAgainTakesPatchesOrTheWholePage() async throws {
        let body = Self.page.replacingOccurrences(of: "\n", with: " ")
        final class Mode: @unchecked Sendable { var answer = "" }
        let mode = Mode()
        let server = try stand { request in
            if request.path.contains("/diff?") {
                return mode.answer.isEmpty ? StandInServer.answer(status: "304 Not Modified") : StandInServer.answer(headers: [#"ETag: "e2""#], body: mode.answer)
            }
            return StandInServer.answer(headers: [#"ETag: "e1""#], body: body)
        }
        let device = SDUIDevice.appleTV(pixelsWide: 1920, reducedMotion: false, views: [])
        let loader = SDUIPageLoader(client: WittyClient(base: server.address, token: "t"), cache: tempCache())
        let first = try await loader.load("home", params: [:], device: device)
        let same = try await loader.refresh("home", params: [:], device: device, current: first)
        XCTAssertEqual(same, first)
        XCTAssertTrue(server.requests.last?.path.hasPrefix("/api/v1/sdui/pages/home/diff?since=%22e1%22&catalog=8") ?? false, server.requests.last?.path ?? "")

        mode.answer = ##"{"etag":"\"e2\"","since":"\"e1\"","patches":[{"op":"remove","path":"#jump:3"}]}"##
        let patched = try await loader.refresh("home", params: [:], device: device, current: first)
        XCTAssertEqual(patched.etag, #""e2""#)
        XCTAssertNil(patched.document.root.find("jump:3"))
        XCTAssertEqual(loader.kept("home", params: [:], device: device)?.etag, #""e2""#, "what's kept is the patched page")

        // A patch that can't be applied: the tree is dropped and the page asked for.
        mode.answer = ##"{"etag":"\"e3\"","patches":[{"op":"remove","path":"#nobody"}]}"##
        let reloaded = try await loader.refresh("home", params: [:], device: device, current: first)
        XCTAssertEqual(reloaded.etag, #""e1""#)
        XCTAssertFalse(server.requests.last?.path.contains("/diff") ?? true)

        mode.answer = #"{"etag":"\"e4\"","document":{"version":1,"page":{"id":"home","kind":"home","title":"New"},"root":{"type":"Page","id":"page"}}}"#
        let whole = try await loader.refresh("home", params: [:], device: device, current: first)
        XCTAssertEqual(whole.document.page.title, "New")
    }

    func testTheOtherRequestsGoWhereTheSpecSays() async throws {
        let server = try stand { request in
            if request.path.contains("/items?") { return StandInServer.answer(body: #"{"version":1,"section":"jump","items":[{"type":"Card","id":"jump:9"}]}"#) }
            if request.path.contains("/navigation?") { return StandInServer.answer(headers: [#"ETag: W/"nav-1""#], body: #"{"version":1,"items":[{"id":"home","label":"Home","kind":"page","page":"home"}]}"#) }
            if request.path.hasSuffix("/personal"), request.line.hasPrefix("GET") { return StandInServer.answer(body: #"{"order":["a"],"density":"compact"}"#) }
            if request.path.contains("/topshelf") { return StandInServer.answer(body: #"{"version":1,"sections":[]}"#) }
            if request.path.contains("/catalog") { return StandInServer.answer(body: #"{"revision":2}"#) }
            return StandInServer.answer(body: "{}")
        }
        let client = WittyClient(base: server.address, token: "t")
        let device = SDUIDevice.appleTV(pixelsWide: 1920, reducedMotion: false, views: [])
        let items = try await client.sduiItems(url: "/api/v1/sdui/pages/home/sections/jump/items?cursor=2", device: device)
        XCTAssertEqual(items.items?.map(\.id), ["jump:9"])
        guard case .new(let menu, let etag, _) = try await client.sduiNavigation(device: device) else { return XCTFail("a menu") }
        XCTAssertEqual(menu.items.map(\.id), ["home"])
        XCTAssertEqual(etag, #"W/"nav-1""#)
        let mine = try await client.sduiPersonal(page: "home")
        XCTAssertEqual(mine, SDUIPersonal(order: ["a"], density: "compact"))
        try await client.setSDUIPersonal(SDUIPersonal(hidden: ["hero"]), page: "home")
        try await client.resetSDUIPersonal(page: nil)
        _ = try await client.sduiTopShelf(deviceClass: "4k")
        _ = try await client.sduiCatalog()
        let done = try await client.sduiCommand(SDUICatalog.builtIn.command("watched.clear"), item: "12")
        XCTAssertTrue(done)
        let nothing = try await client.sduiCommand(SDUICatalog.builtIn.command("refresh"), item: "12")
        XCTAssertFalse(nothing)
        XCTAssertEqual(server.requests.map { $0.line.split(separator: " ").prefix(2).joined(separator: " ") }, [
            "GET /api/v1/sdui/pages/home/sections/jump/items?cursor=2&catalog=8&platform=tvos&formFactor=tv&deviceClass=hd",
            "GET /api/v1/sdui/navigation?catalog=8&platform=tvos&formFactor=tv&deviceClass=hd",
            "GET /api/v1/sdui/pages/home/personal",
            "PUT /api/v1/sdui/pages/home/personal",
            "DELETE /api/v1/sdui/navigation/personal",
            "GET /api/v1/sdui/topshelf?catalog=8&platform=tvos&deviceClass=4k",
            "GET /api/v1/sdui/catalog",
            "DELETE /api/v1/items/12/progress",
        ])
        do {
            _ = try await client.sduiItems(url: "https://example.com/api/v1/sdui/x", device: device)
            XCTFail("not this server's")
        } catch {}
        do {
            _ = try await client.sduiPage("../users", params: [:], device: device)
            XCTFail("not a page's name")
        } catch {}
    }

    func testWhichServersHaveServerDrivenPages() {
        XCTAssertTrue(SDUI.available(["sdui", "sdui-pages", "sdui-catalog", "sdui-navigation", "sdui-personal", "live-tv"]))
        XCTAssertFalse(SDUI.available(["sdui", "sdui-pages", "sdui-catalog"]))
        XCTAssertFalse(SDUI.available([]))
    }
}
