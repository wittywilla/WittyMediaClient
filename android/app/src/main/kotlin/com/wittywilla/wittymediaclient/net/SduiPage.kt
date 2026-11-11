// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// A page while it is on screen: the document as the server rendered it, and over it what this app has since asked
// for itself: the items of deferred sections, the next pages of rows and grids, another season. The two are kept
// apart so a diff from the server applies to exactly the tree it was made against (docs/SDUI.md, Patch protocol),
// and what was fetched is laid back over the result.

// What has been fetched for one section.
data class SduiSectionLoad(
    // The cards fetched: after the section's own, or in their place when `replaced`.
    val items: List<SduiNode> = emptyList(),
    val replaced: Boolean = false,
    // The section's props as the last answer that carried them had them.
    val props: JsonObject? = null,
    // Where the next page is; empty at the end.
    val next: String = "",
    // An answer has arrived: `next` stands for the section's own more.url from then on.
    val answered: Boolean = false,
    // The last request failed, and there is nothing to show in its place.
    val failed: Boolean = false,
    // A deferred section that turned out empty: it is taken off the page.
    val gone: Boolean = false,
)

class SduiPage(val base: SduiDocument, val loads: Map<String, SduiSectionLoad> = emptyMap()) {
    // What is drawn: the server's tree with what was fetched laid over it.
    val shown: SduiDocument by lazy { if (loads.isEmpty()) base else base.copy(root = overlay(base.root) ?: base.root) }

    private fun overlay(node: SduiNode): SduiNode? {
        val load = loads[node.id]
        if (load?.gone == true) return null
        val children = node.children.mapNotNull(::overlay)
        if (load == null) return if (children == node.children) node else node.copy(children = children)
        var props = node.props
        load.props?.let { props = JsonObject(props + it) }
        if (load.answered) {
            props = JsonObject(if (load.next.isEmpty()) props - "more" else props + ("more" to buildJsonObject { put("url", load.next) }))
        }
        val cards = if (load.replaced) load.items else children + load.items
        val state = when {
            load.failed && cards.isEmpty() -> "error"
            load.answered -> ""
            else -> node.state
        }
        return node.copy(props = props, children = cards, state = state)
    }

    fun find(id: String): SduiNode? = find(shown.root, id)

    // Where a section's next page is asked for now: what its last answer said, else its own more.url.
    fun moreUrl(section: String): String = find(section)?.props?.child("more")?.str("url").orEmpty()

    // A page of a section's items has arrived: a deferred section's first, a row's next, or another season's.
    fun withItems(section: String, answer: SduiSectionItems): SduiPage {
        val before = loads[section] ?: SduiSectionLoad()
        val own = find(base.root, section)
        val first = !before.answered && own?.state == "deferred"
        val replace = answer.replace || first
        val have = if (replace) emptySet() else (own?.children.orEmpty() + before.items).mapTo(HashSet()) { it.id }
        // A library can change between two pages: a card already there isn't shown twice.
        val fresh = answer.items.filter { it.id !in have }.distinctBy { it.id }
        val items = if (replace) fresh else before.items + fresh
        val gone = answer.state == "empty" && items.isEmpty() && (first || own?.children.isNullOrEmpty())
        return SduiPage(
            base,
            loads + (section to SduiSectionLoad(items, replace || before.replaced, answer.props ?: before.props, answer.next, answered = true, failed = false, gone = gone)),
        )
    }

    // A section's request failed. Its cards stay; one with nothing to show says so, with Retry.
    fun withFailure(section: String): SduiPage =
        SduiPage(base, loads + (section to (loads[section] ?: SduiSectionLoad()).copy(failed = true)))

    // The server's newer render of the same page. What was fetched for a section the render left as it was stays.
    fun withBase(fresh: SduiDocument): SduiPage {
        val kept = loads.filter { (id, _) -> find(base.root, id).let { it != null && it == find(fresh.root, id) } }
        return SduiPage(fresh, kept)
    }

    companion object {
        fun find(node: SduiNode, id: String): SduiNode? {
            if (node.id == id) return node
            for (child in node.children) find(child, id)?.let { return it }
            return null
        }
    }
}

// The ID-keyed tree diff of docs/SDUI.md, "Patch protocol".
object SduiPatches {
    private class Tree(var node: SduiNode, val children: MutableList<Tree>) {
        fun frozen(): SduiNode = node.copy(children = children.map { it.frozen() })
    }

    private fun thaw(node: SduiNode): Tree = Tree(node.copy(children = emptyList()), node.children.mapTo(ArrayList()) { thaw(it) })

    private fun find(tree: Tree, id: String): Tree? {
        if (tree.node.id == id) return tree
        for (child in tree.children) find(child, id)?.let { return it }
        return null
    }

    private fun parentOf(tree: Tree, id: String): Tree? {
        if (tree.children.any { it.node.id == id }) return tree
        for (child in tree.children) parentOf(child, id)?.let { return it }
        return null
    }

    private inline fun <reified T> decode(value: JsonElement?): T? =
        if (value == null || value is JsonNull) null else json.decodeFromJsonElement(kotlinx.serialization.serializer<T>(), value)

    // The document with the patches applied in order, or null when any step fails (an unknown ID, a bad index, an
    // operation this app doesn't know): the caller then drops its tree and asks for the page.
    fun apply(document: SduiDocument, patches: List<SduiPatch>): SduiDocument? = runCatching {
        var doc = document
        var root = thaw(document.root)
        for (p in patches) {
            if (p.path.startsWith("/")) {
                if (p.op != "replace") return null
                when (p.path) {
                    "/root" -> root = thaw(p.node ?: decode<SduiNode>(p.value) ?: return null)
                    "/page" -> doc = doc.copy(page = decode<SduiPageInfo>(p.value) ?: SduiPageInfo())
                    "/layout" -> doc = doc.copy(layout = decode<SduiLayout>(p.value))
                    "/theme" -> doc = doc.copy(theme = decode<SduiThemeScope>(p.value))
                    "/personal" -> doc = doc.copy(personal = decode<SduiPersonalInfo>(p.value))
                    "/screenTime" -> doc = doc.copy(screenTime = decode<SduiScreenTime>(p.value))
                    "/catalog" -> doc = doc.copy(catalog = (p.value as? JsonPrimitive)?.content?.toIntOrNull() ?: 0)
                    // generatedAt and etag are never in a patch: they stay as they were, and the answer's ETag is set after.
                    "/meta" -> doc = doc.copy(meta = (decode<SduiMeta>(p.value) ?: SduiMeta()).copy(etag = doc.meta.etag, generatedAt = doc.meta.generatedAt))
                    else -> return null
                }
                continue
            }
            if (!p.path.startsWith("#")) return null
            val at = p.path.indexOf("/children/")
            val id = if (at < 0) p.path.drop(1) else p.path.substring(1, at)
            val index = if (at < 0) null else p.path.substring(at + "/children/".length).toIntOrNull() ?: return null
            when (p.op) {
                "add" -> {
                    val parent = find(root, id) ?: return null
                    if (index == null || index !in 0..parent.children.size) return null
                    parent.children.add(index, thaw(p.node ?: return null))
                }
                "remove" -> {
                    if (index != null) return null
                    val parent = parentOf(root, id) ?: return null
                    parent.children.removeAll { it.node.id == id }
                }
                "replace" -> {
                    if (index != null) return null
                    // Every field of the node but its children.
                    (find(root, id) ?: return null).node = (p.node ?: return null).copy(children = emptyList())
                }
                "move" -> {
                    val moving = p.from.removePrefix("#")
                    val from = parentOf(root, moving) ?: return null
                    val to = find(root, id) ?: return null
                    val child = from.children.first { it.node.id == moving }
                    from.children.remove(child)
                    if (index == null || index !in 0..to.children.size) return null
                    to.children.add(index, child)
                }
                else -> return null
            }
        }
        doc.copy(root = root.frozen())
    }.getOrNull()
}
