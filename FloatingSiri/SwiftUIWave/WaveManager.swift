import SwiftUI
import UIKit
import AVFoundation

/// Voice-level bridge + smoothing for the Metal rainbow wave.
/// Fixed vs older builds:
/// - Much lower deadzone (Siri flame levels are often tiny)
/// - Configurable mic gain via `com.kolby.floatingsiri`
/// - Accepts dB or linear inputs
/// - Idle bassLevel stays near 0 so talkingFactor can rise immediately
@objc public class WaveManager: NSObject, ObservableObject {
    @objc public static let shared = WaveManager()

    @objc public var targetPower: Double = 0.0
    @Published public var phase: Double = 0.0
    @Published public var phases: [Double] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    @Published public var currentPower: Double = 0.0

    @Published public var bassLevel: Double = 0.0
    @Published public var midLevel: Double = 0.0
    @Published public var trebleLevel: Double = 0.0

    @objc public var power: Double = 0.0 {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("UpdateSiriPower"), object: power)
        }
    }

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var currentSpeed: Double = 1.0
    @Published public var rawMicLevel: Double = 0.0

    private var micGain: Double = 22.0
    private var micDeadzone: Double = 0.002
    private var waveSpeedDivisor: Double = 3.8

    private override init() {
        super.init()
        reloadPrefs()
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(reloadPrefs),
                                             name: NSNotification.Name("com.kolby.floatingsiri/prefschanged"),
                                             object: nil)
        displayLink = CADisplayLink(target: self, selector: #selector(updatePower))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc public func reloadPrefs() {
        let d = UserDefaults(suiteName: "com.kolby.floatingsiri") ?? .standard
        // Also merge file-backed prefs (PreferenceLoader often writes these)
        let paths = [
            "/var/jb/var/mobile/Library/Preferences/com.kolby.floatingsiri.plist",
            "/var/mobile/Library/Preferences/com.kolby.floatingsiri.plist"
        ]
        var filePrefs: [String: Any] = [:]
        for p in paths {
            if let dict = NSDictionary(contentsOfFile: p) as? [String: Any] {
                filePrefs = dict
                break
            }
        }
        func num(_ key: String, fallback: Double) -> Double {
            if let v = filePrefs[key] as? NSNumber { return v.doubleValue }
            if d.object(forKey: key) != nil { return d.double(forKey: key) }
            return fallback
        }
        micGain = max(1.0, num("micGain", fallback: 22.0))
        micDeadzone = max(0.0, num("micDeadzone", fallback: 0.002))
        waveSpeedDivisor = max(0.4, num("waveSpeed", fallback: 3.8))
    }

    @objc private func updatePower(link: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = link.timestamp }
        let dt = max(0.0001, link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp

        var linearLevel = rawMicLevel
        if linearLevel < 0 {
            // dBFS → linear
            linearLevel = pow(10.0, max(-120.0, linearLevel) / 20.0)
        }
        linearLevel = max(0.0, min(1.0, linearLevel))

        // Soft curve so quiet speech still moves the wave
        let boosted = pow(linearLevel, 0.55)
        let signal = max(0.0, boosted - micDeadzone)

        // Idle visual power ~0; speech ramps quickly
        let targetVisualPower = min(1.5, signal * micGain)

        let attack: Double = targetVisualPower > currentPower ? 0.00001 : 0.18
        currentPower += (targetVisualPower - currentPower) * (1.0 - pow(attack, dt))

        bassLevel = currentPower
        midLevel = currentPower
        trebleLevel = currentPower

        let targetSpeed = (1.0 + min(2.5, signal * 5.0)) * (3.8 / waveSpeedDivisor)
        let speedLerp: Double = targetSpeed > currentSpeed ? 0.01 : 0.15
        currentSpeed += (targetSpeed - currentSpeed) * (1.0 - pow(speedLerp, dt))

        phase += currentSpeed * dt
        if phase > .pi * 100 { phase = phase.truncatingRemainder(dividingBy: .pi * 2) }

        let extraSpeed = min(2.0, signal * 4.0)
        for i in 0..<7 {
            let individualSpeed = currentSpeed + extraSpeed * Double(i - 3) * 0.2
            phases[i] += individualSpeed * dt
            if phases[i] > .pi * 100 { phases[i] = phases[i].truncatingRemainder(dividingBy: .pi * 2) }
        }

        if abs(currentPower - power) > 0.0005 {
            power = currentPower
        }
    }

    @objc public func updateTargetPower(_ newPowerObj: NSNumber) {
        let newPower = newPowerObj.doubleValue
        if Thread.isMainThread {
            self.rawMicLevel = newPower
        } else {
            DispatchQueue.main.async { self.rawMicLevel = newPower }
        }
    }

    @objc public func startRecording() {}

    @objc public func stopRecording() {
        DispatchQueue.main.async {
            self.rawMicLevel = 0
            self.targetPower = 0
        }
    }

    @objc public func createWaveView(frame: CGRect) -> UIView {
        let waveView = SiriWaveView()
        let hostingController = UIHostingController(rootView: waveView)
        hostingController.view.frame = frame
        hostingController.view.backgroundColor = .clear
        hostingController.view.insetsLayoutMarginsFromSafeArea = false
        if #available(iOS 16.4, *) {
            hostingController.safeAreaRegions = []
        }
        return hostingController.view
    }
}
