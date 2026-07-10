# shiki 코드뷰어 번들 재생성

`macos/Sources/muxa/Resources/codeviewer/shiki.bundle.js`는 이 디렉토리의 `code-entry.js`를
esbuild로 IIFE 단일 파일로 번들한 산출물이다. shiki 버전을 올리거나 언어를 추가할 때 재생성한다.

```bash
cd /tmp && mkdir shiki-build && cd shiki-build
npm init -y && npm install shiki@4 esbuild
cp <repo>/scripts/build-shiki/code-entry.js .
npx esbuild code-entry.js --bundle --format=iife --global-name=MuxaShiki --minify \
  --outfile=<repo>/macos/Sources/muxa/Resources/codeviewer/shiki.bundle.js
```

방식: fine-grained core + JavaScript RegExp 엔진(wasm 없음) → file:// 오프라인 완전 지원.
정적 import한 언어만 번들에 포함. `tokenize(code, lang, dark)`가 라인별 토큰 반환(네이티브 표시).
