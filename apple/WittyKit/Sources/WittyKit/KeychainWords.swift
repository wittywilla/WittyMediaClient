// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// What to tell someone whose sign-in the keychain wouldn't keep, by the keychain's status: what happened and what
/// would fix it. The app still works; it asks for the sign-in again next time.
public enum KeychainWords {
    /// errSecMissingEntitlement: an app with no signature (or none for this device) has no keychain.
    public static let missingEntitlement: Int32 = -34018
    /// errSecInteractionNotAllowed: the keychain is closed until the device is unlocked once after it starts.
    public static let interactionNotAllowed: Int32 = -25308

    public static func notice(status: Int32) -> String {
        switch status {
        case missingEntitlement:
            return "This copy of the app isn't signed for this device, so it can't keep your sign-in, and you'll be asked again next time. Install it with AltStore or SideStore, or another signed copy, to stay signed in."
        case interactionNotAllowed:
            return "Your sign-in couldn't be kept because this device hasn't been unlocked since it started. Unlock it, then sign in again to stay signed in."
        default:
            return "This device couldn't keep your sign-in (keychain error \(status)), so you'll be asked again next time. Restarting the device usually fixes this."
        }
    }
}
