<h1 align="center">
  <img src="./docs/assets/icon.png" alt="HyperCapslock" width="96" /><br/>
  HyperCapslock
</h1>

<p align="center">
  <b>Macht aus deiner Caps-Lock-Taste eine systemweite Navigations- und Bearbeitungsebene im vim-Stil – ohne die ursprüngliche Caps-Lock-Funktion zu verlieren.</b>
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
  <a href="https://github.com/XueshiQiao/HyperCapslock/stargazers"><img src="https://img.shields.io/github/stars/XueshiQiao/HyperCapslock?style=social" alt="GitHub stars" /></a>
</p>

<p align="center">
  ⭐ <b>Wenn dir HyperCapslock gefällt, gib dem Repo einen <a href="https://github.com/XueshiQiao/HyperCapslock">Stern</a></b> – das hilft anderen, es zu finden.
</p>

## Die Idee

Caps Lock liegt direkt an der Home-Row, tut aber so gut wie nichts. HyperCapslock bildet die Taste auf **F18** ab – eine Taste, die auf keiner Tastatur physisch existiert – und fängt dann F18 + andere Tastenkombinationen auf OS-Ebene ab, um Navigation, Bearbeitung, Eingabequellen-Wechsel, Tastenkombinationen und Shell-Befehle zu simulieren.

Da F18 kein echter Modifier ist (weder Cmd, Ctrl, Shift noch Alt), **lässt es sich mühelos mit allen kombinieren, ohne eigene Kombinationen zu belegen**:

Wenn du also `Caps + H` auf die `←`-Pfeiltaste legst, bekommst du diese vier Verhaltensweisen ganz von selbst:

| Kombination | Aktion |
|-------------|--------|
| `Caps + H` | ← Nach links bewegen |
| `Caps + Shift + H` | ← Nach links auswählen |
| `Caps + Alt + H` | ← Ein Wort nach links bewegen |
| `Caps + Shift + Alt + H` | ← Ein Wort nach links auswählen |

Keine zusätzliche Konfiguration nötig – die System-Modifier werden unverändert durchgereicht.

Und wenn du Caps Lock nur **kurz antippst** und loslässt, ohne etwas anderes zu drücken, schaltet es Caps Lock weiterhin ganz normal ein und aus.

## ✨ Funktionsübersicht

Hier ist die vollständige Liste der Fähigkeiten der aktuellen Version. Alles lässt sich über die GUI konfigurieren – es gibt keine Konfigurationsdateien, die man von Hand bearbeiten müsste.

### 🎹 Trigger

Ein *Mapping* besteht aus einem **Trigger** plus einer **Aktion**. Unterstützte Trigger:

| Trigger | Beschreibung |
|---------|--------------|
| **Caps + Taste** | Caps (F18) halten und eine Taste drücken, z. B. `Caps + H` |
| **Caps + Shift + Taste** | Ein eigenständiges Mapping mit gehaltenem Shift – kann eine andere Aktion belegen als die Variante ohne Shift |
| **Caps einfach tippen (Caps×1)** | Wird durch einmaliges Tippen von Caps ausgelöst (ersetzt das standardmäßige Caps-Lock-Umschalten) |
| **Caps doppelt tippen (Caps×2)** | Wird durch zweimaliges schnelles Tippen von Caps ausgelöst; beeinflusst das Einfach-Tippen nicht |
| **Modifier doppelt tippen** | Wird durch zweimaliges schnelles Tippen eines Modifiers ausgelöst, mit Links/Rechts-Unterscheidung: ⌘ / ⌃ / ⌥ / ⇧ / Fn |

> Sobald du dem *einfachen Caps-Tippen* eine Aktion zuweist, kannst du das ursprüngliche Caps-Lock-Umschalten weiterhin behalten, indem du eine beliebige Taste auf die eingebaute Aktion **Toggle Caps Lock** legst.

### ⚡ Aktionen

Einem Trigger lässt sich genau eine der folgenden Aktionen zuweisen:

| Aktion | Was sie macht |
|--------|---------------|
| **Cursor bewegen** | Hoch / Runter / Links / Rechts, vorheriges/nächstes Wort, Zeilenanfang (Home), Zeilenende (End) |
| **N Zeilen springen** | Auf einmal beliebig viele Zeilen nach oben oder unten springen (z. B. 10 Zeilen runter); die Anzahl ist konfigurierbar |
| **Backspace / Neue Zeile / Anführungszeichen einfügen** | Backspace, eine neue Zeile darunter öffnen (Zeilenende + Return), ein Paar Anführungszeichen einfügen und den Cursor mittig setzen |
| **Eingabequelle wechseln** | Direkt zu einer bestimmten Eingabequelle wechseln (ABC, WeChat-Pinyin, ein japanisches IME usw.), per Auswahlliste |
| **Key Combo** | Eine beliebige System-Tastenkombination synthetisieren, z. B. `Cmd+Shift+V`, `Cmd+Ctrl+Space` |
| **Shell-Befehl ausführen** | Einen beliebigen Shell-Befehl ausführen (z. B. `open -a Calculator`, ein Skript anstoßen) |
| **App öffnen / wechseln** | Eine bestimmte Anwendung starten und in den Vordergrund holen |
| **Hold Modifier** | Einen Modifier so lange gedrückt halten, wie der Trigger gehalten wird, und beim Loslassen freigeben – gedacht für Push-to-Talk-Apps |
| **Toggle Caps Lock** | Das System-Caps-Lock explizit umschalten (um die ursprüngliche Caps-Lock-Funktion zu erhalten) |
| **Nichts tun (Do Nothing)** | Die Taste schlucken und nichts tun – praktisch, um eine Taste in bestimmten Apps zu „deaktivieren“ |

**Cursor bewegen** und **Backspace** reichen die tatsächlich gehaltenen Modifier (Shift / Option usw.) durch, sodass `Caps + Shift + H` markiert und `Caps + Option + H` wortweise springt – alles ohne weiteres Zutun. (Eingabequelle wechseln, Key Combo, Shell-Befehl, App öffnen und Hold Modifier tragen jeweils ihre eigene, explizite Modifier-Bedeutung und nehmen an diesem Durchreichen nicht teil.)

### 🎯 App-spezifische Regeln (Per-App Rules)

Die größte Neuerung gegenüber älteren Versionen: **Derselbe Trigger kann in verschiedenen Apps unterschiedliche Aktionen ausführen.**

- Füge einem beliebigen Mapping eine *App-Regel* hinzu: Passt die **aktive App** zu deiner gewählten App-Liste, läuft die Aktion der Regel; andernfalls die Standardaktion.
- Die Regeln werden der Reihe nach geprüft – die erste passende gewinnt, und du kannst die Reihenfolge ändern.
- Apps wählst du per App-Picker aus `/Applications`; du musst keine Bundle-IDs von Hand eintippen.
- Typische Einsätze: `Caps + J` in einer App auf etwas anderes umlegen, oder mit **Do Nothing** eine Taste in bestimmten Apps komplett deaktivieren.

### 🧩 Eigene Aktionen (Custom Actions)

- Über die eingebauten Aktionen hinaus kannst du **benannte eigene Aktionen** erstellen (z. B. „20 Zeilen runter springen“, „Rechner öffnen“, „rechtes Option halten“) und in der Bibliothek speichern.
- Eine eigene Aktion lässt sich von mehreren Mappings wiederverwenden – einmal bearbeiten, und jedes Mapping, das sie referenziert, übernimmt die Änderung.
- Eingebaute und eigene Aktionen werden nebeneinander aufgelistet, mit dem Hinweis „Von N Mappings verwendet“; beim Löschen wirst du gewarnt, falls eine noch referenziert wird.

### 🖥️ Bildschirm-Overlay (HUD)

- Wird eine Aktion ausgelöst, erscheint unten am Bildschirm ein HUD, das „Trigger → Aktion“ anzeigt, z. B. `Caps + J → ↓`.
- In den Einstellungen ein-/ausschaltbar; die Anzeigedauer ist einstellbar (300–6000 ms, Standard 1350 ms).
- Bei **Hold-Modifier**-Aktionen **bleibt das HUD sichtbar**, bis du die Taste loslässt, sodass du erkennst, ob Push-to-Talk aktiv ist.

### ⌨️ Eingabequellen-Wechsel & CJKV-Fix

- Die Aktion **Eingabequelle wechseln** springt direkt zu einer bestimmten Eingabequelle.
- Für das altbekannte Problem, dass der Wechsel zu einem chinesischen / japanischen / koreanischen / vietnamesischen (CJKV) IME per `TISSelectInputSource` zwar das Menüleisten-Symbol ändert, das Tippen aber bei der vorherigen Quelle hängen bleibt, gibt es auf der Seite **Eingabequelle** drei Korrektur-Strategien:
  - **Keine** (Standard – einfacher Wechsel)
  - **Tastenkürzel simulieren** (simuliert das System-Kürzel „Vorherige Eingabequelle auswählen“)
  - **Fokus wechseln** (erzwingt es, indem kurz der Fensterfokus gewechselt wird; funktioniert evtl. nicht bei schwebenden / nicht aktivierbaren Fenstern)
- Der Fix gilt nur für Mappings vom Typ „Caps + Taste → Eingabequelle“.

### 🛠️ Mehr

- **Menüleisten-Steuerung**: pausieren / fortsetzen (Gaming Mode – alle Remappings vorübergehend deaktivieren), nach Updates suchen, More Apps, Einstellungen öffnen, beenden.
- **Konfiguration importieren / exportieren**: die vollständige, eigenständige `.yml`-Konfiguration mit einem Klick exportieren oder aus einer Datei importieren.
- **Auto-Update**: integriertes [Sparkle](https://sparkle-project.org), mit Prüfungen im Hintergrund und manuell.
- **Beim Anmelden starten**: startet per `SMAppService` automatisch beim Login.
- **Dock-Symbol ausblenden**: als reine Menüleisten-App betreibbar.
- **Theme**: Hell / Dunkel / dem System folgen.
- **Lokalisierte Oberfläche**: English / 中文 / 日本語 / Deutsch.
- **Konfigurations-Kompatibilität**: Das YAML-Format ist byte-kompatibel mit der früheren Tauri-Version, sodass bestehende `action_mappings.yml` / `app_config.yml` unverändert geladen werden; unbekannte Schlüssel einer neueren Version bleiben beim Speichern durch einen älteren Build verlustfrei erhalten.

## Standard-Tastenbelegung

Das sind die Standards bei einer frischen Installation – **alle davon lassen sich in der GUI anpassen**:

### Navigation (vim-Stil)

| Kombination | Aktion |
|-------------|--------|
| `Caps + H / J / K / L` | ← ↓ ↑ → Pfeiltasten |
| `Caps + A` | Home (Zeilenanfang) |
| `Caps + E` | End (Zeilenende) |
| `Caps + Y` | Vorheriges Wort |
| `Caps + P` | Nächstes Wort |
| `Caps + U` | 10 Zeilen nach oben springen |
| `Caps + D` | 10 Zeilen nach unten springen |

### Bearbeitung

| Kombination | Aktion |
|-------------|--------|
| `Caps + I` | Backspace |
| `Caps + O` | Neue Zeile darunter (Zeilenende + Return) |
| `Caps + N` | Ein Paar Anführungszeichen einfügen und den Cursor mittig setzen |

### Eingabequellen-Wechsel

| Kombination | Aktion |
|-------------|--------|
| `Caps + ,` | Zu ABC (Englisch) wechseln |
| `Caps + .` | Zu WeChat-Pinyin wechseln |

> Das sind nur die Standards. Du kannst Tasten hinzufügen, entfernen und neu belegen und jede Taste auf jede der oben aufgeführten Aktionen legen.

## Installation (macOS)

### Homebrew

```bash
brew install --cask XueshiQiao/tap/hypercapslock
```

Oder lade das `.dmg` aus den [GitHub Releases](https://github.com/XueshiQiao/HyperCapslock/releases) herunter.

### Berechtigungen

Die App benötigt die Berechtigung **Bedienungshilfen (Accessibility)**, um ihren Tastatur-Event-Tap zu installieren:
`Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen`

(„Eingabeüberwachung“ wird *nicht* benötigt – das gilt nur für `.listenOnly`-Taps; diese App verwendet einen aktiven `.defaultTap`, den macOS über die Bedienungshilfen absichert.)

## Screenshot

<div align="center">
  <img src="./docs/assets/screenshots/mappings.png" width="760" alt="Mappings — keyboard view" />
</div>

<table align="center">
  <tr>
    <td width="50%"><img src="./docs/assets/screenshots/settings.png" alt="Settings" /></td>
    <td width="50%"><img src="./docs/assets/screenshots/actions.png" alt="Actions" /></td>
  </tr>
  <tr>
    <td width="50%"><img src="./docs/assets/screenshots/input-source.png" alt="Input Source" /></td>
    <td width="50%"><img src="./docs/assets/screenshots/about.png" alt="About" /></td>
  </tr>
</table>

## Warum nicht Karabiner-Elements?

[Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) ist ein mächtiges Tool mit 21k+ Sternen, und ich habe es jahrelang verwendet. Aber für den speziellen Anwendungsfall „Caps Lock als Navigationsebene“:

- **Konfigurations-Aufwand** – Karabiner erfordert für nicht-triviale Remappings das Bearbeiten von JSON von Hand. HyperCapslock hat eine Point-and-Click-GUI, dazu App-Regeln, eine Bibliothek eigener Aktionen und mehr.
- **Footprint** – Karabiner installiert eine Kernel-Erweiterung und mehrere Hintergrundprozesse. HyperCapslock ist eine einzelne, leichtgewichtige native macOS-App.
- **Das Modifier-Problem** – Karabiner bildet Caps Lock typischerweise auf eine echte Modifier-Kombination ab (z. B. Ctrl+Shift+Cmd+Opt). Dieser „Hyper-Key“-Ansatz funktioniert, kann aber mit bestehenden Shortcuts kollidieren. HyperCapslock bildet auf F18 ab, das mit nichts kollidiert und sich natürlich mit echten Modifiern kombinieren lässt.

Wenn du den vollen Funktionsumfang von Karabiner brauchst (Maus-Remapping, gerätespezifische Profile usw.), nimm Karabiner. Wenn du hauptsächlich überall vim-Navigation und -Bearbeitung mit nahezu null Einrichtung willst, ist das hier vielleicht der einfachere Weg.

## Wie es funktioniert

Caps Lock wird auf OS-Ebene per `hidutil` auf F18 abgebildet. Anschließend installiert die App auf HID-Ebene einen `CGEventTap` – einen systemweiten Event-Tap, der Tastenereignisse abfängt, bevor irgendeine andere Anwendung sie sieht.

Wird F18 gehalten und eine weitere Taste gedrückt, schluckt die App das ursprüngliche Ereignis und injiziert die umgemappte Taste (z. B. eine Pfeiltaste) in den System-Eingabestrom. Injizierte Ereignisse tragen ein Flag, um Rückkopplungsschleifen zu verhindern.

Die Zustandsverwaltung nutzt lock-geschützten Laufzeitzustand (`OSAllocatedUnfairLock` / `NSLock`) für Thread-Sicherheit zwischen Tap-Thread, Timer-Threads und UI. Der Hook-Callback macht das absolute Minimum – Ganzzahl-Vergleiche und frühe Returns –, um keine Eingabeverzögerung zu erzeugen.

Für den vollständigen technischen Deep-Dive siehe [how_does_it_work.md](how_does_it_work.md).

## Tech-Stack

- **Natives macOS** – SwiftUI + AppKit, Swift-5-Sprachmodus, macOS 14+
- CoreGraphics `CGEventTap` + `hidutil` für das F18-Remapping; IOKit für den CapsLock-Zustand; Carbon TIS für den Eingabequellen-Wechsel
- [Sparkle](https://sparkle-project.org) für Auto-Update, [Yams](https://github.com/jpsim/Yams) für die YAML-Konfiguration
- Ein einzelner, leichtgewichtiger nativer Prozess

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

`project.yml` ist die maßgebliche Konfigurationsquelle (single source of truth) für das Xcode-Projekt; führe nach Änderungen `xcodegen generate` aus.

### Build

```bash
xcodebuild -project HyperCapslock.xcodeproj -scheme HyperCapslock -configuration Release build
```

## Fehlerbehebung

- **Hotkeys funktionieren nicht mehr**: Logs werden nach `/tmp/hypercapslock-macos.log` geschrieben. Entferne die App aus den Bedienungshilfen-Berechtigungen, füge sie wieder hinzu und starte sie neu.
- **Gaming Mode**: über das Menüleisten-Symbol pausieren/fortsetzen, um alle Remappings vorübergehend zu deaktivieren.
- **Chinesisch-/Japanisch-Eingabewechsel greift nicht**: probiere auf der Seite **Eingabequelle** die Strategie **Tastenkürzel simulieren** oder **Fokus wechseln**.

## Lizenz

GPL v3.0 – siehe [LICENSE](LICENSE).
