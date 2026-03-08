import AppKit
import SwiftUI

struct AppointmentsView: View {
    let service: Servicing
    let authentication: AuthenticationResponse?
    let userInfo: UserInfoResponse?
    let dataProtectionSecurityKey: String
    let isLoggedIn: Bool
    let onActivityStatusChange: (String?) -> Void
    let onStatusMessage: (String) -> Void

    @State private var appointments: [AppointmentResponse] = []
    @State private var hasLoadedAppointments = false
    @State private var appointmentsErrorMessage: String?

    @State private var selectedUUID: String?
    @State private var editorAppointmentUUID: String?
    @State private var isEditing = false

    @State private var descriptionDraft = ""
    @State private var participantsDraft = ""
    @State private var optionDatesDraft: [Date] = []
    @State private var calendarMonth = Date()

    @State private var isLoadingAppointments = false
    @State private var isSavingAppointment = false
    @State private var isDeletingAppointment = false

    @State private var showDeleteConfirmation = false
    @State private var readOnlyMonthStart: Date?

    private var token: String? {
        authentication?.token
    }

    private var passwordManagerSalt: String? {
        userInfo?.passwordManagerSalt
    }

    private var canManageAppointments: Bool {
        guard isLoggedIn,
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
        isLoadingAppointments || isSavingAppointment || isDeletingAppointment
    }

    private var syncContextID: String {
        "\(isLoggedIn)|\(token ?? "")|\(passwordManagerSalt ?? "")"
    }

    private var selectedAppointment: AppointmentResponse? {
        guard let selectedUUID else {
            return nil
        }
        return appointments.first { $0.uuid == selectedUUID }
    }

    private var appointmentTitleForDelete: String {
        guard let selectedAppointment,
            let description = selectedAppointment.definition?.description,
            !description.isEmpty
        else {
            return L10n.s("appointments.thisAppointment")
        }
        return description
    }

    private var sortedAppointments: [AppointmentResponse] {
        appointments.sorted { lhs, rhs in
            let left = lhs.definition?.description ?? ""
            let right = rhs.definition?.description ?? ""
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.s("section.appointments"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        Task { await loadAppointments(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("appointments.reload"))
                    .disabled(isBusy || !isLoggedIn)

                    Button {
                        startCreatingAppointment()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("appointments.add"))
                    .disabled(isBusy || !canManageAppointments)
                }

                if let appointmentsErrorMessage {
                    Text(appointmentsErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if appointments.isEmpty {
                    Text(L10n.s("appointments.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 2)
                } else {
                    List(sortedAppointments) { item in
                        Button {
                            selectAppointment(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.definition?.description ?? L10n.s("appointments.noDescription"))
                                    .font(.headline)
                                let participants = participantNames(from: item)
                                if !participants.isEmpty {
                                    Text(participants)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedUUID == item.uuid ? Color.primary.opacity(0.12) : Color.clear)
                        .disabled(isBusy)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 320)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(detailTitle)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    if isEditing {
                        Button {
                            Task { await saveAppointment() }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.s("common.save"))
                        .disabled(isBusy || !canManageAppointments)
                    } else if let selectedAppointment {
                        Button {
                            startEditingAppointment(selectedAppointment)
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.s("appointments.edit"))
                        .disabled(isBusy)

                    }

                    if selectedAppointment != nil {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help(L10n.s("appointments.delete"))
                        .disabled(isBusy)
                    }
                }

                if isEditing {
                    TextField(L10n.s("appointments.field.description"), text: $descriptionDraft)

                    TextField(L10n.s("appointments.field.participants"), text: $participantsDraft)

                    VStack(spacing: 8) {
                        HStack {
                            Text(monthTitle)
                                .font(.headline)

                            Spacer(minLength: 0)

                            Button {
                                shiftCalendarMonth(by: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(.plain)
                            .help(L10n.s("appointments.previousMonth"))
                            .disabled(isBusy)

                            Button {
                                shiftCalendarMonth(by: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.plain)
                            .help(L10n.s("appointments.nextMonth"))
                            .disabled(isBusy)
                        }

                        AppointmentMonthGridView(
                            monthDate: calendarMonth,
                            selectedDates: Set(optionDatesDraft.map(normalizedDate)),
                            isBusy: isBusy,
                            onToggleDay: { date in
                                toggleOptionDate(date)
                            })
                    }

                    if optionDatesDraft.isEmpty {
                        Text(L10n.s("appointments.options.empty"))
                            .foregroundStyle(.secondary)
                    }

                } else if let selectedAppointment {
                    DetailRow(label: L10n.s("appointments.field.description"), value: selectedAppointment.definition?.description ?? "")
                    DetailRow(label: L10n.s("appointments.field.participants"), value: participantNames(from: selectedAppointment))
                    if let modified = selectedAppointment.modifiedUtc ?? selectedAppointment.createdUtc,
                        !modified.isEmpty
                    {
                        DetailRow(
                            label: L10n.s("appointments.field.modified"),
                            value: DateFormattingUtility.displayDate(fromUTCISOString: modified) ?? modified)
                    }

                    Text(L10n.s("appointments.field.options"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    let groupedOptionDates = groupedOptionDatesByMonth(from: selectedAppointment)
                    let availableMonths = groupedOptionDates.keys.sorted()
                    if availableMonths.isEmpty {
                        Text(L10n.s("appointments.options.empty"))
                            .foregroundStyle(.secondary)
                    } else {
                        let currentMonth = activeReadOnlyMonth(in: availableMonths)
                        let currentMonthDates = groupedOptionDates[currentMonth] ?? []

                        VStack(spacing: 8) {
                            HStack {
                                Text(monthTitle(for: currentMonth))
                                    .font(.headline)

                                Spacer(minLength: 0)

                                Button {
                                    shiftReadOnlyMonth(by: -1, availableMonths: availableMonths)
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .buttonStyle(.plain)
                                .help(L10n.s("appointments.previousMonth"))
                                .disabled(
                                    isBusy
                                        || !hasPreviousReadOnlyMonth(
                                            current: currentMonth,
                                            availableMonths: availableMonths)
                                )

                                Button {
                                    shiftReadOnlyMonth(by: 1, availableMonths: availableMonths)
                                } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .buttonStyle(.plain)
                                .help(L10n.s("appointments.nextMonth"))
                                .disabled(
                                    isBusy
                                        || !hasNextReadOnlyMonth(
                                            current: currentMonth,
                                            availableMonths: availableMonths)
                                )
                            }

                            AppointmentMonthGridView(
                                monthDate: currentMonth,
                                selectedDates: currentMonthDates,
                                isBusy: true,
                                onToggleDay: { _ in })
                        }
                        .frame(minHeight: 220)
                    }

                    if let url = voteURL(for: selectedAppointment) {
                        HStack {
                            Button(L10n.s("appointments.openVoteURL")) {
                                openVoteURL(url)
                            }
                            .disabled(isBusy)

                            Button(L10n.s("appointments.copyVoteURL")) {
                                copyVoteURL(url)
                            }
                            .disabled(isBusy)
                        }
                    }
                } else {
                    Text(L10n.s("appointments.selectPrompt"))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)
            }
        }
        .alert(L10n.s("appointments.delete.title"), isPresented: $showDeleteConfirmation) {
            Button(L10n.s("common.cancel"), role: .cancel) {}
            Button(L10n.s("common.delete"), role: .destructive) {
                Task { await deleteSelectedAppointment() }
            }
        } message: {
            Text(String(format: L10n.s("appointments.delete.message.format"), appointmentTitleForDelete))
        }
        .task(id: syncContextID) {
            hasLoadedAppointments = false
            selectedUUID = nil
            isEditing = false
            readOnlyMonthStart = nil
            await loadAppointments(force: true)
        }
    }

    private var detailTitle: String {
        if editorAppointmentUUID == nil && isEditing {
            return L10n.s("appointments.new")
        }
        if let selectedAppointment,
            let description = selectedAppointment.definition?.description,
            !description.isEmpty,
            !isEditing
        {
            return description
        }
        return L10n.s("appointments.detail")
    }

    @MainActor
    private func loadAppointments(force: Bool) async {
        if isLoadingAppointments {
            return
        }
        if hasLoadedAppointments && !force {
            return
        }
        guard canManageAppointments,
            let token,
            let passwordManagerSalt
        else {
            appointmentsErrorMessage = isLoggedIn
                ? L10n.s("appointments.error.setKey")
                : L10n.s("appointments.error.loginRequired")
            appointments = []
            hasLoadedAppointments = false
            selectedUUID = nil
            return
        }

        isLoadingAppointments = true
        onActivityStatusChange(L10n.s("appointments.loading"))
        appointmentsErrorMessage = nil
        defer {
            isLoadingAppointments = false
            onActivityStatusChange(nil)
        }

        do {
            appointments = try await service.getAppointments(
                token: token,
                encryptionKey: dataProtectionSecurityKey,
                passwordManagerSalt: passwordManagerSalt)
            hasLoadedAppointments = true
            if let selectedUUID,
                !appointments.contains(where: { $0.uuid == selectedUUID })
            {
                self.selectedUUID = nil
            }
        } catch {
            appointmentsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("appointments.error.load")
            appointments = []
            hasLoadedAppointments = false
            selectedUUID = nil
        }
    }

    private func participantNames(from appointment: AppointmentResponse) -> String {
        (appointment.definition?.participants ?? []).map(\.username).joined(separator: ", ")
    }

    private func optionDates(from appointment: AppointmentResponse) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let options = appointment.definition?.options ?? []
        var dates: [Date] = []
        for option in options {
            for day in option.days {
                var components = DateComponents()
                components.year = option.year
                components.month = option.month
                components.day = day
                components.hour = 12
                if let date = calendar.date(from: components) {
                    dates.append(date)
                }
            }
        }
        return Array(Set(dates)).sorted()
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("LLLL y")
        return formatter.string(from: date)
    }

    private func groupedOptionDatesByMonth(from appointment: AppointmentResponse) -> [Date: Set<Date>] {
        let calendar = Calendar(identifier: .gregorian)
        var grouped: [Date: Set<Date>] = [:]

        for date in optionDates(from: appointment) {
            let normalized = calendar.startOfDay(for: date)
            let monthStart = startOfMonth(for: normalized)
            var set = grouped[monthStart] ?? []
            set.insert(normalized)
            grouped[monthStart] = set
        }

        return grouped
    }

    private func activeReadOnlyMonth(in availableMonths: [Date]) -> Date {
        guard let first = availableMonths.first else {
            return startOfMonth(for: Date())
        }
        if let readOnlyMonthStart,
            availableMonths.contains(readOnlyMonthStart)
        {
            return readOnlyMonthStart
        }
        return first
    }

    private func hasPreviousReadOnlyMonth(current: Date, availableMonths: [Date]) -> Bool {
        guard let index = availableMonths.firstIndex(of: current) else {
            return false
        }
        return index > 0
    }

    private func hasNextReadOnlyMonth(current: Date, availableMonths: [Date]) -> Bool {
        guard let index = availableMonths.firstIndex(of: current) else {
            return false
        }
        return index < availableMonths.count - 1
    }

    private func shiftReadOnlyMonth(by value: Int, availableMonths: [Date]) {
        let current = activeReadOnlyMonth(in: availableMonths)
        guard let index = availableMonths.firstIndex(of: current) else {
            readOnlyMonthStart = availableMonths.first
            return
        }
        let nextIndex = index + value
        guard availableMonths.indices.contains(nextIndex) else {
            return
        }
        readOnlyMonthStart = availableMonths[nextIndex]
    }

    private func selectAppointment(_ appointment: AppointmentResponse) {
        selectedUUID = appointment.uuid
        isEditing = false
        editorAppointmentUUID = nil
        readOnlyMonthStart = groupedOptionDatesByMonth(from: appointment).keys.sorted().first
    }

    private func startCreatingAppointment() {
        isEditing = true
        editorAppointmentUUID = nil
        selectedUUID = nil
        readOnlyMonthStart = nil
        descriptionDraft = ""
        participantsDraft = ""
        optionDatesDraft = []
        calendarMonth = startOfMonth(for: Date())
    }

    private func startEditingAppointment(_ appointment: AppointmentResponse) {
        isEditing = true
        editorAppointmentUUID = appointment.uuid
        readOnlyMonthStart = nil
        descriptionDraft = appointment.definition?.description ?? ""
        participantsDraft = participantNames(from: appointment)
        optionDatesDraft = optionDates(from: appointment)
        calendarMonth = startOfMonth(for: optionDatesDraft.first ?? Date())
    }

    private func normalizedDate(_ date: Date) -> Date {
        Calendar(identifier: .gregorian).startOfDay(for: date)
    }

    private func toggleOptionDate(_ date: Date) {
        let normalized = normalizedDate(date)
        if optionDatesDraft.contains(where: { normalizedDate($0) == normalized }) {
            optionDatesDraft.removeAll { normalizedDate($0) == normalized }
        } else {
            optionDatesDraft.append(normalized)
        }
    }

    private func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: calendarMonth)
    }

    private func shiftCalendarMonth(by value: Int) {
        let calendar = Calendar(identifier: .gregorian)
        if let shifted = calendar.date(byAdding: .month, value: value, to: calendarMonth) {
            calendarMonth = startOfMonth(for: shifted)
        }
    }

    private func parsedParticipants() -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n\t ")
        let parts = participantsDraft
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(parts)).sorted()
    }

    @MainActor
    private func saveAppointment() async {
        guard canManageAppointments,
            let token,
            let passwordManagerSalt
        else {
            appointmentsErrorMessage = L10n.s("appointments.error.setKey")
            return
        }
        if isSavingAppointment {
            return
        }

        let description = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            appointmentsErrorMessage = L10n.s("appointments.error.descriptionMissing")
            return
        }
        let participants = parsedParticipants()
        guard !participants.isEmpty else {
            appointmentsErrorMessage = L10n.s("appointments.error.participantsMissing")
            return
        }
        guard !optionDatesDraft.isEmpty else {
            appointmentsErrorMessage = L10n.s("appointments.error.optionsMissing")
            return
        }

        isSavingAppointment = true
        onActivityStatusChange(L10n.s("appointments.saving"))
        appointmentsErrorMessage = nil
        defer {
            isSavingAppointment = false
            onActivityStatusChange(nil)
        }

        do {
            if let uuid = editorAppointmentUUID,
                let appointment = appointments.first(where: { $0.uuid == uuid })
            {
                try await service.updateAppointment(
                    token: token,
                    appointment: appointment,
                    description: description,
                    participants: participants,
                    options: optionDatesDraft)
                selectedUUID = uuid
                onStatusMessage(L10n.s("appointments.status.updated"))
            } else {
                let uuid = try await service.createAppointment(
                    token: token,
                    description: description,
                    participants: participants,
                    options: optionDatesDraft,
                    encryptionKey: dataProtectionSecurityKey,
                    passwordManagerSalt: passwordManagerSalt)
                selectedUUID = uuid
                onStatusMessage(L10n.s("appointments.status.created"))
            }

            isEditing = false
            editorAppointmentUUID = nil
            hasLoadedAppointments = false
            await loadAppointments(force: true)
        } catch {
            appointmentsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("appointments.error.save")
        }
    }

    @MainActor
    private func deleteSelectedAppointment() async {
        guard let selectedAppointment,
            canManageAppointments,
            let token
        else {
            return
        }
        if isDeletingAppointment {
            return
        }

        isDeletingAppointment = true
        onActivityStatusChange(L10n.s("appointments.deleting"))
        appointmentsErrorMessage = nil
        defer {
            isDeletingAppointment = false
            onActivityStatusChange(nil)
        }

        do {
            try await service.deleteAppointment(token: token, uuid: selectedAppointment.uuid)
            selectedUUID = nil
            hasLoadedAppointments = false
            await loadAppointments(force: true)
            onStatusMessage(L10n.s("appointments.status.deleted"))
        } catch {
            appointmentsErrorMessage =
                (error as? LocalizedError)?.errorDescription ?? L10n.s("appointments.error.delete")
        }
    }

    private func voteURL(for appointment: AppointmentResponse) -> URL? {
        guard let accessToken = appointment.accessToken else {
            return nil
        }
        return service.buildAppointmentVoteURL(accessToken: accessToken)
    }

    private func openVoteURL(_ url: URL) {
        if NSWorkspace.shared.open(url) {
            onStatusMessage(L10n.s("appointments.status.openedVoteURL"))
        } else {
            appointmentsErrorMessage = L10n.s("appointments.error.openVoteURL")
        }
    }

    private func copyVoteURL(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        onStatusMessage(L10n.s("appointments.status.copiedVoteURL"))
    }
}

private struct AppointmentMonthGridView: View {
    let monthDate: Date
    let selectedDates: Set<Date>
    let isBusy: Bool
    let onToggleDay: (Date) -> Void

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale.current
        return c
    }

    private var monthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: monthDate)
        return calendar.date(from: components) ?? monthDate
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    private var firstWeekdayOffset: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    private var weekdaySymbols: [String] {
        var symbols = calendar.standaloneWeekdaySymbols.map { localizedWeekdayAbbreviation($0) }
        let shift = calendar.firstWeekday - 1
        if shift > 0 {
            symbols = Array(symbols[shift...]) + symbols[..<shift]
        }
        return symbols
    }

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: gridColumns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Color.clear
                        .frame(height: 28)
                }

                ForEach(1...daysInMonth, id: \.self) { day in
                    let date = dayDate(day)
                    let normalized = calendar.startOfDay(for: date)
                    Button {
                        onToggleDay(date)
                    } label: {
                        Text("\(day)")
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                selectedDates.contains(normalized)
                                    ? Color.accentColor.opacity(0.25) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dayDate(_ day: Int) -> Date {
        var components = calendar.dateComponents([.year, .month], from: monthStart)
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? monthStart
    }

    private func localizedWeekdayAbbreviation(_ fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 {
            return String(trimmed.prefix(2))
        }
        if let first = trimmed.first {
            return String([first, first])
        }
        return "--"
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
