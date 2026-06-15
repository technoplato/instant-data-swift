// Source-of-truth Swift schema fixture for the validation harness.
//
// The committed TypeScript fixtures in this directory are semantic projections
// of these Swift-owned schema and permissions documents.

import InstantSwiftDataSchema

public enum ValidationFixtureSchema {
  public static let schema = InstantSchemaExamples.validationDocument
  public static let permissions = InstantSchemaExamples.validationPermissions
}
