import SwiftUI

struct GifSearchSheet: View {
    var initialQuery: String = ""
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ExerciseDBItem] = []
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var previewItem: ExerciseDBItem?
    @State private var previewGifData: Data?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                    quickChips

                    if isLoading {
                        Spacer()
                        ProgressView().tint(Color(hex: "#ff5c3a"))
                        Spacer()
                    } else if let err = errorMsg {
                        Spacer()
                        errorView(err)
                        Spacer()
                    } else if results.isEmpty && !query.isEmpty {
                        Spacer()
                        emptyView
                        Spacer()
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Найти GIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .sheet(item: $previewItem) { item in
                GifPreviewSheet(item: item, gifData: previewGifData) {
                    onSelect(item.gifUrl)
                    previewItem = nil
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !initialQuery.isEmpty && query.isEmpty {
                query = initialQuery
                performSearch()
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(hex: "#6b6b80"))
            TextField("Поиск на английском...", text: $query)
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { performSearch() }
                .onChange(of: query) { _, newValue in
                    debounceSearch(newValue)
                }
            if !query.isEmpty {
                Button { query = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .padding(12)
        .background(Color(hex: "#1e1e28"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Quick search chips

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton("bench press")
                chipButton("squat")
                chipButton("deadlift")
                chipButton("pull up")
                chipButton("shoulder press")
                chipButton("bicep curl")
                chipButton("tricep")
                chipButton("lat pulldown")
                chipButton("leg press")
                chipButton("plank")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func chipButton(_ text: String) -> some View {
        Button {
            query = text
            performSearch()
        } label: {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: "#1e1e28"))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(hex: "#2a2a3a"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results list

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(results) { item in
                    resultRow(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }

    private func resultRow(_ item: ExerciseDBItem) -> some View {
        Button {
            loadPreview(item)
        } label: {
            HStack(spacing: 14) {
                AsyncGifThumbnail(url: item.gifUrl)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name.capitalized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Label(item.bodyPart.capitalized, systemImage: "figure.strengthtraining.traditional")
                        Label(item.target.capitalized, systemImage: "scope")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                    Text(item.equipment.capitalized)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#ff5c3a").opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#3a3a4a"))
            }
            .padding(12)
            .background(Color(hex: "#16161d"))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.04), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - States

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: "#ff5c3a"))
            Text(msg)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .multilineTextAlignment(.center)
            Button("Повторить") { performSearch() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#ff5c3a"))
        }
        .padding(40)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: "#6b6b80"))
            Text("Ничего не найдено")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6b6b80"))
            Text("Попробуй другой запрос на английском")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#4a4a5a"))
        }
    }

    // MARK: - Logic

    private func debounceSearch(_ text: String) {
        searchTask?.cancel()
        guard text.count >= 3 else { return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run { performSearch() }
        }
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return }
        errorMsg = nil
        isLoading = true

        Task {
            do {
                print("[GifSearch] Searching: '\(q)'")
                let items = try await ExerciseDBService.shared.search(query: q)
                print("[GifSearch] Got \(items.count) results")
                await MainActor.run {
                    results = items
                    isLoading = false
                }
            } catch {
                print("[GifSearch] ❌ Error: \(error)")
                await MainActor.run {
                    errorMsg = "\(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func loadPreview(_ item: ExerciseDBItem) {
        previewGifData = nil
        previewItem = item
        Task {
            let data = await ExerciseGifManager.shared.loadGif(from: item.gifUrl)
            await MainActor.run { previewGifData = data }
        }
    }
}

// MARK: - Async GIF Thumbnail

struct AsyncGifThumbnail: View {
    let url: String
    @State private var gifData: Data?

    var body: some View {
        Group {
            if let data = gifData {
                AnimatedGifView(data: data)
            } else {
                ZStack {
                    Color(hex: "#1e1e28")
                    ProgressView().tint(Color(hex: "#ff5c3a")).scaleEffect(0.7)
                }
            }
        }
        .task {
            gifData = await ExerciseGifManager.shared.loadGif(from: url)
        }
    }
}

// MARK: - GIF Preview Sheet

struct GifPreviewSheet: View {
    let item: ExerciseDBItem
    let gifData: Data?
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let data = gifData {
                            AnimatedGifView(data: data)
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal, 16)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(hex: "#1e1e28"))
                                    .frame(height: 280)
                                ProgressView().tint(Color(hex: "#ff5c3a"))
                            }
                            .padding(.horizontal, 16)
                        }

                        VStack(spacing: 12) {
                            infoRow("Название", item.name.capitalized)
                            infoRow("Группа мышц", item.bodyPart.capitalized)
                            infoRow("Целевая мышца", item.target.capitalized)
                            infoRow("Оборудование", item.equipment.capitalized)
                        }
                        .padding(16)
                        .background(Color(hex: "#16161d"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.04), lineWidth: 1))
                        .padding(.horizontal, 16)

                        Button(action: onSelect) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Выбрать этот GIF")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "#ff5c3a"))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Предпросмотр")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Назад") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#6b6b80"))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: "#f0f0f5"))
        }
    }
}
