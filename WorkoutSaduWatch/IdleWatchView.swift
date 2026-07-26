import SwiftUI

struct IdleWatchView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "dumbbell.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(WatchTheme.textMuted.opacity(0.7))

            Text("НЕТ АКТИВНОЙ\nТРЕНИРОВКИ")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(WatchTheme.textPrimary)
                .multilineTextAlignment(.center)
                .tracking(0.5)

            Text("Начни тренировку на iPhone")
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.textMuted)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchTheme.bg)
    }
}
