import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct TimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.kaido1070.gtavitimer.open") {
            ControlWidgetButton(action: OpenTimerIntent()) {
                Label("GTA VI Timer", systemImage: "hourglass")
            }
        }
        .displayName("GTA VI Timer")
        .description("افتح العدّاد من مركز التحكم أو زر الإجراءات على الأجهزة الداعمة.")
    }
}
