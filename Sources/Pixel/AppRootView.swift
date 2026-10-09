import SwiftUI

public struct AppRootView: View {
    @ObservedObject var brain: PixelBrain

    public init(brain: PixelBrain) {
        self.brain = brain
    }

    public var body: some View {
        VStack(spacing: 0) {
            NotchView(brain: brain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.85))
    }
}