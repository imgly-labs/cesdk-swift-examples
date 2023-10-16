import IMGLYEngine
import SwiftUI

public struct AudioList<Empty: View, First: View>: View {
  @ViewBuilder private let empty: (_ search: String) -> Empty
  @ViewBuilder private let first: () -> First

  public init(@ViewBuilder empty: @escaping (_ search: String) -> Empty = { _ in Message.noElements },
              @ViewBuilder first: @escaping () -> First = { EmptyView() }) {
    self.empty = empty
    self.first = first
  }

  public var body: some View {
    AssetGrid { asset in
      AudioItem(asset: asset)
    } empty: {
      empty($0)
    } first: {
      first()
    }
    .assetGrid(axis: .vertical)
    .assetGrid(items: [GridItem(.flexible(), spacing: 8)])
    .assetGrid(spacing: 8)
    .assetGrid(padding: 16)
    .assetLoader()
  }
}

struct AudioList_Previews: PreviewProvider {
  static var previews: some View {
    defaultAssetLibraryPreviews
  }
}
