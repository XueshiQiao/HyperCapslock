<h1 align="center">
  <img src="./docs/assets/icon.png" alt="HyperCapslock" width="96" /><br/>
  HyperCapslock
</h1>

<p align="center">
  <b>Verwandle deine Feststelltaste (Caps Lock) in eine systemweite, vim-artige Navigationsebene — ohne die ursprüngliche Caps-Lock-Funktion zu verlieren.</b>
</p>

<p align="center">
  <a href="README.md">🇺🇸 English</a> •
  <a href="README_CN.md">🇨🇳 中文</a> •
  <a href="README_JA.md">🇯🇵 日本語</a> •
  <b>🇩🇪 Deutsch</b>
</p>

<p align="center">
  <a href="https://github.com/XueshiQiao/HyperCapslock/actions/workflows/build.yml"><img src="https://github.com/XueshiQiao/HyperCapslock/actions/workflows/build.yml/badge.svg" alt="Build" /></a>
  <a href="https://github.com/XueshiQiao/HyperCapslock/releases/latest"><img src="https://img.shields.io/github/v/release/XueshiQiao/HyperCapslock" alt="Release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3.0-blue" alt="License" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white" alt="macOS 14+" />
</p>

## Die Idee

Die Feststelltaste liegt direkt auf der Grundreihe (Home Row), tut aber so gut wie nichts. HyperCapslock bildet sie auf **F18** um (eine Taste, die es auf keiner Tastatur physisch gibt) und fängt dann F18 + andere Tastenkombinationen auf Betriebssystemebene ab, um Navigation, Bearbeitung, Wechsel der Eingabequelle und Shell-Befehle zu simulieren.

Da F18 kein echter Modifikator ist (weder Cmd, Ctrl, Shift noch Alt), **lässt es sich ohne zusätzliche Belegung mit all diesen Tasten kombinieren**:

| Kombination | Aktion |
|-------------|--------|
| `Caps + H` | ← Nach links bewegen |
| `Caps + Shift + H` | ← Auswahl nach links erweitern |
| `Caps + Alt + H` | ← Ein Wort nach links bewegen |
| `Caps + Shift + Alt + H` | ← Auswahl um ein Wort nach links erweitern |

Keine zusätzliche Konfiguration nötig. Die Systemmodifikatoren werden einfach durchgereicht.

Wenn du Caps Lock nur **antippst** und loslässt, ohne etwas anderes zu drücken, schaltet es weiterhin ganz normal Caps Lock ein/aus.

## Standard-Tastenbelegung

Alle Belegungen lassen sich über die grafische Oberfläche anpassen. Dies sind die Standardwerte:

### Navigation (vim-artig)

| Kombination | Aktion |
|-------------|--------|
| `Caps + H / J / K / L` | ← ↓ ↑ → Pfeiltasten |
| `Caps + A` | Pos1 (Zeilenanfang) |
| `Caps + E` | Ende (Zeilenende) |
| `Caps + Y` | Vorheriges Wort |
| `Caps + P` | Nächstes Wort |
| `Caps + U` | 10 Zeilen nach oben |
| `Caps + D` | 10 Zeilen nach unten |

### Bearbeitung

| Kombination | Aktion |
|-------------|--------|
| `Caps + I` | Rücktaste (Backspace) |
| `Caps + O` | Neue Zeile darunter (Ende + Enter) |
| `Caps + N` | `""""""` einfügen, Cursor mittig platziert |

### Wechsel der Eingabequelle (macOS)

| Kombination | Aktion |
|-------------|--------|
| `Caps + ,` | Zu ABC (Englisch) wechseln |
| `Caps + .` | Zu chinesischer Eingabe wechseln |

### Shell-Befehle

`Caps + Shift + [Taste]` kann über die grafische Oberfläche so belegt werden, dass beliebige Shell-Befehle ausgeführt werden.

## Installation (macOS)

### Homebrew

```bash
brew install --cask XueshiQiao/tap/hypercapslock
```

Oder lade das `.dmg` von den [GitHub Releases](https://github.com/XueshiQiao/HyperCapslock/releases) herunter.

### Berechtigungen

Die App benötigt die Berechtigung **Bedienungshilfen (Accessibility)**:
`Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen`

## Screenshot

<div align="center">
  <img src="./docs/assets/HyperCapslock.png" width="400" />
</div>

## Warum nicht Karabiner-Elements?

[Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) ist ein mächtiges Werkzeug mit über 21.000 Sternen, und ich habe es jahrelang verwendet. Aber für den speziellen Anwendungsfall „Caps Lock als Navigationsebene":

- **Konfigurationsaufwand** — Karabiner erfordert für nicht-triviale Umbelegungen das Bearbeiten von JSON von Hand. HyperCapslock bietet eine grafische Oberfläche, in der sich alles per Klick konfigurieren lässt.
- **Ressourcenverbrauch** — Karabiner installiert eine Kernel-Erweiterung und mehrere Hintergrundprozesse. HyperCapslock ist eine einzige, leichtgewichtige native macOS-App.
- **Konflikte mit Modifikatoren** — Karabiner bildet Caps Lock üblicherweise auf eine echte Modifikator-Kombination ab (z. B. Ctrl+Shift+Cmd+Opt). Dieser „Hyper-Key"-Ansatz funktioniert, kann aber mit bestehenden Tastenkürzeln kollidieren. HyperCapslock bildet Caps Lock auf F18 ab. Dadurch kollidiert es nicht mit bestehenden Tastenkürzeln und lässt sich problemlos mit echten Modifikatoren kombinieren.

Wenn du die volle Leistung von Karabiner brauchst (App-spezifische Regeln, Maus-Umbelegung, geräteabhängige Profile), nimm Karabiner. Wenn du vor allem überall Vim-Navigation mit minimaler Einrichtung nutzen möchtest, ist HyperCapslock wahrscheinlich die einfachere Lösung.

## Wie es funktioniert

Caps Lock wird auf Betriebssystemebene über `hidutil` auf F18 umgelegt. Anschließend installiert die App einen `CGEventTap` auf HID-Ebene — einen systemweiten Event-Tap, der Tastenereignisse abfängt, bevor irgendeine Anwendung sie zu sehen bekommt.

Wenn F18 gehalten und eine andere Taste gedrückt wird, verschluckt die App das ursprüngliche Ereignis und injiziert die umbelegte Taste (z. B. eine Pfeiltaste) in den Eingabestrom des Systems. Injizierte Ereignisse tragen eine Markierung, um Rückkopplungsschleifen zu verhindern.

Für die Zustandsverfolgung wird ein durch Locks geschützter Laufzeitzustand (`OSAllocatedUnfairLock` / `NSLock`) verwendet, damit Tap-Thread, Timer-Threads und UI threadsicher zusammenarbeiten. Der Hook-Callback macht nur das Nötigste — Ganzzahlvergleiche und frühe Returns — damit keine Eingabeverzögerung entsteht.

Die vollständigen technischen Details stehen in [how_does_it_work.md](how_does_it_work.md).

## Tech-Stack

- **Natives macOS** — SwiftUI + AppKit, Swift-5-Sprachmodus, macOS 14+
- CoreGraphics `CGEventTap` + `hidutil` für die F18-Umbelegung; IOKit für den CapsLock-Zustand; Carbon TIS für den Wechsel der Eingabequelle
- [Sparkle](https://sparkle-project.org) für automatische Updates, [Yams](https://github.com/jpsim/Yams) für die YAML-Konfiguration
- Ein einziger, leichtgewichtiger nativer Prozess

## Entwicklung

### Voraussetzungen

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Einrichtung

```bash
git clone https://github.com/XueshiQiao/HyperCapslock.git
cd HyperCapslock
brew install xcodegen
xcodegen generate
open HyperCapslock.xcodeproj   # Cmd+R zum Bauen & Ausführen
```

`project.yml` ist die maßgebliche Quelle für die Xcode-Projektkonfiguration; führe nach jeder Änderung `xcodegen generate` aus.

### Bauen

```bash
xcodebuild -project HyperCapslock.xcodeproj -scheme HyperCapslock -configuration Release build
```

## Fehlerbehebung

- **Hotkeys funktionieren nicht mehr**: Die Logs werden nach `/tmp/hypercapslock-macos.log` geschrieben. Versuche, die App in den Bedienungshilfen-Berechtigungen zu entfernen und wieder hinzuzufügen, und starte sie anschließend neu.
- **Gaming-Modus**: Über das Menüleistensymbol kannst du pausieren und fortsetzen, um alle Umbelegungen vorübergehend zu deaktivieren.

## Lizenz

GPL v3.0 — siehe [LICENSE](LICENSE).
