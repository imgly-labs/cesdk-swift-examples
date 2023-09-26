import SwiftUI

struct ImageItem: View {
  let asset: AssetItem

  var body: some View {
    switch asset {
    case let .asset(asset):
      ReloadableAsyncImage(asset: asset) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(minWidth: 0, minHeight: 0)
          .clipped()
          .aspectRatio(1, contentMode: .fit)
          .cornerRadius(8)
      }
    case .placeholder:
      GridItemBackground()
        .aspectRatio(1, contentMode: .fit)
    }
  }
}

struct ImageItem_Previews: PreviewProvider {
  static var previews: some View {
    defaultAssetLibraryPreviews
  }
}
