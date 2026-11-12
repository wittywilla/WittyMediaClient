// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// A profile's picture: one of the server's small set of shapes on one of the avatar colours, drawn here from
// the same path data the website draws (WittyKit's ProfilePictures.swift). Nothing is uploaded or downloaded.

/// One of the shapes, scaled from its 24 by 24 grid to whatever room it's given.
struct PictureShape: Shape {
    let steps: [PathStep]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let left = rect.midX - 12 * scale, top = rect.midY - 12 * scale
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: left + CGFloat(x) * scale, y: top + CGFloat(y) * scale) }
        var path = Path()
        for step in steps {
            switch step {
            case .move(let x, let y): path.move(to: point(x, y))
            case .line(let x, let y): path.addLine(to: point(x, y))
            case .curve(let x1, let y1, let x2, let y2, let x, let y):
                path.addCurve(to: point(x, y), control1: point(x1, y1), control2: point(x2, y2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// Choosing a picture and its colour: "Their initial" first, then each shape, then the colours once a shape
/// is chosen. Every one is a button a remote can reach.
struct PicturePicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    /// The name whose initial stands for no picture.
    let name: String
    @Binding var value: String
    var lists: ParentalLists?

    private var chosen: ProfilePicture? { ProfilePicture.parse(value) }
    private var colour: String { chosen?.colourName ?? "blue" }

    private func ring(_ on: Bool, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
            .inset(by: -4)
            .strokeBorder(on ? palette.accent : Color.clear, lineWidth: 3)
    }

    var body: some View {
        let size: CGFloat = metrics.tv ? 96 : 56
        let names = (lists ?? ParentalLists()).pictureNames
        let colours = (lists ?? ParentalLists()).pictureColours
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            FlowLayout(spacing: Tokens.Space.s4, rowSpacing: Tokens.Space.s4) {
                Button { value = "" } label: {
                    AvatarTile(name: name, size: size).overlay { ring(chosen == nil, radius: size * 0.22) }
                }
                .buttonStyle(PictureButtonStyle())
                .accessibilityLabel("Their initial")
                .accessibilityAddTraits(chosen == nil ? [.isSelected] : [])
                ForEach(names, id: \.self) { shape in
                    Button { value = "\(shape):\(colour)" } label: {
                        AvatarTile(name: name, size: size, picture: "\(shape):\(colour)")
                            .overlay { ring(chosen?.name == shape, radius: size * 0.22) }
                    }
                    .buttonStyle(PictureButtonStyle())
                    .accessibilityLabel(ProfilePicture.label(shape))
                    .accessibilityAddTraits(chosen?.name == shape ? [.isSelected] : [])
                    .accessibilityIdentifier("picture-\(shape)")
                }
            }
            .remoteSection()
            if let chosen {
                FlowLayout(spacing: Tokens.Space.s4, rowSpacing: Tokens.Space.s4) {
                    ForEach(colours, id: \.self) { name in
                        Button { value = "\(chosen.name):\(name)" } label: {
                            Circle()
                                .fill(Color(hex: ProfilePicture.colour(named: name) ?? "#0a6fb8"))
                                .frame(width: size * 0.6, height: size * 0.6)
                                .overlay { Circle().inset(by: -5).strokeBorder(chosen.colourName == name ? palette.accent : Color.clear, lineWidth: 3) }
                                .padding(5)
                        }
                        .buttonStyle(PictureButtonStyle())
                        .accessibilityLabel(ProfilePicture.label(name))
                        .accessibilityAddTraits(chosen.colourName == name ? [.isSelected] : [])
                        .accessibilityIdentifier("colour-\(name)")
                    }
                }
                .remoteSection()
            }
        }
    }
}

/// A picture to press: it grows a little under a remote's focus, as the profile tiles do.
private struct PictureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PictureButtonBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct PictureButtonBody<Label: View>: View {
    @Environment(\.isFocused) private var focused
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let pressed: Bool

    var body: some View {
        label
            .scaleEffect(metrics.tv && focused && !reduceMotion ? 1.12 : 1)
            .opacity(pressed ? 0.75 : (metrics.tv && !focused ? 0.8 : 1))
            .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.focus), value: focused)
    }
}
