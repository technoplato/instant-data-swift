import Foundation
import InstantDB

enum SchemaLoader {
  static func load(from path: String) throws -> InstantSchema {
    guard FileManager.default.fileExists(atPath: path) else {
      throw CLIError.fileNotFound(path)
    }
    
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try loadFromData(data)
  }
  
  static func loadFromData(_ data: Data) throws -> InstantSchema {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CLIError.invalidJSON
    }
    
    return try loadFromDictionary(json)
  }
  
  static func loadFromDictionary(_ json: [String: Any]) throws -> InstantSchema {
    var entities: [SchemaEntityDef] = []
    var links: [SchemaLink] = []
    
    if let entitiesDict = json["entities"] as? [String: [String: Any]] {
      for (name, entityConfig) in entitiesDict {
        if let attrs = entityConfig["attrs"] as? [String: [String: Any]] {
          let entity = parseEntity(name: name, attributes: attrs)
          entities.append(entity)
        }
      }
    }
    
    if let linksDict = json["links"] as? [String: [String: [String: Any]]] {
      for (_, config) in linksDict {
        if let link = parseLink(config) {
          links.append(link)
        }
      }
    }
    
    return InstantSchema(entities: entities, links: links)
  }
  
  private static func parseEntity(name: String, attributes: [String: [String: Any]]) -> SchemaEntityDef {
    var parsedAttrs: [SchemaAttribute] = []
    
    for (attrName, attrConfig) in attributes {
      let type = InstantDataType(rawValue: attrConfig["valueType"] as? String ?? "any") ?? .any
      let config = attrConfig["config"] as? [String: Any] ?? [:]
      let isRequired = attrConfig["required"] as? Bool ?? false
      let isIndexed = config["indexed"] as? Bool ?? false
      let isUnique = config["unique"] as? Bool ?? false
      
      let attr = SchemaAttribute(
        attrName,
        type,
        isOptional: !isRequired,
        isIndexed: isIndexed,
        isUnique: isUnique
      )
      parsedAttrs.append(attr)
    }
    
    return SchemaEntityDef(name, attributes: parsedAttrs)
  }
  
  private static func parseLink(_ config: [String: [String: Any]]) -> SchemaLink? {
    guard let fwd = config["forward"],
          let rev = config["reverse"],
          let fwdOn = fwd["on"] as? String,
          let fwdLabel = fwd["label"] as? String,
          let revOn = rev["on"] as? String,
          let revLabel = rev["label"] as? String else {
      return nil
    }
    
    let forward = LinkEndpoint(
      on: fwdOn,
      label: fwdLabel,
      has: Cardinality(rawValue: fwd["has"] as? String ?? "one") ?? .one
    )
    
    let reverse = LinkEndpoint(
      on: revOn,
      label: revLabel,
      has: Cardinality(rawValue: rev["has"] as? String ?? "many") ?? .many
    )
    
    return SchemaLink(forward: forward, reverse: reverse)
  }
}
