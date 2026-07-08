// 릴리스 빌드에서 콘솔 창을 띄우지 않는다 (Windows용이나 관례상 유지)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    muxa_lib::run()
}
