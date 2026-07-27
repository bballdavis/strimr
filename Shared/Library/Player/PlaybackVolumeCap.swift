import Foundation

@MainActor
protocol PlaybackVolumeApplying: AnyObject {
    func setVolume(_ volumePercent: Int)
}

@MainActor
enum PlaybackVolumeCap {
    static func apply(_ volumePercent: Int, to target: any PlaybackVolumeApplying) {
        target.setVolume(PlaybackSettings.clampVolumePercent(volumePercent))
    }
}
