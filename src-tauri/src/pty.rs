// 멀티 PTY 레지스트리 (M1 분할 트리 백엔드).
// 상태의 진실은 Rust가 소유한다 — paneId로 키잉된 PTY 세션들을 보관하고,
// 각 세션의 출력을 패인별 이벤트로 흘려보낸다. 프론트의 각 패인은 자기 이벤트만 구독한다.
// 16ms 배칭·세션 영속은 이후 슬라이스에서 확장한다.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::Mutex;
use std::thread;

use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};
use tauri::{AppHandle, Emitter, State};

pub struct PtySession {
    master: Box<dyn MasterPty + Send>,
    writer: Box<dyn Write + Send>,
    child: Box<dyn Child + Send + Sync>,
}

/// paneId → 세션. 패인 하나당 PTY 하나.
#[derive(Default)]
pub struct PtyState(pub Mutex<HashMap<String, PtySession>>);

fn pty_size(cols: u16, rows: u16) -> PtySize {
    PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    }
}

/// 로그인 셸을 PTY로 띄우고 출력 리더 스레드를 시작한다.
/// 같은 paneId가 이미 있으면 교체한다(이전 세션 drop → PTY 닫힘).
#[tauri::command]
pub fn pty_spawn(
    app: AppHandle,
    state: State<'_, PtyState>,
    pane_id: String,
    cwd: Option<String>,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(pty_size(cols, rows))
        .map_err(|e| e.to_string())?;

    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_string());
    let mut cmd = CommandBuilder::new(shell);
    cmd.arg("-l");
    // 워크스페이스 경로를 셸 cwd로. 없거나 유효하지 않으면 앱의 현재 디렉터리로 폴백
    let dir = cwd
        .map(std::path::PathBuf::from)
        .filter(|p| p.is_dir())
        .or_else(|| std::env::current_dir().ok());
    if let Some(dir) = dir {
        cmd.cwd(dir);
    }

    let child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    // spawn 이후 slave를 닫아야 셸 종료 시 리더가 EOF를 받는다
    drop(pair.slave);

    let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
    let writer = pair.master.take_writer().map_err(|e| e.to_string())?;

    // 패인별 이벤트 이름 — 각 패인이 자기 것만 구독하므로 프론트에서 필터가 불필요
    let out_event = format!("pty://output:{pane_id}");
    let exit_event = format!("pty://exit:{pane_id}");

    // 출력 리더 스레드: PTY 바이트를 그대로 이벤트로 푸시.
    // 바이트로 보내 xterm이 UTF-8 경계를 안전하게 디코딩한다.
    // TODO(설계 §3 IPC 배칭): 다중 세션 부하 시 ~16ms 코얼레싱 도입.
    thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => {
                    let _ = app.emit(&exit_event, ());
                    break;
                }
                Ok(n) => {
                    let _ = app.emit(&out_event, buf[..n].to_vec());
                }
                Err(_) => break,
            }
        }
    });

    state.0.lock().unwrap().insert(
        pane_id,
        PtySession {
            master: pair.master,
            writer,
            child,
        },
    );
    Ok(())
}

/// 키 입력을 해당 패인의 PTY에 쓴다.
#[tauri::command]
pub fn pty_write(state: State<'_, PtyState>, pane_id: String, data: String) -> Result<(), String> {
    let mut map = state.0.lock().unwrap();
    let session = map.get_mut(&pane_id).ok_or("해당 패인 PTY 없음")?;
    session
        .writer
        .write_all(data.as_bytes())
        .map_err(|e| e.to_string())?;
    session.writer.flush().map_err(|e| e.to_string())?;
    Ok(())
}

/// 패인 크기 변경을 PTY에 반영한다 (SIGWINCH).
#[tauri::command]
pub fn pty_resize(
    state: State<'_, PtyState>,
    pane_id: String,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let map = state.0.lock().unwrap();
    let session = map.get(&pane_id).ok_or("해당 패인 PTY 없음")?;
    session
        .master
        .resize(pty_size(cols, rows))
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// 패인을 닫는다 — 셸을 kill하고 세션을 제거한다.
#[tauri::command]
pub fn pty_kill(state: State<'_, PtyState>, pane_id: String) -> Result<(), String> {
    if let Some(mut session) = state.0.lock().unwrap().remove(&pane_id) {
        let _ = session.child.kill();
    }
    Ok(())
}
