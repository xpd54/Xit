import Foundation

/// Abstract base class for file list data sources.
class FileListDataSourceBase: NSObject
{
  @IBOutlet weak var outlineView: NSOutlineView!
  @IBOutlet weak var controller: FileViewController!
  let useWorkspaceList: Bool

  let observers = ObserverCollection()
  
  struct ColumnID
  {
    static let unstaged = ¶"unstaged"
  }
  
  weak var repoController: RepositoryController!
  {
    didSet
    {
      (self as! FileListDataSource).reload()
      observers.addObserver(forName: .XTRepositoryWorkspaceChanged,
                            object: repoController.repository, queue: .main) {
        [weak self] (note) in
        guard let myself = self
        else { return }
        
        if myself.outlineView?.dataSource === myself {
          myself.workspaceChanged(note.userInfo?[XTPathsKey] as? [String])
        }
      }
      observers.addObserver(forName: .XTSelectedModelChanged,
                            object: repoController, queue: .main) {
        [weak self] (_) in
        guard let myself = self,
              myself.outlineView?.dataSource === myself,
              myself.repoController != nil // Otherwise we're on a stale timer
        else { return }
        
        (myself as? FileListDataSource)?.reload()
        myself.updateStagingView()
      }
      
    }
  }
  
  class func transformDisplayChange(_ change: DeltaStatus) -> DeltaStatus
  {
    return (change == .unmodified) ? .mixed : change
  }
  
  init(useWorkspaceList: Bool)
  {
    self.useWorkspaceList = useWorkspaceList
  }

  func model(for selection: RepositorySelection) -> FileListModel?
  {
    return useWorkspaceList
        ? (selection as? StagedUnstagedSelection)?.unstagedFileList
        : selection.fileList
  }
  
  func workspaceChanged(_ paths: [String]?)
  {
    if repoController.selection is StagingSelection {
      (self as! FileListDataSource).reload()
    }
  }
  
  func updateStagingView()
  {
    let unstagedColumn = outlineView.tableColumn(withIdentifier: ColumnID.unstaged)
    
    unstagedColumn?.isHidden = !(repoController.selection is
                                 StagedUnstagedSelection)
  }
}


/// Methods that a file list data source must implement.
protocol FileListDataSource: class
{
  var hierarchical: Bool { get }
  
  func reload()
  func fileChange(at row: Int) -> FileChange?
  func path(for item: Any) -> String
  func change(for item: Any) -> DeltaStatus
}


/// Cell view with custom drawing for deleted files.
class FileCellView: NSTableCellView
{
  /// The change is stored to improve drawing of selected deleted files.
  var change: DeltaStatus = .unmodified
  
  override var backgroundStyle: NSView.BackgroundStyle
  {
    didSet
    {
      if backgroundStyle == .dark {
        textField?.textColor = .textColor
      }
      else if change == .deleted {
        textField?.textColor = .disabledControlTextColor
      }
    }
  }
}


/// Cell view with a button rather than an image.
class TableButtonView: NSTableCellView
{
  @IBOutlet var button: NSButton!
}
