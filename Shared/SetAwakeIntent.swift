import AppIntents

struct SetAwakeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Awake"
    static let description = IntentDescription("Keeps the Mac awake, lid closed included, or lets it sleep again.")
    /// Background so Control Center stays open. Foreground is the fallback if
    /// macOS still hands the tap to Awake.app (it must not fail with error 2018).
    static let supportedModes: IntentModes = [.background, .foreground(.immediate)]

    @Parameter(title: "Awake")
    var value: Bool

    func perform() async throws -> some IntentResult {
        try await Awake.set(value)
        return .result()
    }
}
