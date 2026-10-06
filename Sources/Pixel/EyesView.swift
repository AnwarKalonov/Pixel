import SwiftUI

struct EyesView: View {
    var look: CGPoint
    var blink: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Eye(look: look, blink: blink)
            Eye(look: look, blink: blink)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: look)
        .animation(.easeInOut(duration: 0.07), value: blink)
    }
}

private struct Eye: View {
    var look: CGPoint
    var blink: CGFloat

    var body: some View {
        let height = max(2, 14 * (1 - blink))
        ZStack {
            Capsule()
                .fill(Color.white)
                .frame(width: 16, height: height)

            if blink < 0.7 {
                Circle()
                    .fill(Color.black)
                    .frame(width: 6, height: 6)
                    .offset(x: look.x * 3.4, y: look.y * 2.4)
            }
        }
        .frame(width: 16, height: 16)
    }
}
