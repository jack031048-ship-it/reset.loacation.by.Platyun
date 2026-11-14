// Customized by Platyun
import SwiftUI

struct WidgetIconBackground: View {
    let image: Image?
    let topAligned: Bool
    let topCropRatio: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.fill.tertiary)
            if let image {
                GeometryReader { geo in
                    let side = max(geo.size.width, geo.size.height)
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .offset(y: topAligned ? -side * topCropRatio : 0)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: topAligned ? .top : .center)
                        .clipped()
                }
                .opacity(0.18)
                .accessibilityHidden(true)
            }
        }
    }
}
