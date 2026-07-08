/**
 * WKWebView(Tauri wry) 한글 IME 입력 — 순수 상태기계.
 *
 * 문제: macOS WKWebView는 IME 조합 시 `compositionstart/end` DOM 이벤트를 안 준다
 * (WebKit #165004 계열). xterm 내장 처리는 `insertText`(자음)만 흘리고
 * `insertReplacementText`(모음 조합)를 무시해 "자음만 입력되는" 증상이 난다.
 *
 * 설계 원칙 — 셸 라인을 미러하지 않는다:
 *   터미널 입력 라인의 진짜 소유자는 셸(readline)이다. 커서 이동·히스토리·삭제는 셸이
 *   관리하며, 우리는 그 상태를 알 수 없다. 그래서 셸 라인 전체를 웹에서 흉내 내려 하면
 *   스페이스·백스페이스·화살표마다 어긋난다.
 *
 *   대신 "조합 중인 글자"만 붙든다. 조합 중 글자는 실시간 에코(지우고 다시 쓰기)로 셸에
 *   보여주고, 확정되거나 조합이 아닌 입력(영문·스페이스·백스페이스·엔터)은 바이트만 셸로
 *   흘려보내고 우리는 상태를 갖지 않는다. 유일한 상태는 `composing` 문자열 하나다.
 *
 * 부작용(PTY 쓰기·DOM)은 이 함수 밖(TerminalPane)에서만 일어난다.
 */

export interface ImeEvent {
  inputType: string;
  data: string | null;
  value: string; // 이벤트 직후 textarea.value
}

export interface ImeResult {
  writes: string; // PTY로 보낼 문자열 (DEL 포함)
  composing: string; // 다음 상태: 조합 중인 글자("" = 조합 없음)
  resetValue: string | null; // textarea.value로 설정할 값(null = 건드리지 않음)
}

const DEL = "\x7f"; // 터미널 백스페이스

/** 조합 상태와 input 이벤트로 PTY 전송 문자열·다음 상태를 계산한다. */
export function reduceIme(composing: string, e: ImeEvent): ImeResult {
  const data = e.data ?? "";
  switch (e.inputType) {
    case "insertReplacementText":
      // 마지막 조합 글자 갱신(ㅇ→아→안): 이전 조합을 지우고 새로 에코
      return { writes: erase(composing) + data, composing: data, resetValue: null };

    case "insertText":
      if (isJamo(data)) {
        // 새 조합 시작: 이전 글자는 확정으로 셸에 남기고, value를 새 자모만으로 정리
        return { writes: data, composing: data, resetValue: data };
      }
      // 확정 문자(영문·숫자·기호·스페이스): 그대로 전송, 조합 종료
      return { writes: data, composing: "", resetValue: "" };

    case "insertLineBreak":
      return { writes: "\r", composing: "", resetValue: "" };

    case "deleteContentBackward":
      if (composing) {
        // 조합 편집: 브라우저가 되돌린 결과(value 마지막 글자, 취소 시 "")로 재에코
        const g = lastChar(e.value);
        return { writes: erase(composing) + g, composing: g, resetValue: null };
      }
      // 조합이 없으면 확정 텍스트 삭제 → 셸에 위임(우리 상태 무관)
      return { writes: DEL, composing: "", resetValue: null };

    default:
      // insertFromPaste 등: 확정 취급
      return { writes: data, composing: "", resetValue: "" };
  }
}

/** 조합 중 글자(코드포인트 수)만큼 백스페이스 — 셸 화면에서 이전 에코를 지운다. */
function erase(composing: string): string {
  return DEL.repeat([...composing].length);
}

/** value의 마지막 코드포인트(조합 중 글자 1개). 비어 있으면 "". */
function lastChar(value: string): string {
  const chars = [...value];
  return chars.length ? chars[chars.length - 1] : "";
}

/** 한글 호환 자모(U+3130–U+318F). 새로 삽입되면 새 조합의 시작이다. */
function isJamo(ch: string): boolean {
  const code = ch.codePointAt(0) ?? 0;
  return code >= 0x3130 && code <= 0x318f;
}

/**
 * 이 keydown을 xterm에서 격리하고 브라우저 기본 `input` 이벤트로 처리할 것인가.
 * 문자·Enter·Backspace는 우리 input 경로가 담당하고, 제어키(화살표·Ctrl/⌘·Tab·Esc)는
 * xterm(onData)에 맡긴다. keyCode 229 = IME 조합 중 신호(WKWebView는 isComposing=false).
 */
export function shouldRedirectToInput(e: KeyboardEvent): boolean {
  if (e.isComposing || (e as { keyCode: number }).keyCode === 229) return true;
  if (e.key === "Enter" || e.key === "Backspace") return true;
  return e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey;
}
