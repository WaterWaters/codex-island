import AppKit
import SwiftUI
import IslandCore

@MainActor
enum PreviewRenderer {
    static let galleryStates: [WorkState] = [.running, .needsInput, .blocked, .idle]

    static func sampleModel(state: WorkState) -> IslandModel {
        let model = IslandModel(preferences: IslandPreferences())
        model.connection = .connected
        model.isDemo = true
        model.animationsPaused = true
        model.sessionTitle = "构建 Codex Island"
        model.activity = switch state {
        case .running: .runningCommand
        case .needsInput: .needsInput
        case .blocked: .failed
        case .idle: .idle
        case .ready: nil
        }
        model.summary = .reduce(state == .idle ? [] : [state])
        return model
    }

    static func renderGallery(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for state in galleryStates {
            for notched in [true, false] {
                let model = sampleModel(state: state)
                let name = "\(state.rawValue)-\(notched ? "notched" : "standard").png"
                try write(DesktopPreview(state: state, model: model, notched: notched),
                          to: directory.appendingPathComponent(name))
            }
        }
    }

    private static func write<Content: View>(_ content: Content, to url: URL) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
    }

    static func render(to url: URL) throws {
        let samples = [WorkState.running, .needsInput, .blocked, .idle].map { state in
            let model = IslandModel()
            model.connection = .connected
            model.isDemo = true
            model.animationsPaused = true
            model.sessionTitle = "设计 Codex 浮窗小工具"
            model.activity = state == .running ? .runningCommand : nil
            model.summary = .reduce(state == .idle ? [] : state == .running ? [.running, .running] : [state, .running])
            return PreviewSample(state: state, model: model)
        }
        let renderer = ImageRenderer(content: PreviewBoard(samples: samples))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
    }
}

/// A native view composition, not a desktop screenshot. All session metadata
/// is synthetic and preferences are in memory; no Codex assets are loaded.
private struct DesktopPreview: View {
    let state: WorkState
    let model: IslandModel
    let notched: Bool

    private var label: String {
        switch state {
        case .running: "Working"
        case .needsInput: "Needs your input"
        case .blocked: "Work blocked"
        case .idle: "Idle"
        case .ready: "Ready"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                Circle().fill(IslandPalette.tint(for: state)).frame(width: 7, height: 7)
                Text(label).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(notched ? "MacBook · Notched display" : "External · Standard display")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.07, green: 0.14, blue: 0.19),
                                         Color(red: 0.035, green: 0.065, blue: 0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(Color.cyan.opacity(0.055)).frame(width: 580, height: 130)
                    .blur(radius: 35).offset(x: -130, y: 110)
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo").font(.system(size: 12))
                    Text("Codex Island").font(.system(size: 10, weight: .semibold))
                    Spacer()
                    if let icon = BrandAssets.menuBarIcon {
                        Image(nsImage: icon).resizable().frame(width: 15, height: 15)
                    }
                    Image(systemName: "wifi").font(.system(size: 11))
                    Text("09:41").font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .padding(.horizontal, 18).frame(height: 26)
                .background(.black.opacity(0.18))
                IslandView(model: model,
                           geometry: .layout(screenWidth: 600, notchWidth: notched ? 180 : 0,
                                             notchHeight: notched ? 32 : 0, expanded: true), openCodex: {})
                    .offset(y: notched ? 0 : 36)
                if notched {
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                        .fill(.black).frame(width: 180, height: 32)
                }
                VStack {
                    Spacer()
                    HStack {
                        Text("Codex Island").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("Native view preview · Synthetic content")
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                    }.foregroundStyle(.white.opacity(0.5))
                }.padding(18)
            }
            .frame(width: 600, height: 224)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10), lineWidth: 1))
        }
        .padding(24).foregroundStyle(.white)
        .background(Color(red: 0.035, green: 0.047, blue: 0.06))
        .fixedSize()
    }
}

private struct PreviewSample: Identifiable {
    let state: WorkState
    let model: IslandModel
    var id: String { state.rawValue }
}

private struct PreviewBoard: View {
    let samples: [PreviewSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Codex Island").font(.system(size: 30, weight: .semibold))
                Text("原生 SwiftUI 视图渲染 · 演示状态 · 非桌面运行截图")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.bottom, 10)
            ForEach(samples) { sample in
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sample.state.title).font(.system(size: 16, weight: .medium))
                        Text(sample.state == .idle ? "低亮呼吸 / 常驻等待" : sample.state == .running ? "霓虹环绕 / 两行信息" : "轮廓脉冲 / 点击打开 Codex")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(width: 178, alignment: .leading)
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.13, green: 0.19, blue: 0.21))
                        IslandView(model: sample.model,
                                   geometry: .layout(screenWidth: 1512, notchWidth: 180, notchHeight: 32,
                                                     expanded: sample.model.isExpanded), openCodex: {})
                        RoundedRectangle(cornerRadius: 9).fill(.black)
                            .frame(width: 180, height: 36).offset(y: -5)
                    }
                    .frame(width: 480, height: 124)
                    .clipped()
                }
            }
            Text("会话标题 + 当前活动 · Codex 运行时常驻 · 完整宠物同源仍未接通")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.top, 6)
        }
        .padding(36)
        .foregroundStyle(.white)
        .background(Color(red: 0.055, green: 0.075, blue: 0.085))
        .fixedSize()
    }
}
