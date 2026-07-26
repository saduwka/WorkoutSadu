import SwiftUI

struct WatchStepper: View {
    let label: String
    let valueText: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WatchTheme.textMuted)
                .tracking(1)

            Text(valueText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(WatchTheme.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            HStack(spacing: 10) {
                stepButton(systemName: "minus", action: onDecrement)
                stepButton(systemName: "plus", action: onIncrement)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WatchTheme.textPrimary)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
