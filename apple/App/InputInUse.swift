// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import GameController
import SwiftUI
import WittyKit

/// Which input the person is using, for the key legend (docs/plans/DESIGN-2.md section 3): a game pad when one is connected, a
/// keyboard when one is attached, a Siri Remote on Apple TV; nil when it is touch (or a pointer) alone. The legend
/// shows for a pad or a remote always, for a keyboard only on a large screen, and never for touch.
@MainActor
final class InputInUse: ObservableObject {
    static let shared = InputInUse()
    @Published private(set) var device: InputDevice?

    private init() {
        refresh()
        let centre = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect, .GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    private func refresh() {
        #if os(tvOS)
        device = GCController.controllers().contains { $0.extendedGamepad != nil } ? .gamepad : .remote
        #else
        if GCController.controllers().contains(where: { $0.extendedGamepad != nil }) {
            device = .gamepad
        } else if GCKeyboard.coalesced != nil {
            device = .keyboard
        } else {
            device = nil
        }
        #endif
    }
}
