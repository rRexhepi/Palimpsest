import Testing
@testable import InkAndEchoCore

@MainActor
@Suite("AudioEngine")
struct AudioEngineTests {
    @Test func startsIdle() {
        let engine = AudioEngine()
        #expect(engine.state == .idle)
        #expect(engine.rate == 1.0)
        #expect(engine.currentTime == 0)
        #expect(engine.duration == 0)
    }

    @Test func setRateClampsToBounds() {
        let engine = AudioEngine()
        engine.setRate(5.0)
        #expect(engine.rate == AudioEngine.maxRate)

        engine.setRate(0.1)
        #expect(engine.rate == AudioEngine.minRate)

        engine.setRate(1.25)
        #expect(engine.rate == 1.25)
    }

    @Test func playFailsWhenNotLoaded() {
        let engine = AudioEngine()
        #expect(throws: AudioEngineError.notLoaded) {
            try engine.play()
        }
    }
}
