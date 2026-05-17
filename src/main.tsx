import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import Hud from "./Hud";

const isHud = window.location.hash === "#hud";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>{isHud ? <Hud /> : <App />}</React.StrictMode>,
);
