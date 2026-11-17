import EventKit
import Foundation
import Observation

/// 菜单栏日程面板的数据：日程 / 待办两栏 + 两边的访问权限。
@MainActor
@Observable
final class AgendaModel {
    enum Access: Equatable {
        case pending
        case granted
        case denied
    }

    /// 一栏要显示什么：读取中 / 有内容 / 已授权但为空 / 没有权限
    enum Column: Equatable {
        case loading
        case items([AgendaEntry])
        case empty
        case denied
    }

    private let store: EKEventStore
    private let now: () -> Date

    var events: [AgendaEntry] = []
    var todos: [AgendaEntry] = []
    var eventAccess: Access = .pending
    var reminderAccess: Access = .pending
    var hasLoaded = false
    var isRefreshing = false

    init(store: EKEventStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    // MARK: - 两栏

    var eventsColumn: Column {
        column(access: eventAccess, items: events)
    }

    var todosColumn: Column {
        column(access: reminderAccess, items: todos)
    }

    /// 空栏不显示；没有权限的栏留着，用来放授权入口
    var showsEvents: Bool { eventsColumn != .empty }
    var showsTodos: Bool { todosColumn != .empty }

    var eventCount: Int { eventAccess == .granted ? events.count : 0 }
    var todoCount: Int { reminderAccess == .granted ? todos.count : 0 }

    /// 两边都没权限时只显示一张合并的授权卡片
    var needsUnifiedPermission: Bool {
        hasLoaded && eventAccess == .denied && reminderAccess == .denied
    }

    /// 两边都授权了，但确实一条都没有
    var isEmpty: Bool {
        hasLoaded && eventsColumn == .empty && todosColumn == .empty
    }

    /// 面板显示几栏（决定面板宽度）
    var columnCount: Int {
        guard hasLoaded, !needsUnifiedPermission, !isEmpty else { return 1 }
        return showsEvents && showsTodos ? 2 : 1
    }

    private func column(access: Access, items: [AgendaEntry]) -> Column {
        guard hasLoaded else { return .loading }
        switch access {
        case .pending: return .loading
        case .denied: return .denied
        case .granted: return items.isEmpty ? .empty : .items(items)
        }
    }

    // MARK: - 读取

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        eventAccess = await access(for: .event)
        reminderAccess = await access(for: .reminder)

        let service = AgendaService(store: store, now: now(), calendar: .current)
        events = eventAccess == .granted ? service.events() : []
        todos = reminderAccess == .granted ? await service.reminders() : []
        hasLoaded = true
    }

    // MARK: - 权限

    private func access(for type: EKEntityType) async -> Access {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess:
            return .granted
        case .notDetermined:
            // 用户第一次点开面板时由系统弹一次授权；明确拒绝过之后系统不会再弹
            return await requestAccess(for: type) ? .granted : .denied
        default:
            return .denied
        }
    }

    private func requestAccess(for type: EKEntityType) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // 系统可能在后台队列回调；显式 @Sendable，避免闭包继承 MainActor 隔离
            let completion: @Sendable (Bool, (any Error)?) -> Void = { granted, _ in
                continuation.resume(returning: granted)
            }
            switch type {
            case .event:
                store.requestFullAccessToEvents(completion: completion)
            case .reminder:
                store.requestFullAccessToReminders(completion: completion)
            @unknown default:
                continuation.resume(returning: false)
            }
        }
    }
}
