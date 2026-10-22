import AppKit

/// Font changes are text edits, so undo and autosave follow the same path as typing.
open class FontSizingTextView: NSTextView {
    open override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command || modifiers == [.command, .shift] {
            switch event.charactersIgnoringModifiers {
            case "+", "=": enlargeSelectedText(nil); return true
            case "-": shrinkSelectedText(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc public func enlargeSelectedText(_ sender: Any?) { resizeSelection(by: 2) }
    @objc public func shrinkSelectedText(_ sender: Any?) { resizeSelection(by: -2) }

    private func resizeSelection(by delta: CGFloat) {
        guard isEditable, !hasMarkedText(), let storage = textStorage else { return }
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return }
        let updated = NSMutableAttributedString(attributedString: storage)
        var changed = false
        for range in ranges {
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                let font = value as? NSFont ?? NSFont.systemFont(ofSize: 14)
                let size = min(96, max(8, font.pointSize + delta))
                guard size != font.pointSize else { return }
                updated.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: size), range: run)
                changed = true
            }
        }
        guard changed else { return }
        replaceFormatting(with: updated, selections: selectedRanges)
        undoManager?.setActionName(delta > 0 ? "放大字体" : "缩小字体")
    }

    private func replaceFormatting(with value: NSAttributedString, selections: [NSValue]) {
        guard let storage = textStorage,
              shouldChangeText(in: NSRange(location: 0, length: storage.length), replacementString: nil) else { return }
        let previous = NSAttributedString(attributedString: storage)
        let previousSelections = selectedRanges
        undoManager?.registerUndo(withTarget: self) { target in
            target.replaceFormatting(with: previous, selections: previousSelections)
        }
        storage.setAttributedString(value)
        selectedRanges = selections
        didChangeText()
    }

    public var savedFontSizes: [NoteStore.FontSizeRun] {
        guard let storage = textStorage else { return [] }
        var runs: [NoteStore.FontSizeRun] = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            let size = (value as? NSFont)?.pointSize ?? 14
            if size != 14 {
                runs.append(.init(location: range.location, length: range.length, size: Double(size)))
            }
        }
        return runs
    }

    public func loadFontSizes(_ runs: [NoteStore.FontSizeRun]) {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: storage.length))
        for run in runs where run.location >= 0 && run.length > 0 && run.location <= storage.length && run.length <= storage.length - run.location {
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: run.size), range: NSRange(location: run.location, length: run.length))
        }
        storage.endEditing()
    }
}
