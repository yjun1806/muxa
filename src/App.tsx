import { useEffect, useRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import "@xterm/xterm/css/xterm.css";

function App() {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const term = new Terminal({
      fontFamily: "Menlo, Monaco, monospace",
      fontSize: 13,
      cursorBlink: true,
      theme: { background: "#1e242b", foreground: "#d6dde4" },
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(container);
    fit.fit();

    // 입력(키) → PTY
    const onData = term.onData((data) => {
      void invoke("pty_write", { data });
    });

    // 터미널 그리드 크기 변경 → PTY 리사이즈(SIGWINCH)
    const onResize = term.onResize(({ cols, rows }) => {
      void invoke("pty_resize", { cols, rows });
    });

    // PTY 출력 → 터미널. 바이트로 받아 xterm이 UTF-8 디코딩(멀티바이트 경계 안전)
    const outputUnlisten = listen<number[]>("pty://output", (e) => {
      term.write(new Uint8Array(e.payload));
    });
    const exitUnlisten = listen("pty://exit", () => {
      term.write("\r\n\x1b[90m[프로세스 종료됨]\x1b[0m\r\n");
    });

    // 현재 그리드 크기로 PTY 생성
    void invoke("pty_spawn", { cols: term.cols, rows: term.rows });

    // 창 리사이즈 → fit (fit이 term.onResize를 유발해 PTY까지 전파)
    const onWindowResize = () => fit.fit();
    window.addEventListener("resize", onWindowResize);

    term.focus();

    return () => {
      onData.dispose();
      onResize.dispose();
      window.removeEventListener("resize", onWindowResize);
      void outputUnlisten.then((fn) => fn());
      void exitUnlisten.then((fn) => fn());
      term.dispose();
    };
  }, []);

  return (
    <div
      ref={containerRef}
      style={{ height: "100%", width: "100%", padding: 8, background: "#1e242b" }}
    />
  );
}

export default App;
