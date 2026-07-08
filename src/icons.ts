// 아이콘 테마 — 전 영역에서 동일한 lucide 팩 + 일관된 stroke를 쓴다.
// 크기만 문맥에 따라 두 단계(기본/슬림), strokeWidth는 항상 1.5로 통일.
export const ICON = { size: 16, strokeWidth: 1.5 } as const; // 사이드바·상단바
export const ICON_SM = { size: 14, strokeWidth: 1.5 } as const; // 패인 헤더(슬림)
