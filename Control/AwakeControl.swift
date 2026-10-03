import AppIntents
import SwiftUI
import WidgetKit

@main
struct AwakeControls: WidgetBundle {
    var body: some Widget {
        AwakeControl()
    }
}

struct AwakeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mohdkhan.awake.toggle", provider: Provider()) { isOn in
            ControlWidgetToggle("Awake", isOn: isOn, action: SetAwakeIntent()) { isOn in
                Label(isOn ? "On" : "Off", systemImage: isOn ? "cup.and.heat.waves.fill" : "cup.and.saucer")
            }
            .tint(.orange)
        }
        .displayName("Awake")
        .description("Keep the Mac awake, even with the lid closed.")
    }

    struct Provider: ControlValueProvider {
        let previewValue = false

        func currentValue() async throws -> Bool { Awake.isOn }
    }
}
