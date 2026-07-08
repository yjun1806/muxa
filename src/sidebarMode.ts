// 사이드바 표시 모드 — 상단바 메뉴에서 선택(GitBaro식 관리).
export type SidebarMode = "expanded" | "icon" | "slim" | "hover";

export const SIDEBAR_MODES: { mode: SidebarMode; label: string; hint: string }[] = [
  { mode: "expanded", label: "펼쳐두기", hint: "항상 전체" },
  { mode: "icon", label: "아이콘", hint: "아바타만" },
  { mode: "slim", label: "슬림", hint: "얇은 위치 바" },
  { mode: "hover", label: "호버 시 펼침", hint: "평소 아이콘, 올리면 전체" },
];
