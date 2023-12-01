import Foundation

public typealias BlockKind = RawRepresentableKey<BlockKindKey>

public enum BlockKindKey: String {
  case image
  case video
  case sticker
  case scene
  case camera
  case stack
  case page
  case audio
  case text
  case shape
  case group
}
