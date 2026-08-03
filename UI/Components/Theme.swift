// BOREAL_DIALER_THEME_v27
// The design tokens from the concept mockup, verbatim. The mockup is a dark
// theme with a green accent; the app was default light SwiftUI, which is the
// single biggest reason the two looked unrelated.
import SwiftUI
import UIKit  // BOREAL_DIALER_THREAD_STYLE_v32 - UIBezierPath for per-corner radii

enum Theme {
    // Surfaces
    static let bg = Color(hex: 0x0A0B0D)
    static let surface = Color(hex: 0x121419)
    static let surface2 = Color(hex: 0x181B21)
    static let surface3 = Color(hex: 0x1F232B)

    // Hairlines. The mockup uses white at low alpha rather than a grey, which
    // keeps separators from muddying against the near-black background.
    static let line = Color.white.opacity(0.07)
    static let line2 = Color.white.opacity(0.13)

    // Type
    static let text = Color(hex: 0xF2F4F7)
    static let muted = Color(hex: 0x8B919C)
    static let faint = Color(hex: 0x5B616B)

    // Accent
    static let green = Color(hex: 0x2FA86A)
    static let greenBright = Color(hex: 0x54D08A)
    static let onGreen = Color(hex: 0x05130C)

    // Presence
    static let online = Color(hex: 0x34C759)
    static let away = Color(hex: 0xFFB23E)
    static let offline = Color(hex: 0x5B616B)
    static let red = Color(hex: 0xFF453A)

    // Avatar gradient
    static let ind1 = Color(hex: 0x4257E8)
    static let ind2 = Color(hex: 0x6B45D0)
}

// BOREAL_DIALER_THREAD_STYLE_v32
extension Theme {
    // The mockup's outbound bubble is a deeper green than the accent, so text
    // stays legible on it at 14.5pt.
    static let greenDeep = Color(hex: 0x236F49)
}

// The mockup's .bub: 74% max width, 18pt radius with a 5pt tail corner on the
// sender's side. SwiftUI has no per-corner radius on RoundedRectangle, so the
// tail is drawn as a small square patched into that corner.
struct ChatBubble<Content: View>: View {
    let outbound: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.system(size: 14.5))
            .lineSpacing(2)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .foregroundColor(Theme.text)
            .background(
                ZStack(alignment: outbound ? .bottomTrailing : .bottomLeading) {
                    RoundedRectangle(cornerRadius: 18)
                    Rectangle()
                        .frame(width: 13, height: 13)
                        .cornerRadius(5, corners: outbound ? .bottomRight : .bottomLeft)
                }
                .foregroundColor(outbound ? Theme.greenDeep : Theme.surface3)
            )
    }
}

// The composer bar: pill field, 36pt green send button.
struct ComposerBar: View {
    let placeholder: String
    @Binding var text: String
    let disabled: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 20).fill(Theme.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20).stroke(Theme.line2, lineWidth: 1)
                )

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.onGreen)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(disabled ? Theme.surface3 : Theme.green))
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// Per-corner radius, which SwiftUI does not provide directly.
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// The uppercase, letter-spaced section header from the mockup.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .kerning(0.6)
            .foregroundColor(Theme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 5)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .listRowBackground(Color.clear)
    }
}

// Unread count: green pill, dark numerals.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Theme.onGreen)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(Capsule().fill(Theme.green))
    }
}

// Channel chip, tinted per channel as in the mockup.
struct ChannelChip: View {
    let label: String

    private var tint: Color {
        switch label.lowercased() {
        case "sms": return Color(hex: 0x8FD6B0)
        case "chat": return Color(hex: 0x9BB6FF)
        case "email", "mail": return Color(hex: 0xD6B48F)
        default: return Theme.muted
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
    }
}

// BOREAL_DIALER_ROW_SEGMENT_STYLE_v31
// The mockup's .seg control: a surface2 container with 3pt inset, and the
// selected item raised on surface3. UIKit's segmented picker cannot be made to
// look like this, so it is rebuilt rather than tinted.
struct SegmentedBar<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(on ? Theme.surface3 : Color.clear)
                                .shadow(color: on ? .black.opacity(0.4) : .clear, radius: 1, y: 1)
                        )
                        .foregroundColor(on ? Theme.text : Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface2))
    }
}

// The mockup's .row: 13pt gap, 15.5/600 name, 13pt muted subtitle, 12pt faint
// trailing time. Applied as a modifier so every list reads the same.
struct RowText: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 15.5, weight: .semibold))
    }
}

struct RowSubtext: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 13)).foregroundColor(Theme.muted)
    }
}

extension View {
    func rowTitle() -> some View { modifier(RowText()) }
    func rowSubtitle() -> some View { modifier(RowSubtext()) }
}
