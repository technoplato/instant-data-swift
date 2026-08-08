/**
 * Electron shell for Instant Exercise Gem live list.
 * Starts a high-frequency simple-write loop and pushes rows to the renderer.
 *
 * Env: INSTANT_APP_ID, INSTANT_ADMIN_TOKEN
 * Run: npm run electron (from exercise-gem root after npm install)
 */
import { app, BrowserWindow, ipcMain } from "electron";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const gemRoot = join(__dirname, "..");

let mainWindow = null;
let writer = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 980,
    height: 720,
    title: "Instant Exercise Gem (Electron)",
    webPreferences: {
      preload: join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  mainWindow.loadFile(join(__dirname, "renderer", "index.html"));
}

function startLiveLoop() {
  if (writer) return;
  const tsx = join(gemRoot, "node_modules", ".bin", "tsx");
  const script = join(gemRoot, "src", "electron-live-worker.ts");
  writer = spawn(tsx, [script], {
    cwd: gemRoot,
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  writer.stdout.setEncoding("utf8");
  let buffer = "";
  writer.stdout.on("data", (chunk) => {
    buffer += chunk;
    let idx;
    while ((idx = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, idx);
      buffer = buffer.slice(idx + 1);
      if (!line.trim()) continue;
      try {
        const row = JSON.parse(line);
        mainWindow?.webContents.send("gem-event", row);
      } catch {
        mainWindow?.webContents.send("gem-event", { type: "log", message: line });
      }
    }
  });
  writer.stderr.setEncoding("utf8");
  writer.stderr.on("data", (chunk) => {
    mainWindow?.webContents.send("gem-event", { type: "log", message: String(chunk) });
  });
  writer.on("exit", (code) => {
    mainWindow?.webContents.send("gem-event", { type: "worker-exit", code });
    writer = null;
  });
}

function stopLiveLoop() {
  if (writer) {
    writer.kill("SIGTERM");
    writer = null;
  }
}

app.whenReady().then(() => {
  createWindow();
  ipcMain.handle("gem-start", () => {
    startLiveLoop();
    return { ok: true };
  });
  ipcMain.handle("gem-stop", () => {
    stopLiveLoop();
    return { ok: true };
  });
});

app.on("window-all-closed", () => {
  stopLiveLoop();
  if (process.platform !== "darwin") app.quit();
});
