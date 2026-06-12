// Source-of-truth Swift schema fixture for the validation harness.
//
// This file is intentionally small until InstantSwiftDataSchema exists. It names
// the first entities, links, rooms, topics, files, and permissions the generator
// must support.

import Foundation

struct ValidationSchema {
  struct Profile {
    var id: String
    var handle: String
    var displayName: String
    var createdAt: Date
  }

  struct Post {
    var id: String
    var content: String
    var createdAt: Date
  }

  enum Links {
    static let postAuthor = "posts.author -> profiles.posts"
  }

  struct ValidationRoom {
    struct Presence {
      var name: String
      var cursorX: Double?
      var cursorY: Double?
    }

    struct PingTopic {
      var message: String
      var sentAt: Date
    }
  }

  struct FileRecord {
    var id: String
  }

  enum Permissions {
    static let profiles = "allow authenticated users"
    static let posts = "allow authenticated users"
    static let files = "allow authenticated users"
  }
}
