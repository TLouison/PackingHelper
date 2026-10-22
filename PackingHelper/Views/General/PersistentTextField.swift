//
//  PersistentTextField.swift
//  PackingHelper
//
//  A UIViewRepresentable wrapping UITextField that handles the Return key
//  without resigning first responder, keeping the keyboard up between submissions.
//

import SwiftUI

struct PersistentTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var textStyle: UIFont.TextStyle = .body
    var onSubmit: () -> Void
    /// Called when backspace is pressed while the field is already empty
    var onDeleteBackwardWhenEmpty: (() -> Void)? = nil

    func makeUIView(context: Context) -> BackspaceAwareTextField {
        let tf = BackspaceAwareTextField()
        tf.placeholder = placeholder
        tf.returnKeyType = .done
        tf.delegate = context.coordinator
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        tf.font = .preferredFont(forTextStyle: textStyle)
        tf.adjustsFontForContentSizeCategory = true
        tf.setContentHuggingPriority(.required, for: .vertical)
        tf.setContentCompressionResistancePriority(.required, for: .vertical)
        tf.onDeleteBackwardWhenEmpty = onDeleteBackwardWhenEmpty
        return tf
    }

    func updateUIView(_ tf: BackspaceAwareTextField, context: Context) {
        context.coordinator.parent = self
        tf.onDeleteBackwardWhenEmpty = onDeleteBackwardWhenEmpty
        let font = UIFont.preferredFont(forTextStyle: textStyle)
        if tf.font != font {
            tf.font = font
        }
        if tf.text != text {
            tf.text = text
        }
        if isFocused && !tf.isFirstResponder {
            DispatchQueue.main.async { tf.becomeFirstResponder() }
        } else if !isFocused && tf.isFirstResponder {
            tf.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PersistentTextField

        init(_ parent: PersistentTextField) { self.parent = parent }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false  // Prevent resign — keyboard stays up
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async { self.parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            DispatchQueue.main.async { self.parent.isFocused = false }
        }
    }
}

/// UITextField that reports backspace presses on an empty field (Reminders-style row deletion)
final class BackspaceAwareTextField: UITextField {
    var onDeleteBackwardWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        let wasEmpty = text?.isEmpty ?? true
        super.deleteBackward()
        if wasEmpty {
            onDeleteBackwardWhenEmpty?()
        }
    }
}
