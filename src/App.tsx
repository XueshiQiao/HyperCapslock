import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import "./App.css";

function App() {
  const [status, setStatus] = useState("Initializing...");

  useEffect(() => {
    async function fetchStatus() {
      try {
        const msg = await invoke("get_status");
        setStatus(msg as string);
      } catch (e) {
        setStatus("Error connecting to backend");
      }
    }
    fetchStatus();
  }, []);

  const isRunning = status.toLowerCase().includes("running");

  return (
    <main className="flex flex-col items-center justify-center min-h-screen bg-background p-6 select-none">
      
      {/* Header */}
      <div className="text-center mb-10">
        <h1 className="text-4xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-400 to-purple-500 mb-2">
          Global Vim-Like Navi
        </h1>
        <p className="text-slate-400 text-sm">System-wide Vim navigation for Windows</p>
      </div>

      {/* Status Card */}
      <div className="w-full max-w-md bg-surface border border-slate-700 rounded-2xl p-6 shadow-xl mb-8 flex items-center justify-between">
        <div>
          <h2 className="text-slate-400 text-xs uppercase tracking-wider font-semibold mb-1">Status</h2>
          <p className={`text-xl font-medium ${isRunning ? "text-white" : "text-red-400"}`}>
            {status}
          </p>
        </div>
        <div className="relative flex h-3 w-3">
          {isRunning && <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>}
          <span className={`relative inline-flex rounded-full h-3 w-3 ${isRunning ? "bg-green-500" : "bg-red-500"}`}></span>
        </div>
      </div>

      {/* Mappings Grid */}
      <div className="w-full max-w-md">
        <h3 className="text-slate-400 text-xs uppercase tracking-wider font-semibold mb-4 ml-1">Key Mappings</h3>
        
        <div className="grid gap-3">
          <MappingRow keyChar="H" arrow="Left" />
          <MappingRow keyChar="J" arrow="Down" />
          <MappingRow keyChar="K" arrow="Up" />
          <MappingRow keyChar="L" arrow="Right" />
        </div>

        <div className="mt-8 p-4 bg-slate-800/50 rounded-lg border border-slate-700/50">
          <p className="text-xs text-slate-400 leading-relaxed text-center">
            <span className="font-semibold text-blue-400">Pro Tip:</span> CapsLock acts as a modifier. 
            Tap it quickly to toggle standard CapsLock. Hold it + H/J/K/L to navigate.
          </p>
        </div>
      </div>

    </main>
  );
}

function MappingRow({ keyChar, arrow }: { keyChar: string, arrow: string }) {
  return (
    <div className="flex items-center justify-between bg-surface border border-slate-700/50 rounded-xl p-3 px-4 hover:border-slate-600 transition-colors group">
      <div className="flex items-center gap-2">
        <Kbd>Caps</Kbd>
        <span className="text-slate-500 font-light">+</span>
        <Kbd>{keyChar}</Kbd>
      </div>
      <div className="flex items-center text-slate-300 gap-3">
        <span className="text-sm font-medium tracking-wide">{arrow}</span>
        <ArrowIcon direction={arrow} />
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

function ArrowIcon({ direction }: { direction: string }) {
  const rotate = {
    "Left": "rotate-180",
    "Right": "rotate-0",
    "Up": "-rotate-90",
    "Down": "rotate-90"
  }[direction];

  return (
    <svg className={`w-4 h-4 text-primary ${rotate}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M14 5l7 7m0 0l-7 7m7-7H3" />
    </svg>
  );
}

export default App;
