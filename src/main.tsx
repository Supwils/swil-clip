import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import "./global.css";

const rootElement = document.getElementById("root");
if (!rootElement) throw new Error("Root element not found");

async function bootstrap(): Promise<void> {
  // Browser-only UI preview: `pnpm dev` → http://localhost:5173/?mockui
  // mocks the Tauri IPC with sample data (see devMock.ts). The dynamic
  // import is dead code in production builds.
  if (import.meta.env.DEV && new URLSearchParams(window.location.search).has("mockui")) {
    await import("./devMock");
  }

  createRoot(rootElement!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}

void bootstrap();
