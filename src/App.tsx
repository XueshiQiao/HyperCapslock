import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { listen } from "@tauri-apps/api/event";
import { getVersion } from "@tauri-apps/api/app";
import { check } from "@tauri-apps/plugin-updater";
import { message, ask } from "@tauri-apps/plugin-dialog";
import { enable, disable, isEnabled } from "@tauri-apps/plugin-autostart";
import "./App.css";

function App() {
  const [status, setStatus] = useState("Initializing...");
  const [autostart, setAutostart] = useState(false);
  const [appVersion, setAppVersion] = useState("");
  const [toast, setToast] = useState<{ message: string; type: "success" | "error" } | null>(null);
  
  // Mappings State
  const [mappings, setMappings] = useState<Record<string, string>>({});
  const [newKey, setNewKey] = useState<number | null>(null);
  const [newKeyDisplay, setNewKeyDisplay] = useState("");
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

        const maps = await invoke("get_mappings");
        setMappings(maps as Record<string, string>);

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

  async function addMapping() {
    if (!newKey || !newCommand) return;
    try {
        await invoke("add_mapping", { key: newKey, command: newCommand });
        const maps = await invoke("get_mappings");
        setMappings(maps as Record<string, string>);
        setNewKey(null);
        setNewKeyDisplay("");
        setNewCommand("");
        showToast("Mapping added", "success");
    } catch (e) {
        console.error(e);
        showToast("Failed to add mapping", "error");
    }
  }

  async function removeMapping(key: number) {
    try {
        await invoke("remove_mapping", { key });
        const maps = await invoke("get_mappings");
        setMappings(maps as Record<string, string>);
        showToast("Mapping removed", "success");
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
  const pingColor = isRunning ? "bg-green-400" : isPaused ? "bg-amber-400" : "bg-red-400";

  return (
    <main className="flex flex-col items-center justify-center min-h-screen bg-background p-6 select-none overflow-y-auto relative">
      
      {/* Toast Notification */}
      {toast && (
        <div className={`fixed bottom-10 left-1/2 z-50 px-6 py-3 rounded-xl shadow-2xl flex items-center gap-3 animate-slide-up border whitespace-nowrap ${
          toast.type === "success" 
            ? "bg-slate-800 border-green-500/50 text-green-400" 
            : "bg-slate-800 border-red-500/50 text-red-400"
        }`}>
          {toast.type === "success" ? (
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
          ) : (
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
          )}
          <span className="font-medium text-sm text-slate-200">{toast.message}</span>
        </div>
      )}

      {/* Header */}
      <div className="text-center mb-8 mt-10">
        <h1 className="text-4xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-400 to-purple-500 mb-2">
          HyperCapslock
        </h1>
        <p className="text-slate-400 text-sm">System-wide Vim navigation</p>
      </div>

      {/* Status Card */}
      <div className="w-full max-w-md bg-surface border border-slate-700 rounded-2xl p-6 shadow-xl mb-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-slate-400 text-xs uppercase tracking-wider font-semibold mb-1">Status</h2>
            <p className={`text-xl font-medium ${statusColor}`}>
              {status}
            </p>
          </div>
          <div className="relative flex h-3 w-3">
            {(isRunning || isPaused) && <span className={`animate-ping absolute inline-flex h-full w-full rounded-full ${pingColor} opacity-75`}></span>}
            <span className={`relative inline-flex rounded-full h-3 w-3 ${dotColor}`}></span>
          </div>
        </div>

        <button
          onClick={togglePause}
          className={`w-full py-3 px-4 rounded-xl font-medium transition-all duration-200 transform active:scale-95 flex items-center justify-center gap-2
            ${isRunning 
              ? "bg-slate-700 hover:bg-slate-600 text-slate-200 border border-slate-600" 
              : "bg-blue-600 hover:bg-blue-500 text-white shadow-lg shadow-blue-900/20"
            }`}
        >
          {isRunning ? <><PauseIcon /><span>Pause Service (Gaming Mode)</span></> : <><PlayIcon /><span>Resume Service</span></>}
        </button>
      </div>

      {/* Settings Card */}
      <div className="w-full max-w-md bg-surface border border-slate-700 rounded-2xl p-6 shadow-xl mb-8 flex items-center justify-between">
        <div>
           <h2 className="text-slate-400 text-xs uppercase tracking-wider font-semibold mb-1">Settings</h2>
           <p className="text-slate-200 font-medium">Start at Login</p>
        </div>
        <button 
           onClick={toggleAutostart} 
           className={`w-12 h-6 rounded-full p-1 transition-colors duration-200 ease-in-out cursor-pointer ${autostart ? 'bg-primary' : 'bg-slate-600'}`}
        >
           <div className={`bg-white w-4 h-4 rounded-full shadow-md transform transition-transform duration-200 ease-in-out ${autostart ? 'translate-x-6' : 'translate-x-0'}`} />
        </button>
      </div>

      {/* Shell Mappings Card */}
      <div className="w-full max-w-md bg-surface border border-slate-700 rounded-2xl p-6 shadow-xl mb-8">
        <h2 className="text-slate-400 text-xs uppercase tracking-wider font-semibold mb-4">Custom Shell Mappings (Caps+Shift+Key)</h2>
        
        <div className="flex gap-2 mb-4">
            <input 
                type="text" 
                placeholder="Press Key"
                value={newKeyDisplay}
                readOnly
                onKeyDown={(e) => {
                    e.preventDefault();
                    // Basic filtering
                    if (["Shift", "Control", "Alt", "Meta", "CapsLock"].includes(e.key)) return;
                    setNewKey(e.keyCode);
                    setNewKeyDisplay(e.key.toUpperCase());
                }}
                className="w-24 bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-slate-200 text-center text-sm focus:outline-none focus:border-blue-500 transition-colors cursor-pointer"
            />
            <input 
                type="text" 
                placeholder="Command (e.g. open -a Calculator)"
                value={newCommand}
                onChange={(e) => setNewCommand(e.target.value)}
                className="flex-1 bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-slate-200 text-sm focus:outline-none focus:border-blue-500 transition-colors"
            />
            <button 
                onClick={addMapping}
                disabled={!newKey || !newCommand}
                className="bg-blue-600 hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded-lg px-3 transition-colors"
            >
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" /></svg>
            </button>
        </div>

        <div className="space-y-2 max-h-40 overflow-y-auto pr-1 custom-scrollbar">
            {Object.entries(mappings).map(([k, cmd]) => (
                <div key={k} className="flex items-center justify-between bg-slate-800/50 rounded-lg p-2 px-3 border border-slate-700/50 group">
                    <div className="flex items-center gap-2">
                        <Kbd>C</Kbd>
                        <span className="text-slate-500 font-light text-xs">+</span>
                        <Kbd>S</Kbd>
                        <span className="text-slate-500 font-light text-xs">+</span>
                        <Kbd>{String.fromCharCode(parseInt(k))}</Kbd>
                    </div>
                    <div className="flex items-center gap-3 overflow-hidden flex-1 justify-end">
                        <span className="text-xs text-slate-400 truncate max-w-[150px] font-mono" title={cmd}>{cmd}</span>
                        <button onClick={() => removeMapping(parseInt(k))} className="text-slate-600 hover:text-red-400 transition-colors">
                           <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
                        </button>
                    </div>
                </div>
            ))}
            {Object.keys(mappings).length === 0 && (
                <div className="text-center text-slate-500 text-xs py-2 italic">No custom mappings yet</div>
            )}
        </div>
      </div>

      {/* Mappings Grid */}
      <div className={`w-full max-w-md transition-opacity duration-300 ${isPaused ? "opacity-50 grayscale" : "opacity-100"}`}>
        <h3 className="text-slate-400 text-xs uppercase tracking-wider font-semibold mb-4 ml-1">Key Mappings</h3>
        
        <div className="grid gap-2">
          <MappingRow keyChar="H" action="Left" icon="Left" />
          <MappingRow keyChar="J" action="Down" icon="Down" />
          <MappingRow keyChar="K" action="Up" icon="Up" />
          <MappingRow keyChar="L" action="Right" icon="Right" />
          
          <div className="h-2"></div>

          <MappingRow keyChar="P" action="Word Forward" icon="WordRight" />
          <MappingRow keyChar="Y" action="Word Back" icon="WordLeft" />

          <div className="h-2"></div>

          <MappingRow keyChar="I" action="Backspace" icon="Delete" />
          
          <div className="h-2"></div>

          <MappingRow keyChar="N" action='Insert """|"""' icon="Code" />

          <div className="h-2"></div>
          
          <MappingRow keyChar="A" action="Home" icon="Home" />
          <MappingRow keyChar="E" action="End" icon="End" />
          <MappingRow keyChar="O" action="Next Line" icon="Enter" />

          <div className="h-2"></div>

          <MappingRow keyChar="U" action="Up (10x)" icon="FastUp" />
          <MappingRow keyChar="D" action="Down (10x)" icon="FastDown" />
        </div>

        <div className="mt-8 mb-4 p-4 bg-slate-800/50 rounded-lg border border-slate-700/50">
          <p className="text-xs text-slate-400 leading-relaxed text-center">
            <span className="font-semibold text-blue-400">Pro Tip:</span> CapsLock acts as a modifier. 
            Tap it quickly to toggle standard CapsLock. Hold it + Key to navigate.
          </p>
        </div>
      </div>

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
          `Version ${update.version} is available.\n\nRelease notes:\n${update.body}`, 
          { title: 'Update Available', kind: 'info', okLabel: 'Update', cancelLabel: 'Cancel' }
        );
        if (yes) {
          await update.downloadAndInstall();
          // Restart is required to apply the update
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
    <footer className="mt-6 mb-2 flex flex-col items-center gap-2">
      <div className="flex items-center gap-3 text-slate-500 text-xs font-medium">
        <span>v{version}</span>
        <span className="w-1 h-1 rounded-full bg-slate-600"></span>
        <span>By Xueshi Qiao</span>
      </div>
      <button 
        onClick={handleCheckUpdate}
        className="text-xs text-blue-500/80 hover:text-blue-400 hover:underline transition-colors"
      >
        Check for Updates
      </button>
    </footer>
  );
}

function MappingRow({ keyChar, action, icon }: { keyChar: string, action: string, icon: string }) {
  return (
    <div className="flex items-center justify-between bg-surface border border-slate-700/50 rounded-xl p-3 px-4 hover:border-slate-600 transition-colors group">
      <div className="flex items-center gap-2">
        <Kbd>Caps</Kbd>
        <span className="text-slate-500 font-light">+</span>
        <Kbd>{keyChar}</Kbd>
      </div>
      <div className="flex items-center text-slate-300 gap-3">
        <span className="text-sm font-medium tracking-wide">{action}</span>
        <ActionIcon icon={icon} />
      </div>
    </div>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="bg-slate-700 text-slate-200 border-b-2 border-slate-900 rounded-md px-2 py-1 text-sm font-mono min-w-[32px] text-center shadow-sm group-hover:bg-slate-600 transition-colors">
      {children}
    </kbd>
  );
}

function ActionIcon({ icon }: { icon: string }) {
  const commonClasses = "w-4 h-4 text-primary";
  
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
    case "WordRight": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5-5 5M6 7l5 5-5 5" /></svg>; // Double arrow right
    case "WordLeft": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 17l-5-5 5-5M18 17l-5-5 5-5" /></svg>; // Double arrow left
    case "Code": return <svg className={commonClasses} fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4" /></svg>; // < >
    default: return null;
  }
}

function PlayIcon() {
  return <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" /><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>;
}

function PauseIcon() {
  return <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>;
}

export default App;
