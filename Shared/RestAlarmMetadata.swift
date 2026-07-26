import Foundation

#if canImport(AlarmKit)
import AlarmKit

/// Shared between app and RestTimerWidget for AlarmKit Live Activity.
struct RestAlarmMetadata: AlarmMetadata {
    var exerciseName: String?
}
#endif
