// 앱 레벨 시스템 조회 커맨드.

/// 앱 프로세스의 현재 작업 디렉터리. 초기 워크스페이스 경로·이름에 사용.
#[tauri::command]
pub fn current_dir() -> Option<String> {
    std::env::current_dir()
        .ok()
        .map(|p| p.to_string_lossy().into_owned())
}
