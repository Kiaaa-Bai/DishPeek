import SwiftUI
import PhotosUI

// Screen 1: the camera, pointed at the menu. The whole screen is the viewfinder.
// On a phone it is the live camera and the shutter takes the photo. The Simulator has no camera,
// so there a real Korean menu photo fills the screen as if the camera saw it, and the shutter reads it.
// The photo button reads any menu photo from the library.
struct ScanView: View {
    @Environment(AppState.self) var state
    @State var showAlert = false
    @State var flash = false
    @State var pickerItem: PhotosPickerItem?
    @State var camera = Camera()
    @State var cameraOn = false
    // The real photo being read, frozen in place of the viewfinder.
    @State var preview: UIImage?

    // What the camera is looking at: the user's photo, or the sample menu.
    var inView: ScannedMenu { preview == nil ? SampleMenu.menu : state.menu }

    var body: some View {
        ZStack(alignment: .top) {
            if cameraOn {
                CameraPreview(session: camera.session)
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
                    statusPill
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
                ScanProgress()
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: state.scan)
        .task {
            cameraOn = await camera.start()
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
        .alert(Text("Are you at \(state.place.name)?"), isPresented: $showAlert) {
            // Default action: the system draws it as the green, prominent button.
            Button("Yes, this is it", role: .confirm) {
                state.path.append(.menu)
            }
            .keyboardShortcut(.defaultAction)
            Button("Somewhere else", role: .cancel) {
                // A real scan still shows its menu, just without this restaurant's rating.
                if state.photo != nil {
                    state.forgetPlace()
                    state.path.append(.menu)
                }
            }
        } message: {
            // Enough to tell this branch apart from others nearby.
            Text("\(state.place.area) · \(state.place.distanceText)\n\(rating) on Google Maps, \(state.place.ratingCount) reviews\n\nPhotos and Popular here will come from this place.")
        }
    }
}

extension ScanView {
    // What the scan screen is doing, at the top.
    var statusPill: some View {
        Group {
            if state.scan == .reading && state.scanStep == .redrawing {
                Text("Redrawing the menu…")
            } else if state.scan == .reading {
                Text("Reading the menu…")
            } else if cameraOn && preview == nil {
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
                await read(image)
            }
        }
    }

    var rating: String {
        state.place.rating.formatted(.number.precision(.fractionLength(1)))
    }

    var failedBinding: Binding<Bool> {
        Binding {
            if case .failed = state.scan { return true }
            return false
        } set: { isShown in
            if !isShown { state.scan = .idle }
        }
    }

    // A real photo: read it, then confirm the restaurant if we found one.
    func read(_ image: UIImage) async {
        preview = image
        await state.scanPhoto(image)
        guard state.scan == .done else { return }
        state.scan = .idle
        if state.hasPlace {
            showAlert = true
        } else {
            state.path.append(.menu)
        }
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

// What the scan is doing, with a bar that keeps moving, so a half-minute redraw never looks stuck.
// The real time left is unknown: each step fills its part of the bar quickly at first and slows down
// near the end of its part, and the bar jumps ahead when a step is done.
struct ScanProgress: View {
    @Environment(AppState.self) var state

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                ProgressView(value: progress(at: context.date))
                    .tint(Color.action)
                    .frame(width: 220)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.large))
        }
    }

    var title: String {
        switch state.scanStep {
        case .reading: String(localized: "Reading the menu…")
        case .redrawing: String(localized: "Redrawing the menu…")
        }
    }

    // Reading takes about 8 s, redrawing about 35 s (measured 2026-10-26).
    func progress(at date: Date) -> Double {
        let (start, end, expected): (Double, Double, Double) = switch state.scanStep {
        case .reading: (0, state.redraws ? 0.25 : 0.9, 8)
        case .redrawing: (0.25, 0.97, 35)
        }
        let elapsed = date.timeIntervalSince(state.scanStepStarted)
        return start + (end - start) * (1 - exp(-2 * elapsed / expected))
    }
}
