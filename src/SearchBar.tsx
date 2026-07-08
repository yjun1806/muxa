import { useEffect, useRef, useState } from "react";
import { ChevronDown, ChevronUp, X } from "lucide-react";
import { ICON_SM } from "./icons";

interface Props {
  onChange: (q: string) => void;
  onNext: () => void;
  onPrev: () => void;
  onClose: () => void;
}

/** 패인 우상단 검색바 — 입력 즉시 검색, Enter/⇧Enter 다음/이전, Esc 닫기. */
export function SearchBar({ onChange, onNext, onPrev, onClose }: Props) {
  const [q, setQ] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") {
      e.preventDefault();
      if (e.shiftKey) onPrev();
      else onNext();
    } else if (e.key === "Escape") {
      e.preventDefault();
      onClose();
    }
  };

  return (
    <div className="search-bar" onMouseDown={(e) => e.stopPropagation()}>
      <input
        ref={inputRef}
        className="search-input"
        placeholder="검색…"
        value={q}
        onChange={(e) => {
          setQ(e.target.value);
          onChange(e.target.value);
        }}
        onKeyDown={onKeyDown}
      />
      <button className="tool-btn" title="이전 (⇧Enter)" aria-label="이전" onClick={onPrev}>
        <ChevronUp {...ICON_SM} />
      </button>
      <button className="tool-btn" title="다음 (Enter)" aria-label="다음" onClick={onNext}>
        <ChevronDown {...ICON_SM} />
      </button>
      <button className="tool-btn" title="닫기 (Esc)" aria-label="닫기" onClick={onClose}>
        <X {...ICON_SM} />
      </button>
    </div>
  );
}
