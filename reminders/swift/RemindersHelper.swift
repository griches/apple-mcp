import EventKit
import Foundation

// MARK: - JSON Helpers

func jsonString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
    return "\"\(escaped)\""
}

func jsonStringOrNull(_ value: String?) -> String {
    guard let v = value, !v.isEmpty else { return "null" }
    return jsonString(v)
}

func exitWithError(_ message: String) -> Never {
    let escaped = message
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    print("{\"error\":\"\(escaped)\"}")
    exit(1)
}

// MARK: - Date Formatting

let displayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEEE, d MMMM yyyy 'at' h:mm:ss a"
    f.locale = Locale(identifier: "en_GB")
    return f
}()

func dueDateString(from components: DateComponents?) -> String? {
    guard let components = components,
          let date = Calendar.current.date(from: components) else { return nil }
    return displayFormatter.string(from: date)
}

// MARK: - EventKit Access

func requestAccess(store: EKEventStore) -> Bool {
    var granted = false
    let semaphore = DispatchSemaphore(value: 0)

    if #available(macOS 14.0, *) {
        store.requestFullAccessToReminders { g, _ in
            granted = g
            semaphore.signal()
        }
    } else {
        store.requestAccess(to: .reminder) { g, _ in
            granted = g
            semaphore.signal()
        }
    }
    semaphore.wait()
    return granted
}

// MARK: - Fetch Helper

func fetchAllReminders(store: EKEventStore, in calendars: [EKCalendar]?) -> [EKReminder] {
    var result: [EKReminder] = []
    let semaphore = DispatchSemaphore(value: 0)
    let predicate = store.predicateForReminders(in: calendars)
    store.fetchReminders(matching: predicate) { reminders in
        result = reminders ?? []
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

// MARK: - Reminder JSON

func reminderToJSON(_ reminder: EKReminder, includeBody: Bool = false) -> String {
    var fields = [String]()
    fields.append("\"name\":\(jsonString(reminder.title ?? ""))")
    fields.append("\"id\":\(jsonString(reminder.calendarItemIdentifier))")
    fields.append("\"completed\":\(reminder.isCompleted)")
    fields.append("\"dueDate\":\(jsonStringOrNull(dueDateString(from: reminder.dueDateComponents)))")
    fields.append("\"priority\":\(reminder.priority)")
    fields.append("\"list\":\(jsonString(reminder.calendar?.title ?? ""))")
    if includeBody {
        fields.append("\"body\":\(jsonStringOrNull(reminder.notes))")
    }
    return "{\(fields.joined(separator: ","))}"
}

func sortReminders(_ reminders: [EKReminder]) -> [EKReminder] {
    return reminders.sorted {
        let d1 = $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let d2 = $1.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        switch (d1, d2) {
        case (nil, nil): return ($0.title ?? "") < ($1.title ?? "")
        case (nil, _):   return false
        case (_, nil):   return true
        case let (a?, b?): return a < b
        }
    }
}

// MARK: - Commands

func listLists(store: EKEventStore) {
    let lists = store.calendars(for: .reminder)
    let items = lists.map { l -> String in
        "{\"name\":\(jsonString(l.title)),\"id\":\(jsonString(l.calendarIdentifier))}"
    }
    print("[\(items.joined(separator: ","))]")
}

func listReminders(store: EKEventStore, listName: String, includeCompleted: Bool) {
    let allLists = store.calendars(for: .reminder)
    guard let targetList = allLists.first(where: { $0.title == listName }) else {
        exitWithError("List not found: \(listName)")
    }
    var reminders = fetchAllReminders(store: store, in: [targetList])
    if !includeCompleted {
        reminders = reminders.filter { !$0.isCompleted }
    }
    reminders = reminders.filter { $0.dueDateComponents != nil }
    reminders = sortReminders(reminders)
    let items = reminders.map { reminderToJSON($0) }
    print("[\(items.joined(separator: ","))]")
}

// MARK: - Reminder Lookup

/// Finds a single reminder by ID (fast, O(1)) or by name (searches all reminders in the given list).
/// --id takes precedence; --list is only used for name-based lookup.
@discardableResult
func findReminder(store: EKEventStore, name: String?, id: String?, listName: String?) -> EKReminder {
    if let id = id {
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
            exitWithError("Reminder not found with id: \(id)")
        }
        return item
    }
    guard let name = name else {
        exitWithError("Either --name or --id must be provided")
    }
    var calendars: [EKCalendar]? = nil
    if let listName = listName {
        let matched = store.calendars(for: .reminder).filter { $0.title == listName }
        if matched.isEmpty { exitWithError("List not found: \(listName)") }
        calendars = matched
    }
    let reminders = fetchAllReminders(store: store, in: calendars)
    let nameLower = name.lowercased()
    guard let reminder = reminders.first(where: { ($0.title ?? "").lowercased() == nameLower }) else {
        exitWithError("Reminder not found: \(name)")
    }
    return reminder
}

func getReminder(store: EKEventStore, name: String?, id: String?, listName: String?) {
    let reminder = findReminder(store: store, name: name, id: id, listName: listName)
    print(reminderToJSON(reminder, includeBody: true))
}

func searchReminders(store: EKEventStore, query: String, listName: String?) {
    var calendars: [EKCalendar]? = nil
    if let listName = listName {
        let matched = store.calendars(for: .reminder).filter { $0.title == listName }
        if matched.isEmpty { exitWithError("List not found: \(listName)") }
        calendars = matched
    }
    let allReminders = fetchAllReminders(store: store, in: calendars)
    let queryLower = query.lowercased()
    let matched = allReminders.filter { ($0.title ?? "").lowercased().contains(queryLower) }
    let items = matched.map { r -> String in
        "{\"name\":\(jsonString(r.title ?? "")),\"id\":\(jsonString(r.calendarItemIdentifier)),\"list\":\(jsonString(r.calendar?.title ?? "")),\"completed\":\(r.isCompleted)}"
    }
    print("[\(items.joined(separator: ","))]")
}

func setReminderCompleted(store: EKEventStore, name: String?, id: String?, listName: String?, completed: Bool) {
    let reminder = findReminder(store: store, name: name, id: id, listName: listName)
    let label = reminder.title ?? id ?? name ?? "reminder"
    reminder.isCompleted = completed
    do {
        try store.save(reminder, commit: true)
    } catch {
        exitWithError("Failed to save reminder: \(error.localizedDescription)")
    }
    let action = completed ? "completed" : "uncompleted"
    print("\"Reminder \(action): \(label)\"")
}

// MARK: - ISO Date Parsing

func parseISOToDateComponents(_ string: String) -> DateComponents? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let date = formatter.date(from: string) {
        return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }
    formatter.dateFormat = "yyyy-MM-dd"
    if let date = formatter.date(from: string) {
        return Calendar.current.dateComponents([.year, .month, .day], from: date)
    }
    return nil
}

// MARK: - Source Selection

func reminderSource(store: EKEventStore) -> EKSource? {
    if let source = store.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
        return source
    }
    if let source = store.defaultCalendarForNewReminders()?.source {
        return source
    }
    return store.sources.first(where: { $0.sourceType == .local })
}

// MARK: - Write Commands

func createList(store: EKEventStore, name: String) {
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    calendar.title = name
    guard let source = reminderSource(store: store) else {
        exitWithError("No suitable source found for new reminder list")
    }
    calendar.source = source
    do {
        try store.saveCalendar(calendar, commit: true)
    } catch {
        exitWithError("Failed to create list: \(error.localizedDescription)")
    }
    print("\"List created: \(name)\"")
}

func deleteList(store: EKEventStore, name: String) {
    let allLists = store.calendars(for: .reminder)
    guard let targetList = allLists.first(where: { $0.title == name }) else {
        exitWithError("List not found: \(name)")
    }
    do {
        try store.removeCalendar(targetList, commit: true)
    } catch {
        exitWithError("Failed to delete list: \(error.localizedDescription)")
    }
    print("\"List deleted: \(name)\"")
}

/// Syncs the due-date alarm to match new DateComponents.
/// - Removes all existing absolute-date alarms (the ones Reminders creates to fire at the due date).
/// - Adds a new absolute alarm at the new due date so the Reminders app shows and triggers correctly.
/// - Relative alarms (e.g. "15 min before") are left untouched.
func syncDueDateAlarm(_ reminder: EKReminder, to components: DateComponents?) {
    // Remove existing absolute-date alarms
    if let existing = reminder.alarms {
        for alarm in existing where alarm.absoluteDate != nil {
            reminder.removeAlarm(alarm)
        }
    }
    // Add a new absolute alarm at the due date (matches Reminders.app behaviour)
    if let components = components, let date = Calendar.current.date(from: components) {
        reminder.addAlarm(EKAlarm(absoluteDate: date))
    }
}

func createReminder(store: EKEventStore, name: String, listName: String, body: String?, dueDateISO: String?, priority: Int?) {
    let allLists = store.calendars(for: .reminder)
    guard let targetList = allLists.first(where: { $0.title == listName }) else {
        exitWithError("List not found: \(listName)")
    }
    let reminder = EKReminder(eventStore: store)
    reminder.title = name
    reminder.calendar = targetList
    if let body = body { reminder.notes = body }
    if let priority = priority { reminder.priority = priority }
    if let dueDateISO = dueDateISO {
        guard let components = parseISOToDateComponents(dueDateISO) else {
            exitWithError("Invalid due date: \(dueDateISO)")
        }
        reminder.dueDateComponents = components
        syncDueDateAlarm(reminder, to: components)
    }
    do {
        try store.save(reminder, commit: true)
    } catch {
        exitWithError("Failed to create reminder: \(error.localizedDescription)")
    }
    print("\"Reminder created: \(name)\"")
}

func deleteReminder(store: EKEventStore, name: String?, id: String?, listName: String?) {
    let reminder = findReminder(store: store, name: name, id: id, listName: listName)
    let label = reminder.title ?? id ?? name ?? "reminder"
    do {
        try store.remove(reminder, commit: true)
    } catch {
        exitWithError("Failed to delete reminder: \(error.localizedDescription)")
    }
    print("\"Reminder deleted: \(label)\"")
}

func updateReminder(store: EKEventStore, name: String?, id: String?, listName: String?, newName: String?, body: String?, dueDateISO: String?, priority: Int?) {
    let reminder = findReminder(store: store, name: name, id: id, listName: listName)
    let label = reminder.title ?? id ?? name ?? "reminder"
    if let newName = newName { reminder.title = newName }
    if let body = body { reminder.notes = body }
    if let priority = priority { reminder.priority = priority }
    if let dueDateISO = dueDateISO {
        if dueDateISO == "none" {
            reminder.dueDateComponents = nil
            syncDueDateAlarm(reminder, to: nil)
        } else {
            guard let components = parseISOToDateComponents(dueDateISO) else {
                exitWithError("Invalid due date: \(dueDateISO)")
            }
            reminder.dueDateComponents = components
            syncDueDateAlarm(reminder, to: components)
        }
    }
    do {
        try store.save(reminder, commit: true)
    } catch {
        exitWithError("Failed to update reminder: \(error.localizedDescription)")
    }
    print("\"Reminder updated: \(newName ?? label)\"")
}

// MARK: - TCC responsibility (upstream issues #6 / #10)
//
// When an MCP host (Claude Desktop, Claude Code, ...) spawns this helper, macOS
// treats the *host app* as the "responsible process" for privacy checks. Hosts
// don't declare NSRemindersFullAccessUsageDescription, so EventKit denies access
// immediately, no prompt is shown, and nothing appears in System Settings.
//
// Fix: re-launch ourselves with the responsibility disclaimed, so this helper is
// its own responsible process. Its embedded Info.plist (linked into __TEXT,
// __info_plist at build time) carries the usage strings, so macOS shows a normal
// "Apple MCP Calendar Helper would like to access your calendars" prompt and
// lists the helper under Privacy & Security > Reminders.

@_silgen_name("responsibility_spawnattrs_setdisclaim")
private func responsibility_spawnattrs_setdisclaim(
    _ attrs: UnsafeMutablePointer<posix_spawnattr_t?>, _ disclaim: Int32) -> Int32

private let disclaimedEnvKey = "APPLE_MCP_REMINDERS_HELPER_DISCLAIMED"

/// Re-exec with responsibility disclaimed; returns only in the child.
func becomeResponsibleProcess() {
    let env = ProcessInfo.processInfo.environment
    if env[disclaimedEnvKey] != nil { return }

    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    _ = responsibility_spawnattrs_setdisclaim(&attr, 1)

    var childEnv = env
    childEnv[disclaimedEnvKey] = "1"
    let envp: [UnsafeMutablePointer<CChar>?] = childEnv.map { strdup("\($0.key)=\($0.value)") } + [nil]
    let argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) } + [nil]
    let path = Bundle.main.executablePath ?? CommandLine.arguments[0]

    var pid: pid_t = 0
    // stdin/stdout/stderr are inherited, so the caller still gets our output.
    guard posix_spawn(&pid, path, nil, &attr, argv, envp) == 0 else { return } // fall back to in-process
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    exit((status & 0x7f) == 0 ? (status >> 8) & 0xff : 1)
}

// MARK: - Main

func printUsage() -> Never {
    fputs("""
    Usage: reminders-helper <command> [options]
    Commands:
      list-lists
      list-reminders --list <name> [--include-completed]
      get-reminder (--name <name> | --id <id>) [--list <name>]
      search-reminders --query <text> [--list <name>]
      complete-reminder (--name <name> | --id <id>) [--list <name>]
      uncomplete-reminder (--name <name> | --id <id>) [--list <name>]
      create-list --name <name>
      delete-list --name <name>
      create-reminder --name <name> --list <name> [--body <text>] [--due-date <ISO>] [--priority <0-9>]
      delete-reminder (--name <name> | --id <id>) [--list <name>]
      update-reminder (--name <name> | --id <id>) [--list <name>] [--new-name <name>] [--body <text>] [--due-date <ISO|none>] [--priority <0-9>]
    """, stderr)
    exit(1)
}

func main() {
    let args = CommandLine.arguments
    guard args.count >= 2 else { printUsage() }
    becomeResponsibleProcess()

    let store = EKEventStore()

    if #available(macOS 14.0, *) {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status != .fullAccess {
            guard requestAccess(store: store) else {
                exitWithError("Reminders access denied. Open System Settings > Privacy & Security > Reminders and set Apple MCP Reminders Helper to Full Access.")
            }
        }
    } else {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status != .authorized {
            guard requestAccess(store: store) else {
                exitWithError("Reminders access denied. Please grant access in System Preferences > Security & Privacy > Reminders.")
            }
        }
    }

    let command = args[1]

    func getArg(_ flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    func hasFlag(_ flag: String) -> Bool {
        return args.contains(flag)
    }

    switch command {
    case "list-lists":
        listLists(store: store)

    case "list-reminders":
        guard let listName = getArg("--list") else {
            exitWithError("list-reminders requires --list")
        }
        listReminders(store: store, listName: listName, includeCompleted: hasFlag("--include-completed"))

    case "get-reminder":
        guard getArg("--name") != nil || getArg("--id") != nil else {
            exitWithError("get-reminder requires --name or --id")
        }
        getReminder(store: store, name: getArg("--name"), id: getArg("--id"), listName: getArg("--list"))

    case "search-reminders":
        guard let query = getArg("--query") else {
            exitWithError("search-reminders requires --query")
        }
        searchReminders(store: store, query: query, listName: getArg("--list"))

    case "complete-reminder":
        guard getArg("--name") != nil || getArg("--id") != nil else {
            exitWithError("complete-reminder requires --name or --id")
        }
        setReminderCompleted(store: store, name: getArg("--name"), id: getArg("--id"), listName: getArg("--list"), completed: true)

    case "uncomplete-reminder":
        guard getArg("--name") != nil || getArg("--id") != nil else {
            exitWithError("uncomplete-reminder requires --name or --id")
        }
        setReminderCompleted(store: store, name: getArg("--name"), id: getArg("--id"), listName: getArg("--list"), completed: false)

    case "create-list":
        guard let name = getArg("--name") else {
            exitWithError("create-list requires --name")
        }
        createList(store: store, name: name)

    case "delete-list":
        guard let name = getArg("--name") else {
            exitWithError("delete-list requires --name")
        }
        deleteList(store: store, name: name)

    case "create-reminder":
        guard let name = getArg("--name"), let listName = getArg("--list") else {
            exitWithError("create-reminder requires --name and --list")
        }
        createReminder(store: store, name: name, listName: listName,
                       body: getArg("--body"),
                       dueDateISO: getArg("--due-date"),
                       priority: getArg("--priority").flatMap { Int($0) })

    case "delete-reminder":
        guard getArg("--name") != nil || getArg("--id") != nil else {
            exitWithError("delete-reminder requires --name or --id")
        }
        deleteReminder(store: store, name: getArg("--name"), id: getArg("--id"), listName: getArg("--list"))

    case "update-reminder":
        guard getArg("--name") != nil || getArg("--id") != nil else {
            exitWithError("update-reminder requires --name or --id")
        }
        updateReminder(store: store, name: getArg("--name"), id: getArg("--id"), listName: getArg("--list"),
                       newName: getArg("--new-name"),
                       body: getArg("--body"),
                       dueDateISO: getArg("--due-date"),
                       priority: getArg("--priority").flatMap { Int($0) })

    default:
        printUsage()
    }
}

main()
