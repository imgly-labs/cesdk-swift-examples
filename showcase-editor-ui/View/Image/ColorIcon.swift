import SwiftUI

struct FillColorIcon: View {
  @EnvironmentObject private var interactor: Interactor
  @Environment(\.selection) private var id

  var body: some View {
    if interactor.hasFill(id) {
      let isEnabled: Binding<Bool> = interactor.bind(id, property: .key(.fillEnabled), default: false)

      FillColorImage(
        isEnabled: isEnabled.wrappedValue,
        colors: interactor.bind(id, property: .key(.fillSolidColor), default: [.black], getter: backgroundColorGetter)
      )
    }
  }

  let backgroundColorGetter: Interactor.PropertyGetter<[CGColor]> = { engine, id, _, _ in
    let fillType: ColorFillType = try engine.block.get(id, property: .key(.fillType))
    if fillType == .solid {
      let color: CGColor = try engine.block.get(id, property: .key(.fillSolidColor))
      return [color]
    } else if fillType == .gradient {
      let colorStops: [Interactor.GradientColorStop] = try engine.block
        .get(id, .fill, property: .key(.fillGradientColors))
      let colors = colorStops.compactMap(\.color.cgColor)
      return colors
    }
    return [.black]
  }
}

struct StrokeColorIcon: View {
  @EnvironmentObject private var interactor: Interactor
  @Environment(\.selection) private var id

  var body: some View {
    if interactor.hasStroke(id) {
      let isEnabled: Binding<Bool> = interactor.bind(id, property: .key(.strokeEnabled), default: false)
      let color: Binding<CGColor> = interactor.bind(id, property: .key(.strokeColor), default: .black)

      StrokeColorImage(isEnabled: isEnabled.wrappedValue, color: color)
    }
  }
}
