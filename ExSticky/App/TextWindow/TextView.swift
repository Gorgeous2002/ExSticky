import Cocoa

class TextView: NSView, NSTextViewDelegate {
    private var noteColor = NSColor.white
    private var selectionIsActive = true
    private var temporarySelectionRanges: [NSRange] = []

    func updateSelectionAppearance(noteColor: NSColor? = nil, isActive: Bool? = nil) {
        if let noteColor = noteColor { self.noteColor = noteColor }
        if let isActive = isActive { selectionIsActive = isActive }

        let textRange = NSRange(location: 0, length: (textView.string as NSString).length)
        for range in temporarySelectionRanges {
            let validRange = NSIntersectionRange(range, textRange)
            if validRange.length > 0 {
                textView.layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: validRange)
            }
        }
        temporarySelectionRanges.removeAll()

        if selectionIsActive {
            let palette = ExStickySelectionPalette(noteColor: self.noteColor, mode: UserSettings.text.selectionTextColor)
            textView.selectedTextAttributes = [
                .backgroundColor: palette.background,
                .foregroundColor: palette.foreground,
            ]
        } else {
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor.unemphasizedSelectedTextBackgroundColor,
                .foregroundColor: NSColor.unemphasizedSelectedTextColor,
            ]
            // AppKit ignores selectedTextAttributes' foreground color when inactive.
            // Temporary layout attributes never alter the stored text or its color.
            for value in textView.selectedRanges {
                let range = NSIntersectionRange(value.rangeValue, textRange)
                if range.length > 0 {
                    textView.layoutManager?.addTemporaryAttribute(
                        .foregroundColor, value: NSColor.unemphasizedSelectedTextColor,
                        forCharacterRange: range
                    )
                    temporarySelectionRanges.append(range)
                }
            }
        }
        if let background = textView.selectedTextAttributes[.backgroundColor] as? NSColor,
           let foreground = textView.selectedTextAttributes[.foregroundColor] as? NSColor {
            markdownEditor?.updateSelection(background: background, foreground: foreground)
        }
        textView.needsDisplay = true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateSelectionAppearance()
    }

    func textDidChange(_ notification: Notification) {
        updateSelectionAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSelectionAppearance(isActive: window?.isKeyWindow ?? false)
    }

    private var markdownEditor: MarkdownEditor!
    private var modeControl: NSSegmentedControl!
    private var editorHost: NSView!
    private(set) var isSourceMode = false

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        let wantsSource = sender.selectedSegment == 1
        if wantsSource {
            sender.isEnabled = false
            flushMarkdown { [weak self] in
                guard let self = self else { return }
                self.isSourceMode = true
                self.showMode()
                sender.isEnabled = true
            }
        } else {
            isSourceMode = false
            markdownEditor.setSource(textView.string)
            markdownEditor.updateStyle(font: textView.font)
            showMode()
        }
    }

    private func showMode() {
        scrollView.isHidden = !isSourceMode
        markdownEditor.isHidden = isSourceMode
        window?.makeFirstResponder(isSourceMode ? textView : markdownEditor.webView)
    }

    func flushMarkdown(_ completion: @escaping () -> Void) {
        guard !isSourceMode else { completion(); return }
        markdownEditor.currentSource { [weak self] source in
            if let self = self, self.textView.string != source { self.textView.string = source }
            completion()
        }
    }

    func editingCommand(_ name: String, sourceAction: (NSTextView) -> Void) {
        if isSourceMode { sourceAction(textView) }
        else { markdownEditor.command(name) }
    }

    // MARK: - View

    convenience init(color: NSColor) {
        self.init(frame: .zero) // will extent to the size of parent window

        AddTextView(color: color)
    }

    // MARK: - Subviews

    public var textView: NSTextView!
    private var scrollView: NSScrollView!
    private func AddTextView(color: NSColor) {
        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as? NSTextView
        textView.delegate = self

        textView.drawsBackground = false // transparent
        textView.isRichText = false

        if UserData.times == 0 {
            textView.string = String(localized: "HELP_INFO")
        } else if UserData.times % C.SUPPORT_INFO_FREQUENCY == 0, UserData.did_open_support == false {
            textView.string = String(localized: "You have created \(UserData.times) stickies with ExSticky.\n") + String(localized: "Would you want to buy a cup of coffee for the developer?\n") + String(localized: "Help > Support\n\n")
            // TODO: 购买之后就没有这个机制了
        } else {
            textView.string = ""
        }
        UserData.times += 1

        textView.font = NSFont(
            name: UserSettings.text.font,
            size: CGFloat(UserSettings.text.size)
        )
        textView.usesFontPanel = true // user can change font and size in Font menu
        textView.usesFindPanel = true
        textView.allowsUndo = true

        updateSelectionAppearance(noteColor: color)

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        markdownEditor = MarkdownEditor(frame: .zero)
        markdownEditor.sourceProvider = { [weak self] in self?.textView.string ?? "" }
        markdownEditor.onChange = { [weak self] source in
            guard let self = self else { return }
            // Never store rendered HTML in history. Source mode starts a fresh undo session
            // after rich edits, so stale native undo records cannot overwrite them.
            if self.textView.string != source {
                self.textView.string = source
                self.textView.undoManager?.removeAllActions()
                self.updateSelectionAppearance()
            }
        }
        modeControl = NSSegmentedControl(labels: [String(localized: "Live"), String(localized: "Source")],
                                         trackingMode: .selectOne, target: self, action: #selector(changeMode(_:)))
        modeControl.selectedSegment = 0
        modeControl.controlSize = .small
        modeControl.setToolTip(String(localized: "Edit Markdown with live formatting"), forSegment: 0)
        modeControl.setToolTip(String(localized: "Edit Markdown source"), forSegment: 1)
        addSubview(modeControl)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        editorHost = NSView()
        addSubview(editorHost)
        editorHost.translatesAutoresizingMaskIntoConstraints = false
        editorHost.addSubview(scrollView)
        editorHost.addSubview(markdownEditor)
        markdownEditor.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            modeControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            editorHost.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 3),
            editorHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            editorHost.leadingAnchor.constraint(equalTo: leadingAnchor), editorHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            markdownEditor.topAnchor.constraint(equalTo: editorHost.topAnchor), markdownEditor.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor),
            markdownEditor.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor), markdownEditor.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor)
        ])
        scrollView.isHidden = true
        updateSelectionAppearance()
        markdownEditor.load()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: editorHost.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor),
            scrollView.leftAnchor.constraint(equalTo: editorHost.leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: editorHost.rightAnchor),
        ])
    }
}
