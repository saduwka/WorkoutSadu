import SwiftData
import SwiftUI
import Foundation

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var bodyPart: String = ""
    var gifURL: String? = nil

    init(name: String, bodyPart: String, gifURL: String? = nil) {
        self.id = UUID()
        self.name = name
        self.bodyPart = bodyPart
        self.gifURL = gifURL
    }

    static func findOrCreate(name: String, bodyPart: String, in context: ModelContext) -> Exercise {
        let predicate = #Predicate<Exercise> { $0.name == name && $0.bodyPart == bodyPart }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let new = Exercise(name: name, bodyPart: bodyPart)
        context.insert(new)
        return new
    }
}
