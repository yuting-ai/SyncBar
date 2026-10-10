import Foundation

enum SyncMode: String, CaseIterable, Identifiable {
    /// Copy new and changed files to the target, never delete there.
    case update
    /// Make the target identical to the source, deleting extra files.
    case mirror
    /// Two-way or hand-tuned directions set up in FreeFileSync; left untouched.
    case custom

    var id: Self { self }
}

/// When launchd starts a job. Weekdays use launchd numbering: 1 = Monday … 7 = Sunday.
struct Schedule: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case manual, daily, weekly
        var id: Self { self }
    }

    var kind: Kind = .daily
    var hour = 21
    var minute = 0
    var weekdays: Set<Int> = [7]

    init() {}

    /// Parses a `StartCalendarInterval` value (missing, one dict, or an array of dicts).
    init(plistValue: Any?) {
        let entries: [[String: Int]] = switch plistValue {
        case let dict as [String: Int]: [dict]
        case let array as [[String: Int]]: array
        default: []
        }
        guard let first = entries.first else {
            kind = .manual
            return
        }
        hour = first["Hour"] ?? 0
        minute = first["Minute"] ?? 0
        let days = entries.compactMap { $0["Weekday"] }.map { $0 == 0 ? 7 : $0 }
        if days.isEmpty {
            kind = .daily
        } else {
            kind = .weekly
            weekdays = Set(days)
        }
    }

    /// The `StartCalendarInterval` value, or nil for manual-only jobs.
    var plistValue: Any? {
        switch kind {
        case .manual: nil
        case .daily: ["Hour": hour, "Minute": minute]
        case .weekly: weekdays.sorted().map { ["Weekday": $0, "Hour": hour, "Minute": minute] }
        }
    }

    func nextRun(after date: Date) -> Date? {
        let cal = Calendar.current
        switch kind {
        case .manual:
            return nil
        case .daily:
            return cal.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute),
                                matchingPolicy: .nextTime)
        case .weekly:
            // Calendar weekdays start at Sunday = 1.
            return weekdays.compactMap { day in
                cal.nextDate(after: date,
                             matching: DateComponents(hour: hour, minute: minute, weekday: day % 7 + 1),
                             matchingPolicy: .nextTime)
            }.min()
        }
    }
}

/// The editable fields of a task, as shown in the editor.
struct TaskDraft: Equatable {
    /// nil for a task that does not exist yet.
    var label: String?
    var originalBatchURL: URL?
    var name = ""
    var source = ""
    /// The folder the user picked; see `effectiveTarget` for where files actually go.
    var target = ""
    /// Sync into `target/<source folder name>` instead of straight into `target`.
    var createSubfolder = true
    var mode: SyncMode = .update
    var excludeHidden = true
    var includeGit = false
    var schedule = Schedule()

    var isNew: Bool { label == nil }

    var sourceFolderName: String { URL(filePath: source).lastPathComponent }

    /// The folder FreeFileSync writes into.
    var effectiveTarget: String {
        guard createSubfolder, !source.isEmpty, !target.isEmpty else { return target }
        return URL(filePath: target).appending(path: sourceFolderName).folderPath
    }

    static let forbiddenNameCharacters = CharacterSet(charactersIn: "/:\\")

    var batchURL: URL {
        Paths.jobs.appending(path: name.trimmingCharacters(in: .whitespaces) + ".ffs_batch")
    }

    /// A message describing what still needs fixing, or nil when the draft can be saved.
    func validationError(existingBatchURLs: [URL]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return String(localized: "请填写任务名称") }
        if trimmed.rangeOfCharacter(from: Self.forbiddenNameCharacters) != nil { return String(localized: "任务名称不能包含 / : \\") }
        if source.isEmpty { return String(localized: "请选择源文件夹") }
        if target.isEmpty { return String(localized: "请选择目标文件夹") }
        let s = URL(filePath: source).standardizedFileURL.path(percentEncoded: false)
        let t = URL(filePath: effectiveTarget).standardizedFileURL.path(percentEncoded: false)
        if s == t { return String(localized: "源文件夹和目标文件夹不能相同") }
        if t.hasPrefix(s.hasSuffix("/") ? s : s + "/") { return String(localized: "目标文件夹不能放在源文件夹里面") }
        if s.hasPrefix(t.hasSuffix("/") ? t : t + "/") { return String(localized: "源文件夹不能放在目标文件夹里面") }
        if schedule.kind == .weekly && schedule.weekdays.isEmpty { return String(localized: "请至少选择一天") }
        let clash = existingBatchURLs.contains {
            $0.path.precomposedStringWithCanonicalMapping == batchURL.path.precomposedStringWithCanonicalMapping
                && $0 != originalBatchURL
        }
        if clash { return String(localized: "已经有同名的任务了") }
        return nil
    }
}

/// A FreeFileSync `.ffs_batch` file, edited in place so settings SyncBar doesn't know about survive.
struct BatchFile {
    let doc: XMLDocument

    static let hiddenPattern = "*/.*"
    static let gitPattern = "*/.git/"
    /// git's fsmonitor socket can't be copied and would fail every run.
    static let gitSocketPattern = "*/.git/fsmonitor--daemon.ipc"
    static let junkPatterns = ["*/.DS_Store", "*/._*"]

    init(url: URL) throws {
        doc = try XMLDocument(contentsOf: url)
    }

    /// A fresh batch job using the settings verified to work with FreeFileSync 14.
    init() {
        doc = try! XMLDocument(xmlString: Self.template)
    }

    // MARK: Reading

    var source: String { string("//FolderPairs/Pair[1]/Left") }
    var target: String { string("//FolderPairs/Pair[1]/Right") }

    var mode: SyncMode {
        guard let diff = element("/FreeFileSync/Synchronize/Differences") else { return .custom }
        let values = ["LeftOnly", "LeftNewer", "RightNewer", "RightOnly"].map { diff.attribute(forName: $0)?.stringValue }
        switch values {
        case ["right", "right", "none", "none"]: return .update
        case ["right", "right", "right", "right"]: return .mirror
        default: return .custom
        }
    }

    var excludeHidden: Bool {
        items("/FreeFileSync/Filter/Exclude/Item").contains(Self.hiddenPattern)
            || items("//FolderPairs/Pair/Filter/Exclude/Item").contains(Self.hiddenPattern)
    }

    var includeGit: Bool {
        items("//FolderPairs/Pair/Filter/Include/Item").contains(Self.gitPattern)
    }

    // MARK: Writing

    mutating func apply(_ draft: TaskDraft, isNew: Bool) {
        let filtersChanged = isNew || draft.excludeHidden != excludeHidden
            || (draft.excludeHidden && draft.includeGit != includeGit)
        let targetChanged = isNew || draft.effectiveTarget != target

        if filtersChanged {
            rebuildPairsAndFilter(draft)
        } else {
            for node in nodes("//FolderPairs/Pair/Left") { node.stringValue = draft.source }
            for node in nodes("//FolderPairs/Pair/Right") { node.stringValue = draft.effectiveTarget }
        }

        if draft.mode != .custom && draft.mode != mode { setMode(draft.mode) }

        // Cloud folders refuse moving files to the Trash, so overwrite there instead.
        if targetChanged, let policy = element("/FreeFileSync/Synchronize/DeletionPolicy") {
            policy.stringValue = draft.effectiveTarget.contains("/Library/CloudStorage/") ? "Permanent" : "RecycleBin"
        }
    }

    func write(to url: URL) throws {
        try doc.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement]).write(to: url, options: .atomic)
    }

    private mutating func setMode(_ mode: SyncMode) {
        guard let sync = element("/FreeFileSync/Synchronize") else { return }
        // Replace two-way <Changes> (or old <Differences>) with one-way directions.
        for name in ["Changes", "Differences"] {
            for node in nodes("/FreeFileSync/Synchronize/\(name)") { node.detach() }
        }
        let rightNewer = mode == .mirror ? "right" : "none"
        let diff = try! XMLElement(xmlString:
            #"<Differences LeftOnly="right" LeftNewer="right" RightNewer="\#(rightNewer)" RightOnly="\#(rightNewer)"/>"#)
        sync.insertChild(diff, at: 0)
    }

    /// Hidden files are excluded either globally or, to keep `.git`, through a second
    /// folder pair (FreeFileSync filters can't express "hidden except .git" in one pair).
    private mutating func rebuildPairsAndFilter(_ draft: TaskDraft) {
        let splitGit = draft.excludeHidden && draft.includeGit
        let globalExcludes = draft.excludeHidden && !splitGit ? [Self.hiddenPattern] : Self.junkPatterns
        if let exclude = element("/FreeFileSync/Filter/Exclude") {
            exclude.setChildren(globalExcludes.map { XMLElement(name: "Item", stringValue: $0) })
        }

        guard let pairs = element("/FreeFileSync/FolderPairs") else { return }
        var children = [Self.pair(draft, include: nil, exclude: [])]
        if splitGit {
            children = [Self.pair(draft, include: "*", exclude: [Self.hiddenPattern]),
                        Self.pair(draft, include: Self.gitPattern, exclude: [Self.gitSocketPattern])]
        }
        pairs.setChildren(children)
    }

    private static func pair(_ draft: TaskDraft, include: String?, exclude: [String]) -> XMLElement {
        let pair = XMLElement(name: "Pair")
        pair.addChild(XMLElement(name: "Left", stringValue: draft.source))
        pair.addChild(XMLElement(name: "Right", stringValue: draft.effectiveTarget))
        if let include {
            let filter = XMLElement(name: "Filter")
            let inc = XMLElement(name: "Include")
            inc.addChild(XMLElement(name: "Item", stringValue: include))
            let exc = XMLElement(name: "Exclude")
            exclude.forEach { exc.addChild(XMLElement(name: "Item", stringValue: $0)) }
            filter.addChild(inc)
            filter.addChild(exc)
            filter.addChild(try! XMLElement(xmlString: #"<SizeMin Unit="None">0</SizeMin>"#))
            filter.addChild(try! XMLElement(xmlString: #"<SizeMax Unit="None">0</SizeMax>"#))
            filter.addChild(try! XMLElement(xmlString: #"<TimeSpan Type="None">0</TimeSpan>"#))
            pair.addChild(filter)
        }
        return pair
    }

    /// A job that only lists `source` (the filter matches nothing) and never shows a dialog.
    static func probe(source: String, target: String, logFolder: String) -> BatchFile {
        var batch = BatchFile()
        var draft = TaskDraft()
        draft.source = source
        draft.target = target
        draft.createSubfolder = false
        draft.excludeHidden = false
        batch.apply(draft, isNew: true)
        batch.element("/FreeFileSync/Filter/Include")?.setChildren([XMLElement(name: "Item", stringValue: "*/__syncbar_probe__")])
        batch.element("/FreeFileSync/LogFolder")?.stringValue = logFolder
        batch.element("/FreeFileSync/Errors")?.attribute(forName: "Retry")?.stringValue = "0"
        batch.element("/FreeFileSync/Batch/ErrorDialog")?.stringValue = "Cancel"
        return batch
    }

    // MARK: XPath helpers

    private func nodes(_ xpath: String) -> [XMLNode] { (try? doc.nodes(forXPath: xpath)) ?? [] }
    private func element(_ xpath: String) -> XMLElement? { nodes(xpath).first as? XMLElement }
    private func string(_ xpath: String) -> String { nodes(xpath).first?.stringValue ?? "" }
    private func items(_ xpath: String) -> [String] { nodes(xpath).compactMap(\.stringValue) }

    private static let template = """
    <?xml version="1.0" encoding="utf-8"?>
    <FreeFileSync XmlType="BATCH" XmlFormat="23">
        <Notes/>
        <Compare>
            <Variant>TimeAndSize</Variant>
            <Symlinks>Exclude</Symlinks>
            <IgnoreTimeShift/>
        </Compare>
        <Synchronize>
            <Differences LeftOnly="right" LeftNewer="right" RightNewer="none" RightOnly="none"/>
            <DeletionPolicy>RecycleBin</DeletionPolicy>
            <VersioningFolder Style="Replace"/>
        </Synchronize>
        <Filter>
            <Include>
                <Item>*</Item>
            </Include>
            <Exclude/>
            <SizeMin Unit="None">0</SizeMin>
            <SizeMax Unit="None">0</SizeMax>
            <TimeSpan Type="None">0</TimeSpan>
        </Filter>
        <FolderPairs/>
        <Errors Ignore="true" Retry="1" Delay="5"/>
        <PostSyncCommand Condition="Completion"/>
        <LogFolder/>
        <EmailNotification Condition="Always"/>
        <GridViewType>Action</GridViewType>
        <Batch>
            <ProgressDialog Minimized="true" AutoClose="true"/>
            <ErrorDialog>Show</ErrorDialog>
            <PostSyncAction>None</PostSyncAction>
        </Batch>
    </FreeFileSync>
    """
}

/// The launch agent that runs a batch job, skipping with a notification when its drive is unplugged.
enum LaunchAgent {
    /// Written into each launch agent, so the notification is in the language SyncBar had when saving.
    static var script: String {
        let message = String(localized: "移动硬盘未连接，本次同步已跳过")
            .replacing("\"", with: "").replacing("\\", with: "")
        return #"if [ -n "$1" ] && [ ! -d "$1" ]; then /usr/bin/osascript -e "display notification \"\#(message)\" with title \"FreeFileSync: $(basename "$2" .ffs_batch)\""; exit 0; fi; exec /usr/bin/open -g -b org.freefilesync.FreeFileSync "$2""#
    }

    static func newLabel() -> String {
        Paths.labelPrefix + "task-" + UUID().uuidString.prefix(8).lowercased()
    }

    static func url(for label: String) -> URL {
        Paths.launchAgents.appending(path: label + ".plist")
    }

    /// The mount point the job depends on: the target's volume, else the source's.
    static func requiredVolume(source: String, target: String) -> String {
        for path in [target, source] {
            let parts = path.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0] == "Volumes" { return "/Volumes/\(parts[1])" }
        }
        return ""
    }

    static func plist(label: String, batchURL: URL, draft: TaskDraft) -> [String: Any] {
        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/sh", "-c", script, "sh",
                                 requiredVolume(source: draft.source, target: draft.effectiveTarget),
                                 batchURL.path(percentEncoded: false)],
            "StandardErrorPath": Paths.jobs.appending(path: "launchd-error.log").path(percentEncoded: false),
        ]
        plist["StartCalendarInterval"] = draft.schedule.plistValue
        return plist
    }

    static func write(_ plist: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }
}
