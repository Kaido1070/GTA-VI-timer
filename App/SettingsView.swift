import SwiftUI
import PhotosUI
import WidgetKit
import ImageIO

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TimerSettings
    @State private var date: Date
    @State private var selection: PhotosPickerItem?
    @State private var jpeg: Data?
    @State private var resetImage = false
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    let onSave: (TimerSettings) -> Void

    init(initial: TimerSettings, onSave: @escaping (TimerSettings) -> Void) {
        _draft = State(initialValue: initial)
        _date = State(initialValue: initial.targetDate())
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الموعد") {
                    TextField("اسم اللعبة", text: $draft.name)
                    DatePicker("التاريخ", selection: $date, displayedComponents: .date)
                    Text("الاستهداف: بداية اليوم المختار، الساعة 00:00 حسب المنطقة الزمنية المحلية للجهاز (\(TimeZone.current.identifier)). اليوم المتبقي = 24 ساعة كاملة من المدة الفعلية؛ قد تؤثر تغييرات التوقيت الصيفي.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("الخلفية") {
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label("اختيار صورة من الألبوم", systemImage: "photo")
                    }
                    .disabled(loading)
                    if loading { ProgressView("جارٍ تجهيز الصورة…") }
                    if let jpeg, let image = UIImage(data: jpeg) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    } else {
                        ArtworkView(settings: previewSettings).frame(height: 220)
                    }
                    Button("استعادة صورة GTA VI المضمّنة") {
                        resetImage = true; jpeg = nil; selection = nil
                    }
                }
                Section("التنبيهات الاختيارية") {
                    Picker("التذكير", selection: Binding(get: { draft.reminderMode }, set: { draft.reminders = $0 })) {
                        ForEach(ReminderMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Text("تنبيهات محلية فقط، متوقفة افتراضيًا. عند التفعيل والحفظ سيطلب النظام الإذن. قد تؤخرها إعدادات التركيز أو ملخص الإشعارات.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("التخزين والودجت") {
                    Text("عند توفر App Group، تشترك الإعدادات والصورة مع الودجت. عند غيابها تُحفظ داخل التطبيق فقط، ويظل الودجت على GTA VI و19 نوفمبر 2026 والصورة المضمّنة. يقرر iOS وقت تحديث الودجت وقد يعرض صورة القفل بلون موحّد.")
                        .font(.footnote)
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .navigationTitle("الإعدادات")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("حفظ") { Task { await save() } }.disabled(loading || saving) }
            }
            .task(id: selection) {
                guard let selection else { return }
                loading = true
                defer { loading = false }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self),
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1600
                          ] as CFDictionary),
                          let converted = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try Task.checkCancellation()
                    jpeg = converted; resetImage = false; error = nil
                } catch is CancellationError { }
                catch { self.error = "تعذّر تجهيز الصورة: \(error.localizedDescription)" }
            }
        }
    }

    private var previewSettings: TimerSettings {
        var value = draft
        if resetImage { value.imageFilename = nil }
        return value
    }

    @MainActor private func save() async {
        saving = true
        defer { saving = false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        draft.year = components.year!; draft.month = components.month!; draft.day = components.day!
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if resetImage { draft.imageFilename = nil }
        do {
            let saved = try SettingsStore.available().save(draft, newJPEG: jpeg)
            WidgetCenter.shared.reloadAllTimelines()
            draft = saved; jpeg = nil; resetImage = false
            await LiveCountdownController.reconcile(settings: saved)
            onSave(saved)
            do { try await NotificationManager.apply(settings: saved, requestPermission: true) }
            catch {
                self.error = "حُفظت الإعدادات، لكن التذكير لم يكتمل: \(error.localizedDescription)"
                return
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
