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

    // UI State
    @State private var showingDestinationSearch = false
    @State private var showDeleteAlert = false

    // Template step (new trips only): lists are chosen before the trip exists, applied on create
    @Query(
        filter: #Predicate<PackingList> { $0.template == true },
        sort: [SortDescriptor(\.name)]
    )
    private var templateLists: [PackingList]
    @State private var selectedTemplates: [PackingList] = []
    @State private var showingTemplateStep = false

    @AppStorage("autoCreateDefaultLists") private var autoCreateDefaultLists = true

    private var isCreating: Bool { trip == nil }
    private var canSave: Bool { destinationLocation != nil }
    private var hasTemplateStep: Bool { isCreating && !templateLists.isEmpty }

    /// Name falls back to the destination when left blank.
    private var resolvedName: String {
        let trimmed = tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (destinationLocation?.name ?? "Trip") : trimmed
    }

    private var nights: Int {
        Calendar.current.numberOfDaysBetween(startDate, and: endDate)
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
            .navigationTitle(isCreating ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Depart")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("Depart", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Return")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("Return", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .labelsHidden()
                    }
                }

                Text(nights == 0 ? "Day trip" : nights == 1 ? "1 night" : "\(nights) nights")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: nights)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 15))
        }
        .onChange(of: startDate) { oldStart, newStart in
            // Keep the trip length when departure moves past the return date
            if endDate < newStart {
                endDate = newStart.addingTimeInterval(max(endDate.timeIntervalSince(oldStart), 0))
            }
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
        formSection("Staying at") {
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
            CoverPhotoSection(draft: $coverPhotoDraft, destinationName: destinationLocation?.name)
        }
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
                endDate: endDate,
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

            // nil user = each list goes to the packer who owns the template
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
            SectionCollapseStateManager.removeState(for: tripToDelete.uuid)
            modelContext.delete(tripToDelete)
            isDeleted = true
            dismiss()
        }
    }
}
