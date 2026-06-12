// Source-of-truth Swift schema fixture for the validation harness.
//
// This file is intentionally small until InstantDataSchema exists. It names the
// first entities and links the generator must support.

struct ValidationSchema {
  struct Profile {
    var id: String
    var handle: String
    var displayName: String
    var createdAt: Double
  }

  struct Post {
    var id: String
    var content: String
    var createdAt: Double
  }
}

