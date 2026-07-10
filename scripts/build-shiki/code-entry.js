// muxa 코드 뷰어 — Shiki fine-grained core + JavaScript RegExp 엔진(WASM 없음, 완전 오프라인).
// esbuild --bundle --format=iife --global-name=MuxaShiki 로 단일 파일 산출 → WKWebView가 <script src>로 로드.
import { createHighlighterCore } from 'shiki/core'
import { createJavaScriptRegexEngine } from 'shiki/engine/javascript'
import githubLight from '@shikijs/themes/github-light'
import githubDark from '@shikijs/themes/github-dark'

import swift from '@shikijs/langs/swift'
import typescript from '@shikijs/langs/typescript'
import tsx from '@shikijs/langs/tsx'
import javascript from '@shikijs/langs/javascript'
import jsx from '@shikijs/langs/jsx'
import rust from '@shikijs/langs/rust'
import python from '@shikijs/langs/python'
import go from '@shikijs/langs/go'
import json from '@shikijs/langs/json'
import yaml from '@shikijs/langs/yaml'
import toml from '@shikijs/langs/toml'
import bash from '@shikijs/langs/bash'
import html from '@shikijs/langs/html'
import xml from '@shikijs/langs/xml'
import css from '@shikijs/langs/css'
import scss from '@shikijs/langs/scss'
import c from '@shikijs/langs/c'
import cpp from '@shikijs/langs/cpp'
import objc from '@shikijs/langs/objective-c'
import java from '@shikijs/langs/java'
import kotlin from '@shikijs/langs/kotlin'
import ruby from '@shikijs/langs/ruby'
import php from '@shikijs/langs/php'
import sql from '@shikijs/langs/sql'
import lua from '@shikijs/langs/lua'
import dart from '@shikijs/langs/dart'
import markdown from '@shikijs/langs/markdown'

// 언어 id → 문법 객체. init은 0개로 즉시 뜨고, 파일 열 때 그 언어만 lazy 로드(굼뜸 해소).
const langMap = {
  swift, typescript, tsx, javascript, jsx, rust, python, go, json, yaml, toml,
  bash, html, xml, css, scss, c, cpp, objectivec: objc, java, kotlin, ruby, php, sql, lua, dart, markdown,
}

let hl = null
const loaded = new Set()

export async function init() {
  hl = await createHighlighterCore({
    themes: [githubLight, githubDark],
    langs: [], // lazy — 문법은 highlight 시 필요한 것만 로드
    engine: createJavaScriptRegexEngine(),
  })
  return true
}

/// 코드 → 라인별 토큰 [[content, color], ...]. 네이티브 NSTextView가 attributed로 그린다.
/// 언어 문법은 그때 lazy 로드, 미지원은 평문(text) 폴백.
export async function tokenize(code, lang, dark) {
  const theme = dark ? 'github-dark' : 'github-light'
  let key = lang && langMap[lang] ? lang : null
  if (key && !loaded.has(key)) {
    try {
      await hl.loadLanguage(langMap[key])
      loaded.add(key)
    } catch (e) {
      key = null
    }
  }
  try {
    const r = hl.codeToTokens(code, { lang: key || 'text', theme })
    return r.tokens.map((line) => line.map((t) => [t.content, t.color || '']))
  } catch (e) {
    return code.split('\n').map((l) => [[l, '']])
  }
}
