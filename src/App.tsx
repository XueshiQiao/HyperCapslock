import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { listen } from "@tauri-apps/api/event";
import { getVersion } from "@tauri-apps/api/app";
import { check } from "@tauri-apps/plugin-updater";
import { message, ask } from "@tauri-apps/plugin-dialog";
import { enable, disable, isEnabled } from "@tauri-apps/plugin-autostart";
import { t, useLocale, setLocale, LOCALE_META, type Locale } from "./i18n";
import "./App.css";

type PermissionStatuses = {
  platform: "macos" | "other";
  accessibility: "granted" | "not_granted" | "not_required";
  input_monitoring: "granted" | "not_granted" | "not_required";
};

type DirectionalAction =
  | "left"
  | "right"
  | "up"
  | "down"
  | "word_forward"
  | "word_back"
  | "home"
  | "end";

type JumpDirection = "up" | "down";

type IndependentAction = "backspace" | "next_line" | "insert_quotes";

type ActionConfig =
  | { kind: "directional"; action: DirectionalAction }
  | { kind: "jump"; direction: JumpDirection; count: number }
  | { kind: "independent"; action: IndependentAction }
  | { kind: "input_source"; input_source_id: string }
  | { kind: "command"; command: string };

type ActionMappingEntry = {
  key: number;
  with_shift: boolean;
  action: ActionConfig;
};

type SelectOption = {
  value: string;
  label: string;
};

type ActionGroupKey = ActionConfig["kind"];

const SPECIAL_KEY_DISPLAY: Record<number, string> = {
  8: "Del",
  13: "Enter",
  37: "←",
  38: "↑",
  39: "→",
  40: "↓",
  186: ";",
  187: "=",
  188: ",",
  189: "-",
  190: ".",
  191: "/",
  220: "\\",
  222: "'"
};

function keyCodeToDisplay(keyCode: number): string {
  if (SPECIAL_KEY_DISPLAY[keyCode]) return SPECIAL_KEY_DISPLAY[keyCode];
  const key = String.fromCharCode(keyCode);
  return /^[A-Z0-9]$/.test(key) ? key : `Key ${keyCode}`;
}

type ActionPresentation = {
  category: string;
  value: string;
  icon: string;
  valueClassName?: string;
  iconClassName?: string;
};

function actionToPresentation(action: ActionConfig): ActionPresentation {
  switch (action.kind) {
    case "directional": {
      const iconMap: Record<DirectionalAction, string> = {
        left: "Left", right: "Right", up: "Up", down: "Down",
        word_forward: "WordRight", word_back: "WordLeft", home: "Home", end: "End",
      };
      return { category: t("group.directional"), value: t(`action.${action.action}`), icon: iconMap[action.action] };
    }
    case "jump":
      return {
        category: t("group.jump"),
        value: `${t(`action.${action.direction}`)} x${action.count}`,
        icon: action.direction === "up" ? "FastUp" : "FastDown",
      };
    case "independent": {
      const iconMap: Record<IndependentAction, string> = {
        backspace: "Delete", next_line: "Enter", insert_quotes: "Code",
      };
      return { category: t("group.independent"), value: t(`action.${action.action}`), icon: iconMap[action.action] };
    }
    case "input_source":
      return { category: t("group.input_source"), value: action.input_source_id, icon: "Input" };
    case "command":
      return { category: t("group.command"), value: action.command, icon: "Command" };
    default:
      return { category: t("action.unknown"), value: t("action.unknown"), icon: "Code" };
  }
}

const CARD_WIDTH_CLASS = "w-full max-w-[580px]";
const MODERN_CARD_CLASS = "relative overflow-hidden border border-slate-200/80 dark:border-slate-700/80 rounded-2xl shadow-xl bg-white dark:bg-slate-800";
const ACTION_GROUP_KEYS: ActionGroupKey[] = ["directional", "jump", "independent", "input_source", "command"];

function App() {
  const [status, setStatus] = useState("initializing");
  const [autostart, setAutostart] = useState(false);
  const [appVersion, setAppVersion] = useState("");
  const [toast, setToast] = useState<{ message: string; type: "success" | "error" } | null>(null);
  const [permissions, setPermissions] = useState<PermissionStatuses | null>(null);

  const [actionMappings, setActionMappings] = useState<ActionMappingEntry[]>([]);
  const [newKey, setNewKey] = useState<number | null>(null);
  const [newKeyDisplay, setNewKeyDisplay] = useState("");
  const [newWithShift, setNewWithShift] = useState(false);
  const [newActionKind, setNewActionKind] = useState<ActionConfig["kind"]>("directional");
  const [newDirectionalAction, setNewDirectionalAction] = useState<DirectionalAction>("left");
  const [newJumpDirection, setNewJumpDirection] = useState<JumpDirection>("up");
  const [newJumpCount, setNewJumpCount] = useState(10);
  const [newIndependentAction, setNewIndependentAction] = useState<IndependentAction>("backspace");
  const [newInputSourceId, setNewInputSourceId] = useState("");
  const [newCommand, setNewCommand] = useState("");

  const [showAddModal, setShowAddModal] = useState(false);
  const [permissionsCollapsed, setPermissionsCollapsed] = useState<boolean | null>(null);
  const [showLangMenu, setShowLangMenu] = useState(false);
  const langRef = useRef<HTMLDivElement | null>(null);
  const locale = useLocale();

  const [isDark, setIsDark] = useState<boolean>(() => {
    const stored = localStorage.getItem("hc-theme");
    return stored ? stored === "dark" : true;
  });

  useEffect(() => {
    document.documentElement.classList.toggle("dark", isDark);
    localStorage.setItem("hc-theme", isDark ? "dark" : "light");
  }, [isDark]);

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (langRef.current && !langRef.current.contains(event.target as Node)) {
        setShowLangMenu(false);
      }
    }
    window.addEventListener("mousedown", handleClickOutside);
    return () => window.removeEventListener("mousedown", handleClickOutside);
  }, []);

  useEffect(() => {
    let unlisten: () => void;

    async function init() {
      try {
        const v = await getVersion();
        setAppVersion(v);
        const msg = (await invoke("get_status") as string).toLowerCase();
        setStatus(msg);
        const auto = await isEnabled();
        setAutostart(auto);

        const maps = await invoke("get_action_mappings");
        const sorted = (maps as ActionMappingEntry[]).sort((a, b) =>
          a.key === b.key ? Number(a.with_shift) - Number(b.with_shift) : a.key - b.key
        );
        setActionMappings(sorted);
        await refreshPermissions();

        unlisten = await listen<boolean>("status-update", (event) => {
          const paused = event.payload;
          setStatus(paused ? "paused" : "running");
        });
      } catch (e: any) {
        setStatus("error");
        console.error(e);
      } finally {
        await getCurrentWindow().show();
      }
    }
    init();

    return () => {
      if (unlisten) unlisten();
    };
  }, []);

  const showToast = (message: string, type: "success" | "error" = "success") => {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3000);
  };

  async function refreshPermissions(showFeedback = false) {
    try {
      const p = await invoke("get_permission_statuses") as PermissionStatuses;
      setPermissions(p);
      // Auto-expand if any permission is not granted (only on first load)
      setPermissionsCollapsed((prev) => {
        if (prev !== null) return prev; // user already toggled manually
        const allGranted = p.accessibility !== "not_granted" && p.input_monitoring !== "not_granted";
        return allGranted;
      });
      if (showFeedback) showToast(t("toast.perm_refreshed"), "success");
    } catch (e) {
      console.error("Failed to fetch permission statuses", e);
      if (showFeedback) showToast(t("toast.perm_failed"), "error");
    }
  }

  async function reloadActionMappings() {
    const maps = await invoke("get_action_mappings");
    const sorted = (maps as ActionMappingEntry[]).sort((a, b) =>
      a.key === b.key ? Number(a.with_shift) - Number(b.with_shift) : a.key - b.key
    );
    setActionMappings(sorted);
  }

  function buildDraftAction(): ActionConfig | null {
    switch (newActionKind) {
      case "directional":
        return { kind: "directional", action: newDirectionalAction };
      case "jump":
        return { kind: "jump", direction: newJumpDirection, count: Math.max(1, Math.min(99, newJumpCount)) };
      case "independent":
        return { kind: "independent", action: newIndependentAction };
      case "input_source":
        return newInputSourceId.trim()
          ? { kind: "input_source", input_source_id: newInputSourceId.trim() }
          : null;
      case "command":
        return newCommand.trim() ? { kind: "command", command: newCommand.trim() } : null;
      default:
        return null;
    }
  }

  async function upsertActionMapping() {
    if (!newKey) return;
    const action = buildDraftAction();
    if (!action) return;

    try {
      await invoke("upsert_action_mapping", {
        key: newKey,
        withShift: newWithShift,
        action,
      });
      await reloadActionMappings();
      setNewKey(null);
      setNewKeyDisplay("");
      if (action.kind === "command") setNewCommand("");
      if (action.kind === "input_source") setNewInputSourceId("");
      showToast(t("toast.mapping_saved"), "success");
    } catch (e: any) {
      console.error(e);
      showToast((e?.toString?.() ?? t("toast.mapping_save_failed")).replace("Error: ", ""), "error");
    }
  }

  async function removeActionMapping(key: number, withShift: boolean) {
    try {
      await invoke("remove_action_mapping", { key, withShift });
      await reloadActionMappings();
      showToast(t("toast.mapping_removed"), "success");
    } catch (e) {
      console.error(e);
      showToast(t("toast.mapping_remove_failed"), "error");
    }
  }

  async function togglePause() {
    try {
      const shouldPause = status === "running";
      const newStatus = (await invoke("set_paused", { paused: shouldPause }) as string).toLowerCase();
      setStatus(newStatus);
      showToast(shouldPause ? t("toast.service_paused") : t("toast.service_resumed"), "success");
    } catch (e) {
      console.error("Failed to toggle pause", e);
      showToast(t("toast.service_toggle_failed"), "error");
    }
  }

  async function toggleAutostart() {
    try {
      if (autostart) {
        await disable();
        setAutostart(false);
        showToast(t("toast.autostart_disabled"), "success");
      } else {
        await enable();
        setAutostart(true);
        showToast(t("toast.autostart_enabled"), "success");
      }
    } catch (e) {
      console.error("Failed to toggle autostart", e);
      showToast(t("toast.autostart_failed"), "error");
    }
  }

  const isRunning = status === "running";
  const isPaused = status === "paused";

  const statusColor = isRunning ? "text-green-500 dark:text-green-400" : isPaused ? "text-amber-500 dark:text-amber-400" : "text-red-500 dark:text-red-400";
  const dotColor = isRunning ? "bg-green-500" : isPaused ? "bg-amber-500" : "bg-red-500";
  const pingColor = isRunning ? "bg-green-400" : isPaused ? "bg-amber-400" : "bg-red-400";
  const draftAction = buildDraftAction();
  const canSaveAction = !!newKey && !!draftAction;
  const groupedMappings = ACTION_GROUP_KEYS.map((key) => ({
    key,
    label: t(`group.${key}`),
    entries: actionMappings.filter((entry) => entry.action.kind === key),
  })).filter((group) => group.entries.length > 0);

  return (
    <main className="flex flex-col items-center justify-center min-h-screen bg-slate-50 dark:bg-[#0f172a] p-6 select-none overflow-y-auto relative">

      {/* Drag region — invisible strip at top for window dragging */}
      <div
        data-tauri-drag-region
        onMouseDown={(e) => {
          if (e.buttons === 1) {
            e.detail === 2
              ? getCurrentWindow().toggleMaximize()
              : getCurrentWindow().startDragging();
          }
        }}
        className="fixed top-0 left-0 right-0 h-8 z-40"
      />

      {/* Theme + Language Buttons */}
      <div className="fixed top-1.5 right-3 z-50 flex items-center gap-1">
        <div ref={langRef} className="relative">
          <button
            onClick={() => setShowLangMenu((prev) => !prev)}
            className="p-1.5 rounded-lg text-sm hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors cursor-pointer"
            title="Language"
          >
            {LOCALE_META[locale].flag}
          </button>
          {showLangMenu && (
            <div className="absolute right-0 mt-1 w-36 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-900 shadow-xl overflow-hidden">
              {(Object.keys(LOCALE_META) as Locale[]).map((loc) => (
                <button
                  key={loc}
                  onClick={() => { setLocale(loc); setShowLangMenu(false); }}
                  className={`w-full text-left px-3 py-2 text-sm transition-colors flex items-center gap-2 ${
                    loc === locale
                      ? "bg-blue-600/25 text-blue-600 dark:text-blue-300"
                      : "text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800"
                  }`}
                >
                  <span>{LOCALE_META[loc].flag}</span>
                  <span>{LOCALE_META[loc].label}</span>
                </button>
              ))}
            </div>
          )}
        </div>
        <button
          onClick={() => setIsDark((prev) => !prev)}
          className="p-1.5 rounded-lg text-slate-500 dark:text-slate-400 hover:bg-slate-200 dark:hover:bg-slate-700 hover:text-slate-700 dark:hover:text-slate-200 transition-colors"
          title={isDark ? t("theme.light") : t("theme.dark")}
        >
          {isDark ? <SunIcon /> : <MoonIcon />}
        </button>
      </div>

      {/* Toast Notification */}
      {toast && (
        <div className={`fixed bottom-10 left-1/2 z-50 px-6 py-3 rounded-xl shadow-2xl flex items-center gap-3 animate-slide-up border whitespace-nowrap ${
          toast.type === "success"
            ? "bg-white dark:bg-slate-800 border-green-500/50 text-green-600 dark:text-green-400"
            : "bg-white dark:bg-slate-800 border-red-500/50 text-red-600 dark:text-red-400"
        }`}>
          {toast.type === "success" ? (
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
          ) : (
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
          )}
          <span className="font-medium text-sm text-slate-700 dark:text-slate-200">{toast.message}</span>
        </div>
      )}

      {/* Header */}
      <div className="text-center mb-8 mt-10">
        <h1 className="text-4xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-500 to-purple-500 mb-2">
          HyperCapslock
        </h1>
        <p className="text-slate-500 dark:text-slate-400 text-sm">{t("app.subtitle")}</p>
      </div>

      {/* Status + Settings Row */}
      <div className={`${CARD_WIDTH_CLASS} grid grid-cols-2 gap-3 mb-8`}>
        <div className={`${MODERN_CARD_CLASS} p-5 transition-all duration-200 hover:border-slate-300 dark:hover:border-slate-500 hover:shadow-2xl hover:shadow-blue-100/30 dark:hover:shadow-blue-900/20`}>
          <div className="pointer-events-none absolute -top-8 -right-8 w-24 h-24 rounded-full bg-blue-500/15 blur-2xl" />
          <div className="pointer-events-none absolute -bottom-8 -left-8 w-24 h-24 rounded-full bg-cyan-400/10 blur-2xl" />
          <div className="relative">
            <div className="flex items-center gap-3 mb-4">
              <div className="relative flex h-3 w-3">
                {(isRunning || isPaused) && <span className={`animate-ping absolute inline-flex h-full w-full rounded-full ${pingColor} opacity-75`}></span>}
                <span className={`relative inline-flex rounded-full h-3 w-3 ${dotColor}`}></span>
              </div>
              <div>
                <p className="text-[11px] uppercase tracking-wider text-slate-500 dark:text-slate-400 font-semibold">{t("status.label")}</p>
                <p className={`text-lg font-semibold leading-tight ${statusColor}`}>{t(`status.${status}`)}</p>
              </div>
            </div>
            <button
              onClick={togglePause}
              className={`w-full px-4 py-2 rounded-xl font-medium transition-all duration-200 transform active:scale-95 flex items-center justify-center gap-2
                ${isRunning
                  ? "bg-slate-100 dark:bg-slate-700/90 hover:bg-slate-200 dark:hover:bg-slate-600 text-slate-800 dark:text-slate-100"
                  : "bg-blue-600 hover:bg-blue-500 text-white shadow-lg shadow-blue-900/20"
                }`}
            >
              {isRunning ? <><PauseIcon /><span>{t("status.pause")}</span></> : <><PlayIcon /><span>{t("status.resume")}</span></>}
            </button>
          </div>
        </div>

        <div className={`${MODERN_CARD_CLASS} p-5 flex flex-col justify-between transition-all duration-200 hover:border-slate-300 dark:hover:border-slate-500 hover:shadow-2xl hover:shadow-violet-100/30 dark:hover:shadow-violet-900/20`}>
          <div className="pointer-events-none absolute -top-8 -right-8 w-24 h-24 rounded-full bg-violet-500/12 blur-2xl" />
          <div className="pointer-events-none absolute -bottom-8 -left-8 w-24 h-24 rounded-full bg-cyan-400/10 blur-2xl" />
          <div className="relative">
            <div>
              <p className="text-[11px] uppercase tracking-wider text-slate-500 dark:text-slate-400 font-semibold">{t("settings.label")}</p>
              <p className="text-sm text-slate-800 dark:text-slate-200 font-medium mt-1">{t("settings.autostart")}</p>
              <p className="text-[11px] text-slate-400 dark:text-slate-500 mt-1">{t("settings.autostart_desc")}</p>
            </div>
            <div className="flex justify-end mt-4">
              <button
                onClick={toggleAutostart}
                className={`w-12 h-6 rounded-full p-1 border transition-all duration-200 ease-in-out cursor-pointer ${
                  autostart
                    ? "bg-primary border-blue-400/70 hover:bg-blue-500 hover:border-blue-300"
                    : "bg-slate-200 dark:bg-slate-600 border-slate-300 dark:border-slate-500 hover:bg-slate-300 dark:hover:bg-slate-500 hover:border-slate-400 dark:hover:border-slate-400"
                }`}
              >
                <div className={`bg-white w-4 h-4 rounded-full shadow-md transform transition-transform duration-200 ease-in-out ${autostart ? 'translate-x-6' : 'translate-x-0'}`} />
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Permissions Card (collapsible) */}
      <div className={`${CARD_WIDTH_CLASS} ${MODERN_CARD_CLASS} p-6 mb-8 transition-all duration-200 hover:border-slate-300 dark:hover:border-slate-500 hover:shadow-2xl hover:shadow-emerald-100/30 dark:hover:shadow-emerald-900/20`}>
        <div className="pointer-events-none absolute -top-8 -right-8 w-24 h-24 rounded-full bg-emerald-500/12 blur-2xl" />
        <div className="pointer-events-none absolute -bottom-8 -left-8 w-24 h-24 rounded-full bg-blue-500/10 blur-2xl" />
        <div className="relative">
          <button
            onClick={() => setPermissionsCollapsed((prev) => !(prev ?? true))}
            className="w-full flex items-center justify-between cursor-pointer"
          >
            <div className="text-left">
              <h2 className="text-slate-500 dark:text-slate-400 text-xs uppercase tracking-wider font-semibold mb-1">{t("perm.label")}</h2>
              <p className="text-slate-800 dark:text-slate-200 font-medium">{t("perm.title")}</p>
            </div>
            <svg className={`w-4 h-4 text-slate-400 transition-transform duration-200 ${permissionsCollapsed !== false ? "" : "rotate-180"}`} viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.174l3.71-3.944a.75.75 0 111.08 1.04l-4.25 4.52a.75.75 0 01-1.08 0l-4.25-4.52a.75.75 0 01.02-1.06z" clipRule="evenodd" />
            </svg>
          </button>
          {permissionsCollapsed === false && (
            <div className="mt-4">
              <div className="space-y-2 text-sm">
                <PermissionRow label={t("perm.accessibility")} status={permissions?.accessibility ?? "not_required"} />
                <PermissionRow label={t("perm.input_monitoring")} status={permissions?.input_monitoring ?? "not_required"} />
              </div>
              <div className="flex items-center justify-between mt-3">
                <p className="text-[11px] text-slate-400 dark:text-slate-500">
                  {permissions?.platform === "macos"
                    ? t("perm.macos_hint")
                    : t("perm.other_hint")}
                </p>
                <button
                  onClick={(e) => { e.stopPropagation(); refreshPermissions(true); }}
                  className="text-xs px-3 py-1.5 rounded-lg bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 text-slate-700 dark:text-slate-200 transition-colors shrink-0 ml-3"
                >
                  {t("perm.refresh")}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Action Mappings Card */}
      <div className={`${CARD_WIDTH_CLASS} ${MODERN_CARD_CLASS} p-6 mb-8`}>
        <div className="pointer-events-none absolute -top-8 -right-8 w-24 h-24 rounded-full bg-indigo-500/12 blur-2xl" />
        <div className="pointer-events-none absolute -bottom-8 -left-8 w-24 h-24 rounded-full bg-cyan-500/10 blur-2xl" />
        <div className="relative">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-slate-500 dark:text-slate-400 text-xs uppercase tracking-wider font-semibold">
              {t("mappings.title")}
            </h2>
            <button
              onClick={() => setShowAddModal(true)}
              className="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg bg-blue-600 hover:bg-blue-500 text-white transition-colors font-medium"
            >
              <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M12 4v16m8-8H4" /></svg>
              {t("mappings.add")}
            </button>
          </div>

          <div className="space-y-4">
            {groupedMappings.map((group) => (
              <div key={group.key} className="space-y-2">
                <h3 className="text-[11px] uppercase tracking-wider text-slate-400 dark:text-slate-500 font-semibold px-1">
                  {group.label}
                </h3>
                {group.entries.map((entry) => {
                  const presentation = actionToPresentation(entry.action);
                  return (
                    <div
                      key={`${entry.key}-${entry.with_shift ? "s" : "n"}`}
                      className="flex items-center justify-between bg-slate-50 dark:bg-slate-800/50 rounded-lg p-2 px-3 border border-slate-200/50 dark:border-slate-700/50 hover:border-slate-300 dark:hover:border-slate-500 transition-colors group"
                    >
                      <div className="flex items-center gap-2 min-w-0">
                        <Kbd>Caps</Kbd>
                        <span className="text-slate-400 dark:text-slate-500 font-light text-xs">+</span>
                        {entry.with_shift && (
                          <>
                            <Kbd>Shift</Kbd>
                            <span className="text-slate-400 dark:text-slate-500 font-light text-xs">+</span>
                          </>
                        )}
                        <Kbd>{keyCodeToDisplay(entry.key)}</Kbd>
                      </div>
                      <div className="flex items-center gap-3 overflow-hidden flex-1 justify-end">
                        <div
                          className="flex items-center gap-2 overflow-hidden max-w-[260px]"
                          title={`${presentation.category}: ${presentation.value}`}
                        >
                          <span className="text-xs text-slate-500 dark:text-slate-400 shrink-0">
                            {presentation.category}:
                          </span>
                          <span className={`text-xs truncate ${presentation.valueClassName ?? "text-blue-600 dark:text-blue-300"}`}>
                            {presentation.value}
                          </span>
                          <ActionIcon icon={presentation.icon} className={presentation.iconClassName} />
                        </div>
                        <button onClick={() => removeActionMapping(entry.key, entry.with_shift)} className="text-slate-400 dark:text-slate-600 hover:text-red-500 dark:hover:text-red-400 transition-colors">
                          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            ))}
            {actionMappings.length === 0 && (
              <div className="text-center text-slate-400 dark:text-slate-500 text-xs py-2 italic">{t("mappings.empty")}</div>
            )}
          </div>
        </div>
      </div>

      {/* Add Mapping Modal */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center">
          <div className="absolute inset-0 bg-black/40 backdrop-blur-sm" onClick={() => setShowAddModal(false)} />
          <div className="relative w-full max-w-[420px] mx-4 bg-white dark:bg-slate-800 border border-slate-200/80 dark:border-slate-700/80 rounded-2xl shadow-2xl p-6 animate-modal-in">
            <div className="flex items-center justify-between mb-5">
              <h2 className="text-slate-800 dark:text-slate-200 font-semibold text-base">{t("mappings.add_title")}</h2>
              <button
                onClick={() => setShowAddModal(false)}
                className="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors p-1"
              >
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>

            <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-2 mb-1">
              <FormSelect
                value={newWithShift ? "with_shift" : "plain"}
                onChange={(value) => setNewWithShift(value === "with_shift")}
                wrapperClassName="col-span-1"
                options={[
                  { value: "plain", label: t("mappings.caps") },
                  { value: "with_shift", label: t("mappings.caps_shift") },
                ]}
              />
              <span className="text-slate-400 dark:text-slate-500 text-sm font-medium select-none">+</span>
              <input
                type="text"
                placeholder={t("mappings.press_key")}
                value={newKeyDisplay}
                readOnly
                onKeyDown={(e) => {
                  e.preventDefault();
                  if (["Shift", "Control", "Alt", "Meta", "CapsLock"].includes(e.key)) return;
                  setNewKey(e.keyCode);
                  setNewKeyDisplay(keyCodeToDisplay(e.keyCode));
                }}
                className="col-span-1 bg-slate-50 dark:bg-slate-800 border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 text-slate-800 dark:text-slate-200 text-center text-sm focus:outline-none focus:border-blue-500 hover:border-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700/70 transition-colors cursor-pointer"
              />
            </div>

            <div className="flex justify-center mb-1">
              <span className="text-slate-400 dark:text-slate-500 text-base font-medium select-none">↓</span>
            </div>

            <div className="grid grid-cols-[minmax(130px,1fr)_minmax(0,3fr)] items-center gap-2 mb-4">
              <FormSelect
                value={newActionKind}
                onChange={(value) => setNewActionKind(value as ActionConfig["kind"])}
                wrapperClassName="col-span-1"
                options={[
                  { value: "directional", label: t("group.directional") },
                  { value: "jump", label: t("group.jump") },
                  { value: "independent", label: t("group.independent") },
                  ...(permissions?.platform === "macos"
                    ? [{ value: "input_source", label: t("group.input_source") }]
                    : []),
                  { value: "command", label: t("group.command") },
                ]}
              />
              <div className="min-w-0">
                {newActionKind === "directional" && (
                  <FormSelect
                    value={newDirectionalAction}
                    onChange={(value) => setNewDirectionalAction(value as DirectionalAction)}
                    options={[
                      { value: "left", label: t("action.left") },
                      { value: "right", label: t("action.right") },
                      { value: "up", label: t("action.up") },
                      { value: "down", label: t("action.down") },
                      { value: "word_forward", label: t("action.word_forward") },
                      { value: "word_back", label: t("action.word_back") },
                      { value: "home", label: t("action.home") },
                      { value: "end", label: t("action.end") },
                    ]}
                  />
                )}

                {newActionKind === "jump" && (
                  <div className="grid grid-cols-2 gap-2">
                    <FormSelect
                      value={newJumpDirection}
                      onChange={(value) => setNewJumpDirection(value as JumpDirection)}
                      options={[
                        { value: "up", label: t("action.up") },
                        { value: "down", label: t("action.down") },
                      ]}
                    />
                    <input
                      type="number"
                      min={1}
                      max={99}
                      value={newJumpCount}
                      onChange={(e) => setNewJumpCount(Number(e.target.value))}
                      className="bg-slate-50 dark:bg-slate-800 border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 text-slate-800 dark:text-slate-200 text-sm focus:outline-none focus:border-blue-500 hover:border-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700/70 transition-colors"
                    />
                  </div>
                )}

                {newActionKind === "independent" && (
                  <FormSelect
                    value={newIndependentAction}
                    onChange={(value) => setNewIndependentAction(value as IndependentAction)}
                    options={[
                      { value: "backspace", label: t("action.backspace") },
                      { value: "next_line", label: t("action.next_line") },
                      { value: "insert_quotes", label: t("action.insert_quotes") },
                    ]}
                  />
                )}

                {newActionKind === "input_source" && (
                  <input
                    type="text"
                    placeholder="e.g. com.apple.keylayout.ABC"
                    value={newInputSourceId}
                    onChange={(e) => setNewInputSourceId(e.target.value)}
                    className="w-full bg-slate-50 dark:bg-slate-800 border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 text-slate-800 dark:text-slate-200 text-sm focus:outline-none focus:border-blue-500 hover:border-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700/70 transition-colors font-mono"
                  />
                )}

                {newActionKind === "command" && (
                  <input
                    type="text"
                    placeholder="e.g. open -a Calculator"
                    value={newCommand}
                    onChange={(e) => setNewCommand(e.target.value)}
                    className="w-full bg-slate-50 dark:bg-slate-800 border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 text-slate-800 dark:text-slate-200 text-sm focus:outline-none focus:border-blue-500 hover:border-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700/70 transition-colors"
                  />
                )}
              </div>
            </div>

            <button
              onClick={async () => { await upsertActionMapping(); setShowAddModal(false); }}
              disabled={!canSaveAction}
              className="w-full bg-blue-600 hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded-lg px-3 py-2.5 transition-colors text-sm font-medium"
            >
              {t("mappings.save")}
            </button>
          </div>
        </div>
      )}

      <Footer version={appVersion} />
    </main>
  );
}

function Footer({ version }: { version: string }) {
  async function handleCheckUpdate() {
    try {
      const update = await check();
      if (update) {
        const yes = await ask(
          t("update.available", { version: update.version, body: update.body ?? "" }),
          { title: t("update.title"), kind: 'info', okLabel: t("update.ok"), cancelLabel: t("update.cancel") }
        );
        if (yes) {
          await update.downloadAndInstall();
          await message(t("update.installed"), { title: t("update.success"), kind: 'info' });
        }
      } else {
        await message(t("update.latest"), { title: t("update.no_update"), kind: 'info' });
      }
    } catch (error: any) {
      console.error(error);
      await message(t("update.failed", { error: error?.message || error }), { title: t("update.error"), kind: 'error' });
    }
  }

  return (
    <footer className="mt-6 mb-2 flex flex-col items-center gap-2">
      <div className="flex items-center gap-3 text-slate-400 dark:text-slate-500 text-xs font-medium">
        <span>v{version}</span>
        <span className="w-1 h-1 rounded-full bg-slate-300 dark:bg-slate-600"></span>
        <span>{t("footer.by")}</span>
      </div>
      <button
        onClick={handleCheckUpdate}
        className="text-xs text-blue-500/80 hover:text-blue-500 dark:hover:text-blue-400 hover:underline transition-colors rounded-md px-2 py-1 hover:bg-blue-500/10"
      >
        {t("update.check")}
      </button>
    </footer>
  );
}

function PermissionRow({
  label,
  status,
}: {
  label: string;
  status: "granted" | "not_granted" | "not_required";
}) {
  const text =
    status === "granted" ? t("perm.granted") : status === "not_granted" ? t("perm.not_granted") : t("perm.not_required");
  const badgeClass =
    status === "granted"
      ? "text-xs px-2 py-1 rounded-md transition-colors bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300"
      : status === "not_granted"
      ? "text-xs px-2 py-1 rounded-md border transition-colors bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300 border-red-200 dark:border-red-700/50"
      : "text-xs px-2 py-1 rounded-md border transition-colors bg-slate-100 dark:bg-slate-800 text-slate-500 dark:text-slate-400 border-slate-200 dark:border-slate-600";

  return (
    <div className="group flex items-center justify-between bg-slate-50 dark:bg-slate-800/50 border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 transition-colors hover:bg-slate-100 dark:hover:bg-slate-800/70 hover:border-slate-300 dark:hover:border-slate-500">
      <span className="text-slate-700 dark:text-slate-300">{label}</span>
      <span className={badgeClass}>{text}</span>
    </div>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="bg-slate-200 dark:bg-slate-700 text-slate-700 dark:text-slate-200 border-b-2 border-slate-300 dark:border-slate-900 rounded-md px-2 py-1 text-sm font-mono min-w-[32px] text-center shadow-sm group-hover:bg-slate-300 dark:group-hover:bg-slate-600 transition-colors">
      {children}
    </kbd>
  );
}

function FormSelect({
  wrapperClassName = "",
  className = "",
  value,
  options,
  onChange,
  disabled = false,
}: {
  wrapperClassName?: string;
  className?: string;
  value: string;
  options: SelectOption[];
  onChange: (value: string) => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement | null>(null);
  const selected = options.find((opt) => opt.value === value) ?? options[0];

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }
    window.addEventListener("mousedown", handleClickOutside);
    return () => window.removeEventListener("mousedown", handleClickOutside);
  }, []);

  return (
    <div ref={rootRef} className={`relative w-full ${wrapperClassName}`}>
      <button
        type="button"
        disabled={disabled}
        onClick={() => setOpen((prev) => !prev)}
        className={`w-full bg-slate-50 dark:bg-slate-800 border border-slate-300 dark:border-slate-600 rounded-lg px-3 py-2 pr-9 text-slate-800 dark:text-slate-200 text-sm text-left focus:outline-none focus:border-blue-500 hover:border-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700/70 transition-colors disabled:opacity-60 disabled:cursor-not-allowed ${className}`}
      >
        {selected?.label ?? ""}
      </button>
      <span className="pointer-events-none absolute inset-y-0 right-3 flex items-center text-slate-400">
        <svg className={`w-4 h-4 transition-transform ${open ? "rotate-180" : ""}`} viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path
            fillRule="evenodd"
            d="M5.23 7.21a.75.75 0 011.06.02L10 11.174l3.71-3.944a.75.75 0 111.08 1.04l-4.25 4.52a.75.75 0 01-1.08 0l-4.25-4.52a.75.75 0 01.02-1.06z"
            clipRule="evenodd"
          />
        </svg>
      </span>
      {open && !disabled && (
        <div className="absolute z-30 mt-1 w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-900 shadow-xl overflow-hidden">
          {options.map((option) => {
            const active = option.value === value;
            return (
              <button
                key={option.value}
                type="button"
                onClick={() => {
                  onChange(option.value);
                  setOpen(false);
                }}
                className={`w-full text-left px-3 py-2 text-sm transition-colors ${
                  active
                    ? "bg-blue-600/25 text-blue-600 dark:text-blue-300 hover:bg-blue-600/35"
                    : "text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800"
                }`}
              >
                {option.label}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

function ActionIcon({ icon, className }: { icon: string; className?: string }) {
  const commonClasses = `w-4 h-4 ${className ?? "text-primary"}`;

  switch (icon) {
    case "Left": return <svg className={`${commonClasses} rotate-180`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" /></svg>;
    case "Right": return <svg className={`${commonClasses}`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" /></svg>;
    case "Up": return <svg className={`${commonClasses} -rotate-90`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" /></svg>;
    case "Down": return <svg className={`${commonClasses} rotate-90`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" /></svg>;
    case "FastUp": return <svg className={`${commonClasses} -rotate-90`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M13 5l7 7-7 7M5 5l7 7-7 7" /></svg>;
    case "FastDown": return <svg className={`${commonClasses} rotate-90`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M13 5l7 7-7 7M5 5l7 7-7 7" /></svg>;
    case "Delete": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>;
    case "Home": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 19l-7-7 7-7m8 14l-7-7 7-7" /></svg>;
    case "End": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 5l7 7-7 7M5 5l7 7-7 7" /></svg>;
    case "Enter": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" /></svg>;
    case "WordRight": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5-5 5M6 7l5 5-5 5" /></svg>;
    case "WordLeft": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 17l-5-5 5-5M18 17l-5-5 5-5" /></svg>;
    case "Code": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" /></svg>;
    case "Input": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 2a10 10 0 100 20 10 10 0 000-20zm0 0c2.2 2.3 3.5 5.4 3.5 10S14.2 19.7 12 22m0-20C9.8 4.3 8.5 7.4 8.5 12S9.8 19.7 12 22m-9-10h18" /></svg>;
    case "Command": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 8h8v8H8zM8 2a4 4 0 110 8M2 8a4 4 0 108 0m4 8a4 4 0 108 0m-8 6a4 4 0 110-8" /></svg>;
    default: return null;
  }
}

function PlayIcon() {
  return <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" /><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>;
}

function PauseIcon() {
  return <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>;
}

function SunIcon() {
  return (
    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364-6.364l-.707.707M6.343 17.657l-.707.707m12.728 0l-.707-.707M6.343 6.343l-.707-.707M12 8a4 4 0 100 8 4 4 0 000-8z" />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
    </svg>
  );
}

export default App;
