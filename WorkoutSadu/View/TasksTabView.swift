import SwiftUI
import SwiftData

struct TasksTabView: View {
    @Environment(\.modelContext) private var context
    @State private var section: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker

            Group {
                switch section {
                case 0:  HabitsView()
                case 1:  TodoListView()
                case 2:  GoalsView()
                default: HabitsView()
                }
            }
        }
        .background(Color(hex: "#0e0e12"))
        .onAppear { renewWeeklyGoalsIfNeeded() }
    }

    /// Сброс currentCount и weekStart у целей при смене периода (при открытии вкладки).
    private func renewWeeklyGoalsIfNeeded() {
        let descriptor = FetchDescriptor<WeeklyGoal>()
        guard let goals = try? context.fetch(descriptor) else { return }
        var changed = false
        for goal in goals {
            if goal.renewIfNeeded() { changed = true }
        }
        if changed { try? context.save() }
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            let tabs = [
                ("Привычки", "repeat"),
                ("Задачи", "checklist"),
                ("Цели", "target")
            ]

            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { section = i }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.1)
                            .font(.system(size: 14))
                        Text(tab.0)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(section == i ? Color(hex: "#ff5c3a") : Color(hex: "#6b6b80"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .background(Color(hex: "#0e0e12"))
    }
}

// MARK: - Habits View

struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.archived }, sort: \Habit.createdAt) private var habits: [Habit]

    @State private var showAddHabit = false
    @State private var newHabitName = ""
    @State private var selectedColor = "#ff5c3a"
    @State private var selectedIcon = "checkmark.circle"
    @State private var habitToDelete: Habit?
    @State private var editingHabit: Habit?

    private let colors = ["#ff5c3a", "#5b8cff", "#3aff9e", "#ffb830", "#a855f7", "#f472b6", "#6366f1"]
    private let icons = [
        "checkmark.circle", "drop.fill", "book.fill", "figure.run",
        "moon.fill", "brain.fill", "heart.fill", "leaf.fill",
        "pills.fill", "cup.and.saucer.fill", "pencil", "music.note"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if habits.isEmpty {
                            emptyState
                        } else {
                            contributionGraph
                            ForEach(habits) { habit in
                                habitRow(habit)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("ПРИВЫЧКИ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddHabit = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
            }
            .alert("Новая привычка", isPresented: $showAddHabit) {
                TextField("Название", text: $newHabitName)
                Button("Создать") {
                    guard !newHabitName.isEmpty else { return }
                    let h = Habit(name: newHabitName, icon: selectedIcon, colorHex: selectedColor)
                    context.insert(h)
                    try? context.save()
                    newHabitName = ""
                }
                Button("Отмена", role: .cancel) { newHabitName = "" }
            }
            .alert("Удалить привычку?", isPresented: Binding(
                get: { habitToDelete != nil },
                set: { if !$0 { habitToDelete = nil } }
            )) {
                Button("Удалить", role: .destructive) {
                    if let habit = habitToDelete {
                        for entry in habit.entries { context.delete(entry) }
                        context.delete(habit)
                        try? context.save()
                    }
                    habitToDelete = nil
                }
                Button("Отмена", role: .cancel) { habitToDelete = nil }
            } message: {
                Text("Привычка «\(habitToDelete?.name ?? "")» и вся история будут удалены")
            }
            .sheet(item: $editingHabit) { habit in
                EditHabitSheet(habit: habit, colors: colors, icons: icons)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Contribution graph

    private var contributionGraph: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ПОСЛЕДНИЕ 12 НЕДЕЛЬ")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .tracking(1)

            let weeks = 12
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            // Локаль: первый день недели (воскресенье=1, понедельник=2 и т.д.)
            let todayWeekday = (cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(0..<weeks, id: \.self) { weekOffset in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { row in
                                let daysBack = (weeks - 1 - weekOffset) * 7 + (todayWeekday - row)
                                let isValid = weekOffset < weeks - 1 || row <= todayWeekday
                                if isValid, let day = cal.date(byAdding: .day, value: -daysBack, to: today) {
                                    let count = habits.filter { $0.isCompleted(on: day) }.count
                                    let intensity = habits.isEmpty ? 0 : Double(count) / Double(max(habits.count, 1))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(intensity > 0 ? Color(hex: "#3aff9e").opacity(0.2 + intensity * 0.8) : Color(hex: "#1a1a24"))
                                        .frame(width: 14, height: 14)
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: "#1a1a24"))
                                        .frame(width: 14, height: 14)
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 4) {
                Text("Меньше")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(hex: "#6b6b80"))
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(intensity > 0 ? Color(hex: "#3aff9e").opacity(0.2 + intensity * 0.8) : Color(hex: "#1a1a24"))
                        .frame(width: 10, height: 10)
                }
                Text("Больше")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(hex: "#6b6b80"))
            }
        }
        .padding(14)
        .darkCard()
    }

    // MARK: - Habit row

    private func habitRow(_ habit: Habit) -> some View {
        let today = Date()
        let done = habit.isCompleted(on: today)
        let streak = habit.streak()
        let todos = habit.linkedTodos.sorted { !$0.completed && $1.completed }

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if done {
                        if let entry = habit.entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                            context.delete(entry)
                        }
                    } else {
                        let entry = HabitEntry(date: today, habit: habit)
                        context.insert(entry)
                    }
                    try? context.save()
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26))
                        .foregroundStyle(done ? Color(hex: habit.colorHex) : Color(hex: "#6b6b80"))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    HStack(spacing: 6) {
                        if streak > 0 {
                            Text("\(streak) дн. подряд")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "#ffb830"))
                        }
                        if habit.hasTodos {
                            let doneCount = todos.filter { $0.completed }.count
                            Text("\(doneCount)/\(todos.count)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(habit.allTodosCompleted ? Color(hex: "#3aff9e") : Color(hex: "#6b6b80"))
                        }
                    }
                }
                .onTapGesture { editingHabit = habit }

                Spacer()

                weekDots(habit)

                Button { habitToDelete = habit } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "#6b6b80").opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            if !todos.isEmpty {
                Divider().background(Color(hex: "#2a2a36"))
                VStack(spacing: 0) {
                    ForEach(todos) { todo in
                        habitTodoRow(todo, habit: habit)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .darkCard()
    }

    private func habitTodoRow(_ todo: TodoItem, habit: Habit) -> some View {
        HStack(spacing: 10) {
            Button {
                todo.completed.toggle()
                try? context.save()
                checkAutoComplete(habit)
            } label: {
                Image(systemName: todo.completed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(todo.completed ? Color(hex: habit.colorHex) : Color(hex: "#6b6b80"))
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(.system(size: 13))
                .foregroundStyle(todo.completed ? Color(hex: "#6b6b80") : Color(hex: "#f0f0f5"))
                .strikethrough(todo.completed)

            Spacer()

            Button {
                context.delete(todo)
                try? context.save()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: "#6b6b80").opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func checkAutoComplete(_ habit: Habit) {
        habit.syncAutoComplete(context: context)
    }

    private func weekDots(_ habit: Habit) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { offset in
                if let day = cal.date(byAdding: .day, value: -(6 - offset), to: today) {
                    Circle()
                        .fill(habit.isCompleted(on: day) ? Color(hex: habit.colorHex) : Color(hex: "#1a1a24"))
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "repeat")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: "#6b6b80"))
            Text("Нет привычек")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Добавьте привычку, которую хотите отслеживать каждый день")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .darkCard()
    }
}

// MARK: - Todo List View

struct TodoListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allTodos: [TodoItem]

    @State private var newTodoTitle = ""
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showDatePicker = false
    @State private var newTodoDueDate: Date? = nil
    @State private var calendarMonth: Date = Date()
    @State private var editingTodo: TodoItem?
    @FocusState private var inputFocused: Bool

    private let cal = Calendar.current

    /// Задачи на выбранную дату + inbox (без dueDate всегда видны).
    private var todosForSelectedDate: [TodoItem] {
        return allTodos.filter { todo in
            if let due = todo.dueDate {
                return cal.isDate(due, inSameDayAs: selectedDate)
            }
            // Задачи без даты — inbox, всегда видны
            return true
        }
    }

    private var pendingForDate: [TodoItem] { todosForSelectedDate.filter { !$0.completed } }
    private var completedForDate: [TodoItem] { todosForSelectedDate.filter { $0.completed } }

    /// Количество невыполненных задач на дату (только с dueDate; inbox не привязан к дате).
    private func todoCount(on date: Date) -> Int {
        return allTodos.filter { todo in
            guard !todo.completed else { return false }
            guard let due = todo.dueDate else { return false }
            return cal.isDate(due, inSameDayAs: date)
        }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                VStack(spacing: 0) {
                    calendarView
                    inputBar
                    ScrollView {
                        VStack(spacing: 8) {
                            if pendingForDate.isEmpty && completedForDate.isEmpty {
                                emptyState
                            }
                            ForEach(pendingForDate) { todo in todoRow(todo) }
                            if !completedForDate.isEmpty {
                                HStack {
                                    Text("ВЫПОЛНЕНО (\(completedForDate.count))")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(hex: "#6b6b80"))
                                        .tracking(1)
                                    Spacer()
                                    Button {
                                        for t in completedForDate { context.delete(t) }
                                        try? context.save()
                                    } label: {
                                        Text("Очистить")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color(hex: "#ff5c3a"))
                                    }
                                }
                                .padding(.top, 8)
                                ForEach(completedForDate) { todo in todoRow(todo) }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 40)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .dismissKeyboardOnTap()
            }
            .navigationTitle("ЗАДАЧИ")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editingTodo) { todo in
            EditTodoSheet(todo: todo)
        }
    }

    // MARK: - Calendar

    private var calendarView: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    calendarMonth = cal.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }

                Spacer()

                Text(monthYearString(calendarMonth))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "#f0f0f5"))

                Spacer()

                Button {
                    calendarMonth = cal.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
            }
            .padding(.horizontal, 16)

            let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(hex: "#6b6b80"))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            let days = daysInMonth(calendarMonth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    if let day = day {
                        let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
                        let isToday = cal.isDateInToday(day)
                        let count = todoCount(on: day)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedDate = day }
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(cal.component(.day, from: day))")
                                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                                    .foregroundStyle(
                                        isSelected ? Color.white :
                                        isToday ? Color(hex: "#ff5c3a") :
                                        Color(hex: "#f0f0f5")
                                    )

                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(isSelected ? .white : Color(hex: "#ff5c3a"))
                                } else {
                                    Text(" ")
                                        .font(.system(size: 8))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                isSelected ?
                                    RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#ff5c3a")) :
                                    RoundedRectangle(cornerRadius: 8).fill(Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 10)
        .background(Color(hex: "#161620"))
    }

    private func monthYearString(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date).capitalized
    }

    private func daysInMonth(_ month: Date) -> [Date?] {
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let firstDay = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: firstDay) else { return [] }

        var weekday = cal.component(.weekday, from: firstDay)
        weekday = (weekday - cal.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: weekday)
        for day in range {
            var dc = comps
            dc.day = day
            days.append(cal.date(from: dc))
        }
        return days
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Новая задача...", text: $newTodoTitle)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "#f0f0f5"))
                .padding(12)
                .background(Color(hex: "#1a1a24"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .focused($inputFocused)
                .submitLabel(.done)
                .onSubmit { addTodo() }

            Button {
                showDatePicker = true
            } label: {
                Image(systemName: newTodoDueDate != nil ? "calendar.badge.clock" : "calendar")
                    .font(.system(size: 20))
                    .foregroundStyle(newTodoDueDate != nil ? Color(hex: "#ff5c3a") : Color(hex: "#6b6b80"))
            }
            .buttonStyle(.plain)

            Button {
                addTodo()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty ? Color(hex: "#6b6b80") : Color(hex: "#ff5c3a"))
            }
            .buttonStyle(.plain)
            .disabled(newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .sheet(isPresented: $showDatePicker) {
            dueDatePicker
        }
    }

    private var dueDatePicker: some View {
        NavigationStack {
            VStack {
                DatePicker("Дата", selection: Binding(
                    get: { newTodoDueDate ?? selectedDate },
                    set: { newTodoDueDate = $0 }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Color(hex: "#ff5c3a"))
                .padding()

                if newTodoDueDate != nil {
                    Button("Убрать дату") {
                        newTodoDueDate = nil
                        showDatePicker = false
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                }

                Spacer()
            }
            .background(Color(hex: "#0e0e12"))
            .navigationTitle("Дедлайн")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showDatePicker = false }
                        .foregroundStyle(Color(hex: "#ff5c3a"))
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func addTodo() {
        let title = newTodoTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let due: Date?
        if let picked = newTodoDueDate {
            due = picked
        } else if !cal.isDateInToday(selectedDate) {
            due = selectedDate
        } else {
            due = nil
        }
        let t = TodoItem(title: title, dueDate: due)
        context.insert(t)
        try? context.save()
        newTodoTitle = ""
        newTodoDueDate = nil
        inputFocused = false
    }

    // MARK: - Row

    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(spacing: 12) {
            Button {
                todo.completed.toggle()
                try? context.save()
                if let habit = todo.habit {
                    checkAutoCompleteFromTasks(habit)
                }
            } label: {
                Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(todo.completed ? Color(hex: "#3aff9e") : Color(hex: "#6b6b80"))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .font(.system(size: 15))
                    .foregroundStyle(todo.completed ? Color(hex: "#6b6b80") : Color(hex: "#f0f0f5"))
                    .strikethrough(todo.completed)

                HStack(spacing: 6) {
                    if let habit = todo.habit {
                        HStack(spacing: 3) {
                            Image(systemName: habit.icon)
                                .font(.system(size: 9))
                            Text(habit.name)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Color(hex: habit.colorHex))
                    }
                    if let due = todo.dueDate {
                        let overdue = due < Date() && !todo.completed && !cal.isDateInToday(due)
                        Text(dueDateLabel(due))
                            .font(.system(size: 11))
                            .foregroundStyle(overdue ? Color(hex: "#ff5c3a") : Color(hex: "#6b6b80"))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { editingTodo = todo }

            Spacer()

            if todo.habit == nil {
                Button { context.delete(todo); try? context.save() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#6b6b80").opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .darkCard()
    }

    private func checkAutoCompleteFromTasks(_ habit: Habit) {
        habit.syncAutoComplete(context: context)
    }

    private func dueDateLabel(_ date: Date) -> String {
        if cal.isDateInToday(date) { return "Сегодня" }
        if cal.isDateInTomorrow(date) { return "Завтра" }
        if cal.isDateInYesterday(date) { return "Вчера" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMM"
        return df.string(from: date)
    }

    private var emptyState: some View {
        let isToday = cal.isDateInToday(selectedDate)
        return VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: "#6b6b80"))
            Text(isToday ? "Нет задач на сегодня" : "Нет задач на эту дату")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Введите задачу выше и нажмите +")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#6b6b80"))
        }
        .padding(30)
        .darkCard()
    }
}

// MARK: - Goals View

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeeklyGoal.createdAt, order: .reverse) private var allGoals: [WeeklyGoal]

    @State private var showAddGoal = false
    @State private var editingGoal: WeeklyGoal?

    private func activeGoals(for period: GoalPeriod) -> [WeeklyGoal] {
        allGoals.filter { $0.period == period && $0.isCurrentPeriod }
    }

    private var pastGoals: [WeeklyGoal] {
        allGoals.filter { !$0.isCurrentPeriod }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(GoalPeriod.allCases, id: \.rawValue) { period in
                            let goals = activeGoals(for: period)
                            if !goals.isEmpty {
                                periodSection(period, goals: goals)
                            }
                        }

                        if activeGoals(for: .week).isEmpty && activeGoals(for: .month).isEmpty && activeGoals(for: .year).isEmpty {
                            emptyState
                        }

                        if !pastGoals.isEmpty {
                            Text("ПРОШЛЫЕ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                            ForEach(pastGoals.prefix(10)) { goal in goalCard(goal) }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("ЦЕЛИ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddGoal = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                }
            }
            .sheet(isPresented: $showAddGoal) {
                AddGoalSheet()
            }
            .sheet(item: $editingGoal) { goal in
                EditGoalSheet(goal: goal)
            }
            .onAppear { renewExpiredGoals() }
        }
        .preferredColorScheme(.dark)
    }

    private func periodSection(_ period: GoalPeriod, goals: [WeeklyGoal]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: period.icon)
                    .font(.system(size: 10))
                Text(period.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
            }
            .foregroundStyle(Color(hex: "#6b6b80"))

            ForEach(goals) { goal in goalCard(goal) }
        }
    }

    private func goalCard(_ goal: WeeklyGoal) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "#f0f0f5"))
                    if !goal.isCurrentPeriod {
                        Text(goal.period.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { editingGoal = goal }

                Spacer()

                Text("\(goal.currentCount)/\(goal.targetCount)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(goal.progress >= 1 ? Color(hex: "#3aff9e") : Color(hex: "#f0f0f5"))

                Button {
                    context.delete(goal)
                    try? context.save()
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "#6b6b80").opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#1a1a24"))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(goal.progress >= 1 ? Color(hex: "#3aff9e") : Color(hex: "#ff5c3a"))
                        .frame(width: geo.size.width * goal.progress, height: 8)
                }
            }
            .frame(height: 8)

            if goal.isCurrentPeriod {
                HStack(spacing: 8) {
                    Button {
                        goal.currentCount = max(0, goal.currentCount - 1)
                        try? context.save()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if goal.progress >= 1 {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(hex: "#3aff9e"))
                    }

                    Spacer()

                    Button {
                        goal.currentCount += 1
                        try? context.save()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color(hex: "#ff5c3a"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .darkCard()
    }

    private func renewExpiredGoals() {
        var changed = false
        for goal in allGoals {
            if goal.renewIfNeeded() { changed = true }
        }
        if changed { try? context.save() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: "#6b6b80"))
            Text("Нет активных целей")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#f0f0f5"))
            Text("Добавьте цель на неделю, месяц или год")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#6b6b80"))
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .darkCard()
    }
}

// MARK: - Add Goal Sheet

struct AddGoalSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var targetText = "7"
    @State private var period: GoalPeriod = .week

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ЦЕЛЬ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                        TextField("Название", text: $title)
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                            .padding(12)
                            .background(Color(hex: "#1a1a24"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ПЕРИОД")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                        HStack(spacing: 8) {
                            ForEach(GoalPeriod.allCases, id: \.rawValue) { p in
                                Button {
                                    period = p
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: p.icon)
                                            .font(.system(size: 11))
                                        Text(p.label)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(period == p ? .white : Color(hex: "#6b6b80"))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(period == p ? Color(hex: "#ff5c3a") : Color(hex: "#1a1a24"))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("СКОЛЬКО РАЗ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                        TextField("7", text: $targetText)
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(Color(hex: "#1a1a24"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Spacer()
                }
                .padding(16)
            }
            .dismissKeyboardOnTap()
            .navigationTitle("Новая цель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        let g = WeeklyGoal(title: title.trimmingCharacters(in: .whitespaces), targetCount: max(1, Int(targetText) ?? 7), period: period)
                        context.insert(g)
                        try? context.save()
                        dismiss()
                    }
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

// MARK: - Edit Habit Sheet

struct EditHabitSheet: View {
    @Bindable var habit: Habit
    let colors: [String]
    let icons: [String]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedIcon: String = ""
    @State private var selectedColor: String = ""
    @State private var newTodoTitle: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("НАЗВАНИЕ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            TextField("Привычка", text: $name)
                                .font(.system(size: 16))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                                .padding(12)
                                .background(Color(hex: "#1a1a24"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ПОДЗАДАЧИ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)

                            ForEach(habit.linkedTodos.sorted { $0.createdAt < $1.createdAt }) { todo in
                                HStack(spacing: 8) {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(hex: "#6b6b80"))
                                    Text(todo.title)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(hex: "#f0f0f5"))
                                    Spacer()
                                    Button {
                                        habit.linkedTodos.removeAll { $0.id == todo.id }
                                        todo.habit = nil
                                        context.delete(todo)
                                        try? context.save()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color(hex: "#6b6b80").opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(Color(hex: "#1a1a24"))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            HStack(spacing: 8) {
                                TextField("Новая подзадача...", text: $newTodoTitle)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(hex: "#f0f0f5"))
                                    .submitLabel(.done)
                                    .onSubmit { addLinkedTodo() }
                                Button { addLinkedTodo() } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty ? Color(hex: "#6b6b80") : Color(hex: selectedColor))
                                }
                                .buttonStyle(.plain)
                                .disabled(newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            .padding(10)
                            .background(Color(hex: "#1a1a24"))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ИКОНКА")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                                ForEach(icons, id: \.self) { icon in
                                    Button {
                                        selectedIcon = icon
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.system(size: 18))
                                            .foregroundStyle(selectedIcon == icon ? Color(hex: selectedColor) : Color(hex: "#6b6b80"))
                                            .frame(width: 44, height: 44)
                                            .background(selectedIcon == icon ? Color(hex: selectedColor).opacity(0.15) : Color(hex: "#1a1a24"))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ЦВЕТ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            HStack(spacing: 10) {
                                ForEach(colors, id: \.self) { color in
                                    Button {
                                        selectedColor = color
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: color))
                                            .frame(width: 32, height: 32)
                                            .overlay(
                                                Circle().stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .dismissKeyboardOnTap()
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        habit.name = name.trimmingCharacters(in: .whitespaces)
                        habit.icon = selectedIcon
                        habit.colorHex = selectedColor
                        try? context.save()
                        dismiss()
                    }
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .onAppear {
            name = habit.name
            selectedIcon = habit.icon
            selectedColor = habit.colorHex
        }
    }

    private func addLinkedTodo() {
        let title = newTodoTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let todo = TodoItem(title: title)
        todo.habit = habit
        context.insert(todo)
        habit.linkedTodos.append(todo)
        try? context.save()
        newTodoTitle = ""
    }
}

// MARK: - Edit Todo Sheet

struct EditTodoSheet: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var priority: Int = 0
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ЗАДАЧА")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            TextField("Название", text: $title)
                                .font(.system(size: 16))
                                .foregroundStyle(Color(hex: "#f0f0f5"))
                                .padding(12)
                                .background(Color(hex: "#1a1a24"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ПРИОРИТЕТ")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#6b6b80"))
                                .tracking(1)
                            HStack(spacing: 8) {
                                ForEach([(0, "Обычный", "#5b8cff"), (1, "Средний", "#ffb830"), (2, "Высокий", "#ff5c3a")], id: \.0) { p in
                                    Button {
                                        priority = p.0
                                    } label: {
                                        Text(p.1)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(priority == p.0 ? .white : Color(hex: "#6b6b80"))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(priority == p.0 ? Color(hex: p.2) : Color(hex: "#1a1a24"))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $hasDueDate) {
                                Text("ДЕДЛАЙН")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: "#6b6b80"))
                                    .tracking(1)
                            }
                            .tint(Color(hex: "#ff5c3a"))

                            if hasDueDate {
                                DatePicker("", selection: $dueDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .tint(Color(hex: "#ff5c3a"))
                            }
                        }
                    }
                    .dismissKeyboardOnTap()
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        todo.title = title.trimmingCharacters(in: .whitespaces)
                        todo.priority = priority
                        todo.dueDate = hasDueDate ? dueDate : nil
                        try? context.save()
                        dismiss()
                    }
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
        .onAppear {
            title = todo.title
            priority = todo.priority
            hasDueDate = todo.dueDate != nil
            dueDate = todo.dueDate ?? Date()
        }
    }
}

// MARK: - Edit Goal Sheet

struct EditGoalSheet: View {
    @Bindable var goal: WeeklyGoal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var targetText: String = ""
    @State private var period: GoalPeriod = .week

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0e12").ignoresSafeArea()
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ЦЕЛЬ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                        TextField("Название", text: $title)
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                            .padding(12)
                            .background(Color(hex: "#1a1a24"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ПЕРИОД")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                        HStack(spacing: 8) {
                            ForEach(GoalPeriod.allCases, id: \.rawValue) { p in
                                Button {
                                    period = p
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: p.icon)
                                            .font(.system(size: 11))
                                        Text(p.label)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(period == p ? .white : Color(hex: "#6b6b80"))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(period == p ? Color(hex: "#ff5c3a") : Color(hex: "#1a1a24"))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("СКОЛЬКО РАЗ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#6b6b80"))
                            .tracking(1)
                        TextField("7", text: $targetText)
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "#f0f0f5"))
                            .keyboardType(.numberPad)
                            .padding(12)
                            .background(Color(hex: "#1a1a24"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Spacer()
                }
                .dismissKeyboardOnTap()
                .padding(16)
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color(hex: "#6b6b80"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        goal.title = title.trimmingCharacters(in: .whitespaces)
                        goal.targetCount = max(1, Int(targetText) ?? goal.targetCount)
                        goal.period = period
                        try? context.save()
                        dismiss()
                    }
                    .foregroundStyle(Color(hex: "#ff5c3a"))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
        .onAppear {
            title = goal.title
            targetText = "\(goal.targetCount)"
            period = goal.period
        }
    }
}
