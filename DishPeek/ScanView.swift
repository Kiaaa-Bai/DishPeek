import SwiftUI
import PhotosUI

// Screen 1: the camera, pointed at the menu. The whole screen is the viewfinder.
// On a phone it is the live camera and the shutter takes the photo. The Simulator has no camera,
// so there a real Korean menu photo fills the screen as if the camera saw it, and the shutter reads it.
// The photo button reads any menu photo from the library.
struct ScanView: View {
    @Environment(AppState.self) var state
    @State var flash = false
    @State var pickerItem: PhotosPickerItem?
    @State var camera = Camera()
    @State var cameraOn = false
    // The real photo being read, frozen in place of the viewfinder.
    @State var preview: UIImage?
    // Where the camera picture and the white corners sit on screen, to keep only what is inside the corners.
    @State var cameraFrame: CGRect = .zero
    @State var bracketsFrame: CGRect = .zero

    // What the camera is looking at: the user's photo, or the sample menu.
    var inView: ScannedMenu { preview == nil ? SampleMenu.menu : state.menu }

    var body: some View {
        ZStack(alignment: .top) {
            if cameraOn {
                CameraPreview(session: camera.session)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cameraFrame = $0 }
            } else if preview == nil {
                // The Simulator's stand-in for the camera: the whole menu, prices included.
                Color.black
                    .overlay {
                        Image("example-menu")
                            .resizable()
                            .scaledToFit()
                    }
            } else {
                Color.canvas
            }

            if let preview {
                Color.black
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 0) {
                ZStack {
                    // While scanning, the progress card says what is happening; the pill would say it twice.
                    if state.scan != .reading {
                        statusPill
                    }
                    HStack {
                        Spacer()
                        SettingsButton()
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)

                if preview == nil {
                    // On the camera (or the Simulator's photo): where to put the menu.
                    ScanBrackets()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bracketsFrame = $0 }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 36)
                }

                Spacer(minLength: 0)

                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(Text("Choose a menu photo"))

                    Spacer()

                    Button {
                        if cameraOn {
                            takeCameraPhoto()
                        } else {
                            takePhoto()
                        }
                    } label: {
                        Circle()
                            .fill(cameraOn ? Color.white : Color.action)
                            .frame(width: 60, height: 60)
                            .padding(6)
                            .overlay {
                                Circle().stroke(cameraOn ? Color.white : Color.action, lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Take photo")

                    Spacer()

                    Button {
                    } label: {
                        Image(systemName: "bolt")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
        }
        .overlay {
            // Shutter flash.
            Color.white
                .opacity(flash ? 0.85 : 0)
                .allowsHitTesting(false)
        }
        .overlay {
            if state.scan == .reading {
                ScanOnPhoto()
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: state.scan)
        .task {
            Backend.warmUp()
            // The camera (and its permission prompt) waits until the first-launch pages are done, so it is
            // asked for when it's about to be used (Kia, 2026-11-21).
            guard state.hasSetPreferences else { return }
            cameraOn = await camera.start()
        }
        .onChange(of: state.hasSetPreferences) { _, done in
            guard done else { return }
            Task { cameraOn = await camera.start() }
        }
        .onChange(of: pickerItem) {
            guard let pickerItem else { return }
            Task {
                if let data = try? await pickerItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await read(image)
                }
                self.pickerItem = nil
            }
        }
        .onChange(of: state.path) {
            // Back from the menu: the live camera again. Away from it, the camera rests.
            if state.path.isEmpty {
                preview = nil
                Task { cameraOn = await camera.start() }
            } else {
                camera.stop()
            }
        }
        .alert(Text("Couldn't read this menu"), isPresented: failedBinding) {
            Button("OK", role: .cancel) {
                state.scan = .idle
                preview = nil
            }
        } message: {
            if case .failed(let reason) = state.scan {
                Text(reason)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        // Like the Camera app: no status bar over the viewfinder.
        .statusBarHidden()
        .sensoryFeedback(.impact(weight: .medium), trigger: flash) { _, isOn in isOn }
    }
}

extension ScanView {
    // What the scan screen is doing, at the top.
    var statusPill: some View {
        Group {
            if cameraOn && preview == nil {
                Text("Point at the menu")
            } else {
                Text("\(Languages.name(inView.sourceLanguage)) menu detected")
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Color.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassEffect(.regular, in: .capsule)
    }

    // On a phone: take the photo from the live camera, then read it.
    func takeCameraPhoto() {
        withAnimation(.easeOut(duration: 0.06)) {
            flash = true
        }
        Task {
            let image = await camera.takePhoto()
            withAnimation(.easeOut(duration: 0.3)) {
                flash = false
            }
            if let image {
                // The camera keeps more than the screen shows (the preview is cropped to fill it): keep what the
                // screen showed, the whole screen, so the photo looks the same before and after (Kia, 2026-11-21:
                // cutting to the corners, then to the text, made it jump to a smaller picture).
                await read(image.cropped(toScreenRect: cameraFrame, inPreview: cameraFrame))
            }
        }
    }

    var failedBinding: Binding<Bool> {
        Binding {
            if case .failed = state.scan { return true }
            return false
        } set: { isShown in
            if !isShown { state.scan = .idle }
        }
    }

    // A real photo: read it, then open the menu. Whether we found the right restaurant is asked on the
    // menu itself, in a banner that doesn't stop anything (Kia, 2026-11-21: an alert right after the
    // redrawn menu appeared broke the moment).
    func read(_ image: UIImage) async {
        preview = image
        await state.scanPhoto(image)
        guard state.scan == .done else { return }
        state.scan = .idle
        state.askPlace = state.hasPlace
        state.path.append(.menu)
    }

    // No camera (the Simulator): the shutter reads the menu photo standing in for the camera.
    func takePhoto() {
        withAnimation(.easeOut(duration: 0.06)) {
            flash = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.3)) {
                flash = false
            }
            if let image = UIImage(named: "example-menu") {
                await read(image)
            }
        }
    }
}

// The four white corners of the scan frame.
struct ScanBrackets: Shape {
    func path(in r: CGRect) -> Path {
        let length: CGFloat = 30
        let radius: CGFloat = 16
        var p = Path()

        p.move(to: CGPoint(x: r.minX, y: r.minY + length))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + length, y: r.minY), radius: radius)
        p.addLine(to: CGPoint(x: r.minX + length, y: r.minY))

        p.move(to: CGPoint(x: r.maxX - length, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + length), radius: radius)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + length))

        p.move(to: CGPoint(x: r.maxX, y: r.maxY - length))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - length, y: r.maxY), radius: radius)
        p.addLine(to: CGPoint(x: r.maxX - length, y: r.maxY))

        p.move(to: CGPoint(x: r.minX + length, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - length), radius: radius)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - length))

        return p
    }
}

// The scan, played on the menu photo itself instead of a progress popup (Kia, 2026-11-21, after an HTML
// prototype on a real scan). The photo stays on screen; a green beam sweeps it while the text is read;
// every line then lights up where it is printed and light flows down the menu; the dishes turn green
// once they are understood; and when the redrawn menu arrives it is wiped in over the photo from top to
// bottom (line by line was tried on the phone and dropped, Kia 2026-11-21). A pill at the bottom says what is happening, with the logo drawing, filling and shining.
struct ScanOnPhoto: View {
    @Environment(AppState.self) var state
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // How dark the photo gets behind the lit lines, and how fast light flows down them.
    static let dim = 0.35
    static let flow = 0.8
    // In a card (the first-launch pages) instead of full screen: the corners hug the picture and the pill
    // sits near the bottom, with no room kept for the status bar or the shutter.
    var compact = false

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            ZStack(alignment: .bottom) {
                Canvas { canvas, size in
                    draw(&canvas, size: size, now: now)
                }
                ScanPill(now: now)
                    .padding(.bottom, compact ? 14 : 64)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
    }

    func since(_ step: AppState.ScanStep, _ now: Date) -> Double? {
        state.scanStepTimes[step].map { now.timeIntervalSince($0) }
    }

    func draw(_ context: inout GraphicsContext, size: CGSize, now: Date) {
        let reading = since(.reading, now) ?? 0
        let lit = since(.translating, now)
        let found = since(.redrawing, now)
        let reveal = since(.revealing, now)
        let clock = now.timeIntervalSinceReferenceDate

        // The whole photo first; once the menu part is cut out, that part fades in in its place.
        if let full = state.scanFullImage {
            var c = context
            c.opacity = 1 - out((lit ?? 0) / 0.35)
            c.draw(Image(uiImage: full), in: fit(full.size, in: size))
        }
        guard let image = state.scanImage ?? state.scanFullImage else { return }
        let rect = fit(image.size, in: size)
        if state.scanImage != nil {
            var c = context
            c.opacity = out((lit ?? 0) / 0.35)
            c.draw(Image(uiImage: image), in: rect)
        }

        let dishes = Set(state.scanDishBoxes.map(key))
        let strips = state.scanLines.map { LineStrip($0, in: rect, isDish: dishes.contains(key($0.box))) }
            .sorted { $0.center.y < $1.center.y }
        let wipe = AppState.wipeSeconds

        // The redrawn menu, wiped in from the top.
        var wipeY = -CGFloat.infinity
        if let reveal, let redrawn = state.scanRedrawn {
            let picture = context.resolve(Image(uiImage: redrawn))
            wipeY = rect.minY - 40 + (rect.height + 80) * ease(reveal / wipe)
            var c = context
            c.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: max(0, wipeY))))
            c.draw(picture, in: rect)
            // A softer few pixels under the edge.
            var soft = context
            soft.clip(to: Path(CGRect(x: 0, y: wipeY, width: size.width, height: 24)))
            soft.opacity = 0.5
            soft.draw(picture, in: rect)
        }

        // Darker behind the lines, lifting as the redrawn menu comes in.
        var dim = Self.dim * out((lit ?? 0) / 0.5)
        if let reveal { dim *= 1 - ease((reveal - (state.scanRedrawn == nil ? 0 : wipe * 0.75)) / 0.6) }
        if dim > 0 {
            let top = wipeY.isFinite ? max(0, wipeY) : 0
            context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: size.height - top)), with: .color(.black.opacity(dim)))
        }

        // Reading: a green beam sweeps down the photo until the text is found.
        let beamFade = lit.map { 1 - out($0 / 0.3) } ?? 1
        if beamFade > 0, !reduceMotion {
            let u = reading.truncatingRemainder(dividingBy: 1.1) / 1.1
            let y = rect.minY - 60 + (rect.height + 60) * ease(u)
            context.fill(Path(CGRect(x: 0, y: y - 70, width: size.width, height: 74)), with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.action.opacity(0), location: 0),
                    .init(color: Color.action.opacity(0.32 * beamFade), location: 0.85),
                    .init(color: Color(red: 0.84, green: 0.96, blue: 0.67).opacity(0.9 * beamFade), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: y - 70), endPoint: CGPoint(x: 0, y: y + 4)))
        }

        // The lines: they light up where they are printed, top to bottom, then light flows down them.
        if let lit {
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .white.opacity(0.55), radius: 7))
                for (rank, strip) in strips.enumerated() {
                    let appear = out((lit - Double(rank) * 0.022) / 0.35)
                    guard appear > 0 else { continue }
                    var alpha = appear
                    if let reveal {
                        alpha *= state.scanRedrawn == nil
                            ? 1 - out(reveal / 0.4)
                            : 1 - min(1, max(0, (wipeY - strip.center.y + 10) / 24))
                    }
                    guard alpha > 0.01 else { continue }
                    let green = strip.isDish ? out(((found ?? -1) - Double(rank) * 0.03) / 0.4) : 0
                    let phase = reduceMotion ? 0 : ((clock * Self.flow - Double(strip.center.y / max(1, rect.height)) * 1.2).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                    let pulse = max(0, 1 - abs(phase - 0.5) * 4)
                    let color = Color(red: 1 - 0.42 * green, green: 1 - 0.15 * green, blue: 1 - 0.69 * green)
                    let path = strip.path(grow: appear)
                    layer.opacity = alpha
                    layer.fill(path, with: .color(color.opacity(0.16 + 0.2 * pulse)))
                    layer.stroke(path, with: .color(color.opacity(0.45 + 0.4 * pulse)), lineWidth: 1.2)
                }
            }
        }

        // The bright edge of the wipe.
        if let reveal, state.scanRedrawn != nil, reveal < wipe + 0.1 {
            let fade = 1 - out((reveal - wipe + 0.3) / 0.4)
            context.fill(Path(CGRect(x: 0, y: wipeY - 30, width: size.width, height: 32)), with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.action.opacity(0), location: 0),
                    .init(color: Color.action.opacity(0.35 * fade), location: 0.9),
                    .init(color: Color(red: 0.86, green: 0.97, blue: 0.7).opacity(fade), location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: wipeY - 30), endPoint: CGPoint(x: 0, y: wipeY + 2)))
        }

        // The corners close in on the menu, and open out once it has turned into the new language.
        let open = reveal.map { ease(($0 - wipe) / 0.4) } ?? 0
        let inset = -24 + 34 * out(reading / 0.45) - 40 * open
        let top = compact ? rect.minY : max(64, rect.minY)
        let bottom = compact ? rect.maxY : min(size.height - 150, rect.maxY)
        let corners = CGRect(x: rect.minX + inset, y: top + inset, width: rect.width - 2 * inset, height: bottom - top - 2 * inset)
        var c = context
        c.opacity = 1 - open
        c.stroke(ScanBrackets().path(in: corners), with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }

    // Line boxes compared with a little rounding: the dishes' boxes come back from the server.
    func key(_ box: [Double]) -> String {
        box.map { String(format: "%.4f", $0) }.joined(separator: ",")
    }

    func fit(_ image: CGSize, in size: CGSize) -> CGRect {
        let scale = min(size.width / max(1, image.width), size.height / max(1, image.height))
        let fitted = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }
}

// One line read off the photo, as a rounded strip lying along it (tilted like the printed line).
struct LineStrip {
    var center: CGPoint
    var length: CGFloat
    var thickness: CGFloat
    var angle: CGFloat
    var isDish: Bool

    init(_ line: MenuText, in rect: CGRect, isDish: Bool) {
        let b = line.box
        let q = line.quad ?? [b[0], b[1], b[0] + b[2], b[1], b[0] + b[2], b[1] + b[3], b[0], b[1] + b[3]]
        func point(_ i: Int) -> CGPoint { CGPoint(x: rect.minX + q[i * 2] * rect.width, y: rect.minY + q[i * 2 + 1] * rect.height) }
        let (p0, p1, p2, p3) = (point(0), point(1), point(2), point(3))
        center = CGPoint(x: (p0.x + p1.x + p2.x + p3.x) / 4, y: (p0.y + p1.y + p2.y + p3.y) / 4)
        length = hypot(p1.x - p0.x, p1.y - p0.y) + 6
        thickness = max(7, hypot(p3.x - p0.x, p3.y - p0.y) * 0.78)
        angle = atan2(p1.y - p0.y, p1.x - p0.x)
        self.isDish = isDish
    }

    // The strip, grown from the line's start to `grow` of its length.
    func path(grow: Double) -> Path {
        let width = max(thickness, length * grow)
        return Path(roundedRect: CGRect(x: -length / 2, y: -thickness / 2, width: width, height: thickness), cornerRadius: thickness / 2)
            .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
    }
}

// What the scan is doing, in a glass pill: the logo acts it out, and a line of text says it.
struct ScanPill: View {
    @Environment(AppState.self) var state
    var now: Date

    var body: some View {
        HStack(spacing: 8) {
            ScanLogo(now: now)
                .frame(width: 44, height: 21)
            ZStack {
                Text(title)
                    .id(title)
                    .transition(.blurReplace)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .animation(.smooth(duration: 0.45), value: title)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 42)
        .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
        .animation(.smooth(duration: 0.4), value: title)
        .opacity(1 - ((state.scanStepTimes[.revealing].map { now.timeIntervalSince($0) }).map {
            min(1, max(0, ($0 - AppState.wipeSeconds) / 0.4))
        } ?? 0))
        .accessibilityLabel(Text(title))
    }

    var title: String {
        switch state.scanStep {
        case .reading: String(localized: "Reading the menu…")
        case .translating: String(localized: "Found \(state.scanLines.count) lines, translating…")
        case .redrawing:
            // The redraw is the long wait: after a moment, the dishes it is drawing, one by one.
            if let waited = state.scanStepTimes[.redrawing].map({ now.timeIntervalSince($0) }),
               waited > Self.namesAfter, !state.scanDishNames.isEmpty {
                state.scanDishNames[Int((waited - Self.namesAfter) / Self.nameSeconds) % state.scanDishNames.count]
            } else {
                String(localized: "Redrawing the menu…")
            }
        case .revealing: String(localized: "Done")
        }
    }

    // How long "Redrawing the menu…" stays before the dish names start, and how long each name shows.
    static let namesAfter = 2.5
    static let nameSeconds = 1.6
}

// The DishPeek logo acting out the scan (Kia, 2026-11-21): reading draws its outline, translating fills it
// with green like a glass filling up, waiting for the redraw sends a shine across it while the sparkles
// twinkle, and done makes the sparkles pop. Drawn from the logo's real shapes.
struct ScanLogo: View {
    @Environment(AppState.self) var state
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var now: Date

    var body: some View {
        Canvas { context, size in
            let times = state.scanStepTimes
            func since(_ step: AppState.ScanStep) -> Double? { times[step].map { now.timeIntervalSince($0) } }
            let clock = now.timeIntervalSinceReferenceDate
            let h = size.height
            let t = DishPeekLogo.transform(height: h)
            let d = DishPeekLogo.d.applying(t), p = DishPeekLogo.p.applying(t)
            var logo = d
            logo.addPath(p)
            let eo = FillStyle(eoFill: true)

            // The outline, drawn while the text is read.
            let drawn = since(.translating) == nil ? ease((since(.reading) ?? 0) / 0.9) : 1
            var strokes = context
            strokes.opacity = 1 - 0.85 * out(((since(.redrawing) ?? -1)) / 0.4)
            strokes.stroke(d.trimmedPath(from: 0, to: min(1, drawn * 1.15)), with: .color(Color.action), lineWidth: 1.1)
            strokes.stroke(p.trimmedPath(from: 0, to: min(1, max(0, drawn * 1.15 - 0.15))), with: .color(Color.action), lineWidth: 1.1)

            // The fill, rising while the dishes are translated, and full once they are.
            func rising(_ e: Double) -> Double { 0.92 * (1 - exp(-e / 1.6)) }
            var level = 0.0
            if let lit = since(.translating) {
                if let found = since(.redrawing) {
                    let reached = rising(lit - found)
                    level = reached + (1 - reached) * out(found / 0.35)
                } else {
                    level = rising(lit)
                }
            }
            if level > 0 {
                let y = h * (1.05 - 1.1 * level)
                let amplitude = since(.redrawing) == nil && !reduceMotion ? h * 0.06 : 0
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: y))
                for x in stride(from: 0.0, through: size.width, by: 2) {
                    wave.addLine(to: CGPoint(x: x, y: y + amplitude * sin(x * 0.45 + clock * 7)))
                }
                wave.addLine(to: CGPoint(x: size.width, y: h))
                wave.addLine(to: CGPoint(x: 0, y: h))
                wave.closeSubpath()
                var fill = context
                fill.clip(to: wave)
                fill.fill(logo, with: .color(Color.action), style: eo)
            }

            // The shine, crossing the logo while the menu is redrawn.
            if let found = since(.redrawing), since(.revealing) == nil, !reduceMotion {
                let u = found.truncatingRemainder(dividingBy: 1.5) / 1.5
                let x = -0.4 * size.width + 1.7 * size.width * ease(u)
                var shine = context
                shine.clip(to: logo, style: eo)
                let band = Path(CGRect(x: x, y: -h, width: h * 0.6, height: h * 3))
                    .applying(CGAffineTransform(a: 1, b: 0, c: -0.36, d: 1, tx: 0, ty: 0))
                shine.fill(band, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0), .white.opacity(0.85), .white.opacity(0)]),
                    startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + h * 0.6, y: 0)))
            }

            // The sparkles: faint until the redraw, twinkling while it is drawn, popping when it is done.
            let s = h / PeekMark.box.height
            let reveal = since(.revealing)
            let waiting = since(.redrawing) != nil && reveal == nil
            let pop = reveal.map { 1 + 0.45 * sin(min(1, $0 / 0.45) * .pi) } ?? 1
            var sparks = context
            sparks.opacity = reveal != nil ? 1 : waiting ? 0.55 + 0.45 * (0.5 + 0.5 * sin(clock * 3)) : 0.25
            for (index, spark) in [PeekMark.bigSparkle, PeekMark.smallSparkle].enumerated() {
                let twinkle = waiting && !reduceMotion ? 1 + 0.14 * sin(clock * 5 + Double(index) * 1.6) : 1
                sparks.fill(PeekMark.sparkle(center: CGPoint(x: spark.center.x * s, y: spark.center.y * s), radius: spark.radius * s * twinkle * pop),
                            with: .color(.white))
            }
        }
        .accessibilityHidden(true)
    }
}

// Easing, 0 to 1: smooth at both ends, and fast then gentle.
func ease(_ x: Double) -> Double {
    let x = min(1, max(0, x))
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

func out(_ x: Double) -> Double {
    let x = min(1, max(0, x))
    return 1 - pow(1 - x, 3)
}

// The scan's logo loader on its own clock, for waits that have no steps (Kia, 2026-11-21: "Can't decide?"):
// the outline draws, green fills it like a glass, a shine crosses it and the sparkles pop, then again.
struct LogoLoader: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    static let cycle = 2.8

    var body: some View {
        TimelineView(.animation) { context in
            let t = reduceMotion ? Self.cycle * 0.8 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
            Canvas { canvas, size in
                let h = size.height
                let transform = DishPeekLogo.transform(height: h)
                let d = DishPeekLogo.d.applying(transform), p = DishPeekLogo.p.applying(transform)
                var logo = d
                logo.addPath(p)
                let eo = FillStyle(eoFill: true)
                // 0–0.8 s draw, 0.6–1.6 s fill, 1.6–2.3 s shine, 2.1–2.5 s sparkles pop, 2.5–2.8 s fade out.
                let drawn = ease(t / 0.8)
                let level = ease((t - 0.6) / 1.0)
                let fadeOut = 1 - ease((t - 2.5) / 0.3)
                var strokes = canvas
                strokes.opacity = (1 - 0.8 * level) * fadeOut
                strokes.stroke(d.trimmedPath(from: 0, to: min(1, drawn * 1.15)), with: .color(Color.action), lineWidth: 1.4)
                strokes.stroke(p.trimmedPath(from: 0, to: min(1, max(0, drawn * 1.15 - 0.15))), with: .color(Color.action), lineWidth: 1.4)
                if level > 0 {
                    let y = h * (1.05 - 1.1 * level)
                    var wave = Path()
                    wave.move(to: CGPoint(x: 0, y: y))
                    for x in stride(from: 0.0, through: size.width, by: 2) {
                        wave.addLine(to: CGPoint(x: x, y: y + h * 0.05 * (1 - level) * sin(x * 0.4 + t * 9)))
                    }
                    wave.addLine(to: CGPoint(x: size.width, y: h))
                    wave.addLine(to: CGPoint(x: 0, y: h))
                    wave.closeSubpath()
                    var fill = canvas
                    fill.opacity = fadeOut
                    fill.clip(to: wave)
                    fill.fill(logo, with: .color(Color.action), style: eo)
                }
                let u = (t - 1.6) / 0.7
                if u > 0, u < 1 {
                    let x = -0.4 * size.width + 1.7 * size.width * ease(u)
                    var shine = canvas
                    shine.clip(to: logo, style: eo)
                    let band = Path(CGRect(x: x, y: -h, width: h * 0.6, height: h * 3))
                        .applying(CGAffineTransform(a: 1, b: 0, c: -0.36, d: 1, tx: 0, ty: 0))
                    shine.fill(band, with: .linearGradient(
                        Gradient(colors: [.white.opacity(0), .white.opacity(0.9), .white.opacity(0)]),
                        startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + h * 0.6, y: 0)))
                }
                let s = h / PeekMark.box.height
                let pop = (t - 2.1) / 0.4
                let scale = pop > 0 ? 1 + 0.4 * sin(min(1, pop) * .pi) : 1
                var sparks = canvas
                sparks.opacity = (t < 2.1 ? 0.25 : 1) * fadeOut
                for spark in [PeekMark.bigSparkle, PeekMark.smallSparkle] {
                    sparks.fill(PeekMark.sparkle(center: CGPoint(x: spark.center.x * s, y: spark.center.y * s), radius: spark.radius * s * scale),
                                with: .color(Color.textPrimary))
                }
            }
        }
        .aspectRatio(PeekMark.box.width / PeekMark.box.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

