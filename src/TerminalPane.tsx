import { useEffect, useRef } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { PaneHeader } from "./PaneHeader";
import type { Dir } from "./tree";
import "@xterm/xterm/css/xterm.css";

interface Props {
  paneId: string;
  focused: boolean;
  onFocus: () => void;
  onSplit: (dir: Dir) => void;
  onClose: () => void;
}

/**
 * 패인 하나 = 헤더(분할·닫기) + xterm 뷰 + Rust PTY 하나.
 * PTY 생명주기(spawn/write/resize/kill)를 이 컴포넌트가 캡슐화한다.
 * 컨테이너 크기 변화(창·분할·리사이즈)는 ResizeObserver가 fit으로 흡수한다.
 */
export function TerminalPane({ paneId, focused, onFocus, onSplit, onClose }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const termRef = useRef<Terminal | null>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let disposed = false;

    const term = new Terminal({
      fontFamily: "Menlo, Monaco, monospace",
      fontSize: 13,
      cursorBlink: true,
      theme: { background: "#ffffff", foreground: "#1e242b", cursor: "#1e242b" },
    });
    termRef.current = term;
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(container);
    safeFit(fit);

    const onData = term.onData((data) => {
      void invoke("pty_write", { paneId, data });
    });
    const onResize = term.onResize(({ cols, rows }) => {
      void invoke("pty_resize", { paneId, cols, rows });
    });

    // 컨테이너 크기 변화 → 재fit (창 리사이즈·분할·구분선 드래그를 한 경로로)
    const ro = new ResizeObserver(() => safeFit(fit));
    ro.observe(container);

    let unlistenOut: UnlistenFn | undefined;
    let unlistenExit: UnlistenFn | undefined;

    // 리스너를 먼저 등록한 뒤 spawn — 초기 프롬프트 출력을 놓치지 않도록
    void (async () => {
      unlistenOut = await listen<number[]>(`pty://output:${paneId}`, (e) => {
        term.write(new Uint8Array(e.payload));
      });
      unlistenExit = await listen(`pty://exit:${paneId}`, () => {
        term.write("\r\n\x1b[90m[프로세스 종료됨]\x1b[0m\r\n");
      });
      if (disposed) {
        unlistenOut();
        unlistenExit();
        return;
      }
      await invoke("pty_spawn", { paneId, cols: term.cols, rows: term.rows });
    })();

    return () => {
      disposed = true;
      onData.dispose();
      onResize.dispose();
      ro.disconnect();
      unlistenOut?.();
      unlistenExit?.();
      void invoke("pty_kill", { paneId });
      term.dispose();
      termRef.current = null;
    };
  }, [paneId]);

  // 포커스가 이 패인으로 오면 xterm에 실제 DOM 포커스를 준다
  useEffect(() => {
    if (focused) termRef.current?.focus();
  }, [focused]);

  return (
    <div
      onMouseDown={onFocus}
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100%",
        width: "100%",
        boxSizing: "border-box",
        border: `1px solid ${focused ? "var(--border-focus)" : "var(--border)"}`,
        background: "var(--bg)",
      }}
    >
      <PaneHeader onSplit={onSplit} onClose={onClose} />
      <div ref={containerRef} style={{ flex: 1, minHeight: 0, width: "100%", padding: 2 }} />
    </div>
  );
}

// 컨테이너 크기가 0이거나 미준비일 때 fit이 던질 수 있어 방어한다
function safeFit(fit: FitAddon) {
  try {
    fit.fit();
  } catch {
    /* 크기 미확정 — 다음 ResizeObserver 콜백에서 재시도 */
  }
}
