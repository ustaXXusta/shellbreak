import SwiftUI
import DesktopARShared

@main
struct PhoneClientApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Shellbreak (protocol v\(ProtocolConstants.version))")
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}
