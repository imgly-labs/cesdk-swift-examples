import ActivityView
import IMGLYCore
import IMGLYCoreUI
import IMGLYEngine
import SwiftUI

@MainActor
public final class Interactor: ObservableObject, KeyboardObserver {
  // MARK: - Properties

  static let basePath = URL(string: "https://cdn.img.ly/packages/imgly/cesdk-engine/1.20.0/assets")!

  @ViewBuilder var canvas: some View {
    if let engine {
      IMGLYEngine.Canvas(engine: engine)
    } else {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  let fontLibrary = FontLibrary()

  @Published public private(set) var isLoading = true
  @Published public private(set) var isEditing = true
  @Published private(set) var isExporting = false
  @Published public private(set) var isAddingAsset = false

  @Published var export: ActivityItem?
  @Published var error = AlertState()
  @Published var sheet = SheetState() { didSet { sheetChanged(oldValue) } }

  typealias BlockID = IMGLYEngine.DesignBlockID
  typealias BlockType = IMGLYEngine.DesignBlockType
  typealias EditMode = IMGLYEngine.EditMode
  typealias RGBA = IMGLYEngine.RGBA
  typealias GradientColorStop = IMGLYEngine.GradientColorStop
  typealias Color = IMGLYEngine.Color
  typealias DefaultAssetSource = Engine.DefaultAssetSource
  typealias BlurType = IMGLYEngine.BlurType
  typealias EffectType = IMGLYEngine.EffectType

  struct Selection: Equatable {
    let blocks: [BlockID]
    let boundingBox: CGRect
  }

  @Published public internal(set) var verticalSizeClass: UserInterfaceSizeClass?
  @Published public private(set) var page = 0 { didSet { pageChanged(oldValue) } }
  @Published public var selectionColors = SelectionColors()
  @Published private(set) var selection: Selection? { didSet { selectionChanged(oldValue) } }
  @Published private(set) var editMode: EditMode = .transform { didSet { editModeChanged(oldValue) } }
  @Published private(set) var textCursorPosition: CGPoint?
  @Published private(set) var canUndo = false
  @Published private(set) var canRedo = false
  @Published private var isKeyboardPresented: Bool = false

  var isCanvasActionEnabled: Bool {
    !sheet.isPresented && editMode == .transform && !isGrouped(selection?.blocks.first)
  }

  var sheetTypeForSelection: SheetType? { sheetType(for: selection) }

  func sheetType(_ id: BlockID?) -> SheetType? {
    guard let id, let engine, let type = try? engine.block.getType(id) else {
      return nil
    }
    let fill = try? engine.block.getFill(id)
    let kind: BlockKind? = try? engine.block.getKind(id)
    var fillType: String?
    if let fill {
      fillType = try? engine.block.getType(fill)
    }
    return sheetType(for: type, with: fillType, and: kind)
  }

  func shapeType(_ id: BlockID?) -> ShapeType? {
    guard let id, let engine, let shape = try? engine.block.getShape(id),
          let type = try? engine.block.getType(shape) else {
      return nil
    }
    return ShapeType(rawValue: type)
  }

  var rotationForSelection: CGFloat? {
    guard let first = selection?.blocks.first,
          let rotation = try? engine?.block.getRotation(first) else {
      return nil
    }
    return CGFloat(rotation)
  }

  func isGestureActive(_ started: Bool) {
    guard let engine else {
      return
    }
    do {
      try behavior.isGestureActive(.init(engine, self), started)
    } catch {
      handleError(error)
    }
  }

  var rootBottomBarItems: [RootBottomBarItem] {
    guard let engine else {
      return []
    }
    do {
      return try behavior.rootBottomBarItems(.init(engine, self))
    } catch {
      handleError(error)
      return []
    }
  }

  // MARK: - Life cycle

  public init(behavior: InteractorBehavior) {
    self.behavior = behavior
  }

  init(behavior: InteractorBehavior, sheet: SheetState?) {
    self.behavior = behavior
    if let sheet {
      _sheet = .init(initialValue: sheet)
    }
  }

  deinit {
    stateTask?.cancel()
    eventTask?.cancel()
    sceneTask?.cancel()
    zoom.task?.cancel()
  }

  private func onAppear() {
    updateState()
    stateTask = observeState()
    eventTask = observeEvent()
    keyboardPublisher.assign(to: &$isKeyboardPresented)
  }

  func onWillDisappear() {
    sheet.isPresented = false
  }

  func onDisappear() {
    stateTask?.cancel()
    eventTask?.cancel()
    sceneTask?.cancel()
    zoom.task?.cancel()
    _engine = nil
  }

  // MARK: - Private properties

  private let behavior: InteractorBehavior

  // The optional _engine instance allows to control the deinitialization.
  private var _engine: Engine?

  private var stateTask: Task<Void, Never>?
  private var eventTask: Task<Void, Never>?
  private var sceneTask: Task<Void, Never>?
  private var zoom: (task: Task<Void, Never>?, toTextCursor: Bool) = (nil, false)
}

// MARK: - Block queries

extension Interactor {
  private func block<T>(_ id: BlockID?, _ query: (@MainActor (BlockID) throws -> T)?) -> T? {
    guard let engine, let id, engine.block.isValid(id) else {
      return nil
    }
    do {
      return try query?(id)
    } catch {
      handleErrorWithTask(error)
      return nil
    }
  }

  private func hasColorFillType(_ id: DesignBlockID?, type: ColorFillType) -> Bool {
    guard let id, let engine else { return false }
    do {
      let fillType: ColorFillType? = try engine.block.get(id, .fill, property: .key(.type))
      return fillType == type
    } catch {
      return false
    }
  }

  func canBringForward(_ id: BlockID?) -> Bool { block(id, engine?.block.canBringForward) ?? false }
  func canBringBackward(_ id: BlockID?) -> Bool { block(id, engine?.block.canBringBackward) ?? false }
  func hasFill(_ id: BlockID?) -> Bool { block(id, engine?.block.hasFill) ?? false }
  func hasStroke(_ id: BlockID?) -> Bool { block(id, engine?.block.hasStroke) ?? false }
  func hasOpacity(_ id: BlockID?) -> Bool { block(id, engine?.block.hasOpacity) ?? false }
  func hasBlendMode(_ id: BlockID?) -> Bool { block(id, engine?.block.hasBlendMode) ?? false }
  func hasBlur(_ id: BlockID?) -> Bool { block(id, engine?.block.hasBlur) ?? false }
  func hasCrop(_ id: BlockID?) -> Bool { block(id, engine?.block.hasCrop) ?? false }
  func canResetCrop(_ id: BlockID?) -> Bool { block(id, engine?.block.canResetCrop) ?? false }
  func isGrouped(_ id: BlockID?) -> Bool { block(id, engine?.block.isGrouped) ?? false }
  func hasSolidFill(_ id: DesignBlockID?) -> Bool { hasColorFillType(id, type: .solid) }
  func hasGradientFill(_ id: DesignBlockID?) -> Bool { hasColorFillType(id, type: .gradient) }
  func hasColorFill(_ id: DesignBlockID?) -> Bool { hasSolidFill(id) || hasGradientFill(id) }
}

// MARK: - Property bindings

extension Interactor {
  /// Create a `TextState` binding for a block `id`.
  /// If `resetFontProperties` is enabled bold and italic states would not be preserved on set.
  func bindTextState(_ id: BlockID?, resetFontProperties: Bool) -> Binding<TextState> {
    let fontURL: Binding<URL?> = bind(id, property: .key(.textFontFileURI))
    return .init {
      if let fontURL = fontURL.wrappedValue {
        let selected = self.fontLibrary.fontFor(url: fontURL)
        var text = TextState()
        text.fontID = selected?.font.id
        text.fontFamilyID = selected?.family.id
        text.setFontProperties(selected?.family.fontProperties(for: selected?.font.id))
        return text
      } else {
        return TextState()
      }
    } set: { text in
      func font(fontFamily: FontFamily) -> Font? {
        if resetFontProperties {
          return fontFamily.someFont
        } else {
          return fontFamily.font(for: .init(bold: text.isBold, italic: text.isItalic)) ?? fontFamily.someFont
        }
      }

      if let fontFamilyID = text.fontFamilyID, let fontFamily = self.fontLibrary.fontFamilyFor(id: fontFamilyID),
         let font = font(fontFamily: fontFamily),
         let selected = self.fontLibrary.fontFor(id: font.id) {
        fontURL.wrappedValue = selected.font.url
      }
    }
  }

  // swiftlint:disable cyclomatic_complexity

  /// Create `SelectionColor` bindings categorized by block names for a given set of `selectionColors`.
  func bind(_ selectionColors: SelectionColors,
            completion: PropertyCompletion? = Completion.addUndoStep) -> [(name: String, colors: [SelectionColor])] {
    selectionColors.sorted.map { name, colors in
      let colors = colors.map { color in
        SelectionColor(color: color, binding: .init {
          // Assume all properties and valid blocks assigned to the selection color still share the same color.
          // Otherwise the first found visible color is returned.
          guard let engine = self.engine, let properties = selectionColors[name, color] else {
            return color
          }

          for (property, blocks) in properties {
            let validBlock = blocks.first { id in
              let isEnabled: Bool = {
                guard let enabledProperty = property.enabled else {
                  return false
                }
                do {
                  return try engine.block.get(id, property: enabledProperty)
                } catch {
                  self.handleErrorWithTask(error)
                  return false
                }
              }()
              return engine.block.isValid(id) && isEnabled
            }

            if let validBlock {
              // If the property is set to solid fill color we need to
              // check for gradient color as well.
              if property == .key(.fillSolidColor), self.hasGradientFill(validBlock) {
                if let engine = self.engine, let colorStops: [GradientColorStop] = try? engine.block.get(
                  validBlock,
                  .fill,
                  property: .key(.fillGradientColors)
                ), let color = colorStops.first?.color.cgColor {
                  return color
                }
              } else {
                if let value: CGColor = self.get(validBlock, property: property) {
                  return value
                }
              }
            }
          }

          // No valid block found.
          return color
        } set: { value, _ in
          guard let properties = selectionColors[name, color] else {
            return
          }
          do {
            try properties.forEach { property, ids in
              var gradientIDs: [DesignBlockID] = []
              ids.forEach { id in
                if self.hasGradientFill(id) {
                  gradientIDs.append(id)
                }
              }
              _ = try self.engine?.block.overrideAndRestore(gradientIDs, .fill, scope: .key(.lifecycleDestroy)) { _ in
                self.set(gradientIDs, .fill, property: .key(.type), value: ColorFillType.solid, completion: nil)
              }
              _ = self.set(ids, property: property, value: value,
                           setter: Setter.set(overrideScopes: [.key(.fillChange), .key(.strokeChange)]),
                           completion: completion)
            }
          } catch {
            self.handleErrorWithTask(error)
          }
        })
      }

      return (name: name, colors: colors)
    }
  }

  // swiftlint:enable cyclomatic_complexity

  /// Create a `property` `Binding` for a block `id`. The `defaultValue` will be used as fallback if the property
  /// cannot be resolved.
  func bind<T: MappedType>(_ id: BlockID?, _ propertyBlock: PropertyBlock? = nil,
                           property: Property, default defaultValue: T,
                           getter: @escaping PropertyGetter<T> = Getter.get(),
                           setter: @escaping PropertySetter<T> = Setter.set(),
                           completion: PropertyCompletion? = Completion.addUndoStep) -> Binding<T> {
    .init {
      guard let id, let value: T = self.get(id, propertyBlock, property: property, getter: getter) else {
        return defaultValue
      }
      return value
    } set: { value, _ in
      guard let id else {
        return
      }
      _ = self.set([id], propertyBlock, property: property, value: value, setter: setter, completion: completion)
    }
  }

  /// Create a propertyless `Binding` for a block `id`. The `defaultValue` will be used as fallback if the property
  /// cannot be resolved.
  func bind<T: MappedType>(_ id: BlockID?, default defaultValue: T,
                           getter: @escaping RawGetter<T>,
                           setter: @escaping RawSetter<T>,
                           completion: PropertyCompletion? = Completion.addUndoStep) -> Binding<T> {
    .init {
      guard let id, let value: T = self.get(id, getter: getter) else {
        return defaultValue
      }
      return value
    } set: { value, _ in
      guard let id else {
        return
      }
      _ = self.set([id], value: value, setter: setter, completion: completion)
    }
  }

  /// Create a `property` `Binding` for a block `id`. The value `nil` will be used as fallback if the property
  /// cannot be resolved.
  func bind<T: MappedType>(_ id: BlockID?, _ propertyBlock: PropertyBlock? = nil,
                           property: Property,
                           getter: @escaping PropertyGetter<T> = Getter.get(),
                           setter: @escaping PropertySetter<T> = Setter.set(),
                           completion: PropertyCompletion? = Completion.addUndoStep) -> Binding<T?> {
    .init {
      guard let id else {
        return nil
      }
      return self.get(id, propertyBlock, property: property, getter: getter)
    } set: { value, _ in
      guard let value, let id else {
        return
      }
      _ = self.set([id], propertyBlock, property: property, value: value, setter: setter, completion: completion)
    }
  }

  /// Create a propertyless `Binding` for a block `id`. The value `nil` will be used as fallback if the property
  /// cannot be resolved.
  func bind<T: MappedType>(_ id: BlockID?,
                           getter: @escaping RawGetter<T>,
                           setter: @escaping RawSetter<T>,
                           completion: PropertyCompletion? = Completion.addUndoStep) -> Binding<T?> {
    .init {
      guard let id else {
        return nil
      }
      return self.get(id, getter: getter)
    } set: { value, _ in
      guard let value, let id else {
        return
      }
      _ = self.set([id], value: value, setter: setter, completion: completion)
    }
  }

  func addUndoStep() {
    do {
      try engine?.editor.addUndoStep()
    } catch {
      handleError(error)
    }
  }

  typealias PropertyGetter<T: MappedType> = @MainActor (
    _ engine: Engine,
    _ block: DesignBlockID,
    _ propertyBlock: PropertyBlock?,
    _ property: Property
  ) throws -> T

  typealias RawGetter<T: MappedType> = @MainActor (
    _ engine: Engine,
    _ block: DesignBlockID
  ) throws -> T

  enum Getter {
    static func get<T: MappedType>() -> Interactor.PropertyGetter<T> {
      { engine, block, propertyBlock, property in
        try engine.block.get(block, propertyBlock, property: property)
      }
    }
  }

  typealias PropertySetter<T: MappedType> = @MainActor (
    _ engine: Engine,
    _ blocks: [DesignBlockID],
    _ propertyBlock: PropertyBlock?,
    _ property: Property,
    _ value: T,
    _ completion: PropertyCompletion?
  ) throws -> Bool

  typealias RawSetter<T: MappedType> = @MainActor (
    _ engine: Engine,
    _ blocks: [DesignBlockID],
    _ value: T,
    _ completion: PropertyCompletion?
  ) throws -> Bool

  enum Setter {
    static func set<T: MappedType>() -> Interactor.PropertySetter<T> {
      { engine, blocks, propertyBlock, property, value, completion in
        let didChange = try engine.block.set(blocks, propertyBlock, property: property, value: value)
        return try (completion?(engine, blocks, didChange) ?? false) || didChange
      }
    }

    static func set<T: MappedType>(overrideScope: Scope) -> Interactor.PropertySetter<T> {
      set(overrideScopes: [overrideScope])
    }

    static func set<T: MappedType>(overrideScopes: Set<Scope>) -> Interactor.PropertySetter<T> {
      { engine, blocks, propertyBlock, property, value, completion in
        let didChange = try engine.block.overrideAndRestore(blocks, scopes: overrideScopes) {
          try engine.block.set($0, propertyBlock, property: property, value: value)
        }
        return try (completion?(engine, blocks, didChange) ?? false) || didChange
      }
    }
  }

  typealias PropertyCompletion = @MainActor (
    _ engine: Engine,
    _ blocks: [DesignBlockID],
    _ didChange: Bool
  ) throws -> Bool

  enum Completion {
    static let addUndoStep: PropertyCompletion = addUndoStep()

    static func addUndoStep(completion: Interactor.PropertyCompletion? = nil) -> Interactor.PropertyCompletion {
      { engine, blocks, didChange in
        if didChange {
          try engine.editor.addUndoStep()
        }
        return try (completion?(engine, blocks, didChange) ?? false) || didChange
      }
    }

    static func set(_ propertyBlock: PropertyBlock? = nil,
                    property: Property, value: some MappedType,
                    completion: Interactor.PropertyCompletion? = nil) -> Interactor.PropertyCompletion {
      { engine, blocks, didChange in
        let didSet = try engine.block.set(blocks, propertyBlock, property: property, value: value)
        let didChange = didChange || didSet
        return try (completion?(engine, blocks, didChange) ?? false || didChange)
      }
    }
  }

  func enumValues<T>(property: Property) -> [T]
    where T: CaseIterable & RawRepresentable, T.RawValue == String {
    guard let engine else {
      return []
    }
    do {
      return try engine.block.enumValues(property: property)
    } catch {
      handleErrorWithTask(error)
      return []
    }
  }
}

// MARK: - Constraints

extension Interactor {
  func isAllowed(_ id: BlockID?, scope: ScopeKey) -> Bool {
    guard let engine, let id, engine.block.isValid(id) else {
      return false
    }
    do {
      return try engine.block.isAllowedByScope(id, scope: .init(scope))
    } catch {
      handleErrorWithTask(error)
      return false
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func isAllowed(_ id: BlockID?, _ mode: SheetMode) -> Bool {
    switch mode {
    case .add:
      return true
    case .replace:
      return isAllowed(id, scope: .fillChange)
    case .edit:
      return isAllowed(id, scope: .textEdit)
    case .crop:
      return isAllowed(id, scope: .layerCrop) || isAllowed(id, scope: .layerClipping)
    case .format:
      return isAllowed(id, scope: .textCharacter)
    case .options:
      return isAllowed(id, scope: .shapeChange)
    case .fillAndStroke:
      return isAllowed(id, scope: .fillChange) && isAllowed(id, scope: .strokeChange)
    case .layer:
      let opacity = isAllowed(id, scope: .layerOpacity)
      let blend = isAllowed(id, scope: .layerBlendMode)
      let layer = isAllowed(id, .toTop)
      let duplicate = isAllowed(id, .duplicate)
      let delete = isAllowed(id, .delete)
      return opacity || blend || layer || duplicate || delete
    case .enterGroup:
      return true
    case .selectGroup:
      return isGrouped(id)
    case .selectionColors, .font, .fontSize, .color:
      return true
    case .filter:
      return isAllowed(id, scope: .appearanceFilter)
    case .adjustments:
      return isAllowed(id, scope: .appearanceAdjustments)
    case .effect:
      return isAllowed(id, scope: .appearanceEffect)
    case .blur:
      return isAllowed(id, scope: .appearanceBlur)
    }
  }

  func isAllowed(_ id: BlockID?, _ action: Action) -> Bool {
    switch action {
    case .undo: return canUndo
    case .redo: return canRedo
    case .previewMode: return true
    case .editMode: return true
    case .export: return true
    case .toTop, .up, .down, .toBottom:
      return isAllowed(id, scope: .editorAdd) && !isGrouped(id)
    case .duplicate:
      return isAllowed(id, scope: .lifecycleDuplicate) && !isGrouped(id)
    case .delete:
      return isAllowed(id, scope: .lifecycleDestroy) && !isGrouped(id)
    case .previousPage, .nextPage, .page: return true
    case .resetCrop, .flipCrop:
      return isAllowed(id, .crop) && !isGrouped(id)
    }
  }
}

// MARK: - AssetLibraryInteractor

extension Interactor: AssetLibraryInteractor {
  public func findAssets(sourceID: String, query: AssetQueryData) async throws -> AssetQueryResult {
    guard let engine else {
      throw Error(errorDescription: "Engine unavailable.")
    }
    return try await engine.asset.findAssets(sourceID: sourceID, query: query)
  }

  public func getGroups(sourceID: String) async throws -> [String] {
    guard let engine else {
      throw Error(errorDescription: "Engine unavailable.")
    }
    return try await engine.asset.getGroups(sourceID: sourceID)
  }

  public func getCredits(sourceID: String) -> AssetCredits? {
    engine?.asset.getCredits(sourceID: sourceID)
  }

  public func getLicense(sourceID: String) -> AssetLicense? {
    engine?.asset.getLicense(sourceID: sourceID)
  }

  public func addAsset(to sourceID: String, asset: AssetDefinition) throws {
    guard let engine else {
      throw Error(errorDescription: "Engine unavailable.")
    }
    return try engine.asset.addAsset(to: sourceID, asset: asset)
  }

  public func uploadAsset(to sourceID: String, asset: AssetUpload) async throws -> AssetResult {
    do {
      let asset = try await Self.uploadAsset(interactor: self, to: sourceID, asset: asset)
      assetTapped(sourceID: sourceID, asset: asset)
      return asset
    } catch {
      handleErrorAndDismiss(error)
      throw error
    }
  }

  public func assetTapped(sourceID: String, asset: AssetResult) {
    guard let engine else {
      return
    }
    isAddingAsset = true
    Task(priority: .userInitiated) {
      do {
        if sheet.mode == .replace, let id = selection?.blocks.first {
          switch sheet.type {
          case .sticker:
            guard let url = asset.url else {
              return
            }
            try await engine.block.overrideAndRestore(id, scope: .key(.layerCrop)) {
              _ = try engine.set([$0], .fill, property: .key(.fillImageImageFileURI), value: url)
              try engine.block.setContentFillMode($0, mode: .contain)
            }
          default:
            try await engine.asset.applyToBlock(sourceID: sourceID, assetResult: asset, block: id)
          }
          if try engine.editor.getSettingEnum("role") == "Adopter" {
            try engine.block.setPlaceholderEnabled(id, enabled: false)
          }
          try engine.editor.addUndoStep()
          if sheet.detent == .large || isKeyboardPresented {
            sheet.isPresented = false
          }
        } else {
          if let id = try await engine.asset.apply(sourceID: sourceID, assetResult: asset) {
            try engine.block.appendChild(to: engine.getPage(page), child: id)
            if ProcessInfo.isUITesting {
              try engine.block.setPositionX(id, value: 15)
              try engine.block.setPositionY(id, value: 5)
            }
          }
          sheet.isPresented = false
        }
      } catch {
        handleErrorAndDismiss(error)
      }
      isAddingAsset = false
    }
  }

  public func getBasePath() throws -> String {
    guard let engine else {
      throw Error(errorDescription: "Engine unavailable.")
    }
    return try engine.editor.getSettingString("basePath")
  }
}

// MARK: - Actions

extension Interactor {
  func sheetDismissButtonTapped() {
    sheet.isPresented = false
  }

  func bottomBarCloseButtonTapped() {
    do {
      try engine?.block.deselectAll()
    } catch {
      handleError(error)
    }
  }

  func keyboardBarDismissButtonTapped() {
    setEditMode(.transform)
  }

  // swiftlint:disable:next cyclomatic_complexity
  func bottomBarButtonTapped(for mode: SheetMode) {
    do {
      switch mode {
      case .add:
        try engine?.block.deselectAll()
        sheet.commit { model in
          model = .init(mode, .image)
          model.detent = .large
        }
      case .edit:
        setEditMode(.text)
      case .crop:
        setEditMode(.crop)
      case .enterGroup:
        if let group = selection?.blocks.first {
          try engine?.block.enterGroup(group)
        }
      case .selectGroup:
        if let child = selection?.blocks.first {
          try engine?.block.exitGroup(child)
        }
      case .selectionColors:
        sheet.commit { model in
          model = .init(mode, .selectionColors)
        }
      case .font:
        sheet.commit { model in
          model = .init(mode, .font)
        }
      case .fontSize:
        sheet.commit { model in
          model = .init(mode, .fontSize)
          model.detent = .tiny
          model.detents = [.tiny]
        }
      case .color:
        sheet.commit { model in
          model = .init(mode, .color)
          model.detent = .tiny
          model.detents = [.tiny]
        }
      case .filter, .effect, .blur:
        guard let type = sheetTypeForSelection else {
          return
        }
        sheet.commit { model in
          model = .init(mode, type)
          model.detent = .tiny
          model.detents = [.tiny]
        }
      case .layer, .adjustments:
        guard let type = sheetTypeForSelection else {
          return
        }
        sheet.commit { model in
          model = .init(mode, type)
          model.detent = .medium
          model.detents = [.medium]
        }
      default:
        guard let type = sheetTypeForSelection else {
          return
        }
        sheet.commit { model in
          model = .init(mode, type)
        }
      }
    } catch {
      handleError(error)
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  public func actionButtonTapped(for action: Action) {
    do {
      switch action {
      case .undo: try engine?.editor.undo()
      case .redo: try engine?.editor.redo()
      case .previewMode: try enablePreviewMode()
      case .editMode: try enableEditMode()
      case .export: exportScene()
      case .toTop: try engine?.bringToFrontSelectedElement()
      case .up: try engine?.bringForwardSelectedElement()
      case .down: try engine?.sendBackwardSelectedElement()
      case .toBottom: try engine?.sendToBackSelectedElement()
      case .duplicate: try engine?.duplicateSelectedElement()
      case .delete: try engine?.deleteSelectedElement(delay: NSEC_PER_MSEC * 200)
      case .previousPage: try setPage(page - 1)
      case .nextPage: try setPage(page + 1)
      case let .page(index): try setPage(index)
      case .resetCrop: try engine?.resetCropSelectedElement()
      case .flipCrop: try engine?.flipCropSelectedElement()
      }
    } catch {
      handleError(error)
    }
  }

  func loadScene(from url: URL, with insets: EdgeInsets?) {
    guard sceneTask == nil else {
      return
    }

    sceneTask = Task {
      do {
        let engine = try await Engine(license: Secrets.licenseKey, userID: "showcase-user")
        _engine = engine
        onAppear()

        try await behavior.loadScene(.init(engine, self), from: url, with: insets)

        async let loadFonts = loadFonts()
        async let loadDefaultAssets: () = engine.addDefaultAssetSources()
        async let loadDemoAssetSources: () = engine.addDemoAssetSources(sceneMode: engine.scene.getMode(),
                                                                        withUploadAssetSources: true)

        let (fonts, _, _) = try await (loadFonts, loadDefaultAssets, loadDemoAssetSources)
        fontLibrary.fonts = fonts
        try engine.asset.addSource(UnsplashAssetSource())
        try engine.asset.addSource(TextAssetSource(engine: engine))
        isLoading = false
      } catch LicenseError.missing {
        let message = LicenseError.missing.errorDescription ?? ""
        let error = Error(errorDescription: "Please enter a `licenseKey` in `Secrets.swift`!\n\(message)")
        handleErrorAndDismiss(error)
      } catch {
        handleErrorAndDismiss(error)
      }
    }
  }

  private func getContext(_ action: (@MainActor (_ context: InteractorContext) throws -> Void)?) rethrows {
    guard let engine else {
      return
    }
    try action?(.init(engine, self))
  }

  func updateZoom(with insets: EdgeInsets?, canvasHeight: CGFloat) {
    let lastTask = zoom.task
    lastTask?.cancel()

    zoom.toTextCursor = false
    zoom.task = Task {
      _ = await sceneTask?.result
      _ = await lastTask?.result
      if Task.isCancelled {
        return
      }
      do {
        if isEditing {
          try await engine?.zoomToPage(page, insets)
          if editMode == .text {
            try engine?.zoomToSelectedText(insets, canvasHeight: canvasHeight)
          }
        } else {
          if let engine {
            try await behavior.enablePreviewMode(.init(engine, self), insets)
          }
        }
      } catch {
        handleError(error)
      }
    }
  }

  func zoomToText(with insets: EdgeInsets?, canvasHeight: CGFloat, cursorPosition: CGPoint?) {
    guard editMode == .text, let cursorPosition, cursorPosition != .zero else {
      return
    }

    let lastTask = zoom.task
    if zoom.toTextCursor {
      lastTask?.cancel()
    }

    zoom.toTextCursor = true
    zoom.task = Task {
      _ = await sceneTask?.result
      _ = await lastTask?.result
      if Task.isCancelled {
        return
      }
      do {
        try engine?.zoomToSelectedText(insets, canvasHeight: canvasHeight)
      } catch {
        handleError(error)
      }
    }
  }
}

// MARK: - Private implementation

private extension Interactor {
  var engine: Engine? {
    guard let engine = _engine else {
      return nil
    }
    return engine
  }

  func handleError(_ error: Swift.Error) {
    self.error = .init(error, dismiss: false)
  }

  func handleErrorWithTask(_ error: Swift.Error) {
    // Only show most recent error once.
    if error.localizedDescription != self.error.details?.message {
      Task {
        handleError(error)
      }
    }
  }

  func handleErrorAndDismiss(_ error: Swift.Error) {
    self.error = .init(error, dismiss: true)
  }

  func get<T: MappedType>(_ id: DesignBlockID, _ propertyBlock: PropertyBlock? = nil,
                          property: Property,
                          getter: PropertyGetter<T> = Getter.get()) -> T? {
    guard let engine, engine.block.isValid(id) else {
      return nil
    }
    do {
      return try getter(engine, id, propertyBlock, property)
    } catch {
      handleErrorWithTask(error)
      return nil
    }
  }

  func get<T: MappedType>(_ id: DesignBlockID,
                          getter: RawGetter<T>) -> T? {
    guard let engine, engine.block.isValid(id) else {
      return nil
    }
    do {
      return try getter(engine, id)
    } catch {
      handleErrorWithTask(error)
      return nil
    }
  }

  func set<T: MappedType>(_ ids: [DesignBlockID], _ propertyBlock: PropertyBlock? = nil,
                          property: Property, value: T,
                          setter: PropertySetter<T> = Setter.set(),
                          completion: PropertyCompletion?) -> Bool {
    guard let engine else {
      return false
    }
    do {
      let valid = ids.filter {
        engine.block.isValid($0)
      }
      return try setter(engine, valid, propertyBlock, property, value, completion)
    } catch {
      handleErrorWithTask(error)
      return false
    }
  }

  func set<T: MappedType>(_ ids: [DesignBlockID],
                          value: T,
                          setter: RawSetter<T>,
                          completion: PropertyCompletion?) -> Bool {
    guard let engine else {
      return false
    }
    do {
      let valid = ids.filter {
        engine.block.isValid($0)
      }
      return try setter(engine, valid, value, completion)
    } catch {
      handleErrorWithTask(error)
      return false
    }
  }

  func enablePreviewMode() throws {
    // Call engine?.enablePreviewMode() in updateZoom to avoid page fill flickering.
    withAnimation(.default) {
      isEditing = false
    }
    sheet.isPresented = false
    setEditMode(.transform)
  }

  func enableEditMode() throws {
    try getContext(behavior.enableEditMode)
    withAnimation(.default) {
      isEditing = true
    }
  }

  func exportScene() {
    isExporting = true
    Task(priority: .background) {
      guard let engine else {
        return
      }
      do {
        let (data, contentType) = try await behavior.exportScene(.init(engine, self))
        let name = String(describing: Action.export)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, conformingTo: contentType)
        try data.write(to: url)
        export = ActivityItem(items: url)
        isExporting = false
      } catch {
        handleError(error)
      }
    }
  }

  func sheetType(for designBlockType: String, with fillType: String? = nil,
                 and kind: BlockKind? = nil) -> SheetType? {
    switch designBlockType {
    case BlockType.text.rawValue: return .text
    case BlockType.group.rawValue: return .group
    case BlockType.page.rawValue: return .page
    case BlockType.graphic.rawValue:
      guard let fillType else { return nil }
      switch fillType {
      case FillType.image.rawValue:
        if kind == .key(.sticker) {
          return .sticker
        }
        return .image
      default:
        if kind == .key(.shape) {
          return .shape
        }
        return nil
      }
    default: return nil
    }
  }

  func sheetType(for selection: Selection?) -> SheetType? {
    if let selection, selection.blocks.count == 1,
       let block = selection.blocks.first,
       let type = sheetType(block) {
      return type
    }
    return nil
  }

  func placeholderType(for selection: Selection?) -> SheetType? {
    guard let engine,
          let selection, selection.blocks.count == 1,
          let block = selection.blocks.first,
          let type = sheetType(block) else {
      return nil
    }
    do {
      guard try engine.editor.getSettingEnum("role") == "Adopter",
            try engine.block.hasPlaceholderControls(block) else {
        return nil
      }
      let isPlaceholder = try engine.block.isPlaceholderEnabled(block)
      let showsPlaceholderButton = try engine.block.isPlaceholderControlsButtonEnabled(block)
      let showsPlaceholderOverlay = try engine.block.isPlaceholderControlsOverlayEnabled(block)

      if isPlaceholder, showsPlaceholderButton || showsPlaceholderOverlay {
        return type
      } else {
        return nil
      }
    } catch {
      handleError(error)
      return nil
    }
  }

  func updateState() {
    guard let engine else {
      return
    }
    editMode = engine.editor.getEditMode()
    textCursorPosition = CGPoint(x: CGFloat(engine.editor.getTextCursorPositionInScreenSpaceX()),
                                 y: CGFloat(engine.editor.getTextCursorPositionInScreenSpaceY()))
    canUndo = (try? engine.editor.canUndo()) ?? false
    canRedo = (try? engine.editor.canRedo()) ?? false

    let selected = engine.block.findAllSelected()
    selection = {
      if selected.isEmpty {
        return nil
      } else {
        let box = try? engine.block.getScreenSpaceBoundingBox(containing: selected)
        return .init(blocks: selected, boundingBox: box ?? .zero)
      }
    }()

    do {
      try behavior.updateState(.init(engine, self))
    } catch {
      handleErrorWithTask(error)
    }
  }

  func observeState() -> Task<Void, Never> {
    Task {
      guard let engine else {
        return
      }
      for await _ in engine.editor.onStateChanged {
        updateState()
      }
    }
  }

  func observeEvent() -> Task<Void, Never> {
    Task {
      guard let engine else {
        return
      }
      for await _ in engine.event.subscribe(to: []) {
        updateState()
      }
    }
  }

  func setEditMode(_ newValue: EditMode) {
    guard newValue != editMode else {
      return
    }
    engine?.editor.setEditMode(newValue)
  }

  func setPage(_ newValue: Int) throws {
    guard newValue != page, let engine else {
      return
    }
    let pages = try engine.getSortedPages()
    if (0 ..< pages.endIndex).contains(newValue) {
      page = newValue
    }
  }

  // MARK: - State changes

  func pageChanged(_ oldValue: Int) {
    guard let engine, oldValue != page else {
      return
    }
    do {
      try engine.showPage(page)
      try engine.editor.resetHistory()
      try behavior.pageChanged(.init(engine, self))
      sheet.isPresented = false
    } catch {
      handleError(error)
    }
  }

  func sheetChanged(_ oldValue: SheetState) {
    guard oldValue != sheet else {
      return
    }
    if !sheet.isPresented, oldValue.state == .init(.crop, .image) {
      setEditMode(.transform)
    }
  }

  func selectionChanged(_ oldValue: Selection?) {
    guard oldValue != selection else {
      return
    }
    let wasPresented = sheet.isPresented

    if sheet.isPresented {
      if sheet.mode != .add,
         oldValue?.blocks != selection?.blocks {
        sheet.isPresented = false
      }
      if sheet.mode == .add, selection != nil {
        sheet.isPresented = false
      }
    }
    if oldValue?.blocks != selection?.blocks,
       let type = placeholderType(for: selection) {
      func showReplaceSheet() {
        sheet = .init(.replace, type)
      }

      if wasPresented, sheet.mode != .replace, sheet.type != type {
        if sheet.isPresented {
          sheet.isPresented = false
        }
        Task {
          try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 200)
          showReplaceSheet()
        }
      } else {
        showReplaceSheet()
      }
    }
  }

  func editModeChanged(_ oldValue: EditMode) {
    guard oldValue != editMode else {
      return
    }
    if sheet.isPresented {
      if editMode == .text || oldValue == .crop {
        sheet.isPresented = false
      }
    }
    if editMode == .crop, sheet.state != .init(.crop, .image) {
      func showCropSheet() {
        sheet.commit { model in
          model = .init(.crop, .image)
          model.detent = .small
          model.detents = [.small, .large]
        }
      }

      if sheet.isPresented {
        sheet.isPresented = false
        Task {
          try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 200)
          showCropSheet()
        }
      } else {
        showCropSheet()
      }
    }
  }
}
