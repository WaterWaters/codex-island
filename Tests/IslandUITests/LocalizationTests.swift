import AppKit
import DesktopFeed
import Foundation
import IslandCore
import Observation
import SwiftUI
import Testing
@testable import CodexIsland

@MainActor @Test func localizationBundleLookupSupportsBothSwiftPMDirectoryCasings() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("localization-casing-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    for spelling in ["zh-hans", "zh-Hans", "zh-hant", "zh-Hant"] {
        let bundleRoot = root.appendingPathComponent(spelling + ".bundle")
        let resources = bundleRoot.appendingPathComponent("Contents/Resources")
        let directory = resources.appendingPathComponent(spelling + ".lproj")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "dev.water.synthetic-localization", "CFBundleDevelopmentRegion": "en"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundleRoot.appendingPathComponent("Contents/Info.plist"))
        try Data(#""sentinel" = "中文";"#.utf8).write(to: directory.appendingPathComponent("Localizable.strings"))
        let bundle = try #require(Bundle(url: bundleRoot))
        let language = spelling.lowercased().hasSuffix("hans") ? "zh-Hans" : "zh-Hant"
        let localized = try #require(L10n.resolveLocalizedBundle(language, in: bundle))
        #expect(localized.localizedString(forKey: "sentinel", value: nil, table: nil) == "中文")
        #expect(L10n.resolveLocalizedBundle("ja", in: bundle) == nil)
    }
}

@MainActor @Test func localizationResourcesHaveIdenticalKeysAndFormatArguments() throws {
    let languages: [AppLanguage] = [.en, .zhHans, .zhHant, .ja]
    var catalogs: [[String: String]] = []
    for language in languages {
        let bundle = try #require(L10n.localizedBundle(language.rawValue))
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        let catalog = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        #expect(catalog.count >= 175)
        catalogs.append(catalog)
    }
    let english = try #require(catalogs.first)
    let expression = try NSRegularExpression(pattern: #"%(?:\d+\$)?[@dfsu]"#)
    func parameters(_ value: String) -> [String] {
        expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
    }
    for catalog in catalogs {
        #expect(Set(catalog.keys) == Set(english.keys))
        for (key, value) in catalog {
            #expect(!value.isEmpty)
            #expect(parameters(value) == parameters(english[key] ?? ""))
        }
    }
    #expect(Set(LocalizationSources.keys.values).isSubset(of: Set(english.keys)))
}

@MainActor @Test func switchingLanguageUpdatesEveryDisplayBoundaryWithoutChangingSourceOrPreferences() throws {
    let previous = L10n.shared.language
    defer { L10n.shared.configure(language: previous) }
    let model = IslandModel()
    model.connection = .connected
    model.sessionTitle = "User Title 日本語 🐈"
    model.activity = .thinking
    model.summary = .reduce([.running, .running])
    model.isLocalFeed = true
    model.localFeedHealth = SourceHealth(caughtUp: true)
    model.preferences.values.selectedPetID = "custom:untouched"
    model.preferences.values.approvalRecognitionEnabled = true
    let preferences = model.preferences.values
    let diagnostic = model.privacyDiagnostics.json()
    let expected: [(AppLanguage, String, String)] = [
        (.en, "Thinking", "General"), (.zhHans, "思考中", "常规"),
        (.zhHant, "思考中", "一般"), (.ja, "思考中", "一般")
    ]
    for (language, detail, general) in expected {
        L10n.shared.configure(language: language)
        #expect(model.detail == detail)
        #expect(String(localized: SetupText.general) == general)
        #expect(model.title == "User Title 日本語 🐈")
        #expect(model.accessibilityDescription.contains(model.title))
        #expect(model.preferences.values == preferences)
        #expect(model.privacyDiagnostics.json() == diagnostic)
        #expect(model.connection == .connected && model.activity == .thinking)
        #expect(!String(localized: model.connectionPresentation.nextStep).hasPrefix("connection."))
        #expect(!model.pets.statusMessage.hasPrefix("pet."))
    }
    L10n.shared.configure(language: .en)
    #expect(L10n.count("summary.running", 1) == "1 task running")
    #expect(L10n.count("summary.running", 2) == "2 tasks running")
    #expect(L10n.count("menu.remaining", 1).contains("1 second left"))
    #expect(L10n.count("menu.remaining", 2).contains("2 seconds left"))
    #expect(L10n.format("color.hex_accessibility", "Primary") == "Primary hexadecimal color")
    #expect(L10n.text("User text remains untouched") == "User text remains untouched")
}

@MainActor @Test func titlePrivacyCoversVisibleAndAccessibilityTextWithoutDiscardingOriginalTitle() {
    let previous = L10n.shared.language
    defer { L10n.shared.configure(language: previous) }
    let model = IslandModel()
    model.sessionTitle = "PRIVATE-TITLE-密-🔒"
    model.connection = .connected
    model.summary = .reduce([.needsInput])
    for language in [AppLanguage.en, .zhHans, .zhHant, .ja] {
        L10n.shared.configure(language: language)
        model.preferences.values.hideSessionTitle = true
        #expect(model.title == "Codex")
        #expect(!model.accessibilityDescription.contains("PRIVATE"))
        #expect(!model.displayDetail.contains("PRIVATE"))
        #expect(!(model.privacyDiagnostics.json() ?? "").contains("PRIVATE"))
        #expect(model.sessionTitle == "PRIVATE-TITLE-密-🔒")
        model.preferences.values.hideSessionTitle = false
        #expect(model.title == "PRIVATE-TITLE-密-🔒")
    }
}

@MainActor @Test func hiddenSuspendedAndQuietModesStopMotion() {
    let model = IslandModel()
    #expect(!model.motionPaused)
    model.preferences.values.isVisible = false
    #expect(model.motionPaused)
    model.preferences.values.isVisible = true
    model.animationsPaused = true
    #expect(model.motionPaused)
    model.animationsPaused = false
    model.preferences.values.applyPreset(.quiet)
    #expect(model.motionPaused)
    model.preferences.values.animationsEnabled = true
    #expect(model.motionPaused)
    model.preferences.values.applyPreset(.highContrast)
    #expect(model.motionPaused)
}

// This explicitly opted-in native view render is a layout artifact. It is not
// evidence of menu interaction, display hot-plugging or VoiceOver narration.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_RENDER_PREVIEWS"] == "1",
                         "Set CODEX_ISLAND_TEST_RENDER_PREVIEWS=1 on a Mac with working graphics"))
func localizationNativeSamplesCoverFourLanguagesPrivacyAndAppearance() throws {
    let previous = L10n.shared.language
    defer { L10n.shared.configure(language: previous) }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let directory = project.appendingPathComponent("local/localization-samples", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var distinct = Set<Data>()
    for language in [AppLanguage.en, .zhHans, .zhHant, .ja] {
        L10n.shared.configure(language: language)
        let variants = (0..<6).map { index -> LocalizationRenderSample in
            let model = IslandModel()
            model.isDemo = true
            model.connection = .connected
            model.animationsPaused = true
            model.sessionTitle = switch language {
            case .ja: "🐈 日本語の長いセッションタイトル・繁體中文・简体中文・English 🌊 🚀"
            case .zhHans: "🐈 简体中文长会话标题・日本語・繁體中文・English 🌊 🚀"
            case .zhHant: "🐈 繁體中文長工作階段標題・日本語・简体中文・English 🌊 🚀"
            default: "🐈 Build an exceptionally long multilingual session title — 日本語・繁體中文・简体中文 🌊 🚀"
            }
            let presets: [AppearancePreset] = [.standard, .quiet, .highContrast]
            let preset = presets[index / 2]
            model.preferences.values.applyPreset(preset)
            model.preferences.values.hideSessionTitle = index % 2 == 1
            let states: [WorkState] = [.running, .needsInput, .blocked, .idle]
            let state = states[index % states.count]
            model.summary = .reduce(state == .running ? [.running, .running] : state == .idle ? [] : [state, .running])
            model.activity = state == .running ? .runningCommand : nil
            #expect(model.pets.atlas == nil)
            if model.preferences.values.hideSessionTitle {
                #expect(!model.accessibilityDescription.contains("exceptionally"))
                #expect(model.title == "Codex")
            }
            return LocalizationRenderSample(id: index, model: model, notched: index % 2 == 0,
                                            caption: "\(preset.rawValue) · privacy \(index % 2 == 1 ? "on" : "off") · no pet artwork")
        }
        let connection = IslandModel()
        connection.isDemo = true
        let renderer = ImageRenderer(content: LocalizationSampleBoard(language: language,
            samples: variants, connection: connection))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == 1440)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(language.rawValue + ".png"), options: .atomic)
        distinct.insert(png)
    }
    #expect(distinct.count == 4)
}

private struct LocalizationRenderSample: Identifiable {
    let id: Int
    let model: IslandModel
    let notched: Bool
    let caption: String
}

private struct LocalizationSampleBoard: View {
    let language: AppLanguage
    let samples: [LocalizationRenderSample]
    let connection: IslandModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "Codex Island · \(language.displayName)").font(.title2.bold())
            Text("Native view render · Synthetic content · Not a desktop interaction test")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(samples) { sample in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: sample.caption).font(.caption).foregroundStyle(.secondary)
                    IslandView(model: sample.model,
                        geometry: .layout(screenWidth: 1440, notchWidth: sample.notched ? 180 : 0,
                            notchHeight: sample.notched ? 32 : 0, expanded: true), openCodex: {})
                        .frame(maxWidth: .infinity)
                }
                .padding(10)
                .background(Color.gray.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            }
            Divider()
            HStack {
                Text(SetupText.general)
                Text(SetupText.appearance)
                Text(SetupText.connection)
                Text(SetupText.experiments)
            }.font(.headline)
            ConnectionStatusView(model: connection, provider: .codex, refreshStatus: {}, openApplication: { _ in })
            Text(SetupText.diagnosticPrivacy).font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 720)
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
    }
}
