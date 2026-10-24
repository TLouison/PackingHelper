//
//  UserPickerView.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/16/24.
//

import SwiftUI
import SwiftData

struct UserPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedUser: User?
    
    @Query(sort: \User.created) private var users: [User]
    
    let trip: Trip?
    let style: Style
    let allowAll: Bool
    
    enum Style {
        case menu       // Compact menu for toolbars/navigation
        case inline     // For forms and lists
        case sheet      // Full sheet with grid layout
    }
    
    init(
        selectedUser: Binding<User?>,
        trip: Trip? = nil,
        style: Style = .inline,
        allowAll: Bool = true
    ) {
        self._selectedUser = selectedUser
        self.trip = trip
        self.style = style
        self.allowAll = allowAll
    }
    
    private var filteredUsers: [User] {
        let candidates: [User]
        if let trip {
            candidates = users.filter { user in
                trip.lists?.contains { list in
                    list.user == user
                } ?? false
            }
        } else {
            candidates = users
        }
        return candidates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    var body: some View {
        Group {
            switch style {
            case .menu:
                menuPicker
            case .inline:
                inlinePicker
            case .sheet:
                sheetPicker
            }
        }
    }
    
    // MARK: - Picker Styles
    
    private var menuPicker: some View {
        Menu {
            if allowAll {
                Button {
                    withAnimation(.snappy) {
                        selectedUser = nil
                    }
                } label: {
                    if selectedUser == nil {
                        Label("All Users", systemImage: "checkmark")
                    } else {
                        Text("All Users")
                    }
                }
            } else {
                if selectedUser == nil {
                    Text("Select User")
                }
            }
            
            ForEach(filteredUsers) { user in
                Button {
                    withAnimation(.snappy) {
                        selectedUser = user
                    }
                } label: {
                    if selectedUser == user {
                        Label(user.name, systemImage: "checkmark")
                    } else {
                        Text(user.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let user = selectedUser {
                    user.pillIcon
                } else {
                    if allowAll {
                        Text("All Users")
                            .foregroundStyle(.primary)
                    } else {
                        Text("Select User")
                    }
                }
                
                Image(systemName: "chevron.up.chevron.down")
                    .fontWeight(.semibold)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .clipShape(Capsule())
        }
        // Menus opening upward from the bottom reverse their items by default; keep A–Z top to bottom
        .menuOrder(.fixed)
    }
    
    private var inlinePicker: some View {
        HStack {
            Label("Packer", systemImage: "person.circle")
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Menu {
                if allowAll {
                    Button {
                        withAnimation(.snappy) {
                            selectedUser = nil
                        }
                    } label: {
                        if selectedUser == nil {
                            Label("All Users", systemImage: "checkmark")
                        } else {
                            Text("All Users")
                        }
                    }
                    
                    Divider()
                } else {
                    if selectedUser == nil {
                        Text("Select User")
                    }
                }
                
                ForEach(filteredUsers) { user in
                    Button {
                        withAnimation(.snappy) {
                            selectedUser = user
                        }
                    } label: {
                        if selectedUser == user {
                            Label(user.name, systemImage: "checkmark")
                        } else {
                            Text(user.name)
                        }
                    }
                }
            } label: {
                HStack {
                    if let user = selectedUser {
                        user.pillIcon
                    } else {
                        if allowAll {
                            Text("All Users")
                                .foregroundStyle(.primary)
                        } else {
                            Text("Select User")
                        }
                    }
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .fontWeight(.semibold)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var sheetPicker: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150), spacing: 12)
                ],
                spacing: 12
            ) {
                if allowAll {
                    UserCard(
                        name: "All Users",
                        icon: "person.2.circle.fill",
                        isSelected: selectedUser == nil
                    ) {
                        withAnimation(.snappy) {
                            selectedUser = nil
                        }
                    }
                } else {
                    if selectedUser == nil {
                        Text("Select User")
                    }
                }
                
                ForEach(filteredUsers) { user in
                    UserCard(
                        name: user.name,
                        icon: "person.circle.fill",
                        isSelected: selectedUser == user
                    ) {
                        withAnimation(.snappy) {
                            selectedUser = user
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Supporting Views

private struct UserCard: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? .white : .accentColor)
                
                Text(name)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Usage Examples

//struct ContentView: View {
//    @State private var selectedUser: User?
//    @State private var showingSheet = false
//
//    var body: some View {
//        NavigationStack {
//            List {
//                // Inline picker in a form
//                Section("Inline Picker") {
//                    UserPickerView(
//                        selectedUser: $selectedUser,
//                        style: .inline
//                    )
//                }
//
//                // Menu picker in a form
//                Section("Menu Picker") {
//                    UserPickerView(
//                        selectedUser: $selectedUser,
//                        style: .menu
//                    )
//                }
//            }
//            .toolbar {
//                // Menu picker in toolbar
//                ToolbarItem(placement: .topBarTrailing) {
//                    UserPickerView(
//                        selectedUser: $selectedUser,
//                        style: .menu
//                    )
//                }
//
//                // Button to show sheet picker
//                ToolbarItem(placement: .topBarLeading) {
//                    Button("Sheet Picker") {
//                        showingSheet.toggle()
//                    }
//                }
//            }
//            .sheet(isPresented: $showingSheet) {
//                NavigationStack {
//                    UserPickerView(
//                        selectedUser: $selectedUser,
//                        style: .sheet
//                    )
//                    .navigationTitle("Select User")
//                    .navigationBarTitleDisplayMode(.inline)
//                    .toolbar {
//                        ToolbarItem(placement: .confirmationAction) {
//                            Button("Done") {
//                                showingSheet = false
//                            }
//                        }
//                    }
//                }
//                .presentationDetents([.medium])
//            }
//        }
//    }
//}
