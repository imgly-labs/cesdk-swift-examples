import SwiftUI

struct FontFamiliesKey: EnvironmentKey {
  static let defaultValue: [String]? = nil
}

extension EnvironmentValues {
  var fontFamilies: [String]? {
    get { self[FontFamiliesKey.self] }
    set { self[FontFamiliesKey.self] = newValue }
  }
}
