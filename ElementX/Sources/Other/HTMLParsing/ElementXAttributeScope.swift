//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated enum BlockquoteAttribute: AttributedStringKey {
    typealias Value = Bool
    static let name = "MXBlockquoteAttribute"
}

nonisolated enum UserIDAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "MXUserIDAttribute"
}

/// This attribute is used to help the composer convert a mention into to a markdown link before sending
/// the message. It doesn't interact mention pills, as these fetch display names live from the room.
nonisolated enum UserDisplayNameAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "MXUserDisplayNameAttribute"
}

nonisolated enum RoomDisplayNameAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "MXRoomDisplayNameAttribute"
}

nonisolated enum RoomIDAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "MXRoomIDAttribute"
}

nonisolated enum RoomAliasAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "MXRoomAliasAttribute"
}

nonisolated enum EventOnRoomIDAttribute: AttributedStringKey {
    struct Value: Hashable {
        let roomID: String
        let eventID: String
    }
    
    static let name = "MXEventOnRoomIDAttribute"
}

nonisolated enum EventOnRoomAliasAttribute: AttributedStringKey {
    struct Value: Hashable {
        let alias: String
        let eventID: String
    }
    
    static let name = "MXEventOnRoomAliasAttribute"
}

nonisolated enum AllUsersMentionAttribute: AttributedStringKey {
    typealias Value = Bool
    static let name = "MXAllUsersMentionAttribute"
}

nonisolated enum CodeBlockAttribute: AttributedStringKey {
    typealias Value = Bool
    static let name = "MXCodeBlockAttribute"
}

nonisolated enum InlineCodeAttribute: AttributedStringKey {
    typealias Value = Bool
    static let name = "MXInlineCodeAttribute"
}

// periphery: ignore - required to make NSAttributedString to AttributedString conversion even if not used directly
nonisolated extension AttributeScopes {
    nonisolated struct ElementXAttributes: AttributeScope {
        let blockquote: BlockquoteAttribute
        
        let userID: UserIDAttribute
        let userDisplayName: UserDisplayNameAttribute
        let roomDisplayName: RoomDisplayNameAttribute
        let roomID: RoomIDAttribute
        let roomAlias: RoomAliasAttribute
        let eventOnRoomID: EventOnRoomIDAttribute
        let eventOnRoomAlias: EventOnRoomAliasAttribute
        
        let allUsersMention: AllUsersMentionAttribute
        
        let codeBlock: CodeBlockAttribute
        let inlineCode: InlineCodeAttribute
        
        let swiftUI: SwiftUIAttributes
        let uiKit: UIKitAttributes
    }
    
    var elementX: ElementXAttributes.Type {
        ElementXAttributes.self
    }
}

// periphery: ignore - required to make NSAttributedString to AttributedString conversion even if not used directly
nonisolated extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.ElementXAttributes, T>) -> T {
        self[T.self]
    }
}
