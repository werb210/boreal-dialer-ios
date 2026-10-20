// BOREAL_DIALER_v830_DIALER_CONTROLS - the in-call audio route picker (iPhone, speaker, AirPods / Bluetooth / car).
// There was no way to change where call audio went without Control Center.
import SwiftUI
import UIKit
import AVKit

struct AudioRouteButton: View {
    var body: some View {
        VStack(spacing: 4) {
            AudioRoutePicker()
                .frame(width: 28, height: 28)
            Text("Audio")
                .font(.caption2)
        }
        .frame(width: 60, height: 60)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio output")
    }
}

private struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.label
        picker.activeTintColor = UIColor.systemGreen
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
