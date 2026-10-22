import AppKit
import SwiftUI
import IslandCore

@MainActor
enum PreviewRenderer {
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
