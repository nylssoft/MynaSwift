import SwiftUI

struct DiaryView: View {
    let service: Servicing
    let authentication: AuthenticationResponse?
    let userInfo: UserInfoResponse?
    let dataProtectionSecurityKey: String
    let isLoggedIn: Bool
    let onActivityStatusChange: (String?) -> Void
    let onStatusMessage: (String) -> Void

    @State private var monthDate = Date()
    @State private var daysWithEntries: Set<Int> = []
    @State private var selectedDay: Int?
    @State private var entryDraft = ""
    @State private var loadedEntry = ""
    @State private var isEditingSelection = false

    @State private var isLoadingDays = false
    @State private var isLoadingEntry = false
    @State private var isSavingEntry = false
    @State private var isDeletingEntry = false
    @State private var errorMessage: String?
    @State private var hasLoadedMonth = false

    private var token: String? {
        authentication?.token
    }

    private var passwordManagerSalt: String? {
        userInfo?.passwordManagerSalt
    }

    private var hasDiaryFeature: Bool {
        userInfo?.hasDiary ?? false
    }

    private var canManageDiary: Bool {
        guard isLoggedIn,
            hasDiaryFeature,
            let token,
            !token.isEmpty,
            let passwordManagerSalt,
            !passwordManagerSalt.isEmpty,
            !dataProtectionSecurityKey.isEmpty
        else {
            return false
        }
        return true
    }

    private var isBusy: Bool {
        isLoadingDays || isLoadingEntry || isSavingEntry || isDeletingEntry
    }

    private var syncContextID: String {
        "\(isLoggedIn)|\(token ?? "")|\(passwordManagerSalt ?? "")|\(dataProtectionSecurityKey)|\(hasDiaryFeature)"
    }

    private var displayedYear: Int {
        calendar.component(.year, from: monthDate)
    }

    private var displayedMonth: Int {
        calendar.component(.month, from: monthDate)
    }

    private var monthTitle: String {
        monthTitleFormatter.string(from: monthDate)
    }

    private var weekdaySymbolsMondayFirst: [String] {
        let symbols =
            weekdayFormatter.shortStandaloneWeekdaySymbols
            ?? weekdayFormatter.shortWeekdaySymbols
            ?? []
        guard symbols.count == 7 else {
            return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        }
        return Array(symbols[1...6] + symbols[0...0])
    }

    private var selectedDateTitle: String {
        guard let selectedDate else {
            return L10n.s("diary.noDaySelected")
        }
        return selectedDateFormatter.string(from: selectedDate)
    }

    private var deleteEnabled: Bool {
        canManageDiary && selectedDay != nil && !isBusy && !entryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedDate: Date? {
        guard let selectedDay else {
            return nil
        }
        return dateFor(year: displayedYear, month: displayedMonth, day: selectedDay)
    }

    private var calendarCells: [Int?] {
        let totalDays = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 0
        let firstDayDate = dateFor(year: displayedYear, month: displayedMonth, day: 1) ?? monthDate
        let weekday = calendar.component(.weekday, from: firstDayDate)
        let mondayOffset = (weekday + 5) % 7
        var cells = Array(repeating: Optional<Int>.none, count: mondayOffset)
        cells.append(contentsOf: (1...totalDays).map(Optional.some))
        while !cells.count.isMultiple(of: 7) {
            cells.append(nil)
        }
        return cells
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.s("section.diaryEntries"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        Task {
                            await loadDiaryDays(force: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("diary.reload"))
                    .disabled(isBusy || !isLoggedIn)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                monthNavigationBar
                weekdayHeader
                calendarGrid
            }
            .frame(minWidth: 320, idealWidth: 360)

            Divider()

            diaryEntryEditor
        }
        .task(id: syncContextID) {
            monthDate = startOfMonth(Date())
            daysWithEntries = []
            selectedDay = nil
            entryDraft = ""
            loadedEntry = ""
            isEditingSelection = false
            hasLoadedMonth = false
            await loadDiaryDays(force: true)
        }
    }

    private var monthNavigationBar: some View {
        HStack(spacing: 12) {
            Text(monthTitle)
                .font(.headline)
                .frame(minWidth: 170, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                Task {
                    await moveMonth(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .help(L10n.s("diary.previousMonth"))
            .disabled(isBusy)

            Button {
                Task {
                    await moveMonth(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .help(L10n.s("diary.nextMonth"))
            .disabled(isBusy)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(weekdaySymbolsMondayFirst, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear
                        .frame(height: 36)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let isToday = isDayToday(day)
        let hasEntry = daysWithEntries.contains(day)
        let isSelected = selectedDay == day
        let textColor: Color = {
            if isSelected {
                return .primary
            }
            return hasEntry ? .primary : .primary.opacity(0.45)
        }()

        Button {
            Task {
                await selectDay(day)
            }
        } label: {
            Text("\(day)\(isToday ? "*" : "")")
                .font(.body)
                .fontWeight(hasEntry || isSelected ? .bold : .regular)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isBusy || !canManageDiary)
        .help(hasEntry ? L10n.s("diary.dayHasEntry") : L10n.s("diary.dayNoEntry"))
    }

    private var diaryEntryEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedDateTitle)
                    .font(.headline)
                Spacer(minLength: 0)

                Button {
                    Task {
                        await toggleEditSelection()
                    }
                } label: {
                    Image(systemName: isEditingSelection ? "checkmark" : "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help(
                    isEditingSelection
                        ? L10n.s("diary.help.saveChanges")
                        : L10n.s("diary.help.edit")
                )
                .disabled(!canManageDiary || selectedDay == nil || isBusy)

                Button(role: .destructive) {
                    Task {
                        await deleteEntry()
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help(L10n.s("common.delete"))
                .disabled(!deleteEnabled)
            }

            if !canManageDiary {
                Text(diaryPrerequisiteMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else if selectedDay == nil {
                Text(L10n.s("diary.selectDayPrompt"))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                if isEditingSelection {
                    TextEditor(text: $entryDraft)
                        .font(.body)
                        .frame(minHeight: 220)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .disabled(isBusy)
                } else {
                    Text(readOnlyEntryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var diaryPrerequisiteMessage: String {
        if !isLoggedIn {
            return L10n.s("diary.error.loginRequired")
        }
        if !hasDiaryFeature {
            return L10n.s("diary.error.notAvailable")
        }
        if dataProtectionSecurityKey.isEmpty {
            return L10n.s("diary.error.setKey")
        }
        return L10n.s("diary.error.setKey")
    }

    @MainActor
    private func moveMonth(by delta: Int) async {
        guard let nextMonth = calendar.date(byAdding: .month, value: delta, to: monthDate) else {
            return
        }
        monthDate = startOfMonth(nextMonth)
        selectedDay = nil
        entryDraft = ""
        loadedEntry = ""
        isEditingSelection = false
        await loadDiaryDays(force: true)
    }

    @MainActor
    private func toggleEditSelection() async {
        guard selectedDay != nil else {
            return
        }
        if isEditingSelection {
            let didSave = await saveEntry()
            if didSave {
                isEditingSelection = false
            }
        } else {
            isEditingSelection = true
        }
    }

    @MainActor
    private func selectDay(_ day: Int) async {
        guard canManageDiary,
            let token,
            let passwordManagerSalt
        else {
            errorMessage = diaryPrerequisiteMessage
            return
        }

        if selectedDay == day && !isLoadingEntry {
            return
        }

        selectedDay = day
        errorMessage = nil
        isEditingSelection = false

        if !daysWithEntries.contains(day) {
            entryDraft = ""
            loadedEntry = ""
            return
        }

        isLoadingEntry = true
        onActivityStatusChange(L10n.s("diary.loadingEntry"))
        defer {
            isLoadingEntry = false
            onActivityStatusChange(nil)
        }

        do {
            let diary = try await service.getDiaryEntry(
                token: token,
                year: displayedYear,
                month: displayedMonth,
                day: day,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            entryDraft = diary.entry
            loadedEntry = diary.entry
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L10n.s("diary.error.loadEntry")
            entryDraft = ""
            loadedEntry = ""
        }
    }

    @MainActor
    private func loadDiaryDays(force: Bool) async {
        if isLoadingDays {
            return
        }
        if hasLoadedMonth && !force {
            return
        }

        guard canManageDiary,
            let token
        else {
            daysWithEntries = []
            hasLoadedMonth = false
            errorMessage = diaryPrerequisiteMessage
            return
        }

        isLoadingDays = true
        onActivityStatusChange(L10n.s("diary.loadingDays"))
        errorMessage = nil
        defer {
            isLoadingDays = false
            onActivityStatusChange(nil)
        }

        do {
            let days = try await service.getDiaryDays(
                token: token,
                year: displayedYear,
                month: displayedMonth)
            daysWithEntries = Set(days)
            hasLoadedMonth = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L10n.s("diary.error.loadDays")
            daysWithEntries = []
            hasLoadedMonth = false
        }
    }

    @MainActor
    private func saveEntry() async -> Bool {
        guard canManageDiary,
            let token,
            let passwordManagerSalt,
            let selectedDay
        else {
            errorMessage = diaryPrerequisiteMessage
            return false
        }

        if isSavingEntry {
            return false
        }

        isSavingEntry = true
        onActivityStatusChange(L10n.s("diary.saving"))
        errorMessage = nil
        defer {
            isSavingEntry = false
            onActivityStatusChange(nil)
        }

        do {
            try await service.saveDiaryEntry(
                token: token,
                year: displayedYear,
                month: displayedMonth,
                day: selectedDay,
                entry: entryDraft,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            loadedEntry = entryDraft
            if entryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                daysWithEntries.remove(selectedDay)
            } else {
                daysWithEntries.insert(selectedDay)
            }
            onStatusMessage(L10n.s("diary.status.saved"))
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L10n.s("diary.error.save")
            return false
        }
    }

    @MainActor
    private func deleteEntry() async {
        guard canManageDiary,
            let token,
            let passwordManagerSalt,
            let selectedDay
        else {
            errorMessage = diaryPrerequisiteMessage
            return
        }

        if isDeletingEntry {
            return
        }

        isDeletingEntry = true
        onActivityStatusChange(L10n.s("diary.deleting"))
        errorMessage = nil
        defer {
            isDeletingEntry = false
            onActivityStatusChange(nil)
        }

        do {
            try await service.saveDiaryEntry(
                token: token,
                year: displayedYear,
                month: displayedMonth,
                day: selectedDay,
                entry: "",
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            entryDraft = ""
            loadedEntry = ""
            daysWithEntries.remove(selectedDay)
            onStatusMessage(L10n.s("diary.status.deleted"))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L10n.s("diary.error.delete")
        }
    }

    private func isDayToday(_ day: Int) -> Bool {
        guard let date = dateFor(year: displayedYear, month: displayedMonth, day: day) else {
            return false
        }
        return calendar.isDateInToday(date)
    }

    private func dateFor(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private func startOfMonth(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    private var monthTitleFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }

    private var selectedDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        return formatter
    }

    private var weekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        return formatter
    }

    private var readOnlyEntryText: String {
        let trimmed = entryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.s("common.notSet") : entryDraft
    }
}
