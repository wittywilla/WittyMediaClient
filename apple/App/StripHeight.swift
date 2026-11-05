import SwiftUI

// Stands in for `LibraryStrip.height` until MobileShell.swift has it: the website's bar is 52 high
// (web/src/shell.css, `--topbar-h` on a phone). Remove this file once MobileShell.swift declares it.
extension LibraryStrip {
    static var height: CGFloat { 52 }
}
