// SPDX-License-Identifier: MIT

import SwiftUI

struct MultilineTextArea: View {
    let prompt: String
    @Binding var text: String
    var height: CGFloat = 76
    var automaticallyFocus = false

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(prompt)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(6)
                .focused($isFocused)
        }
        .frame(height: height, alignment: .topLeading)
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isFocused ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: isFocused ? 2 : 1
                )
        }
        .onAppear {
            guard automaticallyFocus else { return }
            Task { @MainActor in
                await Task.yield()
                isFocused = true
            }
        }
    }
}
