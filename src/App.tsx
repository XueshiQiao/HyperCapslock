import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { listen } from "@tauri-apps/api/event";
import { getVersion } from "@tauri-apps/api/app";
import { check } from "@tauri-apps/plugin-updater";
import { message, ask } from "@tauri-apps/plugin-dialog";
import { enable, disable, isEnabled } from "@tauri-apps/plugin-autostart";
import { openUrl } from "@tauri-apps/plugin-opener";
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
  222: "'",
  32: "Space"
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
    case "directional":
      switch (action.action) {
        case "left": return { category: "Directional", value: "Left", icon: "Left" };
        case "right": return { category: "Directional", value: "Right", icon: "Right" };
        case "up": return { category: "Directional", value: "Up", icon: "Up" };
        case "down": return { category: "Directional", value: "Down", icon: "Down" };
        case "word_forward": return { category: "Directional", value: "Word Forward", icon: "WordRight" };
        case "word_back": return { category: "Directional", value: "Word Back", icon: "WordLeft" };
        case "home": return { category: "Directional", value: "Home", icon: "Home" };
        case "end": return { category: "Directional", value: "End", icon: "End" };
      }
    case "jump":
      return {
        category: "Jump",
        value: `${action.direction === "up" ? "Up" : "Down"} x${action.count}`,
        icon: action.direction === "up" ? "FastUp" : "FastDown",
      };
    case "independent":
      switch (action.action) {
        case "backspace": return { category: "Independent", value: "Backspace", icon: "Delete" };
        case "next_line": return { category: "Independent", value: "Next Line", icon: "Enter" };
        case "insert_quotes": return { category: "Independent", value: "Insert quotes", icon: "Code" };
      }
    case "input_source":
      return { category: "Input Source", value: action.input_source_id, icon: "Input" };
    case "command":
      return { category: "Command", value: action.command, icon: "Command" };
    default:
      return { category: "Unknown", value: "Unknown", icon: "Code" };
  }
}

const ACTION_GROUP_ORDER: Array<{ key: ActionGroupKey; label: string }> = [
  { key: "directional", label: "Directional Navigation" },
  { key: "jump", label: "Jump Navigation" },
  { key: "independent", label: "Independent Actions" },
  { key: "input_source", label: "Input Sources" },
  { key: "command", label: "System Commands" },
];

function App() {
  const [status, setStatus] = useState("Initializing...");
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

  useEffect(() => {
    let unlisten: () => void;

    async function init() {
      try {
        const v = await getVersion();
        setAppVersion(v);
        const msg = await invoke("get_status");
        setStatus(msg as string);
        const auto = await isEnabled();
        setAutostart(auto);

        await reloadActionMappings();
        await refreshPermissions();

        unlisten = await listen<boolean>("status-update", (event) => {
          const paused = event.payload;
          setStatus(paused ? "Paused" : "Running");
        });
      } catch (e: any) {
        setStatus(`Error: ${e?.message || e || "Unknown backend error"}`);
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
      const p = await invoke("get_permission_statuses");
      setPermissions(p as PermissionStatuses);
      if (showFeedback) showToast("Permissions refreshed", "success");
    } catch (e) {
      console.error("Failed to fetch permission statuses", e);
      if (showFeedback) showToast("Failed to refresh permissions", "error");
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
      showToast("Action mapping saved", "success");
    } catch (e: any) {
      console.error(e);
      showToast((e?.toString?.() ?? "Failed to save mapping").replace("Error: ", ""), "error");
    }
  }

  async function removeActionMapping(key: number, withShift: boolean) {
    try {
      await invoke("remove_action_mapping", { key, withShift });
      await reloadActionMappings();
      showToast("Action mapping removed", "success");
    } catch (e) {
      console.error(e);
      showToast("Failed to remove mapping", "error");
    }
  }

  async function togglePause() {
    try {
      const shouldPause = status === "Running";
      const newStatus = await invoke("set_paused", { paused: shouldPause });
      setStatus(newStatus as string);
      showToast(shouldPause ? "Service Paused" : "Service Resumed", "success");
    } catch (e) {
      console.error("Failed to toggle pause", e);
      showToast("Failed to toggle service", "error");
    }
  }

  async function toggleAutostart() {
    try {
      if (autostart) {
        await disable();
        setAutostart(false);
        showToast("Autostart disabled", "success");
      } else {
        await enable();
        setAutostart(true);
        showToast("Autostart enabled", "success");
      }
    } catch (e) {
      console.error("Failed to toggle autostart", e);
      showToast("Failed to change settings", "error");
    }
  }

  const isRunning = status === "Running";
  const isPaused = status === "Paused";

  const statusColor = isRunning ? "text-green-400" : isPaused ? "text-amber-400" : "text-red-400";
  const dotColor = isRunning ? "bg-green-500" : isPaused ? "bg-amber-500" : "bg-red-500";
  const glowColor = isRunning ? "glow-success" : isPaused ? "glow-warning" : "glow-danger";

  const draftAction = buildDraftAction();
  const canSaveAction = !!newKey && !!draftAction;
  const groupedMappings = ACTION_GROUP_ORDER.map((group) => ({
    ...group,
    entries: actionMappings.filter((entry) => entry.action.kind === group.key),
  })).filter((group) => group.entries.length > 0);

  return (
    <div className="h-screen w-full bg-[#09090b] text-white/90 overflow-y-auto font-sans relative pb-10 scroll-smooth">
      
      {/* Immersive background effects */}
      <div className="pointer-events-none fixed top-[-20%] left-[-10%] w-[50%] h-[50%] rounded-full bg-blue-600/10 blur-[140px]" />
      <div className="pointer-events-none fixed bottom-[-20%] right-[-10%] w-[50%] h-[50%] rounded-full bg-purple-600/10 blur-[140px]" />

      {/* Toast Notification */}
      {toast && (
        <div className={`fixed bottom-8 left-1/2 -translate-x-1/2 z-50 px-5 py-3 rounded-full shadow-2xl flex items-center gap-3 animate-slide-up border backdrop-blur-xl bg-white/[0.05] ${
          toast.type === "success" ? "border-green-500/30 text-green-300" : "border-red-500/30 text-red-300"
        }`}>
          {toast.type === "success" ? (
            <svg className="w-5 h-5 opacity-80" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
          ) : (
            <svg className="w-5 h-5 opacity-80" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
          )}
          <span className="font-medium text-sm drop-shadow-sm">{toast.message}</span>
        </div>
      )}

      <div className="max-w-[700px] mx-auto pt-14 px-6 relative z-10">
        
        {/* Header */}
        <header className="mb-10 text-center">
          <h1 className="text-4xl md:text-5xl font-extrabold tracking-tight mb-3">
            <span className="bg-clip-text text-transparent bg-gradient-to-r from-blue-400 via-indigo-400 to-purple-400">
              HyperCapslock
            </span>
          </h1>
          <p className="text-white/50 text-sm md:text-base font-medium tracking-wide">
            Make your Capslock Powerful again!
          </p>
        </header>

        {/* Top Control Panel */}
        <section className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          {/* Status Card */}
          <div className="bg-white/[0.02] border border-white/10 backdrop-blur-2xl rounded-3xl p-6 shadow-2xl transition-all hover:bg-white/[0.03] hover:border-white/20 flex flex-col justify-between group relative overflow-hidden">
            <div className="absolute top-0 right-0 w-32 h-32 bg-white/5 rounded-full blur-[50px] -mr-10 -mt-10 pointer-events-none group-hover:bg-blue-500/10 transition-colors" />
            <div className="relative">
              <div className="flex items-center gap-4 mb-6">
                <div className="relative flex items-center justify-center h-4 w-4">
                  {(isRunning || isPaused) && <span className={`animate-ping absolute inline-flex h-full w-full rounded-full ${dotColor} opacity-40`}></span>}
                  <span className={`relative inline-flex rounded-full h-3 w-3 ${dotColor} ${glowColor}`}></span>
                </div>
                <div>
                  <p className="text-[10px] uppercase tracking-widest text-white/40 font-bold mb-0.5">Service Status</p>
                  <p className={`text-lg font-semibold tracking-tight ${statusColor}`}>{status}</p>
                </div>
              </div>
              <button
                onClick={togglePause}
                className={`w-full px-4 py-2.5 rounded-xl font-medium text-sm transition-all active:scale-95 flex items-center justify-center gap-2 border shadow-lg ${
                  isRunning
                    ? "bg-white/5 hover:bg-white/10 text-white border-white/10"
                    : "bg-blue-600 hover:bg-blue-500 text-white border-blue-500 shadow-blue-500/20 glow-primary"
                }`}
              >
                {isRunning ? <><PauseIcon /><span>Pause Service</span></> : <><PlayIcon /><span>Resume Service</span></>}
              </button>
            </div>
          </div>

          {/* Autostart & Permissions Card */}
          <div className="bg-white/[0.02] border border-white/10 backdrop-blur-2xl rounded-3xl p-6 shadow-2xl transition-all hover:bg-white/[0.03] hover:border-white/20 flex flex-col relative overflow-hidden">
            <div className="absolute top-0 left-0 w-32 h-32 bg-white/5 rounded-full blur-[50px] -ml-10 -mt-10 pointer-events-none transition-colors" />
            <div className="relative flex-1 flex flex-col justify-between">
              
              <div className="flex items-center justify-between mb-5">
                <div>
                  <p className="text-[10px] uppercase tracking-widest text-white/40 font-bold mb-0.5">Startup</p>
                  <p className="text-sm font-medium text-white/90">Launch at Login</p>
                </div>
                <button
                  onClick={toggleAutostart}
                  className={`w-11 h-6 rounded-full p-1 border transition-all cursor-pointer shadow-inner relative flex items-center ${
                    autostart ? "bg-blue-500 border-blue-400/50" : "bg-white/10 border-white/10"
                  }`}
                >
                  <div className={`bg-white w-4 h-4 rounded-full shadow-md transform transition-transform ${autostart ? 'translate-x-5' : 'translate-x-0'}`} />
                </button>
              </div>

              <div className="w-full h-px bg-white/5 mb-5" />

              <div>
                <div className="flex items-center justify-between mb-3">
                  <p className="text-[10px] uppercase tracking-widest text-white/40 font-bold">Permissions</p>
                  <button
                    onClick={() => refreshPermissions(true)}
                    className="text-[10px] uppercase tracking-wider text-blue-400 hover:text-blue-300 transition-colors bg-blue-500/10 px-2 py-0.5 rounded-md hover:bg-blue-500/20"
                  >
                    Refresh
                  </button>
                </div>
                <div className="space-y-2">
                  <PermissionRow label="Accessibility" status={permissions?.accessibility ?? "not_required"} />
                  <PermissionRow label="Input Monitor" status={permissions?.input_monitoring ?? "not_required"} />
                </div>
              </div>

            </div>
          </div>
        </section>

        {/* Action Mappings Manager */}
        <section className="bg-white/[0.02] border border-white/10 backdrop-blur-2xl rounded-3xl shadow-2xl relative overflow-hidden flex flex-col group/maps">
          <div className="absolute inset-0 bg-gradient-to-b from-white/[0.02] to-transparent pointer-events-none" />
          
          <div className="p-6 md:p-8 relative">
            <h2 className="text-xl font-bold tracking-tight mb-6 flex items-center gap-2">
              <svg className="w-5 h-5 text-indigo-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4" /></svg>
              Keybind Mappings
            </h2>

            {/* Creator Form */}
            <div className="bg-black/20 border border-white/[0.05] rounded-2xl p-5 mb-8">
              <h3 className="text-[10px] uppercase tracking-widest text-white/40 font-bold mb-4">Add New Mapping</h3>
              
              <div className="flex flex-col gap-3 mb-4">
                <div className="flex items-center gap-3 w-full">
                  <div className="flex-1">
                    <FormSelect
                      value={newWithShift ? "with_shift" : "plain"}
                      onChange={(value) => setNewWithShift(value === "with_shift")}
                      options={[
                        { value: "plain", label: "Caps" },
                        { value: "with_shift", label: "Caps + Shift" },
                      ]}
                    />
                  </div>
                  
                  <svg className="w-5 h-5 text-white/40 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M12 4v16m8-8H4" />
                  </svg>
                  
                  <div className="relative group/input flex-1">
                    <input
                      type="text"
                      placeholder="Press key..."
                      value={newKeyDisplay}
                      readOnly
                      onKeyDown={(e) => {
                        e.preventDefault();
                        if (["Shift", "Control", "Alt", "Meta", "CapsLock"].includes(e.key)) return;
                        setNewKey(e.keyCode);
                        setNewKeyDisplay(keyCodeToDisplay(e.keyCode));
                      }}
                      className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-center text-sm font-medium text-white placeholder-white/30 outline-none hover:bg-white/10 hover:border-white/20 focus:border-blue-500/50 focus:bg-white/10 transition-all cursor-pointer shadow-inner"
                    />
                    <div className="absolute inset-y-0 right-3 flex items-center pointer-events-none opacity-0 group-hover/input:opacity-100 transition-opacity">
                      <svg className="w-4 h-4 text-white/30" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 15l-2 5L9 9l11 4-5 2zm0 0l5 5M7.188 2.239l.777 2.897M5.136 7.965l-2.898-.777M13.95 4.05l-2.122 2.122m-5.657 5.656l-2.12 2.122" /></svg>
                    </div>
                  </div>
                </div>

                <div className="flex justify-center -my-1">
                  <svg className="w-5 h-5 text-blue-400/70 drop-shadow-sm" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 13l-7 7-7-7m14-8l-7 7-7-7" />
                  </svg>
                </div>

                <div className="w-full">
                  <FormSelect
                    value={newActionKind}
                    onChange={(value) => setNewActionKind(value as ActionConfig["kind"])}
                    options={[
                      { value: "directional", label: "Directional" },
                      { value: "jump", label: "Jump" },
                      { value: "independent", label: "Independent" },
                      ...(permissions?.platform === "macos" ? [{ value: "input_source", label: "Input Source" }] : []),
                      { value: "command", label: "System Command" },
                    ]}
                  />
                </div>
              </div>

              {/* Dynamic Action Fields */}
              <div className="mb-4">
                {newActionKind === "directional" && (
                  <FormSelect
                    value={newDirectionalAction}
                    onChange={(value) => setNewDirectionalAction(value as DirectionalAction)}
                    options={[
                      { value: "left", label: "Left" },
                      { value: "right", label: "Right" },
                      { value: "up", label: "Up" },
                      { value: "down", label: "Down" },
                      { value: "word_forward", label: "Word Forward" },
                      { value: "word_back", label: "Word Back" },
                      { value: "home", label: "Home" },
                      { value: "end", label: "End" },
                    ]}
                  />
                )}

                {newActionKind === "jump" && (
                  <div className="grid grid-cols-2 gap-3">
                    <FormSelect
                      value={newJumpDirection}
                      onChange={(value) => setNewJumpDirection(value as JumpDirection)}
                      options={[
                        { value: "up", label: "Up" },
                        { value: "down", label: "Down" },
                      ]}
                    />
                    <input
                      type="number"
                      min={1} max={99}
                      value={newJumpCount}
                      onChange={(e) => setNewJumpCount(Number(e.target.value))}
                      className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white placeholder-white/30 outline-none hover:bg-white/10 hover:border-white/20 focus:border-blue-500/50 focus:bg-white/10 transition-all shadow-inner"
                    />
                  </div>
                )}

                {newActionKind === "independent" && (
                  <FormSelect
                    value={newIndependentAction}
                    onChange={(value) => setNewIndependentAction(value as IndependentAction)}
                    options={[
                      { value: "backspace", label: "Backspace" },
                      { value: "next_line", label: "Next Line" },
                      { value: "insert_quotes", label: "Insert Quotes" },
                    ]}
                  />
                )}

                {newActionKind === "input_source" && (
                  <input
                    type="text"
                    placeholder="e.g. com.apple.keylayout.ABC"
                    value={newInputSourceId}
                    onChange={(e) => setNewInputSourceId(e.target.value)}
                    className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white placeholder-white/30 outline-none hover:bg-white/10 hover:border-white/20 focus:border-blue-500/50 focus:bg-white/10 transition-all font-mono shadow-inner"
                  />
                )}

                {newActionKind === "command" && (
                  <input
                    type="text"
                    placeholder="e.g. open -a Calculator"
                    value={newCommand}
                    onChange={(e) => setNewCommand(e.target.value)}
                    className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white placeholder-white/30 outline-none hover:bg-white/10 hover:border-white/20 focus:border-blue-500/50 focus:bg-white/10 transition-all font-mono shadow-inner"
                  />
                )}
              </div>

              <button
                onClick={upsertActionMapping}
                disabled={!canSaveAction}
                className="w-full bg-white/10 hover:bg-white-20 disabled:bg-white/5 disabled:text-white/30 disabled:border-white/5 text-white border border-white/10 rounded-xl px-4 py-2.5 text-sm font-medium transition-all focus:outline-none focus:ring-2 focus:ring-white/20 active:scale-[0.98]"
                style={canSaveAction ? { backgroundColor: 'rgba(59, 130, 246, 0.8)', borderColor: 'rgba(59, 130, 246, 1)' } : {}}
              >
                Save Mapping
              </button>
            </div>

            {/* Mappings List */}
            <div className="space-y-6">
              {groupedMappings.map((group) => (
                <div key={group.key} className="space-y-2">
                  <h3 className="text-[10px] uppercase tracking-widest text-white/40 font-bold px-1 pb-1 border-b border-white/5">
                    {group.label}
                  </h3>
                  {group.entries.map((entry) => {
                    const presentation = actionToPresentation(entry.action);
                    return (
                      <div
                        key={`${entry.key}-${entry.with_shift ? "s" : "n"}`}
                        className="flex items-center justify-between bg-white/[0.03] rounded-xl p-2 pl-3 pr-2 border border-white/[0.05] hover:border-white/20 hover:bg-white/[0.06] transition-all group/item shadow-sm"
                      >
                        <div className="flex items-center gap-2 min-w-0">
                          <Kbd>Caps</Kbd>
                          <span className="text-white/20 font-light text-xs">+</span>
                          {entry.with_shift && (
                            <>
                              <Kbd>Shift</Kbd>
                              <span className="text-white/20 font-light text-xs">+</span>
                            </>
                          )}
                          <Kbd highlight>{keyCodeToDisplay(entry.key)}</Kbd>
                        </div>
                        <div className="flex items-center gap-3 overflow-hidden flex-1 justify-end">
                          <div className="flex items-center gap-2.5 overflow-hidden" title={`${presentation.category}: ${presentation.value}`}>
                            <span className={`text-xs truncate font-medium ${presentation.valueClassName ?? "text-blue-300/90"}`}>
                              {presentation.value}
                            </span>
                            <ActionIcon icon={presentation.icon} className={`text-white/40 group-hover/item:text-blue-400 transition-colors ${presentation.iconClassName}`} />
                          </div>
                          <button
                            onClick={() => removeActionMapping(entry.key, entry.with_shift)}
                            className="text-white/20 hover:text-red-400 p-1.5 rounded-lg hover:bg-red-500/10 transition-colors"
                            title="Remove Mapping"
                          >
                            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              ))}
              {actionMappings.length === 0 && (
                <div className="text-center text-white/30 text-sm py-8 border border-dashed border-white/10 rounded-2xl">
                  No action mappings defined yet.
                </div>
              )}
            </div>

          </div>
        </section>

        <Footer version={appVersion} />
      </div>
    </div>
  );
}

function Footer({ version }: { version: string }) {
  async function handleCheckUpdate() {
    try {
      const update = await check();
      if (update) {
        const yes = await ask(
          `Version ${update.version} is available.\n\nRelease notes:\n${update.body}`,
          { title: 'Update Available', kind: 'info', okLabel: 'Update', cancelLabel: 'Cancel' }
        );
        if (yes) {
          await update.downloadAndInstall();
          await message('Update installed. Please restart the application.', { title: 'Success', kind: 'info' });
        }
      } else {
        await message('You are on the latest version.', { title: 'No Update', kind: 'info' });
      }
    } catch (error: any) {
      console.error(error);
      await message(`Failed to check for updates: ${error?.message || error}`, { title: 'Error', kind: 'error' });
    }
  }

  return (
    <footer className="mt-10 flex flex-col items-center gap-3 opacity-60 hover:opacity-100 transition-opacity pb-6">
      <div className="flex items-center gap-3 text-white/60 text-xs font-medium tracking-wide">
        <span>v{version}</span>
        <span className="w-1 h-1 rounded-full bg-white/20"></span>
        <button
          onClick={() => openUrl("https://github.com/XueshiQiao/HyperCapslock")}
          className="hover:text-white transition-colors cursor-pointer"
        >
          By Xueshi Qiao
        </button>
      </div>
      <button
        onClick={handleCheckUpdate}
        className="text-[11px] uppercase tracking-wider text-blue-400 hover:text-blue-300 transition-colors bg-blue-500/5 px-3 py-1.5 rounded-full hover:bg-blue-500/15 border border-blue-500/10"
      >
        Check Updates
      </button>
    </footer>
  );
}

function PermissionRow({ label, status }: { label: string; status: "granted" | "not_granted" | "not_required" }) {
  const isGranted = status === "granted";
  const isNotGranted = status === "not_granted";
  
  return (
    <div className="flex items-center justify-between py-1.5">
      <span className="text-sm font-medium text-white/70">{label}</span>
      <div className="flex items-center gap-2">
        <span className="relative flex h-2 w-2">
          {isGranted && <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-20"></span>}
          <span className={`relative inline-flex rounded-full h-2 w-2 ${isGranted ? 'bg-green-500' : isNotGranted ? 'bg-red-500' : 'bg-white/20'}`}></span>
        </span>
        <span className={`text-xs font-medium ${isGranted ? 'text-green-400' : isNotGranted ? 'text-red-400' : 'text-white/40'}`}>
          {isGranted ? "Granted" : isNotGranted ? "Missing" : "N/A"}
        </span>
      </div>
    </div>
  );
}

function Kbd({ children, highlight = false }: { children: React.ReactNode, highlight?: boolean }) {
  return (
    <kbd className={`inline-flex items-center justify-center min-w-[28px] px-2 py-1 text-xs font-mono font-medium rounded-lg border-b-2 shadow-sm transition-colors ${
      highlight 
        ? "bg-white/10 text-white border-white/20 shadow-white/5" 
        : "bg-black/40 text-white/70 border-black/80"
    }`}>
      {children}
    </kbd>
  );
}

function FormSelect({
  wrapperClassName = "", className = "", value, options, onChange, disabled = false,
}: {
  wrapperClassName?: string; className?: string; value: string; options: SelectOption[]; onChange: (value: string) => void; disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement | null>(null);
  const selected = options.find((opt) => opt.value === value) ?? options[0];

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) setOpen(false);
    }
    window.addEventListener("mousedown", handleClickOutside);
    return () => window.removeEventListener("mousedown", handleClickOutside);
  }, []);

  return (
    <div ref={rootRef} className={`relative w-full ${wrapperClassName}`}>
      <button
        type="button" disabled={disabled} onClick={() => setOpen((prev) => !prev)}
        className={`w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 pr-10 text-sm font-medium text-left text-white shadow-inner focus:outline-none hover:bg-white/10 hover:border-white/20 focus:border-blue-500/50 focus:bg-white/10 transition-all disabled:opacity-50 disabled:cursor-not-allowed ${className}`}
      >
        <span className="block truncate">{selected?.label ?? ""}</span>
        <span className="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none text-white/40">
          <svg className={`w-4 h-4 transition-transform duration-200 ${open ? "rotate-180" : ""}`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" /></svg>
        </span>
      </button>
      
      {open && !disabled && (
        <div className="absolute z-50 mt-2 w-full rounded-xl border border-white/10 bg-[#12121a] shadow-2xl overflow-hidden backdrop-blur-3xl transform origin-top animate-dropdown">
          <div className="max-h-60 overflow-y-auto p-1 scrollbar-hide">
            {options.map((option) => {
              const active = option.value === value;
              return (
                <button
                  key={option.value} type="button"
                  onClick={() => { onChange(option.value); setOpen(false); }}
                  className={`w-full text-left px-3 py-2 text-sm font-medium rounded-lg transition-colors flex items-center justify-between ${
                    active ? "bg-blue-500/20 text-blue-300" : "text-white/70 hover:bg-white/10 hover:text-white"
                  }`}
                >
                  {option.label}
                  {active && <svg className="w-4 h-4 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M5 13l4 4L19 7" /></svg>}
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

function ActionIcon({ icon, className }: { icon: string; className?: string }) {
  const base = `w-4 h-4 shrink-0 ${className ?? "text-white/50"}`;

  switch (icon) {
    case "Left": return <svg className={`${base} rotate-180`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" /></svg>;
    case "Right": return <svg className={`${base}`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" /></svg>;
    case "Up": return <svg className={`${base} -rotate-90`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" /></svg>;
    case "Down": return <svg className={`${base} rotate-90`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" /></svg>;
    case "FastUp": return <svg className={`${base} -rotate-90`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M13 5l7 7-7 7M5 5l7 7-7 7" /></svg>;
    case "FastDown": return <svg className={`${base} rotate-90`} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M13 5l7 7-7 7M5 5l7 7-7 7" /></svg>;
    case "Delete": return <svg className={base} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>;
    case "Home": return <svg className={base} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 19l-7-7 7-7m8 14l-7-7 7-7" /></svg>;
    case "End": return <svg className={base} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 5l7 7-7 7M5 5l7 7-7 7" /></svg>;
    case "Enter": return <svg className={base} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" /></svg>;
    case "WordRight": return <svg className={base} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5-5 5M6 7l5 5-5 5" /></svg>;
    case "WordLeft": return <svg className={base} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 17l-5-5 5-5M18 17l-5-5 5-5" /></svg>;
    case "Code": return <svg className={base} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" /></svg>;
    case "Input": return <svg className={base} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 2a10 10 0 100 20 10 10 0 000-20zm0 0c2.2 2.3 3.5 5.4 3.5 10S14.2 19.7 12 22m0-20C9.8 4.3 8.5 7.4 8.5 12S9.8 19.7 12 22m-9-10h18" /></svg>;
    case "Command": return <svg className={base} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 8h8v8H8zM8 2a4 4 0 110 8M2 8a4 4 0 108 0m4 8a4 4 0 108 0m-8 6a4 4 0 110-8" /></svg>;
    default: return null;
  }
}

function PlayIcon() {
  return <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" /><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>;
}

function PauseIcon() {
  return <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>;
}

export default App;
