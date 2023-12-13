import Foundation

public enum RawRepresentableKey<T>: Hashable, RawRepresentable where T: RawRepresentable, T.RawValue == String {
  case key(T)
  case raw(String)

  public init(_ key: T) {
    self = .key(key)
  }

  public init(rawValue: String) {
    if let key = T(rawValue: rawValue) {
      self = .key(key)
    } else {
      self = .raw(rawValue)
    }
  }

  public var rawValue: String {
    switch self {
    case let .key(key): return key.rawValue
    case let .raw(raw): return raw
    }
  }
}
