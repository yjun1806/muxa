#!/usr/bin/env python3
"""Material Icon Theme(PKief, MIT) → muxa 파일 아이콘 슬림 번들 재생성.

VSCode의 그 컬러 파일 아이콘을 오프라인으로 쓰기 위해, npm 패키지에서
'참조되는 아이콘 SVG'만 추려 Resources/fileicons/에 넣고, 확장자·파일명·
폴더명 → 아이콘 매핑을 슬림 json으로 저장한다. (shiki 번들과 같은 재현 방식)

사용:
    python3 scripts/build-fileicons/build.py
전제: npm(패키지 pull), tar. zig·네이티브 빌드 불필요.
출력:
    macos/Sources/muxa/Resources/fileicons/*.svg        (참조 아이콘만)
    macos/Sources/muxa/Resources/fileicons/icons.json   (슬림 매핑)
"""
import json, os, shutil, subprocess, sys, tarfile, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "macos/Sources/muxa/Resources/fileicons"
PKG = "material-icon-theme"  # 버전 고정은 아래 VERSION


def main():
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        print(f"npm pack {PKG} …")
        # 최신 대신 재현성 위해 버전 고정
        version = "5.36.1"
        subprocess.run(["npm", "pack", f"{PKG}@{version}"], cwd=tmp, check=True)
        tgz = next(tmp.glob("*.tgz"))
        with tarfile.open(tgz) as t:
            t.extractall(tmp)
        root = tmp / "package"
        theme = json.load(open(root / "dist/material-icons.json"))
        icons_dir = root / "icons"
        have = {p.stem for p in icons_dir.glob("*.svg")}

        needed = {theme["file"], theme["folder"]}
        file_ext = {k: v for k, v in theme["fileExtensions"].items()}
        file_names = {k: v for k, v in theme["fileNames"].items()}
        # 폴더는 닫힌 아이콘만(open 변형 제외)
        folder_names = {k: v for k, v in theme["folderNames"].items() if not v.endswith("-open")}
        for m in (file_ext, file_names, folder_names):
            needed.update(m.values())
        needed &= have  # 실제 존재하는 svg만

        if OUT.exists():
            shutil.rmtree(OUT)
        OUT.mkdir(parents=True)
        for name in sorted(needed):
            shutil.copy(icons_dir / f"{name}.svg", OUT / f"{name}.svg")

        slim = {
            "file": theme["file"],
            "folder": theme["folder"],
            "fileExtensions": {k: v for k, v in file_ext.items() if v in needed},
            "fileNames": {k: v for k, v in file_names.items() if v in needed},
            "folderNames": {k: v for k, v in folder_names.items() if v in needed},
        }
        json.dump(slim, open(OUT / "icons.json", "w"), separators=(",", ":"), sort_keys=True)

        total = sum((OUT / f"{n}.svg").stat().st_size for n in needed)
        print(f"완료: {len(needed)} 아이콘, {total//1024}KB → {OUT.relative_to(REPO)}")


if __name__ == "__main__":
    sys.exit(main())
