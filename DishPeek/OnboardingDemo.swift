import SwiftUI

// The menu the first-launch pages show (Kia, 2026-11-21). It is drawn in code, so it works offline and for
// everyone: a real photo of one German menu turning into Chinese only spoke to Chinese users. It is written
// in a language the person doesn't read: Korean, or Japanese for Korean speakers. The same noodle shop as
// the sample menu, so the dish photos are real.
enum DemoMenu {
    struct Texts {
        var title: String
        var subtitle: String
        var section: String
        var dishes: [String]      // in the order printed; the first four are shown
        var footer: String
    }

    static let prices = ["9,000", "7,000", "9,000", "10,000", "1,000", "5,000"]
    // The photos of the first four dishes, from the app's own assets.
    static let photos = ["kalguksu", "mandu", "bibim-guksu", "kongguksu"]

    static let korean = Texts(title: "수목칼국수", subtitle: "손칼국수 전문점", section: "식사",
                              dishes: ["칼국수", "만두 (6개)", "비빔국수", "콩국수", "공기밥", "막걸리"],
                              footer: "영업시간 11:00 – 21:00")
    static let japanese = Texts(title: "水木カルグクス", subtitle: "手打ち麺の専門店", section: "お食事",
                                dishes: ["カルグクス", "餃子（6個）", "ビビン麺", "コングクス", "ライス", "マッコリ"],
                                footer: "営業時間 11:00 – 21:00")

    // The menu as translated into each language the app speaks.
    static let translations: [String: Texts] = [
        "zh-Hans": Texts(title: "水木刀切面", subtitle: "手擀面专门店", section: "主食",
                         dishes: ["刀切面", "饺子（6个）", "拌面", "豆浆凉面", "米饭", "米酒"], footer: "营业时间 11:00 – 21:00"),
        "zh-Hant": Texts(title: "水木刀切麵", subtitle: "手擀麵專門店", section: "主食",
                         dishes: ["刀切麵", "餃子（6個）", "拌麵", "豆漿涼麵", "白飯", "米酒"], footer: "營業時間 11:00 – 21:00"),
        "en": Texts(title: "Sumok Kalguksu", subtitle: "Handmade noodle house", section: "Meals",
                    dishes: ["Knife-cut noodle soup", "Dumplings (6)", "Spicy mixed noodles", "Cold soy milk noodles", "Rice", "Makgeolli rice wine"],
                    footer: "Open 11:00 – 21:00"),
        "ja": Texts(title: "水木カルグクス", subtitle: "手打ち麺の専門店", section: "お食事",
                    dishes: ["手切り麺のスープ", "餃子（6個）", "ビビン麺", "冷たい豆乳麺", "ご飯", "マッコリ"], footer: "営業時間 11:00 – 21:00"),
        "ko": korean,
        "de": Texts(title: "Sumok Kalguksu", subtitle: "Handgemachte Nudeln", section: "Hauptgerichte",
                    dishes: ["Nudelsuppe", "Teigtaschen (6)", "Scharfe Nudeln", "Kalte Sojanudeln", "Reis", "Reiswein"],
                    footer: "Geöffnet 11:00 – 21:00"),
        "fr": Texts(title: "Sumok Kalguksu", subtitle: "Nouilles faites main", section: "Plats",
                    dishes: ["Soupe de nouilles", "Raviolis (6)", "Nouilles épicées", "Nouilles froides au soja", "Riz", "Vin de riz"],
                    footer: "Ouvert 11:00 – 21:00"),
        "es": Texts(title: "Sumok Kalguksu", subtitle: "Fideos hechos a mano", section: "Platos",
                    dishes: ["Sopa de fideos", "Empanadillas (6)", "Fideos picantes", "Fideos fríos de soja", "Arroz", "Vino de arroz"],
                    footer: "Abierto 11:00 – 21:00"),
        "th": Texts(title: "ซูมกคัลกุกซู", subtitle: "ร้านบะหมี่ทำมือ", section: "อาหาร",
                    dishes: ["ก๋วยเตี๋ยวเส้นมีด", "เกี๊ยว (6 ชิ้น)", "บะหมี่ยำ", "บะหมี่เย็นนมถั่วเหลือง", "ข้าวสวย", "มักกอลลี"],
                    footer: "เปิด 11:00 – 21:00"),
        "vi": Texts(title: "Sumok Kalguksu", subtitle: "Quán mì cắt tay", section: "Món chính",
                    dishes: ["Mì cắt dao", "Bánh xếp (6 cái)", "Mì trộn cay", "Mì lạnh sữa đậu", "Cơm trắng", "Rượu gạo"],
                    footer: "Mở cửa 11:00 – 21:00"),
    ]

    // The printed menu and its translation for someone reading `language`.
    static func pair(for language: String) -> (printed: Texts, redrawn: Texts) {
        let code = Languages.translationChoices.first { language.hasPrefix($0) } ?? "en"
        let printed = code == "ko" ? japanese : korean
        return (printed, translations[code] ?? translations["en"]!)
    }
}

// The three first-launch pages as one scene that keeps going (Kia, 2026-11-21): no box around it and no
// background, quick, and each page grows out of the last one.
// 1. A plain menu card in brand colours: a green beam reads it, every line is outlined like the phone's OCR,
//    the dishes turn into your language one by one, then the whole card does.
// 2. The dish names and prices fly out of the card into a list, and a photo slides in beside each.
// 3. On the same list, the Peek's Pick lands on one dish and a warning on one you might not eat.
struct FeatureScene: View {
    var page: Int
    var printed: DemoMenu.Texts
    var redrawn: DemoMenu.Texts

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Namespace var flight
    @State var scan = Scan.idle
    @State var beamDown = false
    @State var photosIn = false
    @State var marks = 0            // 1: the pick, 2: and the warning

    enum Scan: Int, Comparable {
        case idle, reading, outlined, lines, whole
        static func < (a: Scan, b: Scan) -> Bool { a.rawValue < b.rawValue }
    }

    static let count = 4

    var body: some View {
        ZStack {
            if page == 0 {
                menu
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.96))))
            } else {
                list
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: settle)
        .task(id: page) { await play() }
    }

    // MARK: Page 1: the menu

    var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: scan >= .whole ? redrawn.title : printed.title)
                .font(.system(size: 22, weight: .bold))
                .contentTransition(.opacity)
                .background { ocr(on: scan >= .outlined && scan < .whole, order: 0) }
                .animation(.smooth(duration: 0.35), value: scan >= .whole)
            Text(verbatim: scan >= .whole ? redrawn.subtitle : printed.subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .contentTransition(.opacity)
                .padding(.top, 4)
                .background { ocr(on: scan >= .outlined && scan < .whole, order: 1) }
                .animation(.smooth(duration: 0.35).delay(0.05), value: scan >= .whole)
            Capsule()
                .fill(Color.action)
                .frame(width: 28, height: 3)
                .padding(.top, 14)
                .padding(.bottom, 6)
            ForEach(0..<Self.count, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Color.border).frame(height: 1)
                }
                HStack {
                    Text(verbatim: scan >= .lines ? redrawn.dishes[index] : printed.dishes[index])
                        .contentTransition(.opacity)
                        .matchedGeometryEffect(id: "name\(index)", in: flight)
                        .background { ocr(on: scan >= .outlined && scan < .whole, translated: scan >= .lines, order: 2 + index * 2) }
                    Spacer(minLength: 12)
                    Text(verbatim: DemoMenu.prices[index])
                        .matchedGeometryEffect(id: "price\(index)", in: flight)
                        .background { ocr(on: scan >= .outlined && scan < .whole, order: 3 + index * 2) }
                }
                .font(.system(size: 16, weight: .semibold))
                .padding(.vertical, 11)
                .animation(.smooth(duration: 0.35).delay(Double(index) * 0.09), value: scan >= .lines)
            }
        }
        .foregroundStyle(Color.textPrimary)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.surface)
                .shadow(color: Color.textPrimary.opacity(0.10), radius: 20, y: 10)
        }
        // The beam that reads the card, top to bottom.
        .overlay {
            GeometryReader { geo in
                LinearGradient(stops: [
                    .init(color: Color.action.opacity(0), location: 0),
                    .init(color: Color.action.opacity(0.22), location: 0.85),
                    .init(color: Color.action.opacity(0.7), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
                .offset(y: beamDown ? geo.size.height : -70)
                .opacity(scan == .reading || scan == .outlined ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: scan)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 6)
    }

    // A line found by the phone's OCR: outlined in green, filled in once it's translated.
    func ocr(on: Bool, translated: Bool = false, order: Int) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.action.opacity(translated ? 0.28 : 0.12))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.action, lineWidth: 1.5) }
            .padding(.horizontal, -6)
            .padding(.vertical, -3)
            .scaleEffect(x: on ? 1 : 0.3, anchor: .leading)
            .opacity(on ? 1 : 0)
            .animation(.smooth(duration: 0.3).delay(on ? Double(order) * 0.035 : 0), value: on)
            .animation(.smooth(duration: 0.3), value: translated)
    }

    // MARK: Pages 2 and 3: the list

    var list: some View {
        VStack(spacing: 12) {
            ForEach(0..<Self.count, id: \.self) { index in
                row(index)
            }
        }
        .padding(.horizontal, 6)
    }

    func row(_ index: Int) -> some View {
        let picked = index == 0 && marks >= 1
        let flagged = index == 1 && marks >= 2
        return HStack(spacing: 12) {
            if photosIn {
                Image(DemoMenu.photos[index])
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .saturation(flagged ? 0.45 : 1)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: redrawn.dishes[index])
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary.opacity(flagged ? 0.55 : 1))
                    .matchedGeometryEffect(id: "name\(index)", in: flight)
                    // The lines leave the menu one after another.
                    .animation(.spring(duration: 0.6, bounce: 0.18).delay(Double(index) * 0.06), value: page)
                Text(verbatim: printed.dishes[index])
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
                if picked {
                    Badge(info: BadgeInfo(text: String(localized: "Peek's Pick"), peekMark: true, style: .neutral))
                        .transition(.scale(scale: 1.6, anchor: .leading).combined(with: .opacity))
                        .padding(.top, 2)
                }
                if flagged {
                    Badge(info: BadgeInfo(text: Allergen.pork.title, emoji: Allergen.pork.emoji, style: .caution))
                        .transition(.offset(y: 6).combined(with: .opacity))
                        .padding(.top, 2)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: DemoMenu.prices[index])
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .matchedGeometryEffect(id: "price\(index)", in: flight)
                .animation(.spring(duration: 0.6, bounce: 0.18).delay(Double(index) * 0.06), value: page)
        }
        // Tall enough for the photo from the start, so the lines spread out as they land and nothing
        // jumps when the photos come in.
        .frame(minHeight: 54)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(picked ? Color(hex: 0xEEF8E2) : flagged ? Color(hex: 0xFDF0EC) : Color.surface)
                .shadow(color: Color.textPrimary.opacity(0.06), radius: 10, y: 4)
        }
        .animation(.smooth(duration: 0.4).delay(Double(index) * 0.08), value: photosIn)
        .animation(.spring(duration: 0.45, bounce: 0.3), value: marks)
    }

    // MARK: Timing

    // Coming back to a later page (from the next screen): show it as it ends, without playing it again.
    func settle() {
        if page >= 1 {
            scan = .whole
            photosIn = true
        }
        if page >= 2 { marks = 2 }
    }

    // Each page's part, quick (Kia, 2026-11-21: "快速过一下就行").
    func play() async {
        func wait(_ seconds: Double) async -> Bool {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.05 : seconds))
            return !Task.isCancelled
        }
        switch page {
        case 0:
            guard scan == .idle else { return }
            guard await wait(0.25) else { return }
            scan = .reading
            withAnimation(.easeInOut(duration: 0.8)) { beamDown = true }
            guard await wait(0.45) else { return }
            scan = .outlined
            guard await wait(0.7) else { return }
            scan = .lines
            guard await wait(0.75) else { return }
            scan = .whole
        case 1:
            scan = .whole
            guard !photosIn, await wait(0.55) else { return }
            photosIn = true
        case 2:
            guard marks < 2, await wait(0.3) else { return }
            marks = 1
            guard await wait(0.55) else { return }
            marks = 2
        default:
            break
        }
    }
}

// Above the chilies (Kia, 2026-11-21): the logo's two eyes, getting hotter. No pupils, as in the logo.
// Calm and green at no spice; then the brows knit, the cheeks flush, a drop of sweat, steam and a tremble,
// the colour going to red; at the hottest, fire in both eyes.
struct SpiceFace: View {
    var level: Int          // -1 before choosing, 0 not spicy … 5 very hot
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    static let colors: [Color] = [
        Color.action, Color(hex: 0xB8D94A), Color(hex: 0xF0C445), Color(hex: 0xF29B3A), Color(hex: 0xEE6A34), Color(hex: 0xE2412C),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: level < 3 || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                draw(&canvas, size: size, t: t)
            }
        }
        .frame(width: 240, height: 150)
        .keyframeAnimator(initialValue: 1.0, trigger: level) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.1, duration: 0.12)
            SpringKeyframe(1.0, duration: 0.35)
        }
        .accessibilityHidden(true)
    }

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let heat = max(0, level)
        let height: CGFloat = 78
        let s = height / DishPeekLogo.size.height
        let moving = !reduceMotion
        // A tremble when it's hot.
        let shake = moving && heat >= 4 ? (heat == 5 ? 2.2 : 1.1) : 0
        let origin = CGPoint(x: (size.width - DishPeekLogo.size.width * s) / 2 + shake * sin(t * 43),
                             y: 56 + (heat == 5 ? shake * 0.5 * sin(t * 57) : 0))
        let tf = DishPeekLogo.transform(height: height, origin: origin)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(tf) }
        let eyes: [CGFloat] = [20.7, 78]
        let color = level < 0 ? Color.action : Self.colors[heat]

        // Steam rising off the top.
        if heat >= 4 {
            for (k, x) in [28.0, 70.0].enumerated() {
                let phase = moving ? (t * 0.9 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1) : 0.4
                let base = -12 - phase * 12
                var puff = Path()
                puff.move(to: pt(x, base))
                puff.addCurve(to: pt(x, base - 13), control1: pt(x + 5, base - 4), control2: pt(x - 5, base - 9))
                c.stroke(puff, with: .color(Color(white: 0.62).opacity(0.75 * (1 - phase))), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }

        // Cheeks flushing.
        if heat >= 2 {
            for x in eyes {
                c.fill(Path(ellipseIn: CGRect(x: x - 9, y: 47, width: 18, height: 7)).applying(tf),
                       with: .color(Color(hex: 0xFF5A4E).opacity(0.1 * Double(heat))))
            }
        }

        // The logo itself, its colour heating up.
        let eo = FillStyle(eoFill: true)
        c.fill(DishPeekLogo.d.applying(tf), with: .color(color), style: eo)
        c.fill(DishPeekLogo.p.applying(tf), with: .color(color), style: eo)

        // Fire in both eyes at the hottest: inside the open eye, and out of the wink.
        if heat == 5 {
            let flicker = moving ? sin(t * 18) : 0
            let sway = moving ? 1.2 * sin(t * 11) : 0
            var open = c
            open.clip(to: Path(ellipseIn: CGRect(x: 20.703 - 10.4, y: 27.267 - 10.4, width: 20.8, height: 20.8)).applying(tf))
            flame(&open, base: pt(20.7 + sway, 38), height: 19 * s * (1 + 0.12 * flicker), width: 15 * s)
            var wink = c
            wink.clip(to: Path(ellipseIn: CGRect(x: 77.97 - 19, y: 27.27 - 19, width: 38, height: 38)).applying(tf))
            flame(&wink, base: pt(78 - sway, 34), height: 20 * s * (1 - 0.1 * flicker), width: 15 * s)
        }

        // A drop of sweat by the winking eye.
        if heat >= 3 {
            let bob = moving ? 1.5 * sin(t * 4) : 0
            // A round bottom and a point on top.
            let center = pt(103, 6 + bob), r = 4.2 * s
            var drop = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            drop.move(to: CGPoint(x: center.x, y: center.y - 2.6 * r))
            drop.addLine(to: CGPoint(x: center.x + r * 0.92, y: center.y - r * 0.4))
            drop.addLine(to: CGPoint(x: center.x - r * 0.92, y: center.y - r * 0.4))
            drop.closeSubpath()
            c.fill(drop, with: .color(Color(hex: 0x6EC3F4)))
        }

        // Brows: relaxed at no spice, knitting tighter as it gets hotter.
        let angle = level < 0 ? 0 : (heat == 0 ? -0.12 : Double(heat) * 0.1)
        for (x, inward) in [(eyes[0], 1.0), (eyes[1], -1.0)] {
            let half = 11.0, y = -6.0
            var brow = Path()
            brow.move(to: pt(x - half, y - inward * half * sin(angle)))
            brow.addLine(to: pt(x + half, y + inward * half * sin(angle)))
            c.stroke(brow, with: .color(Color.textOnAction.opacity(level < 0 ? 0.35 : 0.85)),
                     style: StrokeStyle(lineWidth: 3.6 * s, lineCap: .round))
        }
    }

    // One flame: orange outside, yellow inside, standing on `base`.
    func flame(_ c: inout GraphicsContext, base: CGPoint, height: CGFloat, width: CGFloat) {
        func shape(_ h: CGFloat, _ w: CGFloat) -> Path {
            var p = Path()
            let top = CGPoint(x: base.x, y: base.y - h)
            p.move(to: top)
            p.addCurve(to: base, control1: CGPoint(x: base.x + w * 0.2, y: base.y - h * 0.55), control2: CGPoint(x: base.x + w * 0.6, y: base.y))
            p.addCurve(to: top, control1: CGPoint(x: base.x - w * 0.6, y: base.y), control2: CGPoint(x: base.x - w * 0.2, y: base.y - h * 0.55))
            return p
        }
        c.fill(shape(height, width), with: .color(Color(hex: 0xFF7A1A)))
        c.fill(shape(height * 0.6, width * 0.6), with: .color(Color(hex: 0xFFD23F)))
    }
}
