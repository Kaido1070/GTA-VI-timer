import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct TimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.kaido1070.gtavitimer.open") {
            ControlWidgetButton(action: OpenTimerIntent()) {
                Label("AnyTimer", systemImage: "hourglass")
            }
        }
        .displayName("AnyTimer")
        .description("افتح العدّاد من مركز التحكم أو زر الإجراءات على الأجهزة الداعمة.")
    }
}
