//
//  WorkoutSaduApp.swift
//  WorkoutSadu
//
//  Created by Nurzhan on 03.02.2026.
//

import SwiftUI
import CoreData

@main
struct WorkoutSaduApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
