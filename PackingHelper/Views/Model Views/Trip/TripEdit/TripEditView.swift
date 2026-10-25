import SwiftUI
import SwiftData

struct TripEditView: View {
    // MARK: - Properties
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Trip model (can be nil for new trip creation)
    var trip: Trip?
    @Binding var isDeleted: Bool
    /// Called with the newly inserted trip, before the sheet dismisses. Not called when editing.
    var onCreate: ((Trip) -> Void)?

    // State properties for editing
    @State private var tripName: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(86400 * 5) // 5 days later
    @State private var tripType: TripType = .plane
    @State private var tripAccomodation: TripAccomodation = .hotel
    @State private var destinationLocation: TripLocation?
    /// Staged cover photo; written to the trip only on save. nil = destination map.
    @State private var coverPhotoDraft: CoverPhotoDraft?
    /// Random photo picked for a new trip's destination. Re-picked when the
    /// destination changes, until the user changes or removes the cover photo.
    @State private var autoCoverPhoto: CoverPhotoDraft?
    /// Destination the last pick ran for; `.task` re-runs when the template
    /// step pops back, which shouldn't re-roll the photo.
    @State private var autoCoverDestinationID: PersistentIdentifier?
    @State private var coverPhotoIsUserChosen = false
    /// Set while a pick is in flight; a superseded pick doesn't clear a newer one's.
    @State private var coverPhotoFetchID: UUID?

    // UI State
    @State private var showingDestinationSearch = false
    @State private var showDeleteAlert = false
    @State private var showMovingToPastAlert = false
    @State private var showDiscardConfirmation = false
    /// Form state when the sheet opened; anything different counts as unsaved changes
    @State private var initialSnapshot: EditSnapshot?

    // Template step (new trips only): lists are chosen before the trip exists, applied on create
    @Query(
        filter: #Predicate<PackingList> { $0.template == true },
        sort: [SortDescriptor(\.name)]
    )
    private var templateLists: [PackingList]
    @State private var selectedTemplates: [PackingList] = []
    @State private var showingTemplateStep = false

    @AppStorage("autoCreateDefaultLists") private var autoCreateDefaultLists = false
    @AppStorage("defaultTripCover") private var defaultTripCover = DefaultTripCover.photo.rawValue

    private var isCreating: Bool { trip == nil }
    private var canSave: Bool { destinationLocation != nil }
    private var hasTemplateStep: Bool { isCreating && !templateLists.isEmpty }

    /// Editing an upcoming trip so it has already ended moves it out of the
    /// upcoming list (same cutoff as TripListView's queries), so warn first.
    private var willMoveToPastTrips: Bool {
        guard let trip else { return false }
        return trip.endDate > .now && endDate <= .now
    }

    /// Name falls back to the destination when left blank.
    private var resolvedName: String {
        let trimmed = tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (destinationLocation?.name ?? "Trip") : trimmed
    }

    /// The picker only sets the day, so a new trip returning today could carry a
    /// time that's already passed and land straight in Past Trips. Push it to the
    /// end of today instead.
    private var resolvedEndDate: Date {
        guard isCreating, endDate <= .now else { return endDate }
        let startOfTomorrow = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
        return startOfTomorrow.addingTimeInterval(-1)
    }

    /// The fields a person can edit, reduced to cheap comparable values
    private struct EditSnapshot: Equatable {
        var name: String
        var startDay: Date
        var endDay: Date
        var type: TripType
        var accomodation: TripAccomodation
        var destinationID: PersistentIdentifier?
        var coverPhotoID: UUID?
        var coverFraming: [Double]
        var templateCount: Int
    }

    private var currentSnapshot: EditSnapshot {
        let calendar = Calendar.current
        return EditSnapshot(
            name: tripName,
            startDay: calendar.startOfDay(for: startDate),
            endDay: calendar.startOfDay(for: endDate),
            type: tripType,
            accomodation: tripAccomodation,
            destinationID: destinationLocation?.persistentModelID,
            coverPhotoID: coverPhotoDraft?.uuid,
            coverFraming: coverPhotoDraft.map { [$0.focalX, $0.focalY, $0.zoom] } ?? [],
            templateCount: selectedTemplates.count
        )
    }

    private var hasChanges: Bool {
        guard let initialSnapshot else { return false }
        return currentSnapshot != initialSnapshot
    }

    // MARK: - Initialization
    init(trip: Trip?, isDeleted: Binding<Bool>, onCreate: ((Trip) -> Void)? = nil) {
        self.trip = trip
        self._isDeleted = isDeleted
        self.onCreate = onCreate

        // Initialize state properties from trip if it exists
        if let trip = trip {
            _tripName = State(initialValue: trip.name)
            _startDate = State(initialValue: trip.startDate)
            _endDate = State(initialValue: trip.endDate)
            _tripType = State(initialValue: trip.type)
            _tripAccomodation = State(initialValue: trip.accomodation)
            _destinationLocation = State(initialValue: trip.destination)
            _coverPhotoDraft = State(initialValue: trip.coverPhoto.map { CoverPhotoDraft($0) })
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    destinationSection
                    nameSection
                    coverPhotoSection
                    datesSection
                    transportSection
                    accommodationSection

                    if !isCreating {
                        deleteButton
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
            .navigationDestination(isPresented: $showingTemplateStep) {
                templateStep
            }
            .sheet(isPresented: $showingDestinationSearch) {
                LocationSearchView(location: $destinationLocation, title: "Where to?")
            }
            .task(id: destinationLocation?.persistentModelID) {
                await pickRandomCoverPhoto()
            }
            .onChange(of: coverPhotoDraft) { _, newDraft in
                if newDraft != autoCoverPhoto {
                    coverPhotoIsUserChosen = true
                }
            }
            .navigationTitle(isCreating ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog(
                        isCreating ? "Discard this trip?" : "Discard your changes?",
                        isPresented: $showDiscardConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(isCreating ? "Discard Trip" : "Discard Changes", role: .destructive) {
                            dismiss()
                        }
                        Button("Keep Editing", role: .cancel) { }
                    }
                }
            }
            // Swiping the sheet down would silently drop unsaved edits; Cancel asks first instead
            .interactiveDismissDisabled(hasChanges)
            .onAppear {
                if initialSnapshot == nil {
                    initialSnapshot = currentSnapshot
                }
            }
            .alert("Delete Trip", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteTrip()
                }
            } message: {
                Text("Are you sure you want to delete this trip? This action cannot be undone.")
            }
            .alert("Moving to Past Trips", isPresented: $showMovingToPastAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    saveTrip()
                }
            } message: {
                Text("This trip's return date has passed, so it will no longer appear with your upcoming trips. You can find it under Past Trips on the Trips tab.")
            }
        }
    }

    // MARK: - Destination Section
    var destinationSection: some View {
        formSection("Where to?") {
            Button {
                showingDestinationSearch = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: destinationLocation == nil ? "magnifyingglass" : "mappin.and.ellipse")
                        .foregroundStyle(destinationLocation == nil ? Color.secondary : Color.accentColor)

                    Text(destinationLocation?.name ?? "Search for a city or place")
                        .font(.title3.weight(destinationLocation == nil ? .regular : .semibold))
                        .foregroundStyle(destinationLocation == nil ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer()

                    if destinationLocation != nil {
                        Text("Change")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 15))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Dates Section
    var datesSection: some View {
        formSection("When") {
            TripDateRangePicker(
                startDate: $startDate,
                endDate: $endDate,
                // New trips can't be in the past; existing trips keep their full range
                earliestDay: isCreating ? Calendar.current.startOfDay(for: .now) : nil
            )
        }
    }

    // MARK: - Transport Section
    var transportSection: some View {
        formSection("Getting there") {
            FlowLayout(spacing: 10) {
                ForEach(TripType.allCases, id: \.self) { type in
                    chip(type.name, icon: type.startIcon, isSelected: tripType == type) {
                        tripType = type
                    }
                }
            }
        }
    }

    // MARK: - Accommodation Section
    var accommodationSection: some View {
        formSection("Where you'll stay") {
            FlowLayout(spacing: 10) {
                ForEach(TripAccomodation.allCases, id: \.self) { accom in
                    chip(accom.name, icon: Image(systemName: accommodationIcon(for: accom)), isSelected: tripAccomodation == accom) {
                        tripAccomodation = accom
                    }
                }
            }
        }
    }

    // MARK: - Name Section
    var nameSection: some View {
        formSection("Trip Name", footer: "Optional. Uses the destination if left blank.") {
            TextField(destinationLocation?.name ?? "Trip name", text: $tripName)
                .submitLabel(.done)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 15))
        }
    }

    // MARK: - Cover Photo Section
    var coverPhotoSection: some View {
        formSection("Cover Photo", footer: "Optional. Shown instead of the map on your trip.") {
            CoverPhotoSection(
                draft: $coverPhotoDraft,
                destinationName: destinationLocation?.name,
                tripName: tripName,
                isLoading: coverPhotoFetchID != nil
            )
        }
    }

    /// New trips only, when Settings → Default Cover is Photo. Searches the
    /// destination city, then the trip name; a failed or empty search leaves
    /// the map (dropping a photo picked for a previous destination).
    private func pickRandomCoverPhoto() async {
        guard isCreating,
              defaultTripCover == DefaultTripCover.photo.rawValue,
              !coverPhotoIsUserChosen,
              let destination = destinationLocation,
              destination.persistentModelID != autoCoverDestinationID else { return }

        let fetchID = UUID()
        coverPhotoFetchID = fetchID
        defer {
            if coverPhotoFetchID == fetchID { coverPhotoFetchID = nil }
        }

        var queries: [String] = []
        for query in [
            UnsplashPickerView.initialQuery(forDestination: destination.name),
            tripName.trimmingCharacters(in: .whitespacesAndNewlines),
        ] where !query.isEmpty && !queries.contains(query) {
            queries.append(query)
        }

        for query in queries {
            do {
                guard let photo = try await UnsplashService.shared.randomPhoto(query: query) else { continue }
                guard !Task.isCancelled, !coverPhotoIsUserChosen else { return }
                let draft = CoverPhotoDraft(unsplash: photo)
                autoCoverDestinationID = destination.persistentModelID
                autoCoverPhoto = draft
                coverPhotoDraft = draft
                return
            } catch {
                if Task.isCancelled { return }
                AppLogger.trip.error("Failed to fetch random cover photo: \(error.localizedDescription)")
                break
            }
        }

        guard !Task.isCancelled, !coverPhotoIsUserChosen else { return }
        autoCoverDestinationID = destination.persistentModelID
        autoCoverPhoto = nil
        coverPhotoDraft = nil
    }

    // MARK: - Buttons
    var saveBar: some View {
        VStack(spacing: 8) {
            if !canSave {
                Text("Choose a destination to continue")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                if hasTemplateStep {
                    showingTemplateStep = true
                } else if willMoveToPastTrips {
                    showMovingToPastAlert = true
                } else {
                    saveTrip()
                }
            } label: {
                Text(hasTemplateStep ? "Next" : isCreating ? "Create Trip" : "Save Changes")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Template Step
    var templateStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add lists you've used before to get a head start. You can always add more later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVStack(spacing: 8) {
                    ForEach(templateLists) { list in
                        SelectablePackingListCard(
                            list: list,
                            isSelected: selectedTemplates.contains(list)
                        ) {
                            withAnimation(.snappy) {
                                if let index = selectedTemplates.firstIndex(of: list) {
                                    selectedTemplates.remove(at: index)
                                } else {
                                    selectedTemplates.append(list)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Start From Templates")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                saveTrip()
            } label: {
                Text(selectedTemplates.isEmpty
                     ? "Create Trip"
                     : "Create Trip with \(selectedTemplates.count) List\(selectedTemplates.count == 1 ? "" : "s")")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }

    var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Text("Delete Trip")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemRed).opacity(0.2))
                .foregroundStyle(Color(.systemRed))
                .clipShape(.rect(cornerRadius: 15))
        }
    }

    // MARK: - Helper Views
    private func formSection<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, icon: Image, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                Text(title)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Helper Methods
    func accommodationIcon(for accom: TripAccomodation) -> String {
        switch accom {
        case .hotel:
            return "building.2"
        case .rental:
            return "house"
        case .family:
            return "person.3"
        case .friend:
            return "person.2"
        }
    }

    // MARK: - Data Operations
    func saveTrip() {
        guard let destination = destinationLocation else {
            return
        }

        var createdTrip: Trip?

        if let existingTrip = trip {
            // Update existing trip (origin is no longer edited here; leave it untouched)
            existingTrip.name = resolvedName
            existingTrip.startDate = startDate
            existingTrip.endDate = endDate
            existingTrip.type = tripType
            existingTrip.destination = destination
            existingTrip.accomodation = tripAccomodation
            existingTrip.applyCoverPhoto(coverPhotoDraft, in: modelContext)
        } else {
            // Create new trip
            let newTrip = Trip(
                name: resolvedName,
                startDate: startDate,
                endDate: resolvedEndDate,
                type: tripType,
                origin: nil,
                destination: destination,
                accomodation: tripAccomodation
            )
            modelContext.insert(newTrip)
            newTrip.applyCoverPhoto(coverPhotoDraft, in: modelContext)

            // Auto-create one default catch-all section (if enabled in settings)
            if autoCreateDefaultLists {
                PackingList.createDefaultList(for: newTrip, in: modelContext)
            }

            // nil user = each template's items go to its owner (shared templates stay unassigned)
            newTrip.applyDefaultLists(to: nil, lists: selectedTemplates, in: modelContext)
            createdTrip = newTrip
        }

        do {
            try modelContext.save()
        } catch {
            AppLogger.trip.error("Failed to save trip: \(error.localizedDescription)")
        }

        // Unsplash requires a download ping when a photo is actually used;
        // only freshly picked photos carry a pending location.
        if let downloadLocation = coverPhotoDraft?.pendingDownloadLocation {
            Task {
                do {
                    try await UnsplashService.shared.trackDownload(downloadLocation)
                } catch {
                    AppLogger.trip.error("Failed to track Unsplash download: \(error.localizedDescription)")
                }
            }
        }

        if let createdTrip {
            onCreate?(createdTrip)
        }
        dismiss()
    }

    func deleteTrip() {
        if let tripToDelete = trip {
            modelContext.delete(tripToDelete)
            isDeleted = true
            dismiss()
        }
    }
}
