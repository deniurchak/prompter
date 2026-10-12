import AVFoundation
import AppKit
import Carbon.HIToolbox
import Combine
import NaturalLanguage
import Speech
import SwiftUI
import UniformTypeIdentifiers

// MARK: - State

final class Model: ObservableObject {
    private let d = UserDefaults.standard

    @Published var playing = false
    @Published var editing = false
    /// Lines per minute, so pace stays the same when the font size changes.
    @Published var speed: Double { didSet { d.set(speed, forKey: "speed") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    @Published var opacity: Double { didSet { d.set(opacity, forKey: "opacity") } }
    @Published var hiddenFromCapture: Bool { didSet { d.set(hiddenFromCapture, forKey: "hidden") } }
    /// Follow the speaker's voice instead of scrolling at a fixed speed.
    @Published var voice: Bool { didSet { d.set(voice, forKey: "voice") } }

    static let speedRange = 6.0...90.0
    static let fontRange = 18.0...72.0

    init() {
        d.register(defaults: ["speed": 24.0, "fontSize": 34.0, "opacity": 0.78, "hidden": true])
        speed = d.double(forKey: "speed")
        fontSize = d.double(forKey: "fontSize")
        opacity = d.double(forKey: "opacity")
        hiddenFromCapture = d.bool(forKey: "hidden")
        voice = d.bool(forKey: "voice")
    }

    var script: String {
        get { d.string(forKey: "script") ?? Model.welcome }
        set { d.set(newValue, forKey: "script") }
    }

    static let welcome = """
    Welcome to Prompter.

    Park this window right under your camera, so your eyes stay close to the lens while you read.

    Press E to edit this text, or just paste your script. Press Escape when you are done.

    Space starts and pauses. Up and Down change the speed. Left and Right jump back and forward. R goes back to the top.

    While another app is focused, hold Control and Option with the same keys to drive the prompter without clicking on it.

    The microphone button makes the text follow your voice instead of a fixed speed: it moves as you read, and waits when you stop.

    The eye button hides this window from screen sharing and recordings, so only you can see it.

    Now replace me with something worth saying.
    """
}

// MARK: - Views

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Panels close on Escape and beep on stray keys; this one should only close from its button or ⌘Q.
    override func cancelOperation(_ sender: Any?) {}
    override func keyDown(with event: NSEvent) {}
}

final class RootView: NSView {
    var onLayout: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

final class ScriptTextView: NSTextView {
    // Drag the window by the text whenever it isn't being edited.
    override var mouseDownCanMoveWindow: Bool { !isEditable }
}

final class ScriptScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        onUserScroll?()
    }
}

struct Shortcuts: View {
    private let rows = [
        ("Space", "Play / pause"),
        ("↑  ↓", "Slower / faster"),
        ("←  →", "Jump back / forward"),
        ("R", "Back to top"),
        ("E  or  ⌫", "Edit the script"),
        ("Esc", "Finish editing"),
        ("⌘V", "Replace script with clipboard"),
        ("⌘O", "Open a text file"),
        ("⌘+  ⌘−", "Text size"),
        ("⌘Q", "Quit"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shortcuts").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text(row.1).font(.system(size: 13))
                    }
                }
            }
            Divider()
            Text("Hold ⌃⌥ with Space, the arrows or R to control Prompter while another app is in front.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 290)
        .preferredColorScheme(.dark)
    }
}

struct Controls: View {
    @ObservedObject var m: Model
    var restart: () -> Void
    @State private var showShortcuts = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: restart) { Image(systemName: "backward.end.fill") }
                .help("Back to top (R)")
            Button { m.playing.toggle() } label: {
                Image(systemName: m.playing ? "pause.fill" : "play.fill").frame(width: 14)
            }
            .help("Play / pause (Space)")

            Button { m.voice.toggle() } label: {
                Image(systemName: m.voice ? "mic.fill" : "mic.slash.fill").frame(width: 16)
                    .foregroundStyle(m.voice ? Color.yellow : Color.white)
            }
            .help(m.voice ? "Following your voice" : "Follow my voice")
            slider("hare.fill", $m.speed, Model.speedRange, "Speed (↑ / ↓)")
                .disabled(m.voice)
                .opacity(m.voice ? 0.35 : 1)
            slider("textformat.size", $m.fontSize, Model.fontRange, "Text size (⌘+ / ⌘−)")
            slider("circle.lefthalf.filled", $m.opacity, 0.15...1.0, "Background opacity")

            Button { m.editing.toggle() } label: {
                Image(systemName: m.editing ? "checkmark" : "pencil").frame(width: 14)
            }
            .help(m.editing ? "Done editing (Esc)" : "Edit script (E)")
            Button { m.hiddenFromCapture.toggle() } label: {
                Image(systemName: m.hiddenFromCapture ? "eye.slash.fill" : "eye.fill").frame(width: 18)
            }
            .help(m.hiddenFromCapture ? "Hidden from screen sharing" : "Visible in screen sharing")
            Button { showShortcuts.toggle() } label: { Image(systemName: "keyboard").frame(width: 20) }
                .help("Keyboard shortcuts")
                .popover(isPresented: $showShortcuts, arrowEdge: .bottom) { Shortcuts() }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
        .environment(\.colorScheme, .dark)
    }

    private func slider(_ icon: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        _ help: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.white.opacity(0.7))
            Slider(value: value, in: range).controlSize(.small).frame(width: 78)
        }
        .help(help)
    }
}

// MARK: - Voice

/// Streams the microphone into the speech recogniser and reports the last few words heard.
final class VoiceFollower {
    var onHeard: (([String]) -> Void)?
    var onFailure: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private(set) var running = false

    func start(locales: [Locale]) {
        stop()
        recognizer = locales.lazy.compactMap { SFSpeechRecognizer(locale: $0) }.first ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            onFailure?("Speech recognition isn't available for this script's language right now.")
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onFailure?("No microphone found.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            onFailure?("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }
        running = true
        NSLog("voice: listening, locale %@, on-device %d", recognizer.locale.identifier,
              recognizer.supportsOnDeviceRecognition ? 1 : 0)
        startTask()
    }

    func stop() {
        guard running else { return }
        running = false
        generation += 1
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func startTask() {
        guard running, let recognizer else { return }
        task?.cancel()
        generation += 1
        let gen = generation
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }
        request = r
        task = recognizer.recognitionTask(with: r) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.running, gen == self.generation else { return }
                if let result {
                    let heard = tokenize(result.bestTranscription.formattedString).map(\.word)
                    if !heard.isEmpty { self.onHeard?(Array(heard.suffix(5))) }
                    // Start a fresh request at pauses and before the transcript gets unwieldy.
                    if result.isFinal || heard.count > 150 { self.startTask() }
                } else if let error {
                    NSLog("voice: recogniser error %@", error.localizedDescription)
                    // Usually "no speech detected" after a silence; keep listening.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if gen == self.generation { self.startTask() }
                    }
                }
            }
        }
    }
}

/// Words reduced to bare lowercase letters and digits, with where they sit in the text.
func tokenize(_ s: String) -> [(word: String, range: NSRange)] {
    var out: [(word: String, range: NSRange)] = []
    let ns = s as NSString
    ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { sub, range, _, _ in
        guard let sub else { return }
        let w = sub.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
        if !w.isEmpty { out.append((w, range)) }
    }
    return out
}

/// Forgiving comparison: the recogniser often gets word endings wrong.
func soundsLike(_ a: String, _ b: String) -> Bool {
    a == b || (a.count >= 5 && b.count >= 5 && a.prefix(4) == b.prefix(4))
}

// MARK: - Controller

final class Prompter: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    let model = Model()
    private var window: Panel!
    private let root = RootView()
    private let fade = NSView()
    private let scroll = ScriptScrollView()
    private var text: ScriptTextView!
    private let marker = NSTextField(labelWithString: "▸")
    private var controls: NSHostingView<Controls>!

    private var bag = Set<AnyCancellable>()
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var offset = 0.0
    private var lineHeight = 40.0
    private var hovering = false

    private let follower = VoiceFollower()
    private var words: [(word: String, range: NSRange)] = []
    /// Index of the next script word we expect to hear.
    private var cursor = 0
    private var lastHeard: [String] = []

    /// How far down the window the line being read sits.
    private let readFraction = 0.3

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        bind()
        registerHotKeys()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in self?.handleKey($0) ?? $0 }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Setup

    private func buildWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 760, height: 250)
        let frame = NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
                           width: size.width, height: size.height)
        window = Panel(contentRect: frame,
                       styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                       backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        [.miniaturizeButton, .zoomButton].forEach { window.standardWindowButton($0)?.isHidden = true }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 620, height: 150)
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameAutosaveName("PrompterWindow")

        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true
        window.contentView = root

        // Text fades out above and below the reading line.
        let gradient = CAGradientLayer()
        gradient.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.55).cgColor,
                           NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        gradient.locations = [0, 0.3, 0.6, 0.86, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        fade.wantsLayer = true
        fade.layer?.mask = gradient
        root.addSubview(fade)

        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: size.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        text = ScriptTextView(frame: NSRect(origin: .zero, size: size), textContainer: container)
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.drawsBackground = false
        text.isRichText = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.insertionPointColor = .systemYellow
        text.delegate = self
        text.string = model.script

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = text
        scroll.onUserScroll = { [weak self] in
            guard let self else { return }
            self.offset = self.scroll.contentView.bounds.origin.y
            self.syncCursorToScroll()
        }
        fade.addSubview(scroll)

        marker.font = .systemFont(ofSize: 22, weight: .bold)
        marker.textColor = .systemYellow
        marker.sizeToFit()
        root.addSubview(marker)

        controls = NSHostingView(rootView: Controls(m: model, restart: { [weak self] in self?.restart() }))
        root.addSubview(controls)

        root.onLayout = { [weak self] in self?.layoutViews() }
        root.onHover = { [weak self] in
            self?.hovering = $0
            self?.updateControlsVisibility()
        }

        applyStyle()
        setEditing(false)
    }

    private func bind() {
        // DispatchQueue.main so the model already holds the new value, and so
        // updates keep flowing while a slider is being dragged.
        let main = DispatchQueue.main
        model.$playing.removeDuplicates().receive(on: main).sink { [weak self] in self?.setPlaying($0) }.store(in: &bag)
        model.$editing.removeDuplicates().receive(on: main).sink { [weak self] in self?.setEditing($0) }.store(in: &bag)
        model.$fontSize.removeDuplicates().receive(on: main).sink { [weak self] _ in self?.applyStyle() }.store(in: &bag)
        model.$opacity.receive(on: main).sink { [weak self] in
            self?.root.layer?.backgroundColor = NSColor.black.withAlphaComponent($0).cgColor
        }.store(in: &bag)
        model.$voice.removeDuplicates().dropFirst().receive(on: main).sink { [weak self] _ in
            guard let self else { return }
            // Re-enter the current play state in the new mode.
            self.setPlaying(self.model.playing)
            if !self.model.voice { self.setCursor(0) }
        }.store(in: &bag)
        follower.onHeard = { [weak self] in self?.heard($0) }
        follower.onFailure = { [weak self] in self?.voiceFailed($0) }
        model.$hiddenFromCapture.receive(on: main).sink { [weak self] in
            self?.window.sharingType = $0 ? .none : .readOnly
        }.store(in: &bag)
    }

    private func buildMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Hide Prompter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Prompter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(app, to: main)

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open Script…", action: #selector(openScript), keyEquivalent: "o").target = self
        addSubmenu(file, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(paste), keyEquivalent: "v").target = self
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(edit, to: main)

        NSApp.mainMenu = main
    }

    private func addSubmenu(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem()
        item.submenu = menu
        main.addItem(item)
    }

    // MARK: Layout & style

    private func layoutViews() {
        let b = root.bounds
        fade.frame = b
        fade.layer?.mask?.frame = fade.bounds
        scroll.frame = fade.bounds
        if text.frame.width != scroll.contentSize.width { text.frame.size.width = scroll.contentSize.width }
        if text.frame.origin != .zero { text.setFrameOrigin(.zero) }

        let readY: CGFloat = b.height * readFraction
        let inset = NSSize(width: 40, height: max(8, readY - lineHeight / 2))
        if text.textContainerInset != inset { text.textContainerInset = inset }

        marker.frame.origin = NSPoint(x: 12, y: b.height - readY - marker.frame.height / 2.0)

        let c = controls.fittingSize
        controls.frame = NSRect(x: (b.width - c.width) / 2, y: 10, width: c.width, height: c.height)
        scrollTo(offset)
    }

    private func applyStyle() {
        let font = NSFont.systemFont(ofSize: model.fontSize, weight: .semibold)
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.15
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: para]

        let oldHeight = max(text.frame.height, 1)
        text.typingAttributes = attrs
        if let storage = text.textStorage {
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }
        lineHeight = (text.layoutManager?.defaultLineHeight(for: font) ?? model.fontSize * 1.2) * 1.15
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        text.sizeToFit()
        // Keep roughly the same place in the script.
        scrollTo(offset * text.frame.height / oldHeight)
    }

    private func updateControlsVisibility() {
        let show = hovering || !model.playing
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            controls.animator().alphaValue = show ? 1 : 0
            window.standardWindowButton(.closeButton)?.animator().alphaValue = show ? 1 : 0
        }
    }

    // MARK: Playback

    private var maxOffset: Double { max(0, text.frame.height - scroll.contentView.bounds.height) }

    private func scrollTo(_ y: Double) {
        offset = min(max(0, y), maxOffset)
        scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: offset))
    }

    private func setPlaying(_ playing: Bool) {
        timer?.invalidate()
        timer = nil
        follower.stop()
        if playing {
            if model.editing { model.editing = false }
            if offset >= maxOffset - 1 { scrollTo(0) }
            if model.voice { startVoice() }
            lastTick = CACurrentMediaTime()
            let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        updateControlsVisibility()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        if model.voice {
            // Ease towards the word being spoken.
            scrollTo(offset + (voiceTarget() - offset) * min(1, dt * 5))
            return
        }
        scrollTo(offset + model.speed / 60 * lineHeight * dt)
        if offset >= maxOffset { model.playing = false }
    }

    private func setEditing(_ editing: Bool) {
        if editing, model.playing { model.playing = false }
        text.isEditable = editing
        text.isSelectable = editing
        marker.isHidden = editing
        if editing { setCursor(0) }
        window.makeFirstResponder(editing ? text : nil)
        if editing { NSApp.activate(ignoringOtherApps: true); window.makeKey() }
    }

    func restart() { scrollTo(0); syncCursorToScroll() }
    func jump(lines: Double) { scrollTo(offset + lines * lineHeight); syncCursorToScroll() }
    func nudgeSpeed(_ delta: Double) {
        model.speed = min(max(model.speed + delta, Model.speedRange.lowerBound), Model.speedRange.upperBound)
    }
    func nudgeFont(_ delta: Double) {
        model.fontSize = min(max(model.fontSize + delta, Model.fontRange.lowerBound), Model.fontRange.upperBound)
    }

    // MARK: Voice following

    private func startVoice() {
        words = tokenize(text.string)
        lastHeard = []
        syncCursorToScroll()
        SFSpeechRecognizer.requestAuthorization { status in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async { [self] in
                    guard model.playing, model.voice else { return }
                    guard status == .authorized, mic else {
                        voiceFailed("Prompter needs Microphone and Speech Recognition access. "
                            + "Allow both in System Settings → Privacy & Security.")
                        return
                    }
                    follower.start(locales: scriptLocales())
                }
            }
        }
    }

    private func voiceFailed(_ message: String) {
        NSLog("voice: failed %@", message)
        model.playing = false
        model.voice = false
        let alert = NSAlert()
        alert.messageText = "Can't follow your voice"
        alert.informativeText = message
        alert.runModal()
    }

    /// Recogniser locales to try, best first, based on the language the script is written in.
    private func scriptLocales() -> [Locale] {
        let current = Locale.current
        guard let code = NLLanguageRecognizer.dominantLanguage(for: text.string)?.rawValue,
              current.language.languageCode?.identifier != code else {
            return [current, Locale(identifier: "en-US")]
        }
        let matching = SFSpeechRecognizer.supportedLocales()
            .filter { $0.language.languageCode?.identifier == code }
            .sorted { $0.identifier < $1.identifier }
        let home = code == "en" ? "US" : code.uppercased()
        let preferred = matching.first { $0.region?.identifier == home }
        return ([preferred] + matching.map(Optional.some)).compactMap { $0 }
    }

    /// Finds where the last few spoken words line up with the script, looking ahead of the cursor only.
    private func heard(_ tail: [String]) {
        guard model.playing, model.voice, tail != lastHeard, cursor < words.count else { return }
        lastHeard = tail
        var best = (score: 0, end: -1)
        for end in cursor...min(words.count - 1, cursor + 30) {
            guard soundsLike(words[end].word, tail[tail.count - 1]) else { continue }
            var score = 0
            for i in 0..<tail.count where end - i >= 0 {
                if soundsLike(words[end - i].word, tail[tail.count - 1 - i]) { score += 1 }
            }
            if score > best.score { best = (score, end) }
        }
        // The very next word is enough on its own; skipping ahead needs more agreement the further it goes.
        let skip = best.end - cursor
        let needed = skip == 0 ? 1 : (skip <= 8 ? 2 : 3)
        NSLog("voice: heard [%@] cursor %d/%d match end %d score %d needed %d", tail.joined(separator: " "),
              cursor, words.count, best.end, best.score, needed)
        guard best.end >= 0, best.score >= needed else { return }
        setCursor(best.end + 1)
        if cursor >= words.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.cursor >= self.words.count else { return }
                self.model.playing = false
            }
        }
    }

    /// Moves the cursor and dims everything already read.
    private func setCursor(_ i: Int) {
        cursor = max(0, min(i, words.count))
        guard let lm = text.layoutManager, let storage = text.textStorage else { return }
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
        guard cursor > 0 else { return }
        let end = min(cursor < words.count ? words[cursor].range.location : storage.length, storage.length)
        lm.addTemporaryAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.4),
                                 forCharacterRange: NSRange(location: 0, length: end))
    }

    /// After a manual scroll or jump, carry on from the line sitting at the marker.
    private func syncCursorToScroll() {
        guard model.voice, !words.isEmpty, let lm = text.layoutManager, let tc = text.textContainer,
              lm.numberOfGlyphs > 0 else { return }
        let y = offset + scroll.bounds.height * readFraction - text.textContainerInset.height
        let glyph = lm.glyphIndex(for: NSPoint(x: 0, y: max(0, y)), in: tc)
        var line = NSRange()
        _ = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &line)
        let char = lm.characterIndexForGlyph(at: line.location)
        lastHeard = []
        setCursor(words.firstIndex { $0.range.location >= char } ?? words.count)
    }

    /// Scroll position that puts the word at the cursor on the reading line.
    private func voiceTarget() -> Double {
        guard !words.isEmpty, let lm = text.layoutManager, let tc = text.textContainer,
              let storage = text.textStorage else { return offset }
        let range = words[min(cursor, words.count - 1)].range
        guard NSMaxRange(range) <= storage.length else { return offset }
        let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let line = lm.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let word = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        // Slide through the line as it's read, rather than hopping a line at a time.
        var progress = line.width > 0 ? Double((word.minX - line.minX) / line.width) : 0
        if cursor >= words.count { progress = 1 }
        let y = Double(line.midY) + (progress - 0.5) * Double(line.height) + Double(text.textContainerInset.height)
        return y - Double(scroll.bounds.height) * readFraction
    }

    // MARK: Script

    func textDidChange(_ notification: Notification) {
        model.script = text.string
    }

    private func setScript(_ s: String) {
        model.playing = false
        setCursor(0)
        words = []
        text.string = s
        model.script = s
        applyStyle()
        scrollTo(0)
    }

    @objc private func openScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url,
              let s = try? String(contentsOf: url, encoding: .utf8) else { return }
        setScript(s)
    }

    /// ⌘V while editing pastes at the cursor; otherwise it replaces the whole script.
    @objc private func paste() {
        if model.editing {
            text.pasteAsPlainText(nil)
        } else if let s = NSPasteboard.general.string(forType: .string), !s.isEmpty {
            setScript(s)
        }
    }

    // MARK: Keys

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard e.window === window else { return e }
        let cmd = e.modifierFlags.contains(.command)
        let key = Int(e.keyCode)

        if cmd {
            switch key {
            case kVK_ANSI_Equal: nudgeFont(2); return nil
            case kVK_ANSI_Minus: nudgeFont(-2); return nil
            default: return e
            }
        }
        if model.editing {
            if key == kVK_Escape { model.editing = false; return nil }
            return e
        }
        switch key {
        case kVK_Space: model.playing.toggle()
        case kVK_UpArrow: nudgeSpeed(2)
        case kVK_DownArrow: nudgeSpeed(-2)
        case kVK_LeftArrow: jump(lines: -2)
        case kVK_RightArrow: jump(lines: 2)
        case kVK_ANSI_R: restart()
        case kVK_ANSI_E, kVK_Delete: model.editing = true
        default: return e
        }
        return nil
    }

    /// ⌃⌥ + the same keys, system-wide, so the prompter can be driven while another app has focus.
    private let hotKeys = [kVK_Space, kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow, kVK_ANSI_R]

    private func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            prompter.hotKeyPressed(Int(id.id))
            return noErr
        }, 1, &spec, nil, nil)

        for (i, key) in hotKeys.enumerated() {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey),
                                EventHotKeyID(signature: OSType(0x50524D54), id: UInt32(i)),
                                GetApplicationEventTarget(), 0, &ref)
        }
    }

    func hotKeyPressed(_ index: Int) {
        guard hotKeys.indices.contains(index) else { return }
        switch hotKeys[index] {
        case kVK_Space: model.playing.toggle()
        case kVK_UpArrow: nudgeSpeed(2)
        case kVK_DownArrow: nudgeSpeed(-2)
        case kVK_LeftArrow: jump(lines: -2)
        case kVK_RightArrow: jump(lines: 2)
        case kVK_ANSI_R: restart()
        default: break
        }
    }
}

// MARK: - Main

let prompter = Prompter()
let application = NSApplication.shared
application.delegate = prompter
application.setActivationPolicy(.regular)
application.run()
