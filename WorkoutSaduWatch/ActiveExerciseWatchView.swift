import SwiftUI

struct ActiveExerciseWatchView: View {
    @ObservedObject var store: WatchSessionStore
    let snapshot: ActiveWorkoutSnapshot

    @State private var selectedPage = 0

    private var exercise: WatchExerciseDTO? { snapshot.currentExercise }
    private var hasQueue: Bool { snapshot.exercises.filter { !$0.isCardio }.count > 1 }

    var body: some View {
        Group {
            if hasQueue {
                TabView(selection: $selectedPage) {
                    setPage.tag(0)
                    queuePage.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            } else {
                setPage
            }
        }
        .background(WatchTheme.bg)
    }

    // MARK: - Page 1: Current Set

    private var setPage: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            if let exercise {
                WatchDisplayText(text: exercise.name, size: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if exercise.isCardio {
                    Text("Кардио — отмечай на iPhone")
                        .font(.system(size: 12))
                        .foregroundStyle(WatchTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let nextSet = snapshot.nextIncompleteSet {
                    Text("СЕТ \(setNumber(for: nextSet))/\(totalSets)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WatchTheme.accent)
                        .tracking(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        WatchStepper(
                            label: "КГ",
                            valueText: String(format: "%.1f", store.draftWeight),
                            onDecrement: { store.adjustWeight(by: -2.5) },
                            onIncrement: { store.adjustWeight(by: 2.5) }
                        )

                        WatchStepper(
                            label: "ПОВТ",
                            valueText: "\(store.draftReps)",
                            onDecrement: { store.adjustReps(by: -1) },
                            onIncrement: { store.adjustReps(by: 1) }
                        )
                    }

                    WatchPrimaryButton(title: "Готово") {
                        store.completeCurrentSet()
                    }
                    .opacity(store.isCompletingSet ? 0.45 : 1)
                    .disabled(store.isCompletingSet)
                } else {
                    Text("Все подходы выполнены")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WatchTheme.success)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)

            Button("Завершить тренировку") {
                store.finishWorkout()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.red.opacity(0.85))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    // MARK: - Page 2: Exercise Queue

    private var queuePage: some View {
        List {
            ForEach(snapshot.exercises.filter { !$0.isCardio }) { item in
                Button {
                    store.selectExercise(item.id)
                    selectedPage = 0
                } label: {
                    HStack(spacing: 6) {
                        if item.id == exercise?.id {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(WatchTheme.accent)
                        }
                        Text(item.name)
                            .font(.system(size: 13, weight: item.id == exercise?.id ? .semibold : .regular))
                            .foregroundStyle(item.id == exercise?.id ? WatchTheme.accent : WatchTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.sets.filter(\.isCompleted).count)/\(item.sets.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(WatchTheme.textMuted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.carousel)
    }

    private func setNumber(for set: WatchSetDTO) -> Int {
        guard let exercise else { return 1 }
        return exercise.sets.filter { $0.order < set.order }.count + 1
    }

    private var totalSets: Int { exercise?.sets.count ?? 0 }
}
