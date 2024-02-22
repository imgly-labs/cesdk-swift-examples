@_spi(Internal) import IMGLYCoreUI
import enum IMGLYEngine.LicenseError
import SwiftUI

@MainActor
struct ContentView: View {
  private let title = "CE.SDK Showcases"

  var body: some View {
    NavigationView {
      List {
        Showcases()
      }
      .listStyle(.sidebar)
      .navigationTitle(title)
      .imgly.buildInfo(ciBuildsHost: secrets.ciBuildsHost, githubRepo: secrets.githubRepo)
    }
    // `StackNavigationViewStyle` forces to deinitialize the view and thus its engine when exiting a showcase.
    .navigationViewStyle(.stack)
    .alert("License Key Required", isPresented: .constant(secrets.licenseKey.isEmpty)) {} message: {
      let message = LicenseError.missing.errorDescription ?? ""
      Text(verbatim: "Please enter a `licenseKey` in `Secrets.swift`!\n\(message)")
    }
    .accessibilityIdentifier("showcases")
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
    ContentView()
      .imgly.nonDefaultPreviewSettings()
  }
}
