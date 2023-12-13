import IMGLYCoreUI
import SwiftUI

public struct EditorUI: View {
  @EnvironmentObject private var interactor: Interactor

  @Environment(\.layoutDirection) private var layoutDirection

  private let url: URL

  public init(scene url: URL) {
    self.url = url
  }

  @State private var canvasGeometry: Geometry?
  @State private var sheetGeometry: Geometry?
  private var sheetGeometryIfPresented: Geometry? { interactor.sheet.isPresented ? sheetGeometry : nil }
  private let zoomPadding: CGFloat = 16

  private func zoomParameters(canvasGeometry: Geometry?,
                              sheetGeometry: Geometry?) -> (insets: EdgeInsets?, canvasHeight: CGFloat) {
    let canvasHeight = canvasGeometry?.size.height ?? 0

    let insets: EdgeInsets?
    if let sheetGeometry, let canvasGeometry {
      var sheetInsets = canvasGeometry.safeAreaInsets
      let height = canvasGeometry.size.height
      let sheetMinY = sheetGeometry.frame.minY - sheetGeometry.safeAreaInsets.top
      sheetInsets.bottom = max(sheetInsets.bottom, zoomPadding + height - sheetMinY)
      sheetInsets.bottom = min(sheetInsets.bottom, height * 0.7)
      insets = sheetInsets
    } else {
      insets = canvasGeometry?.safeAreaInsets
    }

    if var rtl = insets, layoutDirection == .rightToLeft {
      swap(&rtl.leading, &rtl.trailing)
      return (rtl, canvasHeight)
    }

    return (insets, canvasHeight)
  }

  @State private var interactivePopGestureRecognizer: UIGestureRecognizer?

  var isBackButtonHidden: Bool { !interactor.isEditing }

  public var body: some View {
    Canvas(zoomPadding: zoomPadding)
      .background {
        Color(uiColor: .systemGroupedBackground)
          .ignoresSafeArea()
      }
      .allowsHitTesting(interactor.isEditing)
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(isBackButtonHidden)
      .preference(key: BackButtonHiddenKey.self, value: isBackButtonHidden)
      .introspectNavigationController { navigationController in
        // Disable swipe-back gesture and restore `onDisappear`
        interactivePopGestureRecognizer = navigationController.interactivePopGestureRecognizer
        interactivePopGestureRecognizer?.isEnabled = false
      }
      .conditionalNavigationBarBackground(.visible)
      .onPreferenceChange(CanvasGeometryKey.self) { newValue in
        canvasGeometry = newValue
      }
      .onChange(of: canvasGeometry) { newValue in
        let zoom = zoomParameters(canvasGeometry: newValue, sheetGeometry: sheetGeometryIfPresented)
        interactor.updateZoom(with: zoom.insets, canvasHeight: zoom.canvasHeight)
      }
      .onChange(of: interactor.page) { _ in
        let zoom = zoomParameters(canvasGeometry: canvasGeometry, sheetGeometry: sheetGeometryIfPresented)
        interactor.updateZoom(with: zoom.insets, canvasHeight: zoom.canvasHeight)
      }
      .onChange(of: interactor.textCursorPosition) { newValue in
        let zoom = zoomParameters(canvasGeometry: canvasGeometry, sheetGeometry: sheetGeometryIfPresented)
        interactor.zoomToText(with: zoom.insets, canvasHeight: zoom.canvasHeight, cursorPosition: newValue)
      }
      .sheet(isPresented: $interactor.sheet.isPresented) {
        let zoom = zoomParameters(canvasGeometry: canvasGeometry, sheetGeometry: sheetGeometryIfPresented)
        interactor.updateZoom(with: zoom.insets, canvasHeight: zoom.canvasHeight)
      } content: {
        Sheet()
          .background {
            GeometryReader { geo in
              Color.clear
                .preference(key: SheetGeometryKey.self, value: Geometry(geo, Canvas.safeCoordinateSpace))
            }
          }
          .onPreferenceChange(SheetGeometryKey.self) { newValue in
            sheetGeometry = newValue
          }
          .onChange(of: sheetGeometry) { newValue in
            let zoom = zoomParameters(canvasGeometry: canvasGeometry, sheetGeometry: newValue)
            interactor.updateZoom(with: zoom.insets, canvasHeight: zoom.canvasHeight)
          }
          .errorAlert(isSheet: true)
      }
      .errorAlert(isSheet: false)
      .onAppear {
        let zoom = zoomParameters(canvasGeometry: canvasGeometry, sheetGeometry: sheetGeometryIfPresented)
        interactor.loadScene(from: url, with: zoom.insets)
      }
      .onWillDisappear {
        interactor.onWillDisappear()
      }
      .onDisappear {
        interactor.onDisappear()
        interactivePopGestureRecognizer?.isEnabled = true
      }
  }
}

private struct SheetGeometryKey: PreferenceKey {
  static let defaultValue: Geometry? = nil
  static func reduce(value: inout Geometry?, nextValue: () -> Geometry?) {
    value = value ?? nextValue()
  }
}

struct EditorUI_Previews: PreviewProvider {
  static var previews: some View {
    defaultPreviews
  }
}
