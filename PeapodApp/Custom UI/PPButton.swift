//
//  PeapodButton.swift
//  Peapod
//
//  Created by Brady Valentino on 2025-03-12.
//

import SwiftUI

struct ButtonCustomColors {
    var foreground: Color
    private var _background: AnyShapeStyle

    var background: AnyShapeStyle {
        _background
    }

    init(foreground: Color, background: some ShapeStyle) {
        self.foreground = foreground
        self._background = AnyShapeStyle(background)
    }
}

struct ShadowButton: ButtonStyle {
    var iconOnly: Bool = false
    var filled: Bool = false
    var borderless: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        
        return HStack(spacing: iconOnly ? 0 : 2) {
            configuration.label
        }
        .if(iconOnly, transform: { $0.labelStyle(.iconOnly) })
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .if(!borderless,
            transform: {
                $0.background(filled ? Color.accentColor : .white)
        })
        .foregroundStyle(filled ? Color.white : Color.black)
        .textBody()
        .if(iconOnly,
            transform: {
            $0.clipShape(Circle())
        })
        .if(!iconOnly,
            transform: {
            $0.clipShape(Capsule())
        })
        .if(!borderless,
            transform: {
            $0.shadow(color: filled ? Color.accentColor.opacity(0.25) : .black.opacity(0.03), radius: 1, x: 0, y: 2)
        })
        .if(!borderless && !iconOnly,
            transform: {
            $0.overlay(
                Capsule()
                .stroke(.black.opacity(0.1), lineWidth: 1)
            )
        })
        .if(!borderless && iconOnly,
            transform: {
            $0.overlay(
                Circle()
                .stroke(.black.opacity(0.1), lineWidth: 1)
            )
        })
        .scaleEffect(isPressed ? 0.95 : 1)
        .animation(.easeOut(duration: 0.2), value: isPressed)
    }
}

struct PPButton: ButtonStyle {
    enum ButtonType {
        case filled, transparent
    }

    enum ColorStyle {
        case tinted, monochrome
    }

    var type: ButtonType
    var colorStyle: ColorStyle
    var iconOnly: Bool = false
    var medium: Bool = false
    var large: Bool = false
    var borderless: Bool = false
    var customColors: ButtonCustomColors? = nil

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        return HStack(spacing: iconOnly ? 0 : 4) {
            configuration.label
                .opacity(iconOnly ? 1 : 1)
        }
        .if(iconOnly, transform: { $0.labelStyle(.iconOnly) })
        .padding(.vertical, iconOnly ? 12 : 10)
        .padding(.horizontal, iconOnly ? 12 : 16)
        .if(medium, transform: {
            $0.padding(.vertical, 3).padding(.horizontal, 12)
        })
        .if(iconOnly, transform: {
            $0.frame(width: large ? 60 : medium ? 54 : 38, height: large ? 60 : medium ? 54 : 38)
            })
        .if(medium, transform: { $0.font(.system(size:20))})
        .if(large, transform: { $0.font(.system(size:26))})
        .background(borderless ? AnyShapeStyle(.clear) : effectiveBackground(isPressed))
        .foregroundColor(effectiveForeground)
        .textBodyEmphasis()
        .clipShape(Capsule())
        .scaleEffect(isPressed ? 0.95 : 1)
        .animation(.easeOut(duration: 0.2), value: isPressed)
    }

    private func effectiveBackground(_ isPressed: Bool) -> AnyShapeStyle {
        if let custom = customColors {
            return custom.background
        }
        return AnyShapeStyle(backgroundColor(isPressed))
    }

    private var effectiveForeground: Color {
        if let custom = customColors {
            return custom.foreground
        }
        return foregroundColor
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch (type, colorStyle) {
        case (.filled, .tinted):
            return isPressed ? .accentColor.opacity(0.7) : .accentColor
        case (.filled, .monochrome):
            return isPressed ? .heading.opacity(0.7) : .heading
        case (.transparent, .tinted):
            return isPressed ? .accentColor.opacity(0.05) : .accentColor.opacity(0.15)
        case (.transparent, .monochrome):
            return isPressed ? .surface.opacity(0.7) : .surface
        }
    }

    private var foregroundColor: Color {
        switch (type, colorStyle) {
        case (.filled, _):
            return .background
        case (.transparent, .tinted):
            return .accentColor
        case (.transparent, .monochrome):
            return .heading
        }
    }
}

struct NoHighlight: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
      let isPressed = configuration.isPressed
      configuration.label
          .scaleEffect(isPressed ? 0.95 : 1)
          .animation(.easeOut(duration: 0.2), value: isPressed)
  }
}
 
extension ButtonStyle where Self == NoHighlight {
  static var noHighlight: NoHighlight {
    get { NoHighlight() }
  }
}

struct PPButtonTest: View {
    
    var body: some View {
        VStack {
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(ShadowButton(iconOnly: true, filled: false))
            
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(ShadowButton(iconOnly: true, filled: true))
            
            Button("Close", systemImage: "xmark") {
            }
            .buttonStyle(ShadowButton(filled: true))
            
            
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(PPButton(type:.filled, colorStyle:.tinted))
            
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(PPButton(type:.filled, colorStyle:.monochrome))
            
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted))
            
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome))
            
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(PPButton(type:.filled, colorStyle:.tinted, iconOnly: true))
            
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(PPButton(type:.filled, colorStyle:.monochrome, iconOnly: true))
            
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(PPButton(type:.transparent, colorStyle:.tinted, iconOnly: true))
            
            Button("Dismiss", systemImage: "chevron.down") {
            }
            .buttonStyle(PPButton(type:.transparent, colorStyle:.monochrome, iconOnly: true))
        }
    }
}

#Preview {
    PPButtonTest()
}
