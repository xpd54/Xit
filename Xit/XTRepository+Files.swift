import Foundation

public enum FileContext
{
  case commit(Commit)
  case index
  case workspace
}

extension XTRepository: FileContents
{
  static let textNames = ["AUTHORS", "CONTRIBUTING", "COPYING", "LICENSE",
                          "Makefile", "README"]
  
  static func isTextExtension(_ name: String) -> Bool
  {
    let ext = (name as NSString).pathExtension
    guard !ext.isEmpty
    else { return false }
    
    let unmanaged = UTTypeCreatePreferredIdentifierForTag(
          kUTTagClassFilenameExtension, ext as CFString, nil)
    let utType = unmanaged?.takeRetainedValue()
    
    return utType.map { UTTypeConformsTo($0, kUTTypeText) } ?? false
  }
  
  /// Returns true if the file seems to be text, based on its name or its content.
  /// - parameter path: File path relative to the repository
  /// - parameter context: Where to look for the specified file
  public func isTextFile(_ path: String, context: FileContext) -> Bool
  {
    let name = (path as NSString).lastPathComponent
    guard !name.isEmpty
    else { return false }
    
    if XTRepository.textNames.contains(name) {
      return true
    }
    if XTRepository.isTextExtension(name) {
      return true
    }
    
    switch context {
      case .commit(let commit):
        if let blob = commit.tree?.entry(path: path)?.object as? Blob {
          return !blob.isBinary
        }
      case .index:
        if let oid = GitIndex(repository: self)?.entry(at: path)?.oid,
           let blob = GitBlob(repository: self, oid: oid) {
          return !blob.isBinary
        }
      case .workspace:
        let url = self.fileURL(path)
        guard let data = try? Data(contentsOf: url)
        else { return false }
        
        return !data.isBinary()
    }
    
    return false
  }
  
  public func contentsOfFile(path: String, at commit: Commit) -> Data?
  {
    // TODO: make a Tree protocol to eliminate this cast
    guard let commit = commit as? XTCommit,
          let tree = commit.tree,
          let entry = tree.entry(path: path),
          let blob = entry.object as? Blob
    else { return nil }
    
    return blob.makeData()
  }
  
  public func contentsOfStagedFile(path: String) -> Data?
  {
    var result: Data?
    
    _ = try? stagedBlob(file: path)?.withData {
      (data) in
      result = (data as NSData).copy() as? Data
    }
    return result
  }
  
  public func stagedBlob(file: String) -> Blob?
  {
    guard let index = GitIndex(repository: self),
          let entry = index.entry(at: file),
          let blob = GitBlob(gitRepository: gitRepo,
                             oid: entry.oid)
    else { return nil }
    
    return blob
  }
  
  public func fileBlob(ref: String, path: String) -> Blob?
  {
    guard let headTree = XTCommit(ref: ref, repository: self)?.tree,
          let headEntry = headTree.entry(path: path),
          let headObject = headEntry.object
    else { return nil }
    
    return headObject as? Blob
  }
  
  /// Returns a file URL for a given relative path.
  public func fileURL(_ file: String) -> URL
  {
    return repoURL.appendingPathComponent(file)
  }
}

extension XTRepository: FileDiffing
{
  /// Returns a diff maker for a file at the specified commit, compared to the
  /// parent commit.
  public func diffMaker(forFile file: String,
                        commitOID: OID,
                        parentOID: OID?) -> PatchMaker.PatchResult?
  {
    guard let toCommit = commit(forOID: commitOID as! GitOID) as? XTCommit
    else { return nil }
    
    let parentCommit = parentOID.flatMap({ commit(forOID: $0) })
    guard isTextFile(file, context: .commit(toCommit)) ||
          parentCommit.map({ isTextFile(file, context: .commit($0)) }) ?? false
    else { return .binary }
    
    var fromSource = PatchMaker.SourceType.data(Data())
    var toSource = PatchMaker.SourceType.data(Data())
    
    if let toTree = toCommit.tree,
       let toEntry = toTree.entry(path: file),
       let toBlob = toEntry.object as? GitBlob {
      toSource = .blob(toBlob)
    }
    
    if let fromTree = parentCommit?.tree,
       let fromEntry = fromTree.entry(path: file),
       let fromBlob = fromEntry.object as? GitBlob {
      fromSource = .blob(fromBlob)
    }
    
    return .diff(PatchMaker(from: fromSource, to: toSource, path: file))
  }
  
  // Returns a file diff for a given commit.
  public func diff(for path: String,
                   commitSHA sha: String,
                   parentOID: OID?) -> DiffDelta?
  {
    let diff = self.diff(forSHA: sha, parent: parentOID)
    
    return diff?.delta(forNewPath: path)
  }
  
  /// Returns a diff maker for a file in the index, compared to the workspace
  /// file.
  public func stagedDiff(file: String) -> PatchMaker.PatchResult?
  {
    guard isTextFile(file, context: .index)
    else { return .binary }
    
    guard let headRef = self.headRef
    else { return nil }
    let indexBlob = stagedBlob(file: file)
    let headBlob = fileBlob(ref: headRef, path: file)
    
    return .diff(PatchMaker(from: PatchMaker.SourceType(headBlob),
                             to: PatchMaker.SourceType(indexBlob),
                             path: file))
  }
  
  /// Returns a diff maker for a file in the workspace, compared to the index.
  public func unstagedDiff(file: String) -> PatchMaker.PatchResult?
  {
    guard isTextFile(file, context: .workspace)
    else { return .binary }
    
    let url = self.repoURL.appendingPathComponent(file)
    let exists = FileManager.default.fileExists(atPath: url.path)
    
    do {
      let data = exists ? try Data(contentsOf: url) : Data()
      
      if let index = GitIndex(repository: self),
         let indexEntry = index.entry(at: file),
         let indexBlob = GitBlob.init(gitRepository: gitRepo,
                                      oid: indexEntry.oid) {
        return .diff(PatchMaker(from: PatchMaker.SourceType(indexBlob),
                                 to: .data(data), path: file))
      }
      else {
        return .diff(PatchMaker(from: .data(Data()),
                                 to: .data(data),
                                 path: file))
      }
    }
    catch {
      return nil
    }
  }
  
  public func blame(for path: String,
                    from startOID: OID?, to endOID: OID?) -> Blame?
  {
    return GitBlame(repository: self, path: path, from: startOID, to: endOID)
  }
  
  public func blame(for path: String,
                    data fromData: Data?, to endOID: OID?) -> Blame?
  {
    return GitBlame(repository: self, path: path,
                    data: fromData ?? Data(), to: endOID)
  }
}

extension XTRepository
{
  
  /// Returns the diff for the referenced commit, compared to its first parent
  /// or to a specific parent.
  func diff(forSHA sha: String, parent parentOID: OID?) -> Diff?
  {
    let parentSHA = parentOID?.sha ?? ""
    let key = sha.appending(parentSHA)
    
    if let diff = diffCache[key] {
      return diff
    }
    else {
      guard let commit = commit(forSHA: sha)
      else { return nil }
      
      let parentSHAs = commit.parentSHAs
      let parentSHA: String? = (parentSHA == "")
            ? parentSHAs.first
            : parentSHAs.first(where: { $0 == parentSHA })
      let parentCommit = parentSHA.map({ self.commit(forSHA: $0) })
      
      guard let diff = GitDiff(oldTree: parentCommit??.tree, newTree: commit.tree,
                               repository: gitRepo)
      else { return nil }
      
      diffCache[key] = diff
      return diff
    }
  }
  
  /// Applies the given patch hunk to the specified file in the index.
  /// - parameter path: Target file path
  /// - parameter hunk: Hunk to be applied
  /// - parameter stage: True if the change is being staged, falses if unstaged
  /// (the patch should be reversed)
  /// - throws: `Error.patchMismatch` if the patch can't be applied, or any
  /// errors from resultings stage/unstage actions.
  func patchIndexFile(path: String, hunk: DiffHunk, stage: Bool) throws
  {
    guard let index = GitIndex(repository: self)
    else { throw Error.unexpected }
    
    if let entry = index.entry(at: path) {
      if (hunk.newStart == 1) || (hunk.oldStart == 1) {
        let status = try self.status(file: path)
        
        if stage {
          if status.0 == .deleted {
            try self.stage(file: path)
            return
          }
        }
        else {
          switch status.1 {
            case .added, .deleted:
              // If it's added/deleted in the index, and we're unstaging, then
              // the hunk must cover the whole file
              try unstage(file: path)
              return
            default:
              break
          }
        }
      }
      
      guard let blob = GitBlob(gitRepository: gitRepo,
                               oid: entry.oid)
      else { throw Error.unexpected }
      
      try blob.withData {
        (data) in
        guard let text = String(data: data, encoding: .utf8),
              let patchedText = hunk.applied(to: text, reversed: !stage)
        else { throw Error.patchMismatch }
        
        guard let patchedData = patchedText.data(using: .utf8)
        else { throw Error.unexpected }
        
        try index.add(data: patchedData, path: path)
      }
      try index.save()
      return
    }
    else {
      let status = try self.status(file: path)
      
      // Assuming the hunk covers the whole file
      if stage && status.0 == .untracked && hunk.newStart == 1 {
        try self.stage(file: path)
        return
      }
      else if !stage && (status.1 == .deleted) && (hunk.oldStart == 1) {
        try unstage(file: path)
        return
      }
    }
    throw Error.patchMismatch
  }
}
