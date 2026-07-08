import { useEffect, useRef, useState } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { SearchAddon } from "@xterm/addon-search";
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { PaneHeader } from "./PaneHeader";
import { SearchBar } from "./SearchBar";
import { reduceIme, shouldRedirectToInput } from "./ime";
import type { Dir } from "./tree";
import "@xterm/xterm/css/xterm.css";

// 검색 매치 하이라이트 스타일
const SEARCH_OPTS = {
  decorations: {
    matchBackground: "#ffe082",
    matchOverviewRuler: "#ffb300",
    activeMatchBackground: "#ff9800",
    activeMatchColorOverviewRuler: "#e65100",
  },
};

interface Props {
  paneId: string;
  cwd?: string;
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
export function TerminalPane({ paneId, cwd, focused, onFocus, onSplit, onClose }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const termRef = useRef<Terminal | null>(null);
  const searchRef = useRef<SearchAddon | null>(null);
  const queryRef = useRef("");
  const [searchOpen, setSearchOpen] = useState(false);

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
    const search = new SearchAddon();
    term.loadAddon(search);
    searchRef.current = search;
    term.open(container);
    safeFit(fit);

    // 한글 IME 우회(WKWebView는 composition 이벤트를 안 줘 xterm이 모음을 흘린다).
    // 조합 중인 글자만 우리가 붙들고(composing), 그 외(확정 문자·삭제·화살표·히스토리)는 셸에 위임한다.
    // 제어키가 onData로 오면 조합 세션 경계이므로 composing을 리셋한다.
    const ta = term.textarea;
    let composing = "";
    const onData = term.onData((data) => {
      composing = "";
      void invoke("pty_write", { paneId, data });
    });

    // 문자·Enter·Backspace·IME 조합 keydown을 xterm에서 격리 → 브라우저 기본 input 이벤트로 유도
    term.attachCustomKeyEventHandler((e) => !(e.type === "keydown" && shouldRedirectToInput(e)));
    // input을 document 캡처 단계에서 가로채(=xterm보다 먼저) 조합을 직접 처리한다
    const onInput = (e: Event) => {
      if (e.target !== ta || !ta) return;
      e.stopPropagation(); // xterm의 자체 input 처리(자음만 유출)를 막는다
      const ie = e as InputEvent;
      const r = reduceIme(composing, { inputType: ie.inputType, data: ie.data, value: ta.value });
      composing = r.composing;
      if (r.resetValue !== null) ta.value = r.resetValue;
      if (r.writes) void invoke("pty_write", { paneId, data: r.writes });
    };
    document.addEventListener("input", onInput, true);

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
      await invoke("pty_spawn", { paneId, cwd, cols: term.cols, rows: term.rows });
    })();

    return () => {
      disposed = true;
      onData.dispose();
      onResize.dispose();
      document.removeEventListener("input", onInput, true);
      ro.disconnect();
      unlistenOut?.();
      unlistenExit?.();
      void invoke("pty_kill", { paneId });
      term.dispose();
      termRef.current = null;
      searchRef.current = null;
    };
    // cwd는 패인당 고정이라 재실행되지 않지만, effect가 실제로 의존하므로 명시한다
  }, [paneId, cwd]);

  // 포커스가 이 패인으로 오면 xterm에 실제 DOM 포커스를 준다
  useEffect(() => {
    if (focused) termRef.current?.focus();
  }, [focused]);

  // ⌘F — 포커스된 패인에서 검색 열기
  useEffect(() => {
    if (!focused) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey && e.key.toLowerCase() === "f") {
        e.preventDefault();
        e.stopPropagation();
        setSearchOpen(true);
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [focused]);

  const onSearchChange = (q: string) => {
    queryRef.current = q;
    if (q) searchRef.current?.findNext(q, { ...SEARCH_OPTS, incremental: true });
    else searchRef.current?.clearDecorations();
  };
  const closeSearch = () => {
    setSearchOpen(false);
    searchRef.current?.clearDecorations();
    termRef.current?.focus();
  };

  return (
    <div
      onMouseDown={onFocus}
      style={{
        position: "relative",
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
      {searchOpen && (
        <SearchBar
          onChange={onSearchChange}
          onNext={() => searchRef.current?.findNext(queryRef.current, SEARCH_OPTS)}
          onPrev={() => searchRef.current?.findPrevious(queryRef.current, SEARCH_OPTS)}
          onClose={closeSearch}
        />
      )}
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
