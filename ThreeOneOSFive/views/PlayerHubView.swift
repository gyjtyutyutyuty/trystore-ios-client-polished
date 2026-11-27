import SwiftUI

/// The player tab. Wardrobe was removed, so this is the Intel screen on its own.
///
/// The backdrop deliberately stays inside `PlayerIntelView`'s NavigationStack:
/// a stack paints its own background, and a backdrop placed behind the stack
/// never reaches the screen. Keeping it in the same ZStack as the scroll content
/// is what makes the storm loop visible.
struct PlayerHubView: View {
    var body: some View {
        PlayerIntelView()
    }
}
