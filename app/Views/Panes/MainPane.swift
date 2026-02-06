import SwiftUI

struct MainPane: View {
    @ObservedObject var manager: FileExplorerManager

    var body: some View {
        switch manager.currentPane {
        case .browser:
            FileBrowserPane(manager: manager)
        case .selection:
            SelectionPane(manager: manager)
        case .iphone:
            iPhoneBrowserPane(manager: manager)
        }
    }
}
