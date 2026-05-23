import Foundation
import SwiftUI

enum AppLocale: String, CaseIterable {
    case en, zh, ja, de
    var flag: String {
        switch self {
        case .en: return "🇺🇸"
        case .zh: return "🇨🇳"
        case .ja: return "🇯🇵"
        case .de: return "🇩🇪"
        }
    }
    var label: String {
        switch self {
        case .en: return "English"
        case .zh: return "中文"
        case .ja: return "日本語"
        case .de: return "Deutsch"
        }
    }
}

/// Observable localization. Mirrors `i18n.ts`: same keys/values, system-locale
/// detection, `hc-locale` persistence, and `{param}` interpolation. SwiftUI
/// views observe `shared` so a language switch re-renders the whole UI.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var locale: AppLocale

    /// Called whenever the locale changes (used to refresh the tray menu).
    var onLocaleChange: ((AppLocale) -> Void)?

    private init() {
        locale = LocalizationManager.detectLocale()
    }

    private static func detectLocale() -> AppLocale {
        if let stored = UserDefaults.standard.string(forKey: "hc-locale"),
           let l = AppLocale(rawValue: stored) { return l }
        for code in Locale.preferredLanguages {
            let short = code.lowercased().split(separator: "-").first.map(String.init) ?? ""
            if let l = AppLocale(rawValue: short) { return l }
        }
        return .en
    }

    func setLocale(_ l: AppLocale) {
        locale = l
        UserDefaults.standard.set(l.rawValue, forKey: "hc-locale")
        onLocaleChange?(l)
    }

    func t(_ key: String, _ params: [String: String] = [:]) -> String {
        var text = Self.tables[locale]?[key] ?? Self.tables[.en]?[key] ?? key
        for (k, v) in params { text = text.replacingOccurrences(of: "{\(k)}", with: v) }
        return text
    }

    // MARK: - String tables (ported from i18n.ts)

    static let tables: [AppLocale: [String: String]] = [
        .en: [
            "app.subtitle": "Make your Capslock Powerful again!",
            "status.label": "Status", "status.initializing": "Initializing...",
            "status.running": "Running", "status.paused": "Paused", "status.error": "Error",
            "status.pause": "Pause", "status.resume": "Resume",
            "settings.label": "Settings", "settings.autostart": "Start at Login",
            "settings.hide_dock": "Hide Dock Icon", "settings.show_hud": "Show On-screen HUD",
            "settings.hud_duration": "HUD Duration",
            "perm.label": "Permissions", "perm.title": "Authority Status", "perm.refresh": "Refresh",
            "perm.accessibility": "Accessibility", "perm.input_monitoring": "Input Monitoring",
            "perm.granted": "Granted", "perm.not_granted": "Not Granted", "perm.not_required": "Not Required",
            "perm.macos_hint": "Required on macOS for reliable global hotkeys.",
            "perm.open_settings": "Open System Settings",
            "perm.other_hint": "These permissions are only required on macOS.",
            "mappings.title": "Action Mappings (Caps+Key)", "mappings.add": "Add",
            "mappings.add_title": "Add Mapping", "mappings.edit": "Edit", "mappings.edit_title": "Edit Mapping",
            "mappings.delete": "Delete", "mappings.save": "Save", "mappings.empty": "No action mappings yet",
            "mappings.press_key": "Press Key", "mappings.caps": "Caps", "mappings.caps_shift": "Caps + Shift",
            "trigger.hyper_plus_key": "Caps + Key", "trigger.single_tap_hyper": "Single-tap Caps",
            "trigger.double_tap_hyper": "Double-tap Caps", "trigger.double_tap_prefix": "Double-tap",
            "trigger.experimental": "experimental", "trigger.double_tap_hint": "Tap Caps twice quickly",
            "group.directional": "Directional", "group.jump": "Jump", "group.independent": "Independent",
            "group.input_source": "Input Source", "group.command": "Command", "group.key_combo": "Key Combo",
            "action.left": "Left", "action.right": "Right", "action.up": "Up", "action.down": "Down",
            "action.word_forward": "Word Forward", "action.word_back": "Word Back",
            "action.home": "Home", "action.end": "End", "action.backspace": "Backspace",
            "action.next_line": "Next Line", "action.insert_quotes": "Insert Quotes",
            "action.toggle_caps_lock": "Toggle Caps Lock", "action.switch_input_source": "Switch Input Source",
            "action.unknown": "Unknown",
            "theme.light": "Switch to Light Mode", "theme.dark": "Switch to Dark Mode",
            "toast.perm_refreshed": "Permissions refreshed", "toast.perm_failed": "Failed to refresh permissions",
            "toast.mapping_saved": "Action mapping saved", "toast.mapping_save_failed": "Failed to save mapping",
            "toast.mapping_removed": "Action mapping removed", "toast.mapping_remove_failed": "Failed to remove mapping",
            "toast.service_paused": "Service Paused", "toast.service_resumed": "Service Resumed",
            "toast.service_toggle_failed": "Failed to toggle service",
            "toast.autostart_disabled": "Autostart disabled", "toast.autostart_enabled": "Autostart enabled",
            "toast.autostart_failed": "Failed to change settings",
            "toast.hide_dock_enabled": "Dock icon hidden", "toast.hide_dock_disabled": "Dock icon shown",
            "toast.hide_dock_failed": "Failed to change Dock icon setting",
            "toast.show_hud_enabled": "On-screen HUD enabled", "toast.show_hud_disabled": "On-screen HUD disabled",
            "toast.show_hud_failed": "Failed to change HUD setting",
            "config.export": "Export", "config.import": "Import", "config.import_title": "Import Configuration",
            "config.import_prompt": "This will replace your current mappings. Continue?",
            "config.import_confirm": "Replace", "config.overwrite_title": "File Already Exists",
            "config.overwrite_prompt": "{path} already exists. Overwrite?", "config.overwrite_confirm": "Overwrite",
            "toast.config_exported": "Configuration exported", "toast.config_export_failed": "Failed to export configuration",
            "toast.config_imported": "Imported {count} mapping(s)", "toast.config_import_failed": "Import failed: {error}",
            "update.available": "Version {version} is available.\n\nRelease notes:\n{body}",
            "update.title": "Update Available", "update.ok": "Update", "update.cancel": "Cancel",
            "update.installed": "Update installed. Please restart the application.", "update.success": "Success",
            "update.latest": "You are on the latest version.", "update.no_update": "No Update",
            "update.failed": "Failed to check for updates: {error}", "update.error": "Error",
            "update.check": "Check for Updates",
            "footer.by": "By", "footer.github": "GitHub Repository",
            "footer.more_apps_desc": "Check out all apps I created at:",
            "tray.open": "Open Window", "tray.quit": "Quit HyperCapslock", "tray.more_apps": "More Apps by Author…",
            "nav.settings": "Settings", "nav.mappings": "Mappings", "nav.actions": "Actions", "nav.about": "About",
            "appearance.label": "Appearance", "settings.language": "Language", "settings.theme": "Theme",
            "theme.light_opt": "Light", "theme.dark_opt": "Dark", "theme.system_opt": "System",
            "perm.refresh_label": "Re-check after granting",
            "mappings.action": "Action", "mappings.action_hint": "Pick an action from the library. Create new ones on the Actions tab.",
            "mappings.current_inline": "Current (inline action)", "mappings.invalid": "⚠ Invalid (action missing)",
            "actions.add": "Add Action", "actions.custom": "Custom", "actions.builtin": "Built-in",
            "actions.none_custom": "No custom actions yet", "actions.builtin_hint": "Built-in actions can't be edited or deleted, but you can bind any of them to a trigger.",
            "actions.used_by": "{count} mapping(s)", "actions.delete_blocked": "Can't delete — used by: {triggers}",
            "actions.edit_title": "Edit Action", "actions.add_title": "New Action",
            "actions.name": "Name", "actions.name_placeholder": "e.g. Open Calculator", "actions.type": "Type",
            "about.version": "Version", "about.license": "GPL-3.0",
            "toast.action_saved": "Action saved", "toast.action_removed": "Action removed", "toast.action_remove_failed": "Failed to remove action",
        ],
        .zh: [
            "app.subtitle": "唤醒沉睡的 Capslock",
            "status.label": "状态", "status.initializing": "初始化中...",
            "status.running": "运行中", "status.paused": "已暂停", "status.error": "错误",
            "status.pause": "暂停", "status.resume": "恢复",
            "settings.label": "设置", "settings.autostart": "开机启动",
            "settings.hide_dock": "隐藏 Dock 图标", "settings.show_hud": "显示屏幕提示",
            "settings.hud_duration": "提示停留时长",
            "perm.label": "权限", "perm.title": "授权状态", "perm.refresh": "刷新",
            "perm.accessibility": "辅助功能", "perm.input_monitoring": "输入监听",
            "perm.granted": "已授权", "perm.not_granted": "未授权", "perm.not_required": "无需授权",
            "perm.macos_hint": "macOS 上需要此权限以确保全局快捷键正常工作。",
            "perm.open_settings": "打开系统设置", "perm.other_hint": "这些权限仅在 macOS 上需要。",
            "mappings.title": "按键映射 (Caps+按键)", "mappings.add": "添加",
            "mappings.add_title": "添加映射", "mappings.edit": "编辑", "mappings.edit_title": "编辑映射",
            "mappings.delete": "删除", "mappings.save": "保存", "mappings.empty": "还没有映射配置",
            "mappings.press_key": "按下按键", "mappings.caps": "Caps", "mappings.caps_shift": "Caps + Shift",
            "trigger.hyper_plus_key": "Caps + 按键", "trigger.single_tap_hyper": "单击 Caps",
            "trigger.double_tap_hyper": "双击 Caps", "trigger.double_tap_prefix": "双击",
            "trigger.experimental": "实验性", "trigger.double_tap_hint": "快速连点两下 Caps",
            "group.directional": "方向", "group.jump": "跳转", "group.independent": "独立",
            "group.input_source": "输入法", "group.command": "命令", "group.key_combo": "组合键",
            "action.left": "左", "action.right": "右", "action.up": "上", "action.down": "下",
            "action.word_forward": "下一个词", "action.word_back": "上一个词",
            "action.home": "行首", "action.end": "行尾", "action.backspace": "退格",
            "action.next_line": "下一行", "action.insert_quotes": "插入引号",
            "action.toggle_caps_lock": "大小写切换", "action.switch_input_source": "输入法切换",
            "action.unknown": "未知",
            "theme.light": "切换到浅色模式", "theme.dark": "切换到深色模式",
            "toast.perm_refreshed": "权限已刷新", "toast.perm_failed": "刷新权限失败",
            "toast.mapping_saved": "映射已保存", "toast.mapping_save_failed": "保存映射失败",
            "toast.mapping_removed": "映射已删除", "toast.mapping_remove_failed": "删除映射失败",
            "toast.service_paused": "服务已暂停", "toast.service_resumed": "服务已恢复",
            "toast.service_toggle_failed": "切换服务失败",
            "toast.autostart_disabled": "已关闭自启", "toast.autostart_enabled": "已开启自启",
            "toast.autostart_failed": "设置更改失败",
            "toast.hide_dock_enabled": "已隐藏 Dock 图标", "toast.hide_dock_disabled": "已显示 Dock 图标",
            "toast.hide_dock_failed": "Dock 图标设置修改失败",
            "toast.show_hud_enabled": "已开启屏幕提示", "toast.show_hud_disabled": "已关闭屏幕提示",
            "toast.show_hud_failed": "屏幕提示设置修改失败",
            "config.export": "导出", "config.import": "导入", "config.import_title": "导入配置",
            "config.import_prompt": "这将替换当前所有的映射，是否继续？", "config.import_confirm": "替换",
            "config.overwrite_title": "文件已存在", "config.overwrite_prompt": "{path} 已存在，是否覆盖？",
            "config.overwrite_confirm": "覆盖",
            "toast.config_exported": "配置已导出", "toast.config_export_failed": "导出配置失败",
            "toast.config_imported": "已导入 {count} 项映射", "toast.config_import_failed": "导入失败：{error}",
            "update.available": "版本 {version} 可用。\n\n更新日志：\n{body}",
            "update.title": "发现新版本", "update.ok": "更新", "update.cancel": "取消",
            "update.installed": "更新已安装，请重启应用。", "update.success": "成功",
            "update.latest": "已是最新版本。", "update.no_update": "无可用更新",
            "update.failed": "检查更新失败：{error}", "update.error": "错误", "update.check": "检查更新",
            "footer.by": "By", "footer.github": "GitHub 仓库", "footer.more_apps_desc": "查看我创作的所有应用:",
            "tray.open": "打开窗口", "tray.quit": "退出 HyperCapslock", "tray.more_apps": "作者的更多应用…",
            "nav.settings": "设置", "nav.mappings": "按键映射", "nav.actions": "动作", "nav.about": "关于",
            "appearance.label": "外观", "settings.language": "语言", "settings.theme": "主题",
            "theme.light_opt": "浅色", "theme.dark_opt": "深色", "theme.system_opt": "跟随系统",
            "perm.refresh_label": "授权后重新检查",
            "mappings.action": "动作", "mappings.action_hint": "从动作库中选择一个动作。可在「动作」页新建。",
            "mappings.current_inline": "当前(内联动作)", "mappings.invalid": "⚠ 无效(动作缺失)",
            "actions.add": "添加动作", "actions.custom": "自定义", "actions.builtin": "内置",
            "actions.none_custom": "还没有自定义动作", "actions.builtin_hint": "内置动作不可编辑或删除,但可以绑定到任意触发键。",
            "actions.used_by": "{count} 个映射", "actions.delete_blocked": "无法删除 — 被以下触发键引用:{triggers}",
            "actions.edit_title": "编辑动作", "actions.add_title": "新建动作",
            "actions.name": "名称", "actions.name_placeholder": "例如 打开计算器", "actions.type": "类型",
            "about.version": "版本", "about.license": "GPL-3.0",
            "toast.action_saved": "动作已保存", "toast.action_removed": "动作已删除", "toast.action_remove_failed": "删除动作失败",
        ],
        .ja: [
            "app.subtitle": "Capslockをもっとパワフルに！",
            "status.label": "ステータス", "status.initializing": "初期化中...",
            "status.running": "実行中", "status.paused": "一時停止", "status.error": "エラー",
            "status.pause": "一時停止", "status.resume": "再開",
            "settings.label": "設定", "settings.autostart": "ログイン時に起動",
            "settings.hide_dock": "Dock アイコンを非表示", "settings.show_hud": "画面 HUD を表示",
            "settings.hud_duration": "HUD 表示時間",
            "perm.label": "権限", "perm.title": "権限状況", "perm.refresh": "更新",
            "perm.accessibility": "アクセシビリティ", "perm.input_monitoring": "入力監視",
            "perm.granted": "許可済み", "perm.not_granted": "未許可", "perm.not_required": "不要",
            "perm.macos_hint": "macOSでグローバルホットキーを使うために必要です。",
            "perm.open_settings": "システム設定を開く", "perm.other_hint": "これらの権限はmacOSでのみ必要です。",
            "mappings.title": "キーマッピング (Caps+キー)", "mappings.add": "追加",
            "mappings.add_title": "マッピングを追加", "mappings.edit": "編集", "mappings.edit_title": "マッピングを編集",
            "mappings.delete": "削除", "mappings.save": "保存", "mappings.empty": "マッピングがまだありません",
            "mappings.press_key": "キーを押す", "mappings.caps": "Caps", "mappings.caps_shift": "Caps + Shift",
            "trigger.hyper_plus_key": "Caps + キー", "trigger.single_tap_hyper": "Caps をシングルタップ",
            "trigger.double_tap_hyper": "Caps をダブルタップ", "trigger.double_tap_prefix": "ダブルタップ",
            "trigger.experimental": "実験的", "trigger.double_tap_hint": "Caps を素早く2回押す",
            "group.directional": "方向", "group.jump": "ジャンプ", "group.independent": "独立",
            "group.input_source": "入力ソース", "group.command": "コマンド", "group.key_combo": "キーコンボ",
            "action.left": "左", "action.right": "右", "action.up": "上", "action.down": "下",
            "action.word_forward": "次の単語", "action.word_back": "前の単語",
            "action.home": "行頭", "action.end": "行末", "action.backspace": "バックスペース",
            "action.next_line": "次の行", "action.insert_quotes": "引用符を挿入",
            "action.toggle_caps_lock": "Caps Lock 切り替え", "action.switch_input_source": "入力ソース切り替え",
            "action.unknown": "不明",
            "theme.light": "ライトモードに切替", "theme.dark": "ダークモードに切替",
            "toast.perm_refreshed": "権限を更新しました", "toast.perm_failed": "権限の更新に失敗",
            "toast.mapping_saved": "マッピングを保存しました", "toast.mapping_save_failed": "マッピングの保存に失敗",
            "toast.mapping_removed": "マッピングを削除しました", "toast.mapping_remove_failed": "マッピングの削除に失敗",
            "toast.service_paused": "サービスを一時停止", "toast.service_resumed": "サービスを再開",
            "toast.service_toggle_failed": "サービスの切替に失敗",
            "toast.autostart_disabled": "自動起動を無効化", "toast.autostart_enabled": "自動起動を有効化",
            "toast.autostart_failed": "設定の変更に失敗",
            "toast.hide_dock_enabled": "Dock アイコンを非表示にしました", "toast.hide_dock_disabled": "Dock アイコンを表示しました",
            "toast.hide_dock_failed": "Dock アイコン設定の変更に失敗",
            "toast.show_hud_enabled": "画面 HUD を有効化", "toast.show_hud_disabled": "画面 HUD を無効化",
            "toast.show_hud_failed": "HUD 設定の変更に失敗",
            "config.export": "エクスポート", "config.import": "インポート", "config.import_title": "設定をインポート",
            "config.import_prompt": "現在のマッピングを置き換えます。続行しますか？", "config.import_confirm": "置き換え",
            "config.overwrite_title": "ファイルは既に存在します", "config.overwrite_prompt": "{path} は既に存在します。上書きしますか？",
            "config.overwrite_confirm": "上書き",
            "toast.config_exported": "設定をエクスポートしました", "toast.config_export_failed": "エクスポートに失敗しました",
            "toast.config_imported": "{count} 件のマッピングをインポートしました", "toast.config_import_failed": "インポートに失敗：{error}",
            "update.available": "バージョン {version} が利用可能です。\n\nリリースノート:\n{body}",
            "update.title": "アップデートがあります", "update.ok": "アップデート", "update.cancel": "キャンセル",
            "update.installed": "アップデートがインストールされました。アプリを再起動してください。", "update.success": "成功",
            "update.latest": "最新バージョンです。", "update.no_update": "更新なし",
            "update.failed": "アップデートの確認に失敗: {error}", "update.error": "エラー", "update.check": "アップデートを確認",
            "footer.by": "By", "footer.github": "GitHub リポジトリ", "footer.more_apps_desc": "他のアプリもチェック:",
            "tray.open": "ウィンドウを開く", "tray.quit": "HyperCapslock を終了", "tray.more_apps": "作者の他のアプリ…",
        ],
        .de: [
            "app.subtitle": "Mach deine Capslock-Taste wieder mächtig!",
            "status.label": "Status", "status.initializing": "Initialisierung...",
            "status.running": "Läuft", "status.paused": "Pausiert", "status.error": "Fehler",
            "status.pause": "Pause", "status.resume": "Fortsetzen",
            "settings.label": "Einstellungen", "settings.autostart": "Beim Anmelden starten",
            "settings.hide_dock": "Dock-Symbol ausblenden", "settings.show_hud": "Bildschirm-HUD anzeigen",
            "settings.hud_duration": "HUD-Dauer",
            "perm.label": "Berechtigungen", "perm.title": "Berechtigungsstatus", "perm.refresh": "Aktualisieren",
            "perm.accessibility": "Bedienungshilfen", "perm.input_monitoring": "Eingabeüberwachung",
            "perm.granted": "Gewährt", "perm.not_granted": "Nicht gewährt", "perm.not_required": "Nicht erforderlich",
            "perm.macos_hint": "Erforderlich auf macOS für zuverlässige globale Hotkeys.",
            "perm.open_settings": "Systemeinstellungen öffnen", "perm.other_hint": "Diese Berechtigungen sind nur auf macOS erforderlich.",
            "mappings.title": "Tastenbelegungen (Caps+Taste)", "mappings.add": "Hinzufügen",
            "mappings.add_title": "Belegung hinzufügen", "mappings.edit": "Bearbeiten", "mappings.edit_title": "Belegung bearbeiten",
            "mappings.delete": "Löschen", "mappings.save": "Speichern", "mappings.empty": "Noch keine Tastenbelegungen",
            "mappings.press_key": "Taste drücken", "mappings.caps": "Caps", "mappings.caps_shift": "Caps + Shift",
            "trigger.hyper_plus_key": "Caps + Taste", "trigger.single_tap_hyper": "Caps einmal tippen",
            "trigger.double_tap_hyper": "Caps doppelt tippen", "trigger.double_tap_prefix": "Doppeltippen",
            "trigger.experimental": "experimentell", "trigger.double_tap_hint": "Caps zweimal schnell tippen",
            "group.directional": "Richtung", "group.jump": "Sprung", "group.independent": "Unabhängig",
            "group.input_source": "Eingabequelle", "group.command": "Befehl", "group.key_combo": "Tastenkombination",
            "action.left": "Links", "action.right": "Rechts", "action.up": "Oben", "action.down": "Unten",
            "action.word_forward": "Wort vor", "action.word_back": "Wort zurück",
            "action.home": "Zeilenanfang", "action.end": "Zeilenende", "action.backspace": "Rücktaste",
            "action.next_line": "Nächste Zeile", "action.insert_quotes": "Anführungszeichen",
            "action.toggle_caps_lock": "Caps Lock umschalten", "action.switch_input_source": "Eingabequelle wechseln",
            "action.unknown": "Unbekannt",
            "theme.light": "Zum hellen Modus wechseln", "theme.dark": "Zum dunklen Modus wechseln",
            "toast.perm_refreshed": "Berechtigungen aktualisiert", "toast.perm_failed": "Aktualisierung fehlgeschlagen",
            "toast.mapping_saved": "Belegung gespeichert", "toast.mapping_save_failed": "Speichern fehlgeschlagen",
            "toast.mapping_removed": "Belegung entfernt", "toast.mapping_remove_failed": "Entfernen fehlgeschlagen",
            "toast.service_paused": "Dienst pausiert", "toast.service_resumed": "Dienst fortgesetzt",
            "toast.service_toggle_failed": "Dienstumschaltung fehlgeschlagen",
            "toast.autostart_disabled": "Autostart deaktiviert", "toast.autostart_enabled": "Autostart aktiviert",
            "toast.autostart_failed": "Einstellungen konnten nicht geändert werden",
            "toast.hide_dock_enabled": "Dock-Symbol ausgeblendet", "toast.hide_dock_disabled": "Dock-Symbol eingeblendet",
            "toast.hide_dock_failed": "Dock-Symbol-Einstellung fehlgeschlagen",
            "toast.show_hud_enabled": "Bildschirm-HUD aktiviert", "toast.show_hud_disabled": "Bildschirm-HUD deaktiviert",
            "toast.show_hud_failed": "HUD-Einstellung fehlgeschlagen",
            "config.export": "Exportieren", "config.import": "Importieren", "config.import_title": "Konfiguration importieren",
            "config.import_prompt": "Dies ersetzt Ihre aktuellen Belegungen. Fortfahren?", "config.import_confirm": "Ersetzen",
            "config.overwrite_title": "Datei existiert bereits", "config.overwrite_prompt": "{path} existiert bereits. Überschreiben?",
            "config.overwrite_confirm": "Überschreiben",
            "toast.config_exported": "Konfiguration exportiert", "toast.config_export_failed": "Export fehlgeschlagen",
            "toast.config_imported": "{count} Belegung(en) importiert", "toast.config_import_failed": "Import fehlgeschlagen: {error}",
            "update.available": "Version {version} ist verfügbar.\n\nÄnderungen:\n{body}",
            "update.title": "Update verfügbar", "update.ok": "Aktualisieren", "update.cancel": "Abbrechen",
            "update.installed": "Update installiert. Bitte starten Sie die Anwendung neu.", "update.success": "Erfolg",
            "update.latest": "Sie verwenden die neueste Version.", "update.no_update": "Kein Update",
            "update.failed": "Update-Prüfung fehlgeschlagen: {error}", "update.error": "Fehler", "update.check": "Nach Updates suchen",
            "footer.by": "Von", "footer.github": "GitHub-Repository", "footer.more_apps_desc": "Alle meine Apps:",
            "tray.open": "Fenster öffnen", "tray.quit": "HyperCapslock beenden", "tray.more_apps": "Weitere Apps des Autors…",
        ],
    ]
}
