import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("server.port")              var serverPort: Int = 8787
    @AppStorage("server.autostart")         var startServerAutomatically: Bool = true
    @AppStorage("font.familyName")          var familyName: String = "SF Custom"
    @AppStorage("font.styleName")           var styleName: String = "Regular"
    @AppStorage("preview.showGuides")       var showGuides: Bool = true
    @AppStorage("preview.darkBackground")   var darkBackground: Bool = false
}
