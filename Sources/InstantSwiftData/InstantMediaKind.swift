import Foundation

/// Common Instant media / attachment kinds for app schemas (ADR 0015).
///
/// Prefer this (or an app-specific enum) over raw `String` for `kind` fields.
/// Wire encoding uses stable raw values for Instant attribute storage.
public enum InstantMediaKind: String, Codable, Sendable, Hashable, CaseIterable {
  case audio
  case image
  case video
  case file

  /// Best-effort map from a MIME type (e.g. `image/jpeg` → `.image`).
  public init?(contentType: String) {
    let lowered = contentType.lowercased()
    if lowered.hasPrefix("image/") {
      self = .image
    } else if lowered.hasPrefix("audio/") {
      self = .audio
    } else if lowered.hasPrefix("video/") {
      self = .video
    } else if lowered.isEmpty {
      return nil
    } else {
      self = .file
    }
  }
}

/// Narrow set of content types Instant apps often store as attributes.
/// Prefer enum cases over free-form strings when the set is known.
public enum InstantContentType: String, Codable, Sendable, Hashable, CaseIterable {
  case jpeg = "image/jpeg"
  case png = "image/png"
  case heic = "image/heic"
  case gif = "image/gif"
  case webp = "image/webp"
  case mp4 = "video/mp4"
  case m4a = "audio/mp4"
  case mpeg = "audio/mpeg"
  case wav = "audio/wav"
  case octetStream = "application/octet-stream"

  public var mediaKind: InstantMediaKind {
    InstantMediaKind(contentType: rawValue) ?? .file
  }

  /// Parse a MIME string into a known case, or `nil` if unknown.
  public init?(mimeType: String) {
    let trimmed = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let exact = InstantContentType(rawValue: trimmed) {
      self = exact
      return
    }
    // Allow "image/jpeg; charset=binary"
    let base = trimmed.split(separator: ";", maxSplits: 1).first.map(String.init) ?? trimmed
    if let exact = InstantContentType(rawValue: base) {
      self = exact
    } else {
      return nil
    }
  }
}
