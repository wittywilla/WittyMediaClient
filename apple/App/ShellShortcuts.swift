// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if !os(tvOS)
import SwiftUI
import WittyKit

// The keyboard of docs/plans/DESIGN-2.md section 3 on an iPad with a keyboard, a Mac and a Vision Pro: Search on Command or Control
// and K, the tab before and after on Control and the square brackets, Back on Command and [ (Escape closes what is open, as
// the system does). They are in one place so the key map in WittyKit (`KeyMap`) and what is bound here stay the same.

struct ShellShortcuts: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter

    private var tabs: [AppTab] { center.enabled ? center.phoneTabs : AppTab.phoneTabs }

    private func step(_ by: Int) {
        guard let at = tabs.firstIndex(of: model.tab) else { return }
        let next = at + by
        // Nothing wraps (section 3).
        if tabs.indices.contains(next) { model.tab = tabs[next] }
    }

    private func back() {
        guard var path = model.paths[model.tab], !path.isEmpty else { return }
        path.removeLast()
        model.paths[model.tab] = path
    }

    func body(content: Content) -> some View {
        content.background {
            // Buttons nobody sees or presses, which the system lists as the keys' owners (and a Mac shows in no menu).
            Group {
                Button("Search") { model.tab = .search }.keyboardShortcut("k", modifiers: .command)
                Button("Search") { model.tab = .search }.keyboardShortcut("k", modifiers: .control)
                Button("Search") { model.tab = .search }.keyboardShortcut("f", modifiers: .command)
                Button("Previous tab") { step(-1) }.keyboardShortcut("[", modifiers: .control)
                Button("Next tab") { step(1) }.keyboardShortcut("]", modifiers: .control)
                Button("Back") { back() }.keyboardShortcut("[", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}
#endif
