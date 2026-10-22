//
//  User.swift
//  PackingHelper
//
//  Created by Todd Louison on 6/3/24.
//

import SwiftUI
import SwiftData
import OSLog

@Model
final class User: Comparable {
    static func < (lhs: User, rhs: User) -> Bool {
        lhs.name < rhs.name
    }
    
    var name: String = "Packer"
    var created: Date = Date.now
    var profileImageData: Data?
    
    // Legacy: sections were assigned to users; new code assigns users to items
    @Relationship(deleteRule: .cascade, inverse: \PackingList.user) var lists: [PackingList]?
    // Items assigned to this packer
    @Relationship(deleteRule: .nullify, inverse: \Item.user) var items: [Item]?
    @Relationship(deleteRule: .nullify) var defaultLocation: TripLocation?

    var colorHex: String = Color.teal.toHex() ?? "008080"
    
    init(name: String, colorHex: String? = nil) {
        self.name = name
        
        if let colorHex {
            self.colorHex = colorHex
        }
    }
    
    @discardableResult
    static func create_or_update(_ user: User?, name: String, color: Color, profileImage: UIImage? = nil, in context: ModelContext) -> User {
        if let user {
            user.name = name
            user.setUserColor(color)
            if let image = profileImage {
                user.setProfileImage(image)
            }
            return user
        } else {
            let newUser = User(name: name)
            newUser.setUserColor(color)
            if let image = profileImage {
                newUser.setProfileImage(image)
            }
            context.insert(newUser)
            return newUser
        }
    }
}

extension User {
    @discardableResult
    static func delete(_ user: User, from context: ModelContext) -> Bool {
        // Nullify PackingList.user to prevent cascade-deleting trip sections
        user.lists?.forEach { $0.user = nil }
        // Nullify Item.user so items remain, just unassigned
        user.items?.forEach { $0.user = nil }
        AppLogger.user.info("Deleting user \(user.name)")
        context.delete(user)
        return true
    }
}

extension User {
    static var sampleUser: User {
        return User(name: "Todd")
    }
}

extension User {
    func setUserColor(_ color: Color) {
        self.colorHex = color.toHex() ?? "007AFF"
    }
    
    var userColor: Color {
        return Color(hex: self.colorHex) ?? Color.accentColor
    }
}

extension User {
    func setProfileImage(_ image: UIImage) {
        AppLogger.user.debug("Setting profile image")
        if let data = image.jpegData(compressionQuality: 0.7) {
            AppLogger.user.debug("Image data size: \(data.count) bytes")
            self.profileImageData = data
        }
    }

    func verifyImageData() {
        if let data = profileImageData {
            AppLogger.user.debug("Profile image data exists: \(data.count) bytes")
        } else {
            AppLogger.user.debug("No profile image data found")
        }
    }
    
    var profileImage: Image? {
        if let data = profileImageData, let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return nil
    }
}

extension User {
    var profileView: some View {
        Group {
            if let profileImage = profileImage {
                profileImage
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(userColor)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(Circle())
        .shadow(radius: 2)
    }
    
    var pillIcon: some View {
        Text(self.name)
            .foregroundStyle(Color.white)
            .font(.caption2.smallCaps())
            .fontWeight(.semibold)
            .shadow(
                color: Color.gray.opacity(0.3),
                radius: 3,
                x: 0,
                y: 2
            )
            .padding(.horizontal)
            .padding(.vertical, 5)
            .background(self.userColor.opacity(0.6))
            .clipShape(.capsule)
            .shaded()
            .glassEffectIfAvailable()
    }
    
    var pillFirstInitialIcon: some View {
        Text(name.prefix(1).uppercased())
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(self.userColor.opacity(0.6))
            .clipShape(Circle())
            .glassEffectIfAvailable()
    }
    
    var pillFirstInitialIconSolid: some View {
        if #available(iOS 26.0, *) {
            AnyView(
                pillFirstInitialIcon
                    .glassEffect(.regular.tint(self.userColor).interactive())
            )
        } else {
            AnyView(
                pillFirstInitialIcon
                    .background(self.userColor.opacity(1))
                    .clipShape(Circle())
            )
        }
    }
}
