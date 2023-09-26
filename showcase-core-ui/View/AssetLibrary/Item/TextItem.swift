import IMGLYCore
import SwiftUI

struct TextItem: View {
  @EnvironmentObject private var interactor: AnyAssetLibraryInteractor
  let asset: AssetItem

  @State var fontName: String?

  @ViewBuilder var placeholder: some View {
    GridItemBackground()
      .frame(width: 160, height: 24)
    Spacer()
  }

  var body: some View {
    HStack(spacing: 0) {
      switch asset {
      case let .asset(asset):
        if let fontName {
          Text(asset.result.label ?? "Text")
            .font(.custom(fontName, size: asset.result.fontSize ?? 17))
          Spacer()
          Image(systemName: "plus.square.fill")
            .foregroundStyle(.secondary)
            .imageScale(.large)
        } else {
          placeholder
            .task {
              do {
                guard let basePath = URL(string: try interactor.getBasePath()),
                      let fontPath = asset.result.url
                else {
                  fontName = "" // Fallback system font
                  return
                }
                let url = basePath.appendingPathComponent(fontPath.path, isDirectory: false)
                let fontID = url.absoluteString
                if let registeredFontName = FontImporter.registeredFonts[fontID] {
                  fontName = registeredFontName
                  return
                }
                let (data, _) = try await URLSession.get(url)
                let fonts = FontImporter.importFonts([fontID: data])
                if let name = fonts.first?.value {
                  fontName = name
                  return
                }
              } catch {}
              fontName = "" // Fallback system font
            }
        }
      case .placeholder:
        placeholder
      }
    }
    .padding([.leading, .trailing], 16)
    .contentShape(Rectangle())
    .onTapGesture {
      guard case let .asset(asset) = asset else {
        return
      }
      interactor.assetTapped(sourceID: asset.sourceID, asset: asset.result)
    }
    .frame(height: 48)
  }
}

struct TextItem_Previews: PreviewProvider {
  static var previews: some View {
    defaultAssetLibraryPreviews
  }
}
