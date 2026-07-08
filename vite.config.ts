import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Tauri는 고정 dev 포트를 기대한다. 기본 1420은 다른 로컬 Tauri 앱과 겹치므로 muxa는 1430을 쓴다.
const host = process.env.TAURI_DEV_HOST;

export default defineConfig({
  plugins: [react()],
  // Tauri가 자체 로그를 남기므로 Vite가 화면을 지우지 않게 한다
  clearScreen: false,
  server: {
    port: 1430,
    strictPort: true,
    host: host || false,
    hmr: host
      ? { protocol: "ws", host, port: 1431 }
      : undefined,
    // src-tauri 변경은 Vite가 감시하지 않는다 (Rust 쪽 워처가 담당)
    watch: { ignored: ["**/src-tauri/**"] },
  },
});
