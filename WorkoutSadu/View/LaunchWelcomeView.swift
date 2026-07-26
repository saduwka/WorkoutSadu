import SwiftUI

struct LaunchWelcomeView: View {
    let userName: String

    @State private var appeared = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default:      return "Доброй ночи"
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date()).capitalized
    }

    private var trimmedName: String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color(hex: "#0e0e12").ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(hex: "#ff5c3a").opacity(0.18),
                    Color.clear,
                    Color(hex: "#3aff9e").opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Text(dateString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    .tracking(0.5)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                Text(greeting)
                    .font(.custom("BebasNeue-Regular", size: 48))
                    .foregroundStyle(Color(hex: "#f0f0f5"))
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.92)

                if !trimmedName.isEmpty {
                    Text(trimmedName)
                        .font(.custom("BebasNeue-Regular", size: 36))
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                }
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) {
                appeared = true
            }
        }
    }
}

#Preview {
    LaunchWelcomeView(userName: "Саду")
}
