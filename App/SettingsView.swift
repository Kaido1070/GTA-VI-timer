import SwiftUI
import PhotosUI
import WidgetKit
import ImageIO

/// Create or edit one countdown: details, image, colours, font and widget layout.
struct CountdownEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Countdown
    @State private var date: Date
    @State private var selection: PhotosPickerItem?
    @State private var jpeg: Data?
    @State private var preview: UIImage?
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    let isNew: Bool
    let onSave: ([Countdown]) -> Void

    init(initial: Countdown, isNew: Bool, onSave: @escaping ([Countdown]) -> Void) {
        _draft = State(initialValue: initial)
        _date = State(initialValue: initial.targetDate())
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        CountdownCard(countdown: previewCountdown, now: context.date, height: 190, imageOverride: preview)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section("العدّاد") {
                    TextField("الاسم", text: $draft.name)
                    DatePicker("التاريخ والوقت", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker("التذكير", selection: Binding(get: { draft.reminderMode }, set: { draft.reminders = $0 })) {
                        ForEach(ReminderMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                }
                Section("الصورة") {
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(hasImage ? "تغيير الصورة" : "اختيار صورة", systemImage: "photo")
                    }
                    .disabled(loading)
                    if loading { ProgressView("جارٍ تجهيز الصورة…") }
                    if hasImage {
                        Picker("مكان الصورة", selection: $draft.style.imageMode) {
                            ForEach(ImageMode.allCases) { Text($0.title).tag($0) }
                        }
                        VStack(alignment: .leading) {
                            Text("تعتيم الصورة \(Int(draft.style.imageDim * 100))٪")
                            Slider(value: $draft.style.imageDim, in: 0...0.8)
                        }
                        Button("إزالة الصورة", role: .destructive) {
                            draft.imageFilename = nil; draft.builtinArtwork = false
                            jpeg = nil; preview = nil; selection = nil
                        }
                    }
                }
                Section("الألوان") {
                    ColorPicker("الخلفية", selection: hexBinding(\.background), supportsOpacity: false)
                    ColorPicker("النص", selection: hexBinding(\.text), supportsOpacity: false)
                    ColorPicker("الأرقام", selection: hexBinding(\.accent), supportsOpacity: false)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Self.palettes) { palette in
                                Button {
                                    draft.style.background = palette.background
                                    draft.style.text = palette.text
                                    draft.style.accent = palette.accent
                                } label: {
                                    ZStack {
                                        Circle().fill(Color(hex: palette.background))
                                        Circle().fill(Color(hex: palette.accent)).frame(width: 14, height: 14)
                                    }
                                    .frame(width: 36, height: 36)
                                    .overlay(Circle().stroke(.white.opacity(0.3)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("الخط") {
                    Picker("نوع الخط", selection: $draft.style.font) {
                        ForEach(FontChoice.allCases) { choice in
                            Text(choice.title).font(choice.font(17)).tag(choice)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("الودجت والبطاقة") {
                    Picker("محاذاة النص", selection: $draft.style.alignment) {
                        ForEach(TextAlignmentChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("إظهار الاسم", isOn: $draft.style.showName)
                    Toggle("إظهار التاريخ", isOn: $draft.style.showDate)
                    Toggle("إظهار الساعات والدقائق والثواني", isOn: $draft.style.showClock)
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .navigationTitle(isNew ? "عدّاد جديد" : "تعديل العدّاد")
            .navigationBarTitleDisplayMode(.inline)
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
                    jpeg = converted; preview = UIImage(data: converted); error = nil
                } catch is CancellationError { }
                catch { self.error = "تعذّر تجهيز الصورة: \(error.localizedDescription)" }
            }
        }
    }

    struct Palette: Identifiable {
        let background: String, text: String, accent: String
        var id: String { background + accent }
    }
    static let palettes: [Palette] = [
        Palette(background: "#14161F", text: "#FFFFFF", accent: "#D6A84E"),
        Palette(background: "#000000", text: "#FFFFFF", accent: "#FFFFFF"),
        Palette(background: "#1B1036", text: "#FFFFFF", accent: "#FF9EC7"),
        Palette(background: "#0B1E3F", text: "#E8F1FF", accent: "#5AC8FA"),
        Palette(background: "#0F2A1D", text: "#EAF7EE", accent: "#34C759"),
        Palette(background: "#3A0D0D", text: "#FFECEC", accent: "#FF453A"),
        Palette(background: "#F5F0E6", text: "#1C1C1E", accent: "#B8860B"),
        Palette(background: "#FFFFFF", text: "#111111", accent: "#FF2D55"),
        Palette(background: "#2B1A00", text: "#FFF4E0", accent: "#FF9F0A"),
    ]

    private var hasImage: Bool { preview != nil || draft.imageFilename != nil || draft.builtinArtwork }

    /// The draft with its pending photo, for the live card preview.
    private var previewCountdown: Countdown {
        var value = draft
        value.setTarget(date)
        if !value.isValid { value.name = value.name.isEmpty ? " " : value.name }
        return value
    }

    private func hexBinding(_ key: WritableKeyPath<CountdownStyle, String>) -> Binding<Color> {
        Binding(get: { Color(hex: draft.style[keyPath: key]) }, set: { draft.style[keyPath: key] = $0.hex })
    }

    @MainActor private func save() async {
        saving = true
        defer { saving = false }
        draft.setTarget(date)
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.isValid else { error = SettingsStore.Failure.invalidSettings.localizedDescription; return }
        do {
            let store = try SettingsStore.available()
            if let jpeg {
                draft.imageFilename = try store.saveImage(jpeg)
                draft.builtinArtwork = false
            }
            let saved = try store.upsert(draft)
            WidgetCenter.shared.reloadAllTimelines()
            await LiveCountdownController.reconcile(countdowns: saved)
            onSave(saved)
            do { try await NotificationManager.apply(countdowns: saved, requestPermission: draft.reminderMode != .off) }
            catch {
                self.error = "حُفظ العدّاد، لكن التذكير لم يكتمل: \(error.localizedDescription)"
                return
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
