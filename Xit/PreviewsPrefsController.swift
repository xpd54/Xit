import Cocoa

extension NSNotification.Name
{
  static let XTFontChanged: NSNotification.Name = ◊"XTFontChanged"
}

enum WhitespaceSetting: String
{
  case showAll
  case ignoreEOL
  case ignoreAll
  
  static let allValues: [WhitespaceSetting] = [.showAll, .ignoreEOL, .ignoreAll]
}

class PreviewsPrefsController: NSViewController
{
  @IBOutlet weak var whitespacePopup: NSPopUpButton!
  @IBOutlet weak var tabPopup: NSPopUpButton!
  @IBOutlet weak var contextPopup: NSPopUpButton!
  @IBOutlet weak var wrappingPopup: NSPopUpButton!
  @IBOutlet weak var fontField: NSTextField!
  
  var textFont: NSFont?
  {
    didSet
    {
      guard textFont != oldValue
      else { return }
      
      if let name = textFont?.displayName,
         let size = textFont?.pointSize {
        fontField.stringValue = "\(name) \(Int(size))"
      }
      else {
        fontField.stringValue = ""
      }
      saveFont()
      NotificationCenter.default.post(name: .XTFontChanged, object: nil)
    }
  }

  struct PreferenceKeys
  {
    static let diffWhitespace = "diffWhitespace"
    static let tabWidth = "tabWidth"
    static let contextLines = "contextLines"
    static let fontName = "fontName"
    static let fontSize = "fontSize"
    static let wrapping = "wrapping"
  }
  
  struct Values
  {
    static let tabs: [UInt] = [2, 4, 6, 8]
    static let context: [UInt] = [0, 3, 6, 12, 25]
  }
  
  struct Initial
  {
    static let whitespace = WhitespaceSetting.showAll
    static let tabWidth: UInt = 4
    static var contextLines: UInt
    {
      return PatchMaker.defaultContextLines
    }
  }
  
  struct Default
  {
    /// Default or user-selected font
    static func font() -> NSFont
    {
      let defaults = UserDefaults.standard
      let fontName = defaults.string(forKey: PreferenceKeys.fontName)
                     ?? "SF Mono"
      let storedSize = defaults.integer(forKey: PreferenceKeys.fontSize)
      let fontSize = CGFloat((storedSize == 0) ? 11 : storedSize)
      
      return NSFont(name: fontName, size: fontSize)
             ?? NSFont(name: "Monaco", size: fontSize)
             ?? NSFont.systemFont(ofSize: fontSize)
    }
    
    /// Default or user-selected whitespace setting
    static func whitespace() -> WhitespaceSetting
    {
      let defaults = UserDefaults.standard
      let defaultWhitespace = Initial.whitespace
      let whitespaceString = defaults.string(forKey: PreferenceKeys.diffWhitespace)
                             ?? defaultWhitespace.rawValue
      
      return WhitespaceSetting.init(rawValue: whitespaceString)
             ?? defaultWhitespace
    }
    
    /// Default or user-selected tab width
    static func tabWidth() -> UInt
    {
      let defaults = UserDefaults.standard
      let tabSetting = UInt(defaults.integer(forKey: PreferenceKeys.tabWidth))
      
      return (tabSetting == 0) ? Initial.tabWidth : tabSetting
    }
    
    /// Default or user-selected context line count
    static func contextLines() -> UInt
    {
      let defaults = UserDefaults.standard
      
      // 0 is a valid value, so defaults using that as the "value not set"
      // marker isn't useful.
      if let contextSetting = defaults.value(forKey: PreferenceKeys.contextLines)
                              as? UInt,
         Values.context.index(of: contextSetting) != nil {
        return contextSetting
      }
      else {
        return Initial.contextLines
      }
    }
    
    /// Default or user-selected text wrapping option
    static func wrapping() -> Wrapping
    {
      let defaults = UserDefaults.standard
      let wrapSetting = defaults.integer(forKey: PreferenceKeys.wrapping)
      
      return Wrapping(rawValue: wrapSetting) ?? .windowWidth
    }
  }

  override func viewDidLoad()
  {
    super.viewDidLoad()
    
    let whitespaceValue = Default.whitespace()
    
    whitespacePopup.selectItem(at:
        WhitespaceSetting.allValues.index(of: whitespaceValue)!)
    
    let tabSetting = Default.tabWidth()
    let tabIndex = Values.tabs.index(of: tabSetting) ??
                   Values.tabs.index(of: Initial.tabWidth)!
    
    tabPopup.selectItem(at: tabIndex)
    
    let contextIndex = Values.context.index(of: Default.contextLines()) ?? 1
    
    contextPopup.selectItem(at: contextIndex)
    
    textFont = Default.font()
    
    let wrapping = Default.wrapping()
    
    switch wrapping {
      case .windowWidth:
        wrappingPopup.selectItem(at: 0)
      case .columns:
        wrappingPopup.selectItem(at: 1)
      case .none:
        wrappingPopup.selectItem(at: 2)
    }
  }
  
  override func viewDidDisappear()
  {
    let manager = NSFontManager.shared
    
    if manager.target === self {
      manager.target = nil
    }
  }
  
  @IBAction func showFontPanel(_ sender: Any)
  {
    guard let font = textFont
    else { return }
    
    let manager = NSFontManager.shared
  
    manager.fontPanel(true)?.delegate = self
    manager.setSelectedFont(font, isMultiple: false)
    manager.orderFrontFontPanel(sender)
    manager.target = self
  }
  
  // The return type of validModesForFontPanel changed in the 10.13 SDK,
  // so there's pretty much no way to compile this until the deployment version
  // is updated to 10.13.
  /*
  override func validModesForFontPanel(_ fontPanel: NSFontPanel)
      -> NSFontPanel.ModeMask
  {
    return [.face, .size, .collection]
  }
  */
  
  override func changeFont(_ sender: Any?)
  {
    guard let newFont = textFont.map({ NSFontManager.shared.convert($0) })
    else { return }
    
    textFont = newFont
  }
}

extension PreviewsPrefsController: NSWindowDelegate
{
  // It just needs the protocol to be able to set the font panel delegate.
}

extension PreviewsPrefsController: PreferencesSaver
{
  func wrappingValue() -> Int
  {
    switch wrappingPopup.indexOfSelectedItem {
      case 0:
        return 0
      case 1:
        return 80
      case 2:
        return -1
      default:
        return 0
    }
  }
  
  func savePreferences()
  {
    let defaults = UserDefaults.standard
    let whitespaceIndex = whitespacePopup.indexOfSelectedItem
    let tabIndex = tabPopup.indexOfSelectedItem
    let contextIndex = contextPopup.indexOfSelectedItem
    
    defaults.set(WhitespaceSetting.allValues[whitespaceIndex].rawValue,
                 forKey: PreferenceKeys.diffWhitespace)
    defaults.set(Values.tabs[tabIndex],
                 forKey: PreferenceKeys.tabWidth)
    defaults.set(Values.context[contextIndex],
                 forKey: PreferenceKeys.contextLines)
    defaults.set(wrappingValue(),
                 forKey: PreferenceKeys.wrapping)
    
    saveFont()
  }
  
  func saveFont()
  {
    if let font = textFont {
      let defaults = UserDefaults.standard
      
      defaults.set(font.displayName, forKey: PreferenceKeys.fontName)
      defaults.set(Int(font.pointSize), forKey: PreferenceKeys.fontSize)
    }
  }
}
