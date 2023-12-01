import Combine
import Foundation
import IMGLYCore
import IMGLYEngine

@MainActor
class AssetLibraryInteractorMock: ObservableObject {
  @Published private(set) var isAddingAsset = false

  private var engine: Engine?
  private var sceneTask: Task<Void, Swift.Error>?

  func loadScene() {
    guard sceneTask == nil else {
      return
    }
    sceneTask = Task {
      let engine = try await Engine(license: Secrets.licenseKey)
      self.engine = engine
      try engine.scene.createVideo()
      let basePath = "https://cdn.img.ly/packages/imgly/cesdk-engine/1.19.0-rc.0/assets"
      try engine.editor.setSettingString("basePath", value: basePath)
      try engine.asset.addSource(UnsplashAssetSource())
      try engine.asset.addSource(TextAssetSource(engine: engine))
      async let loadDefaultAssets: () = engine.addDefaultAssetSources()
      async let loadDemoAssetSources: () = engine.addDemoAssetSources(sceneMode: engine.scene.getMode(),
                                                                      withUploadAssetSources: true)
      _ = try await (loadDefaultAssets, loadDemoAssetSources)
    }
  }
}

extension AssetLibraryInteractorMock: AssetLibraryInteractor {
  func findAssets(sourceID: String, query: IMGLYEngine.AssetQueryData) async throws -> IMGLYEngine.AssetQueryResult {
    loadScene()
    _ = await sceneTask?.result
    guard let engine else { throw Error(errorDescription: "Engine unavailable.") }
    return try await engine.asset.findAssets(sourceID: sourceID, query: query)
  }

  func getGroups(sourceID: String) async throws -> [String] {
    loadScene()
    _ = await sceneTask?.result
    guard let engine else { throw Error(errorDescription: "Engine unavailable.") }
    return try await engine.asset.getGroups(sourceID: sourceID)
  }

  func getCredits(sourceID: String) -> AssetCredits? {
    guard let engine else { return nil }
    return engine.asset.getCredits(sourceID: sourceID)
  }

  func getLicense(sourceID: String) -> AssetLicense? {
    guard let engine else { return nil }
    return engine.asset.getLicense(sourceID: sourceID)
  }

  func addAsset(to sourceID: String, asset: IMGLYEngine.AssetDefinition) throws {
    guard let engine else { throw Error(errorDescription: "Engine unavailable.") }
    try engine.asset.addAsset(to: sourceID, asset: asset)
  }

  func assetTapped(sourceID _: String, asset _: IMGLYEngine.AssetResult) {
    isAddingAsset = true
    Task {
      try await Task.sleep(nanoseconds: NSEC_PER_SEC)
      isAddingAsset = false
    }
  }

  func getBasePath() throws -> String {
    guard let engine else { throw Error(errorDescription: "Engine unavailable.") }
    return try engine.editor.getSettingString("basePath")
  }
}
