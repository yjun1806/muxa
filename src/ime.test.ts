import { describe, it, expect } from "vitest";
import { reduceIme, shouldRedirectToInput, type ImeEvent } from "./ime";

const DEL = "\x7f";

// WKWebView input 이벤트열을 순서대로 흘려 PTY 출력과 최종 조합 상태를 얻는다.
function run(events: ImeEvent[]): { out: string; composing: string } {
  let composing = "";
  let out = "";
  for (const e of events) {
    const r = reduceIme(composing, e);
    composing = r.composing;
    out += r.writes;
  }
  return { out, composing };
}

// 헬퍼: 이벤트 생성
const rep = (data: string, value: string): ImeEvent => ({
  inputType: "insertReplacementText",
  data,
  value,
});
const ins = (data: string, value: string): ImeEvent => ({ inputType: "insertText", data, value });
const del = (value: string): ImeEvent => ({
  inputType: "deleteContentBackward",
  data: null,
  value,
});
const enter = (): ImeEvent => ({ inputType: "insertLineBreak", data: null, value: "" });

describe("reduceIme — 한글 조합", () => {
  it("'안' 한 글자를 조합하면 지우고-다시쓰기로 에코된다", () => {
    // ㅇ → 아 → 안 (실측 시퀀스)
    const { out, composing } = run([ins("ㅇ", "ㅇ"), rep("아", "아"), rep("안", "안")]);
    expect(out).toBe("ㅇ" + DEL + "아" + DEL + "안");
    expect(composing).toBe("안");
  });

  it("'안녕' — 새 글자 시작(insertText 자모)은 이전 글자를 확정으로 남긴다", () => {
    const { out, composing } = run([
      ins("ㅇ", "ㅇ"),
      rep("아", "아"),
      rep("안", "안"),
      ins("ㄴ", "안ㄴ"), // 새 조합 시작: "안" 확정, "ㄴ" 에코
      rep("녀", "녀"),
      rep("녕", "녕"),
    ]);
    // "안"까지 에코 후, "ㄴ" 추가 → "녀" → "녕"
    expect(out).toBe("ㅇ" + DEL + "아" + DEL + "안" + "ㄴ" + DEL + "녀" + DEL + "녕");
    expect(composing).toBe("녕");
  });
});

describe("reduceIme — 확정 문자(조합 아님)", () => {
  it("영문은 그대로 전송하고 조합을 비운다", () => {
    const r = reduceIme("", ins("a", "a"));
    expect(r.writes).toBe("a");
    expect(r.composing).toBe("");
    expect(r.resetValue).toBe("");
  });

  it("스페이스도 그대로 한 번만 전송한다", () => {
    const r = reduceIme("안", ins(" ", "안 "));
    expect(r.writes).toBe(" ");
    expect(r.composing).toBe("");
  });

  it("한글 확정 뒤 영문 — 조합 글자는 확정으로 남고 영문이 이어진다", () => {
    const { out } = run([ins("ㅎ", "ㅎ"), rep("하", "하"), ins("a", "하a")]);
    // "하" 조합 후 'a' 확정. 'a'는 isJamo=false라 하를 지우지 않는다
    expect(out).toBe("ㅎ" + DEL + "하" + "a");
  });
});

describe("reduceIme — 삭제", () => {
  it("조합이 없으면 백스페이스는 셸로 위임(DEL 1개)", () => {
    const r = reduceIme("", del(""));
    expect(r.writes).toBe(DEL);
    expect(r.composing).toBe("");
    expect(r.resetValue).toBe(null); // value 건드리지 않음
  });

  it("조합 중 백스페이스는 조합을 되돌린다", () => {
    // "안"(composing) 상태에서 백스페이스 → "아"
    const r = reduceIme("안", del("아"));
    expect(r.writes).toBe(DEL + "아");
    expect(r.composing).toBe("아");
  });

  it("조합 중 백스페이스로 완전 취소되면 조합만 지운다", () => {
    const r = reduceIme("ㅇ", del(""));
    expect(r.writes).toBe(DEL);
    expect(r.composing).toBe("");
  });
});

describe("reduceIme — 엔터", () => {
  it("CR을 보내고 조합을 비운다", () => {
    const r = reduceIme("녕", enter());
    expect(r.writes).toBe("\r");
    expect(r.composing).toBe("");
    expect(r.resetValue).toBe("");
  });
});

describe("reduceIme — 통합 시나리오", () => {
  it("'안녕 하세요' 입력이 정확히 재현된다 (중복·유실 없음)", () => {
    const { out } = run([
      // 안
      ins("ㅇ", "ㅇ"),
      rep("아", "아"),
      rep("안", "안"),
      // 녕
      ins("ㄴ", "안ㄴ"),
      rep("녀", "녀"),
      rep("녕", "녕"),
      // 스페이스
      ins(" ", "녕 "),
      // 하
      ins("ㅎ", "ㅎ"),
      rep("하", "하"),
      // 세
      ins("ㅅ", "하ㅅ"),
      rep("세", "세"),
      // 요
      ins("ㅇ", "세ㅇ"),
      rep("요", "요"),
    ]);
    // 최종적으로 셸에 눈에 보이는 텍스트는 "안녕 하세요"여야 한다.
    // DEL로 지운 것을 반영해 실제 화면 상태를 계산해 검증한다.
    expect(applyToScreen(out)).toBe("안녕 하세요");
  });
});

describe("shouldRedirectToInput", () => {
  const k = (p: Partial<KeyboardEvent> & { keyCode?: number }): KeyboardEvent => p as KeyboardEvent;

  it("문자·스페이스·Enter·Backspace·IME는 input 경로", () => {
    expect(shouldRedirectToInput(k({ key: "a" }))).toBe(true);
    expect(shouldRedirectToInput(k({ key: " " }))).toBe(true);
    expect(shouldRedirectToInput(k({ key: "Enter" }))).toBe(true);
    expect(shouldRedirectToInput(k({ key: "Backspace" }))).toBe(true);
    expect(shouldRedirectToInput(k({ key: "ㅇ", keyCode: 229 }))).toBe(true);
  });

  it("제어키·modifier 조합은 xterm(onData) 경로", () => {
    expect(shouldRedirectToInput(k({ key: "ArrowUp" }))).toBe(false);
    expect(shouldRedirectToInput(k({ key: "Tab" }))).toBe(false);
    expect(shouldRedirectToInput(k({ key: "Escape" }))).toBe(false);
    expect(shouldRedirectToInput(k({ key: "c", ctrlKey: true }))).toBe(false);
    expect(shouldRedirectToInput(k({ key: "v", metaKey: true }))).toBe(false);
  });
});

// PTY로 나간 바이트열을 가상 화면에 적용해 "보이는 텍스트"를 계산한다(DEL=백스페이스).
function applyToScreen(bytes: string): string {
  const chars: string[] = [];
  for (const ch of bytes) {
    if (ch === DEL) chars.pop();
    else chars.push(ch);
  }
  return chars.join("");
}
