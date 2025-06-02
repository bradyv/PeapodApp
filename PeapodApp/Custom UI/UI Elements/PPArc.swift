//
//  PPArc.swift
//  PeapodApp
//
//  Created by Brady Valentino on 2025-05-04.
//

import SwiftUI

struct PPArc: View {
    @State var textWidths: [Int:Double] = [:]
    @State var degreesRotating = 0.0

    var text: String
    var texts: [(offset: Int, element: Character)] {
        return Array(text.enumerated())
    }
    var radius: Double
    var size: CGSize = .init(width: 300, height: 300)

    var body: some View {
        ZStack {
            ForEach(texts, id: \.offset) { index, letter in
                VStack {
                    Text(String(letter))
                        .background(Sizeable())
                        .onPreferenceChange(WidthPreferenceKey.self, perform: { width in
                            textWidths[index] = width
                        })
                    Spacer()
                }
                .rotationEffect(angle(at: index))
            }
        }
        .blendMode(.overlay)
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(degreesRotating))
        .onAppear {
            withAnimation(.linear(duration: 1.5)
              .speed(0.1).repeatForever(autoreverses: false)) {
                  degreesRotating = 360.0
              }
        }
    }
    
    func angle(at index: Int) -> Angle {
        guard let labelWidth = textWidths[index] else { return .radians(0) }

        let circumference = radius * 2 * .pi

        let percent = labelWidth / circumference
        let labelAngle = percent * 2 * .pi

        let widthBeforeLabel = textWidths.filter{$0.key < index}.map{$0.value}.reduce(0, +)
        let percentBeforeLabel = widthBeforeLabel / circumference
        let angleBeforeLabel = percentBeforeLabel * 2 * .pi

        return .radians(angleBeforeLabel + labelAngle)
    }
}

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = nextValue()
    }
}

struct Sizeable: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: WidthPreferenceKey.self, value: geometry.size.width)
        }
    }
}

#Preview {
    VStack {
        ZStack {
            Image("ppface")
                .resizable()
                .frame(width:64,height:64)
            
            PPArc(text: "Listener Since Mar 12 • Listener Since Mar 12 •  ".uppercased(), radius: 48, size:.init(width: 100, height: 100))
                .font(.system(size:10, design: .monospaced)).bold()
                .foregroundStyle(.black)
        }
        
//        ZStack {
//            Image("ppface")
//                .resizable()
//                .frame(width:64,height:64)
//            
//            PPArc(text: "Beta Tester Since Mar 12 • Beta Tester Since Mar 12 •  ".uppercased(), radius: 39, size:.init(width: 100, height: 100))
//                .font(.system(size: 10).width(.condensed)).bold()
//                .foregroundStyle(.black)
//        }
    }
    .background(Image("Splash-Pastel"))
}
