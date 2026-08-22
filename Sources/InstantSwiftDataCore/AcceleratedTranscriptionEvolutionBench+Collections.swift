extension AcceleratedTranscriptionEvolutionBench {
  public static func canonicalHash<Lines: Collection>(
    _ lines: Lines
  ) -> String where Lines.Element == String {
    canonicalHash(Array(lines))
  }
}
