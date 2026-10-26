import SwiftUI
import WidgetKit

@main
struct AnyTimerApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView().preferredColorScheme(.dark)
        }
    }
}

struct HomeView: View {
    @Environment(\.scenePhase) private var phase
    @State private var countdowns: [Countdown] = []
    @State private var appearance = AppAppearance()
    @State private var error: String?
    @State private var editing: Countdown?
    @State private var showingSettings = false
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if countdowns.isEmpty { emptyState } else { list }
            }
            .background(Color(hex: appearance.background).ignoresSafeArea())
            .navigationTitle("AnyTimer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("الإعدادات")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = Countdown() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("عدّاد جديد")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let countdown = countdowns.first(where: { $0.id == id }) {
                    CountdownDetailView(countdown: countdown, onEdit: { editing = countdown },
                                        onDelete: { delete(id) })
                }
            }
            .sheet(item: $editing) { countdown in
                CountdownEditor(initial: countdown, isNew: !countdowns.contains { $0.id == countdown.id }) { saved in
                    countdowns = saved
                    error = nil
                }
            }
            .sheet(isPresented: $showingSettings) {
                AppSettingsView(appearance: $appearance, countdowns: countdowns)
            }
            .onAppear(perform: reload)
            .task { await reconcileIntegrations() }
            .onOpenURL { url in
                guard url.scheme == "gtavitimer" else { return }
                if url.host == "settings" { showingSettings = true }
                if url.host == "countdown", let id = UUID(uuidString: url.lastPathComponent),
                   countdowns.contains(where: { $0.id == id }) { path = [id] }
            }
            .onChange(of: phase) { _, value in
                if value == .active {
                    reload(); WidgetCenter.shared.reloadAllTimelines()
                    Task { await reconcileIntegrations() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                reload(); WidgetCenter.shared.reloadAllTimelines()
                Task { await reconcileIntegrations() }
            }
        }
        .tint(Color(hex: appearance.accent))
    }

    private var list: some View {
        // Only the visible application refreshes each second.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                        .listRowBackground(Color.clear)
                }
                ForEach(countdowns) { countdown in
                    NavigationLink(value: countdown.id) {
                        CountdownCard(countdown: countdown, now: context.date, height: appearance.cardSize.height)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .contextMenu {
                        Button { editing = countdown } label: { Label("تعديل", systemImage: "pencil") }
                        Button { duplicate(countdown) } label: { Label("تكرار", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) { delete(countdown.id) } label: { Label("حذف", systemImage: "trash") }
                    }
                    .swipeActions {
                        Button(role: .destructive) { delete(countdown.id) } label: { Label("حذف", systemImage: "trash") }
                        Button { editing = countdown } label: { Label("تعديل", systemImage: "pencil") }.tint(.gray)
                    }
                }
                .onMove(perform: move)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass").font(.system(size: 54, weight: .light))
                .foregroundStyle(Color(hex: appearance.accent))
            Text("لا توجد عدّادات").font(.title2.bold())
            Button { editing = Countdown() } label: { Label("إضافة عدّاد", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func persist(_ list: [Countdown]) {
        do {
            try SettingsStore.available().save(list)
            countdowns = list; error = nil
            WidgetCenter.shared.reloadAllTimelines()
            Task { await reconcileIntegrations() }
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ id: UUID) {
        path.removeAll { $0 == id }
        persist(countdowns.filter { $0.id != id })
    }

    private func duplicate(_ countdown: Countdown) {
        var copy = countdown
        copy.id = UUID(); copy.name = String((countdown.name + " 2").prefix(80))
        var list = countdowns
        list.insert(copy, at: (list.firstIndex { $0.id == countdown.id } ?? list.count - 1) + 1)
        persist(list)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = countdowns
        list.move(fromOffsets: source, toOffset: destination)
        persist(list)
    }

    private func reconcileIntegrations() async {
        guard let saved = try? SettingsStore.available().load() else { return }
        await LiveCountdownController.reconcile(countdowns: saved)
        // With all reminders off, a foreground launch should not contact the
        // notification daemon. Saving a countdown re-plans explicitly.
        if saved.contains(where: { $0.reminderMode != .off }) {
            try? await NotificationManager.apply(countdowns: saved, requestPermission: false)
        }
    }

    private func reload() {
        do {
            let store = try SettingsStore.available()
            countdowns = try store.seedIfEmpty()
            appearance = store.loadAppearance()
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }
}

/// One countdown full screen, in its own style.
struct CountdownDetailView: View {
    let countdown: Countdown
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var liveMessage: String?
    @State private var confirmingDelete = false

    var body: some View {
        let style = countdown.style
        let image = ArtworkLoader.load(countdown, maximumPixelSize: 1400)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Remaining(target: countdown.targetDate(), now: context.date)
            ZStack {
                CountdownBackdrop(countdown: countdown, image: image, forceImage: style.imageMode != .hidden)
                    .ignoresSafeArea()
                LinearGradient(colors: [.clear, .black.opacity(image == nil || style.imageMode == .hidden ? 0 : 0.55)],
                               startPoint: .center, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(alignment: style.alignment.horizontal, spacing: 18) {
                    Spacer()
                    CountdownTitle(countdown: countdown, nameSize: 34)
                    if remaining.reached {
                        Text("وصل الموعد").font(style.font.font(44)).foregroundStyle(style.accentColor)
                    } else {
                        HStack(spacing: 6) {
                            unit(remaining.days, "يوم")
                            unit(remaining.hours, "ساعة")
                            unit(remaining.minutes, "دقيقة")
                            unit(remaining.seconds, "ثانية")
                        }
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(.vertical, 18).padding(.horizontal, 8)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 24))
                    }
                    if LiveCountdownEligibility.allows(target: countdown.targetDate(), now: context.date) {
                        Button("بدء النشاط المباشر") {
                            Task { @MainActor in
                                do { try await LiveCountdownController.start(countdown: countdown); liveMessage = nil }
                                catch { liveMessage = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let liveMessage { Text(liveMessage).font(.footnote).foregroundStyle(.orange) }
                }
                .frame(maxWidth: .infinity, alignment: style.alignment.frame)
                .padding(20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { onEdit() } label: { Label("تعديل", systemImage: "pencil") }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("حذف", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .confirmationDialog("حذف «\(countdown.name)»؟", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive, action: onDelete)
        }
    }

    private func unit(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: String(value)).font(countdown.style.font.font(34))
                .foregroundStyle(countdown.style.accentColor)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(countdown.style.textColor)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
