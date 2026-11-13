// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Saving the server's name and mark (administrators): the settings the server keeps (`brandName`, `brandColouring`,
// `brandSpans`, `brandMark`) and its logo (`/branding/logo`, a PNG or JPEG up to 2 MB, 16 to 4096 pixels on a side).

extension WittyClient {
    /// The longest a logo may be, the server's own limit.
    public static let maxLogoBytes = 2 << 20

    /// Saves the name, how it is coloured and the mark. The server answers with every setting; the theme is asked again after.
    public func saveBrand(_ draft: BrandDraft) async throws {
        let problems = draft.problems
        if let first = problems.first { throw APIError(status: 400, message: first) }
        _ = try await call("PUT", "/settings", body: try JSONEncoder().encode(try draft.settings()))
    }

    /// The owner's logo: the picture itself as the body.
    public func uploadBrandLogo(_ image: Data, png: Bool) async throws {
        guard image.count <= Self.maxLogoBytes else { throw APIError(status: 413, message: "The logo must be 2 MB or smaller.") }
        _ = try await send("PUT", "/branding/logo", body: image, headers: ["Content-Type": png ? "image/png" : "image/jpeg"])
    }

    /// Back to the app's own icon.
    public func removeBrandLogo() async throws { _ = try await call("DELETE", "/branding/logo") }
}
