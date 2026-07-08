// 단일 PTY 세션 (M1 첫 조각).
// 설계상 상태의 진실은 Rust가 소유한다 — 여기서는 PTY 하나를 열고,
// 출력 바이트를 이벤트로 프론트에 흘려보내고, 입력·리사이즈를 받는다.
// 다중 세션·분할 트리·16ms 배칭은 이후 슬라이스에서 확장한다.

use std::io::{Read, Write};
use std::sync::Mutex;
use std::thread;

use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize};
use tauri::{AppHandle, Emitter, State};

pub struct PtySession {
    master: Box<dyn MasterPty + Send>,
    writer: Box<dyn Write + Send>,
    // 셸 프로세스 핸들을 세션과 함께 살려둔다 (세션 교체·앱 종료 시 정리)
    _child: Box<dyn Child + Send + Sync>,
}

#[derive(Default)]
pub struct PtyState(pub Mutex<Option<PtySession>>);

fn pty_size(cols: u16, rows: u16) -> PtySize {
    PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    }
}

/// 로그인 셸을 PTY로 띄우고, 출력 리더 스레드를 시작한다.
/// 이미 세션이 있으면 교체한다(이전 세션은 drop되며 PTY가 닫힌다).
#[tauri::command]
pub fn pty_spawn(
    app: AppHandle,
    state: State<'_, PtyState>,
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
    if let Ok(cwd) = std::env::current_dir() {
        cmd.cwd(cwd);
    }

    let child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    // spawn 이후 slave 핸들을 닫아야 셸 종료 시 리더가 EOF를 받는다
    drop(pair.slave);

    let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
    let writer = pair.master.take_writer().map_err(|e| e.to_string())?;

    // 출력 리더 스레드: PTY 바이트를 읽어 그대로 이벤트로 푸시한다.
    // UTF-8 멀티바이트가 read 경계에서 쪼개질 수 있으므로 문자열이 아닌 바이트로 보내고,
    // 프론트의 xterm이 Uint8Array로 받아 디코딩을 처리한다.
    // TODO(설계 §3 IPC 배칭): 다중 세션 부하에서 ~16ms 코얼레싱 도입. 단일 세션엔 read별 emit으로 충분.
    thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => {
                    let _ = app.emit("pty://exit", ());
                    break;
                }
                Ok(n) => {
                    let _ = app.emit("pty://output", buf[..n].to_vec());
                }
                Err(_) => break,
            }
        }
    });

    *state.0.lock().unwrap() = Some(PtySession {
        master: pair.master,
        writer,
        _child: child,
    });
    Ok(())
}

/// 키 입력을 PTY에 쓴다 (xterm onData 문자열).
#[tauri::command]
pub fn pty_write(state: State<'_, PtyState>, data: String) -> Result<(), String> {
    let mut guard = state.0.lock().unwrap();
    let session = guard.as_mut().ok_or("PTY가 아직 생성되지 않음")?;
    session
        .writer
        .write_all(data.as_bytes())
        .map_err(|e| e.to_string())?;
    session.writer.flush().map_err(|e| e.to_string())?;
    Ok(())
}

/// 창·패인 크기 변경을 PTY에 반영한다 (SIGWINCH).
#[tauri::command]
pub fn pty_resize(state: State<'_, PtyState>, cols: u16, rows: u16) -> Result<(), String> {
    let guard = state.0.lock().unwrap();
    let session = guard.as_ref().ok_or("PTY가 아직 생성되지 않음")?;
    session
        .master
        .resize(pty_size(cols, rows))
        .map_err(|e| e.to_string())?;
    Ok(())
}
