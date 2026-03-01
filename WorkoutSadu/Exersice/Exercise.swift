import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var id: String
    var name: String
    var bodyPart: String
    var gifUrl: String?

    init(id: String, name: String, bodyPart: String, gifUrl: String?) {
        self.id = id
        self.name = name
        self.bodyPart = bodyPart
        self.gifUrl = gifUrl
    }
}
