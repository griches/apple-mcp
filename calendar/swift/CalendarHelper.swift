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

let iso8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

let displayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEEE, d MMMM yyyy 'at' h:mm:ss a"
    f.locale = Locale(identifier: "en_GB")
    return f
}()

func parseISO(_ string: String) -> Date? {
    // Try standard ISO 8601 first
    if let d = iso8601Formatter.date(from: string) { return d }
    // Try without timezone (local time)
    let local = DateFormatter()
    local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    local.locale = Locale(identifier: "en_US_POSIX")
    return local.date(from: string)
}

// MARK: - EventKit Access

func requestAccess(store: EKEventStore) -> Bool {
    var granted = false
    let semaphore = DispatchSemaphore(value: 0)

    if #available(macOS 14.0, *) {
        store.requestFullAccessToEvents { g, _ in
            granted = g
            semaphore.signal()
        }
    } else {
        store.requestAccess(to: .event) { g, _ in
            granted = g
            semaphore.signal()
        }
    }
    semaphore.wait()
    return granted
}

// MARK: - Event JSON

func eventToJSON(_ event: EKEvent, includeDetails: Bool = false) -> String {
    var fields = [String]()
    fields.append("\"summary\":\(jsonString(event.title ?? ""))")
    fields.append("\"startDate\":\(jsonString(displayFormatter.string(from: event.startDate)))")
    fields.append("\"endDate\":\(jsonString(displayFormatter.string(from: event.endDate)))")
    fields.append("\"location\":\(jsonStringOrNull(event.location))")
    fields.append("\"calendar\":\(jsonString(event.calendar?.title ?? ""))")
    fields.append("\"uid\":\(jsonString(event.eventIdentifier ?? ""))")

    if includeDetails {
        fields.append("\"description\":\(jsonStringOrNull(event.notes))")
        fields.append("\"url\":\(jsonStringOrNull(event.url?.absoluteString))")
        fields.append("\"allDay\":\(event.isAllDay)")
        let alarmStrs: [String] = (event.alarms ?? []).compactMap { alarm in
            guard alarm.absoluteDate == nil else { return nil } // skip absolute-date alarms
            let offsetMinutes = Int(-alarm.relativeOffset / 60)
            return "{\"offsetMinutes\":\(offsetMinutes)}"
        }
        fields.append("\"alerts\":[\(alarmStrs.joined(separator: ","))]")
    }

    return "{\(fields.joined(separator: ","))}"
}

/// Deduplicate events by (title, startDate, endDate) tuple
func deduplicate(_ events: [EKEvent]) -> [EKEvent] {
    var seen = Set<String>()
    var result = [EKEvent]()
    for e in events {
        let key = "\(e.title ?? "")|\(e.startDate.timeIntervalSince1970)|\(e.endDate.timeIntervalSince1970)"
        if seen.insert(key).inserted {
            result.append(e)
        }
    }
    return result
}

/// Normalize smart quotes/apostrophes to ASCII for comparison
func normalizeQuotes(_ s: String) -> String {
    return s
        .replacingOccurrences(of: "\u{2018}", with: "'")  // left single
        .replacingOccurrences(of: "\u{2019}", with: "'")  // right single
        .replacingOccurrences(of: "\u{201C}", with: "\"") // left double
        .replacingOccurrences(of: "\u{201D}", with: "\"") // right double
}

// MARK: - Commands

func listCalendars(store: EKEventStore) {
    let calendars = store.calendars(for: .event)
    let items = calendars.map { cal -> String in
        let desc = cal.source?.title ?? ""
        return "{\"name\":\(jsonString(cal.title)),\"description\":\(jsonString(desc))}"
    }
    print("[\(items.joined(separator: ","))]")
}

func listEvents(store: EKEventStore, from: Date, to: Date, calendarName: String?) {
    var calendars: [EKCalendar]? = nil
    if let name = calendarName {
        let matched = store.calendars(for: .event).filter { $0.title == name }
        if matched.isEmpty {
            exitWithError("Calendar not found: \(name)")
        }
        calendars = matched
    }

    let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
    let events = deduplicate(store.events(matching: predicate))

    let items = events.map { eventToJSON($0) }
    print("[\(items.joined(separator: ","))]")
}

func searchEvents(store: EKEventStore, query: String, calendarName: String?) {
    var calendars: [EKCalendar]? = nil
    if let name = calendarName {
        let matched = store.calendars(for: .event).filter { $0.title == name }
        if matched.isEmpty {
            exitWithError("Calendar not found: \(name)")
        }
        calendars = matched
    }

    // Search within a wide range: 1 year back to 2 years forward
    let from = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
    let to = Calendar.current.date(byAdding: .year, value: 2, to: Date())!
    let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
    let allEvents = store.events(matching: predicate)

    let queryNorm = normalizeQuotes(query.lowercased())
    let matched = deduplicate(allEvents.filter {
        normalizeQuotes(($0.title ?? "").lowercased()).contains(queryNorm)
    })

    let items = matched.map { eventToJSON($0) }
    print("[\(items.joined(separator: ","))]")
}

func getEvent(store: EKEventStore, title: String, calendarName: String?) {
    var calendars: [EKCalendar]? = nil
    if let name = calendarName {
        let matched = store.calendars(for: .event).filter { $0.title == name }
        if matched.isEmpty {
            exitWithError("Calendar not found: \(name)")
        }
        calendars = matched
    }

    // Search within a wide range
    let from = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
    let to = Calendar.current.date(byAdding: .year, value: 2, to: Date())!
    let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
    let allEvents = store.events(matching: predicate)

    let titleNorm = normalizeQuotes(title.lowercased())
    guard let event = allEvents.first(where: { normalizeQuotes(($0.title ?? "").lowercased()) == titleNorm }) else {
        exitWithError("Event not found: \(title)")
    }

    print(eventToJSON(event, includeDetails: true))
}

// MARK: - TCC responsibility (upstream issues #6 / #10)
//
// When an MCP host (Claude Desktop, Claude Code, ...) spawns this helper, macOS
// treats the *host app* as the "responsible process" for privacy checks. Hosts
// don't declare NSCalendarsFullAccessUsageDescription, so EventKit denies access
// immediately, no prompt is shown, and nothing appears in System Settings.
//
// Fix: re-launch ourselves with the responsibility disclaimed, so this helper is
// its own responsible process. Its embedded Info.plist (linked into __TEXT,
// __info_plist at build time) carries the usage strings, so macOS shows a normal
// "Apple MCP Calendar Helper would like to access your calendars" prompt and
// lists the helper under Privacy & Security > Calendars.

@_silgen_name("responsibility_spawnattrs_setdisclaim")
private func responsibility_spawnattrs_setdisclaim(
    _ attrs: UnsafeMutablePointer<posix_spawnattr_t?>, _ disclaim: Int32) -> Int32

private let disclaimedEnvKey = "APPLE_MCP_CALENDAR_HELPER_DISCLAIMED"

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
    Usage: calendar-helper <command> [options]
    Commands:
      list-calendars
      list-events --from <ISO> --to <ISO> [--calendar <name>]
      search-events --query <text> [--calendar <name>]
      get-event --title <text> [--calendar <name>]
    """, stderr)
    exit(1)
}

func main() {
    let args = CommandLine.arguments
    guard args.count >= 2 else { printUsage() }
    becomeResponsibleProcess()

    let store = EKEventStore()
    let status = EKEventStore.authorizationStatus(for: .event)

    if status != .authorized {
        if #available(macOS 14.0, *) {
            if status != .fullAccess {
                guard requestAccess(store: store) else {
                    exitWithError("Calendar access denied. Open System Settings > Privacy & Security > Calendars and set Apple MCP Calendar Helper to Full Access.")
                }
            }
        } else {
            guard requestAccess(store: store) else {
                exitWithError("Calendar access denied. Please grant access in System Preferences > Security & Privacy > Calendars.")
            }
        }
    }

    let command = args[1]

    func getArg(_ flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    switch command {
    case "list-calendars":
        listCalendars(store: store)

    case "list-events":
        guard let fromStr = getArg("--from"), let toStr = getArg("--to") else {
            exitWithError("list-events requires --from and --to ISO dates")
        }
        guard let fromDate = parseISO(fromStr) else {
            exitWithError("Invalid --from date: \(fromStr)")
        }
        guard let toDate = parseISO(toStr) else {
            exitWithError("Invalid --to date: \(toStr)")
        }
        listEvents(store: store, from: fromDate, to: toDate, calendarName: getArg("--calendar"))

    case "search-events":
        guard let query = getArg("--query") else {
            exitWithError("search-events requires --query")
        }
        searchEvents(store: store, query: query, calendarName: getArg("--calendar"))

    case "get-event":
        guard let title = getArg("--title") else {
            exitWithError("get-event requires --title")
        }
        getEvent(store: store, title: title, calendarName: getArg("--calendar"))

    default:
        printUsage()
    }
}

main()
