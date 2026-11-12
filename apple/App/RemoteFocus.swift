// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import UIKit

// The arrows and Select of another device's remote, on Apple TV's own screens. SwiftUI has no way to press a
// key for the person: it can only be told where the highlight should start. So this asks the system's focus
// engine, which SwiftUI's highlight is, through UIKit.

@MainActor
enum RemoteFocus {
    static func press(_ key: String) throws {
        throw RemoteRefusal("This Apple TV can't move its highlight from another device.")
    }
}
#endif
