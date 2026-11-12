import AppKit
import SwiftUI

/// O aplikaci DockPeek: značkový panel se symbolem a sloganem, verze, poznámka
/// o soukromí, autor (logo KOLARCIK) a právní dokumenty. Stejné rozložení jako Mindonia.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Verze \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 24) {
            BrandPanel()

            Text(version)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label("Náhledy oken vznikají jen v paměti vašeho Macu a nikam se neukládají ani neodesílají. DockPeek nemá žádný server, reklamy ani analytiku.",
                  systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 420, alignment: .leading)

            VStack(spacing: 12) {
                Text("Vytvořil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CreatorLogo()
                    .frame(maxWidth: 260)
                    .accessibilityLabel(Text(verbatim: "KOLARCIK – Simple solutions for complex days"))
                Text(verbatim: "© 2026 Luděk Kolarčík")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                LegalLinks()
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Vzhled ikony aplikace: bílý symbol na modrofialovém přechodu, s názvem a sloganem.
private struct BrandPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: StatusIcon.make())
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 88, height: 88)
                .padding(24)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text(verbatim: "DockPeek")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text("Všechna okna na dosah přímo z Docku.")
                .font(.headline)
                .opacity(0.85)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                // Barvy podkladu ikony aplikace (Tools/make-icon.swift)
                LinearGradient(colors: [Color(red: 0.43, green: 0.61, blue: 1.0),
                                        Color(red: 0.29, green: 0.31, blue: 0.90),
                                        Color(red: 0.20, green: 0.14, blue: 0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 220)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("DockPeek. Všechna okna na dosah přímo z Docku."))
    }
}

/// Logo autora – světlá a tmavá varianta podle vzhledu.
private struct CreatorLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let name = colorScheme == .dark ? "CreatorLogo-dark" : "CreatorLogo"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Text(verbatim: "KOLARCIK").font(.title3.weight(.semibold))
        }
    }
}

// MARK: - Právní dokumenty

/// Podmínky použití a Zásady ochrany soukromí.
enum LegalDocument: String, Identifiable, CaseIterable {
    case terms, privacy

    var id: String { rawValue }

    static let effectiveDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 11, day: 12).date ?? .now

    var title: String {
        switch self {
        case .terms: "Podmínky použití"
        case .privacy: "Zásady ochrany soukromí"
        }
    }

    struct Section: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }

    var intro: String {
        switch self {
        case .terms:
            "DockPeek je bezplatná aplikace, která po najetí myší na ikonu v Docku ukáže náhledy oken dané aplikace. Používáním aplikace souhlasíte s těmito podmínkami."
        case .privacy:
            "DockPeek je postavený tak, aby jeho autor neměl přístup k ničemu, co máte na obrazovce. Tyto zásady popisují, s jakými daty aplikace pracuje a kam se dostanou."
        }
    }

    var sections: [Section] {
        switch self {
        case .terms: [
            Section(title: "Aplikace „tak, jak je“",
                    text: "DockPeek je poskytován zdarma a bez záruky, tak jak je. Autor se snaží, aby fungoval spolehlivě, ale nezaručuje, že je bez chyb nebo vždy dostupný. Odpovědnost autora je omezena v rozsahu, který zákon dovoluje."),
            Section(title: "Systémová oprávnění",
                    text: "Ke své funkci DockPeek potřebuje oprávnění Zpřístupnění a Nahrávání obrazovky. Používá je jen k zobrazení náhledů oken, přepnutí na vybrané okno a ovládání přehrávačů. Oprávnění můžete kdykoli odebrat v Nastavení systému."),
            Section(title: "Ovládání přehrávačů",
                    text: "Ovládání Spotify a Hudby probíhá přes jejich veřejné rozhraní AppleScript. Na jejich používání se vztahují podmínky jejich poskytovatelů."),
            Section(title: "Změny podmínek",
                    text: "Podmínky se mohou s novými verzemi aplikace měnit. Aktuální znění je vždy v okně O aplikaci DockPeek."),
        ]
        case .privacy: [
            Section(title: "Žádný sběr dat",
                    text: "DockPeek nemá vlastní server. Autor neshromažďuje, nevidí ani nezpracovává žádná vaše data. Aplikace neobsahuje reklamy, analytiku ani sledování a nesdílí žádná data s třetími stranami."),
            Section(title: "Náhledy oken",
                    text: "Snímky oken se pořizují jen ve chvíli, kdy najedete myší na ikonu v Docku, drží se pouze v paměti Macu a nikam se neukládají ani neodesílají. Po ukončení aplikace zmizí."),
            Section(title: "Přehrávače",
                    text: "Název skladby, interpreta a pozici přehrávání čte DockPeek přímo ze Spotify nebo Hudby na vašem Macu. Obal alba ze Spotify se stahuje z adresy, kterou poskytne Spotify; nic dalšího se při tom neodesílá."),
            Section(title: "Nastavení",
                    text: "Zvolený vzhled náhledů a stav průvodce nastavením se ukládají jen lokálně v předvolbách aplikace. Odstraněním aplikace a jejích předvoleb zmizí vše, co DockPeek uložil."),
        ]
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(document.title).font(.title2.weight(.bold))
                    Text(document.intro).font(.body)
                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title).font(.headline)
                            Text(section.text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Platné od \(LegalDocument.effectiveDate.formatted(date: .long, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Spacer()
                Button("Hotovo", action: onDone).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
    }
}

/// Odkazy na právní dokumenty – otevírají se v listu (sheet) nad oknem O aplikaci.
struct LegalLinks: View {
    @State private var shown: LegalDocument?

    var body: some View {
        HStack(spacing: 16) {
            ForEach(LegalDocument.allCases) { document in
                Button(document.title) { shown = document }
                    .buttonStyle(.link)
                    .font(.footnote)
            }
        }
        .sheet(item: $shown) { document in
            LegalDocumentView(document: document) { shown = nil }
        }
    }
}

// MARK: - Okno

final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = "O aplikaci DockPeek"
        self.init(window: window)
        let hosting = NSHostingController(rootView: AboutView())
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting
    }

    func present() {
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
