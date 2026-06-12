import Foundation

enum Terminal {
  static let reset = "\u{001B}[0m"
  static let bold = "\u{001B}[1m"
  static let dim = "\u{001B}[2m"
  static let italic = "\u{001B}[3m"
  
  static let black = "\u{001B}[30m"
  static let red = "\u{001B}[31m"
  static let green = "\u{001B}[32m"
  static let yellow = "\u{001B}[33m"
  static let blue = "\u{001B}[34m"
  static let magenta = "\u{001B}[35m"
  static let cyan = "\u{001B}[36m"
  static let white = "\u{001B}[37m"
  static let gray = "\u{001B}[90m"
  
  static let bgBlack = "\u{001B}[40m"
  static let bgRed = "\u{001B}[41m"
  static let bgGreen = "\u{001B}[42m"
  static let bgYellow = "\u{001B}[43m"
  static let bgBlue = "\u{001B}[44m"
  static let bgMagenta = "\u{001B}[45m"
  static let bgCyan = "\u{001B}[46m"
  static let bgWhite = "\u{001B}[47m"
  
  static func green(_ text: String) -> String {
    "\(green)\(text)\(reset)"
  }
  
  static func red(_ text: String) -> String {
    "\(red)\(text)\(reset)"
  }
  
  static func yellow(_ text: String) -> String {
    "\(yellow)\(text)\(reset)"
  }
  
  static func blue(_ text: String) -> String {
    "\(blue)\(text)\(reset)"
  }
  
  static func gray(_ text: String) -> String {
    "\(gray)\(text)\(reset)"
  }
  
  static func bold(_ text: String) -> String {
    "\(bold)\(text)\(reset)"
  }
  
  static func italic(_ text: String) -> String {
    "\(italic)\(text)\(reset)"
  }
  
  static func greenBadge(_ text: String) -> String {
    "\(bgGreen)\(black) \(text) \(reset)"
  }
  
  static func redBadge(_ text: String) -> String {
    "\(bgRed)\(white) \(text) \(reset)"
  }
  
  static func yellowBadge(_ text: String) -> String {
    "\(bgYellow)\(black) \(text) \(reset)"
  }
  
  static func blueBadge(_ text: String) -> String {
    "\(bgBlue)\(black) \(text) \(reset)"
  }
  
  static let checkmark = "\(green)✓\(reset)"
  static let cross = "\(red)✗\(reset)"
  static let warning = "\(yellow)⚠\(reset)"
  
  static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
}
