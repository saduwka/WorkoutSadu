import Foundation
import ActivityKit

public struct TimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var endTime: Date
        public init(endTime: Date) { self.endTime = endTime }
    }

    public var exerciseName: String?
    public init(exerciseName: String?) { self.exerciseName = exerciseName }
}
