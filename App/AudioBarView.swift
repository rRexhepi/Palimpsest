import SwiftUI
import InkAndEchoCore

struct AudioBarView: View {
    let engine: AudioEngine
    var onAlign: (() -> Void)? = nil
    var alignmentEnabled: Bool = false
    var alignmentExists: Bool = false

    private let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        HStack(spacing: 12) {
            playPauseButton
            skipButton(seconds: -15, symbol: "gobackward.15")
            skipButton(seconds: 15, symbol: "goforward.15")

            Text(formatTime(engine.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.inkMuted)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { min(engine.currentTime, max(engine.duration, 0.001)) },
                    set: { engine.seek(to: $0) }
                ),
                in: 0...max(engine.duration, 0.001)
            )
            .tint(Theme.accent)
            .disabled(engine.duration <= 0)

            Text(formatTime(engine.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.inkMuted)
                .monospacedDigit()
                .frame(width: 52, alignment: .leading)

            rateMenu

            if alignmentEnabled, let onAlign {
                Button {
                    onAlign()
                } label: {
                    Label(alignmentExists ? "Re-align" : "Align", systemImage: "waveform.path")
                        .font(.caption)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(alignmentExists
                      ? "Re-run alignment. Useful after improving the aligner or if quality is poor."
                      : "Transcribe audio and align with the ebook text. First run downloads a ~140MB Whisper model.")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(Theme.canvasCool)
        .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .top)
    }

    private var playPauseButton: some View {
        Button {
            if engine.state == .playing {
                engine.pause()
            } else {
                try? engine.play()
            }
        } label: {
            Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                .font(.title3)
                .foregroundStyle(Theme.onAccent)
                .frame(width: 36, height: 36)
                .background(Theme.accent)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(engine.state == .idle || engine.state == .loading)
    }

    private func skipButton(seconds: TimeInterval, symbol: String) -> some View {
        Button {
            let target = max(0, min(engine.duration, engine.currentTime + seconds))
            engine.seek(to: target)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(engine.duration <= 0)
        .help(seconds < 0 ? "Skip back 15 seconds" : "Skip forward 15 seconds")
    }

    private var rateMenu: some View {
        Menu {
            ForEach(rates, id: \.self) { rate in
                Button {
                    engine.setRate(rate)
                } label: {
                    HStack {
                        Text(formatRate(rate))
                        if abs(engine.rate - rate) < 0.001 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(formatRate(engine.rate))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 44, alignment: .center)
                .padding(.vertical, 6)
                .background(Theme.canvas)
                .foregroundStyle(Theme.inkSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func formatRate(_ rate: Float) -> String {
        rate == floor(rate) ? "\(Int(rate))×" : String(format: "%.2g×", rate)
    }
}
