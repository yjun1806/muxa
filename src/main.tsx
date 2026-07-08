import ReactDOM from "react-dom/client";
import App from "./App";
import "./index.css";

// StrictMode는 개발 모드에서 effect를 두 번(mount→unmount→mount) 실행한다.
// 터미널은 PTY·xterm 같은 싱글톤 네이티브 리소스를 잡으므로, 이중 실행은
// 셸이 두 번 뜨는 등의 부작용을 낳는다. 터미널 앱 관례대로 StrictMode를 쓰지 않는다.
ReactDOM.createRoot(document.getElementById("root")!).render(<App />);
