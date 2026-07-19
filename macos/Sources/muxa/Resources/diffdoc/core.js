/*
 * diffdoc/core.js — 문서 diff 계산. **DOM을 만지지 않는다.**
 *
 * 그래서 vanilla JavaScriptCore에서 그대로 돌고, `swift test`가 골든 픽스처로 검증한다
 * (WKWebView·비동기·플레이키 없음). muxa의 "순수 로직은 테스트로 못 박는다"를 JS까지 늘린 장치다.
 *
 * 계산은 markdown-it 토큰 트리 위에서 3층으로 한다:
 *   1층 블록 — 헤딩·문단·리스트항목·코드펜스·표행을 다중 패스로 매칭
 *   2층 어절 — modified 쌍의 텍스트를 Intl.Segmenter('ko')로 갈라 시퀀스 diff
 *   3층 문자 — 인접 삭제/삽입 어절이 닮았으면 문자 단위로 세분(한국어 조사·어미)
 *
 * **렌더된 HTML끼리 diff하지 않는다.** 그건 `<ins>`/`<del>`이 블록 경계를 못 넘는 명세 제약과
 * 태그 짝 깨짐에 정면으로 부딪힌다. 여기서는 블록 매칭이 **먼저** 일어나므로 모든 변경 조각이
 * 태생적으로 한 블록 안에 갇힌다 — 그게 이 설계의 핵심 불변식이다.
 *
 * 의존: markdown-it(렌더러와 **같은 파서** — 파서가 둘이면 좌표가 어긋나 유령 diff가 난다),
 *       diff-match-patch(문자 diff + cleanupSemantic).
 */
(function (global) {
  'use strict';

  // ── 노브: 실사용 후 조정 대상 ─────────────────────────────────────────────
  var OPTS = {
    // 블록 유사 매칭 임계값. 이 아래면 "닮은 블록"이 아니라 삭제+삽입이다.
    blockSimilarity: 0.5,
    // 어절 쌍을 문자 단위로 세분할 임계값. "문단을/문단이"=0.67 통과, "고양이/강아지"=0.00 탈락.
    wordSimilarity: 0.5,
    // 과분절 상한 — cleanup 후에도 변경 조각이 이만큼 많고 공통 조각이 잘면 통째 교체로 승격.
    maxFragments: 3,
    minCommonRun: 2,
    // 인접 변경 스팬 병합 거리(문자). "3글자 고쳤는데 하이라이트 다섯 조각"을 막는다.
    mergeDistance: 2,
    // 이동 판정 최소 길이 — 짧은 블록의 우연 일치를 배제한다.
    moveMinChars: 20,
    // **어절 단계 과분절 상한.** 한 문단에서 변경 조각이 이보다 많으면 삭제·삽입이 뒤엉켜
    // "단어 수프"가 된다(실제로 읽을 수 없는 화면이 나왔다). 그 경우 문단을 통째 교체로 보여준다.
    maxWordFragments: 8,
    // 변경 비율 상한 — 문단의 이만큼 넘게 바뀌었으면 "고친 것"이 아니라 "다시 쓴 것"이다.
    maxChangeRatio: 0.5,
    // **비율은 긴 문단에서만 본다.** 짧은 문장은 단어 하나만 바꿔도 비율이 쉽게 넘는데
    // ("안녕 🎉 반가워"→"반갑다"는 67%) 그건 전혀 안 읽히는 화면이 아니다.
    // 단어 수프는 긴 문단에 변경이 흩뿌려질 때만 생긴다.
    ratioMinChars: 80
  };

  function dmpInstance() {
    if (typeof diff_match_patch !== 'function') throw new Error('diff-match-patch 미로드');
    return new diff_match_patch();
  }

  // ── 유사도: 공통 문자 비율 ────────────────────────────────────────────────
  function similarity(a, b) {
    if (!a.length && !b.length) return 1;
    if (!a.length || !b.length) return 0;
    var dmp = dmpInstance();
    var d = dmp.diff_main(a, b);
    var common = 0;
    for (var i = 0; i < d.length; i++) if (d[i][0] === 0) common += d[i][1].length;
    return common / Math.max(a.length, b.length);
  }

  // ── 1층: 토큰 → 블록 단위 ─────────────────────────────────────────────────
  // 원자는 "사람이 한 덩어리로 읽는 것"이다: 리스트는 통짜가 아니라 **항목**, 표는 **행**.
  // 그래야 항목 하나 추가가 리스트 전체 교체로 보이지 않는다.
  var BLOCK_OPEN = {
    heading_open: 'heading', paragraph_open: 'paragraph', blockquote_open: 'blockquote',
    list_item_open: 'list_item'
  };
  // **표는 통째로 원자다(P0).** 행 하나(`| 하나 | 1 |`)는 헤더·구분선 없이는 유효한 표 문법이
  // 아니라, 행 단위로 잘라 다시 렌더하면 생 파이프 텍스트가 된다(실측으로 확인했다).
  // 행 정렬 → 셀 매칭은 소스 재조립이 필요해 별도 단계로 미룬다.
  var BLOCK_SELF = { fence: 'code', code_block: 'code', hr: 'hr', html_block: 'html' };

  /**
   * 토큰 시퀀스 → 블록 배열.
   * 각 블록: {type, text, norm, map, tokens, info}
   *  - text: 인라인 텍스트 프로젝션(마크업 기호가 없는 순수 텍스트)
   *  - norm: 매칭용 정규화(공백 collapse) — 소스 랩·마커 차이를 여기서 흡수한다
   */
  function toBlocks(md, src) {
    var tokens = md.parse(src || '', {});
    var blocks = [];
    var stack = [];
    // 리스트 소속 추적 — 항목마다 따로 렌더하면 `<ul>`이 항목 수만큼 쪼개지고,
    // 순서 리스트는 번호가 전부 1로 초기화된다("포맷이 깨지지 않아야 한다"는 요구의 핵심).
    var lists = [], listSeq = 0;
    var table = null;   // 표를 통째로 모으는 중이면 {tok, text}
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];

      // ── 표: 블록은 통짜지만 **셀 좌표는 기억한다** ──
      // 통짜로 두는 이유는 행 하나가 유효한 표 문법이 아니라서고(헤더·구분선이 없다),
      // 셀 좌표를 남기는 이유는 "어느 칸이 바뀌었나"를 칸 안에서 짚어주기 위해서다.
      if (t.type === 'table_open') { table = { tok: t, text: '', cells: [], row: -1, col: 0 }; continue; }
      if (t.type === 'table_close') {
        if (table) {
          var tb = mkBlock('table', table.text, table.tok.map, [table.tok], '',
                           lists[lists.length - 1]);
          tb.cells = table.cells;
          blocks.push(tb);
          table = null;
        }
        continue;
      }
      if (table) {
        if (t.type === 'tr_open') { table.row++; table.col = 0; }
        else if (t.type === 'inline') {
          table.text += t.content + ' ';
          table.cells.push({ row: table.row, col: table.col++, text: t.content });
        }
        continue;   // 표 안의 tr/td는 블록으로 세지 않는다
      }

      if (t.type === 'bullet_list_open' || t.type === 'ordered_list_open') {
        lists.push({ tag: t.type === 'ordered_list_open' ? 'ol' : 'ul', id: 'L' + (listSeq++) });
        continue;
      }
      if (t.type === 'bullet_list_close' || t.type === 'ordered_list_close') { lists.pop(); continue; }
      if (BLOCK_SELF[t.type]) {
        blocks.push(mkBlock(BLOCK_SELF[t.type], t.content || '', t.map, [t], t.info || '',
                            lists[lists.length - 1]));
        continue;
      }
      if (BLOCK_OPEN[t.type]) {
        // 열 때 현재 블록 수를 기억한다 — 닫을 때 "내 안에서 블록이 나왔나"를 이걸로 안다.
        stack.push({ kind: BLOCK_OPEN[t.type], tok: t, text: '', mark: blocks.length });
        continue;
      }
      if (t.type === 'inline' && stack.length) { stack[stack.length - 1].text += t.content; continue; }
      if (t.nesting === -1 && stack.length) {
        var open = stack[stack.length - 1];
        var closes = t.type.replace('_close', '_open');
        if (BLOCK_OPEN[closes] === open.kind) {
          stack.pop();
          // **잎 컨테이너만 원자로 삼는다.** 리스트 항목·인용은 안에 문단을 품는데, 바깥까지
          // 블록으로 뱉으면 같은 내용이 두 번 세어져 "항목 하나 추가"가 2개 삽입으로 보인다.
          var emittedChild = blocks.length > open.mark;
          if (!emittedChild && open.text.length) {
            blocks.push(mkBlock(open.kind, open.text, open.tok.map, [open.tok],
                                open.kind === 'heading' ? open.tok.tag : '',
                                lists[lists.length - 1]));
          }
        }
      }
    }
    return blocks;
  }

  function mkBlock(type, text, map, tokens, info, list) {
    return {
      type: type, text: text, info: info || '',
      // 같은 리스트에 속한 연속 항목은 페인트가 하나의 `<ul>`/`<ol>`로 묶는다.
      listTag: list ? list.tag : null, listId: list ? list.id : null,
      norm: normalize(text),
      line: map ? map[0] : 0,
      endLine: map ? map[1] : 0,
      tokens: tokens
    };
  }

  /** 매칭용 정규화 — 공백 접기. 프로젝션엔 마커·소프트랩이 애초에 없다. */
  function normalize(s) { return String(s).replace(/\s+/g, ' ').trim(); }

  /** 매칭 키 — 타입과 정규화 텍스트가 같으면 같은 블록으로 본다(동등성 술어). */
  // 구분자는 제어문자 — 공백이나 콜론을 쓰면 본문에 같은 글자가 있을 때 서로 다른 블록이
  // 같은 키를 갖는다. (소스 파일엔 이스케이프 표기로 둔다 — 생 제어문자를 박으면 grep 같은
  // 도구가 파일을 바이너리로 판단해 침묵한다. 실제로 한 번 당했다.)
  var SEP = String.fromCharCode(1);

  function key(b) { return b.type + SEP + b.info + SEP + b.norm; }

  // ── 1층: 다중 패스 매칭 ───────────────────────────────────────────────────
  // nbdime의 "기준을 점점 느슨하게" 구조. 엄격 일치부터 잡아야 느슨한 패스가 엉뚱한 짝을 안 만든다.
  function matchBlocks(olds, news, opts) {
    var pairs = [];                    // {o, n, kind}
    var usedO = new Array(olds.length), usedN = new Array(news.length);

    // Pass 1 — 정확 일치를 patience 방식으로. 양쪽에서 **유일한** 블록만 앵커로 삼아
    // `}`나 빈 문단처럼 흔한 것이 순서를 뒤엉키게 하는 걸 막는다.
    var countO = {}, countN = {};
    olds.forEach(function (b) { countO[key(b)] = (countO[key(b)] || 0) + 1; });
    news.forEach(function (b) { countN[key(b)] = (countN[key(b)] || 0) + 1; });
    var anchors = [];
    for (var i = 0; i < olds.length; i++) {
      var k = key(olds[i]);
      if (countO[k] !== 1 || countN[k] !== 1) continue;
      for (var j = 0; j < news.length; j++) {
        if (key(news[j]) === k) { anchors.push([i, j]); break; }
      }
    }
    // 앵커 중 순서가 증가하는 최장 부분열만 남긴다(교차 = 이동이므로 나중 패스로).
    var lis = longestIncreasing(anchors.map(function (a) { return a[1]; }));
    lis.forEach(function (idx) {
      var a = anchors[idx];
      usedO[a[0]] = usedN[a[1]] = true;
      pairs.push({ o: a[0], n: a[1], kind: 'same' });
    });

    // Pass 1b — 남은 정확 일치를 순서대로(중복 텍스트 블록들).
    for (var oi = 0; oi < olds.length; oi++) {
      if (usedO[oi]) continue;
      for (var ni = 0; ni < news.length; ni++) {
        if (usedN[ni] || key(news[ni]) !== key(olds[oi])) continue;
        usedO[oi] = usedN[ni] = true;
        pairs.push({ o: oi, n: ni, kind: 'same' });
        break;
      }
    }

    // Pass 2 — 유사 매칭. 같은 타입끼리, 앞뒤 순서를 보존하는 짝만.
    for (var oi2 = 0; oi2 < olds.length; oi2++) {
      if (usedO[oi2]) continue;
      var best = -1, bestScore = opts.blockSimilarity;
      for (var ni2 = 0; ni2 < news.length; ni2++) {
        if (usedN[ni2] || news[ni2].type !== olds[oi2].type) continue;
        if (!orderOK(pairs, oi2, ni2)) continue;
        var s = similarity(olds[oi2].norm, news[ni2].norm);
        if (s >= bestScore) { bestScore = s; best = ni2; }
      }
      if (best >= 0) {
        usedO[oi2] = usedN[best] = true;
        pairs.push({ o: oi2, n: best, kind: 'modified' });
      }
    }

    // Pass 3 — 이동. 내용은 같은데 자리가 다른 것(순서 보존 조건을 만족 못 해 남은 것들).
    for (var oi3 = 0; oi3 < olds.length; oi3++) {
      if (usedO[oi3] || olds[oi3].norm.length < opts.moveMinChars) continue;
      for (var ni3 = 0; ni3 < news.length; ni3++) {
        if (usedN[ni3] || key(news[ni3]) !== key(olds[oi3])) continue;
        usedO[oi3] = usedN[ni3] = true;
        pairs.push({ o: oi3, n: ni3, kind: 'moved' });
        break;
      }
    }

    pairs.sort(function (a, b) { return a.n - b.n; });
    return { pairs: pairs, usedO: usedO, usedN: usedN };
  }

  /** 이미 잡힌 짝들과 순서가 어긋나지 않는가(단조성 유지). */
  function orderOK(pairs, oi, ni) {
    for (var i = 0; i < pairs.length; i++) {
      var p = pairs[i];
      if (p.kind === 'moved') continue;
      if ((p.o < oi) !== (p.n < ni)) return false;
    }
    return true;
  }

  /** 최장 증가 부분열의 **인덱스** 목록. */
  function longestIncreasing(arr) {
    if (!arr.length) return [];
    var tails = [], prev = new Array(arr.length), idxs = [];
    for (var i = 0; i < arr.length; i++) {
      var lo = 0, hi = tails.length;
      while (lo < hi) { var mid = (lo + hi) >> 1; if (arr[tails[mid]] < arr[i]) lo = mid + 1; else hi = mid; }
      prev[i] = lo > 0 ? tails[lo - 1] : -1;
      if (lo === tails.length) tails.push(i); else tails[lo] = i;
    }
    var k = tails[tails.length - 1];
    while (k >= 0) { idxs.push(k); k = prev[k]; }
    return idxs.reverse();
  }

  // ── 2·3층: 텍스트 안의 변경 스팬 ──────────────────────────────────────────
  /**
   * 옛/새 텍스트 → 새 텍스트 기준 변경 스팬 + 삭제 조각.
   * 반환: { ins:[{start,end}], del:[{at, text}] }  (offset은 UTF-16, 새 텍스트 기준)
   */
  function textSpans(oldText, newText, opts) {
    var segs = segmentPairs(oldText, newText);
    var ins = [], del = [], pos = 0;

    for (var i = 0; i < segs.length; i++) {
      var s = segs[i];
      if (s.op === 0) { pos += s.text.length; continue; }
      if (s.op === 1) { ins.push({ start: pos, end: pos + s.text.length }); pos += s.text.length; continue; }
      // op === -1 (삭제): 새 텍스트엔 자리가 없다 — 위치만 기록한다.
      del.push({ at: pos, text: s.text });
    }

    // 3층 — 인접한 삭제/삽입 쌍이 **닮았으면** 문자 단위로 세분한다.
    // 한국어는 조사가 어절에 붙어("문단을"→"문단이") 어절 단위로만 보면 통째로 빨개진다.
    var refined = refineAdjacent(segs, opts);
    if (refined) { ins = refined.ins; del = refined.del; }

    var merged = mergeSpans(ins, opts.mergeDistance);

    // **과분절 방어(어절 단계).** 조각이 너무 많거나 문단 대부분이 바뀌었으면 인라인 강조를
    // 포기하고 통째 교체로 넘긴다 — 삭제·삽입이 단어마다 뒤엉킨 화면은 diff가 아니라 소음이다.
    var changedChars = merged.reduce(function (n, s) { return n + (s.end - s.start); }, 0)
                     + del.reduce(function (n, d) { return n + d.text.length; }, 0);
    var total = Math.max(1, newText.length);
    var ratioApplies = total >= opts.ratioMinChars;
    if (merged.length + del.length > opts.maxWordFragments ||
        (ratioApplies && changedChars / total > opts.maxChangeRatio)) {
      return { ins: merged, del: del, tooFragmented: true };
    }
    return { ins: merged, del: del };
  }

  /** 어절 단위 diff — `Intl.Segmenter('ko')`로 자른 뒤 그 시퀀스를 비교한다. */
  function segmentPairs(a, b) {
    var A = segmentsOf(a), B = segmentsOf(b);
    // 어절을 유니코드 사문자로 압축해 dmp의 문자 diff를 시퀀스 diff로 쓴다(dmp linesToChars 트릭).
    var map = {}, list = [];
    function enc(arr) {
      var out = '';
      for (var i = 0; i < arr.length; i++) {
        var w = arr[i];
        if (!(w in map)) { map[w] = list.length; list.push(w); }
        out += String.fromCharCode(map[w] + 0xE000); // 사용자 영역 — 본문과 충돌 없음
      }
      return out;
    }
    var dmp = dmpInstance();
    var d = dmp.diff_main(enc(A), enc(B), false);
    var out = [];
    for (var i = 0; i < d.length; i++) {
      var text = '';
      for (var j = 0; j < d[i][1].length; j++) text += list[d[i][1].charCodeAt(j) - 0xE000];
      if (text.length) out.push({ op: d[i][0], text: text });
    }
    return out;
  }

  function segmentsOf(s) {
    if (typeof Intl !== 'undefined' && Intl.Segmenter) {
      var seg = new Intl.Segmenter('ko', { granularity: 'word' });
      var out = [];
      var it = seg.segment(String(s));
      for (var x of it) out.push(x.segment);
      return out;
    }
    // 폴백 — 공백 보존 분할.
    return String(s).split(/(\s+)/).filter(function (t) { return t.length; });
  }

  /**
   * 인접 삭제/삽입 쌍의 문자 단위 세분(3층).
   * 발동 조건과 과분절 상한이 여기 다 있다 — 조각조각난 하이라이트는 안 읽히느니만 못하다.
   */
  function refineAdjacent(segs, opts) {
    var changed = false;
    var ins = [], del = [], pos = 0;

    for (var i = 0; i < segs.length; i++) {
      var s = segs[i], next = segs[i + 1];
      // 삭제 바로 뒤 삽입이 오는 "교체" 구간만 후보다.
      if (s.op === -1 && next && next.op === 1) {
        var a = s.text, b = next.text;
        if (a.length >= 2 && b.length >= 2 && similarity(a, b) >= opts.wordSimilarity) {
          var fine = charDiff(a, b, opts);
          if (fine) {
            changed = true;
            for (var k = 0; k < fine.length; k++) {
              var f = fine[k];
              if (f.op === 0) { pos += f.text.length; }
              else if (f.op === 1) { ins.push({ start: pos, end: pos + f.text.length }); pos += f.text.length; }
              else { del.push({ at: pos, text: f.text }); }
            }
            i++; // 짝지은 삽입 세그먼트를 소비했다
            continue;
          }
        }
      }
      if (s.op === 0) pos += s.text.length;
      else if (s.op === 1) { ins.push({ start: pos, end: pos + s.text.length }); pos += s.text.length; }
      else del.push({ at: pos, text: s.text });
    }
    return changed ? { ins: ins, del: del } : null;
  }

  /** 문자 diff + cleanupSemantic + 과분절 상한. 너무 잘게 쪼개지면 null(통째 교체로 남긴다). */
  function charDiff(a, b, opts) {
    var dmp = dmpInstance();
    var d = dmp.diff_main(a, b);
    dmp.diff_cleanupSemantic(d);
    var frags = 0, commonRuns = [];
    for (var i = 0; i < d.length; i++) {
      if (d[i][0] === 0) commonRuns.push(d[i][1].length); else frags++;
    }
    if (frags > opts.maxFragments) return null;
    if (commonRuns.length) {
      var avg = commonRuns.reduce(function (x, y) { return x + y; }, 0) / commonRuns.length;
      if (avg < opts.minCommonRun) return null; // 공통 조각이 잘면 읽히지 않는다
    }
    return d.map(function (x) { return { op: x[0], text: x[1] }; });
  }

  /** 가까운 스팬 병합 — 하이라이트가 조각조각 나는 걸 막는다. */
  function mergeSpans(spans, distance) {
    if (spans.length < 2) return spans;
    var sorted = spans.slice().sort(function (x, y) { return x.start - y.start; });
    var out = [sorted[0]];
    for (var i = 1; i < sorted.length; i++) {
      var last = out[out.length - 1];
      if (sorted[i].start - last.end <= distance) last.end = Math.max(last.end, sorted[i].end);
      else out.push(sorted[i]);
    }
    return out;
  }

  /**
   * 코드블록 내부 — **줄 단위** diff. 코드에 어절 하이라이트를 치면 안 읽히므로 줄로 간다.
   * 반환 스팬의 오프셋은 새 코드 텍스트 기준이고, 렌더된 `<code>`의 textContent와 일치한다.
   */
  function codeLineSpans(oldCode, newCode) {
    var oldLines = String(oldCode).split('\n'), newLines = String(newCode).split('\n');
    // 줄을 사문자로 압축해 dmp의 문자 diff를 줄 diff로 쓴다(dmp linesToChars와 같은 트릭).
    var map = {}, list = [];
    function enc(arr) {
      var out = '';
      for (var i = 0; i < arr.length; i++) {
        var l = arr[i];
        if (!(l in map)) { map[l] = list.length; list.push(l); }
        out += String.fromCharCode(map[l] + 0xE000);
      }
      return out;
    }
    var dmp = dmpInstance();
    var d = dmp.diff_main(enc(oldLines), enc(newLines), false);
    var ins = [], del = [], pos = 0;
    for (var i = 0; i < d.length; i++) {
      var op = d[i][0], n = d[i][1].length;
      var text = '';
      for (var j = 0; j < n; j++) text += list[d[i][1].charCodeAt(j) - 0xE000] + '\n';
      if (op === 0) { pos += text.length; }
      else if (op === 1) { ins.push({ start: pos, end: pos + text.length }); pos += text.length; }
      else { del.push({ at: pos, text: text }); }
    }
    return { ins: ins, del: del };
  }

  /**
   * 표 내부 — **칸 단위** 매칭 후 칸 안에서 어절 diff.
   * 표 구조(행·열 추가)는 diff하지 않는다 — 좌표가 어긋나면 통짜 변경으로 물러선다.
   */
  function tableCellSpans(oldCells, newCells, opts) {
    if (!oldCells || !newCells) return null;
    var byKey = {};
    oldCells.forEach(function (c) { byKey[c.row + ',' + c.col] = c.text; });
    var out = [];
    for (var i = 0; i < newCells.length; i++) {
      var c = newCells[i];
      var prev = byKey[c.row + ',' + c.col];
      if (prev === undefined) return null;      // 구조가 바뀌었다 — 칸 매칭을 포기한다
      if (prev === c.text) continue;
      var spans = textSpans(prev, c.text, opts);
      if (spans.tooFragmented) { spans = { ins: [{ start: 0, end: c.text.length }], del: [] }; }
      out.push({ row: c.row, col: c.col, ins: spans.ins, del: spans.del });
    }
    return out;
  }

  // ── 진입점 ────────────────────────────────────────────────────────────────
  /**
   * 문서 diff 모델. 렌더는 shell이 하고, 여기서는 **무엇이 어디서 바뀌었나**만 낸다.
   *
   * 반환 blocks[]는 **새 문서 기준 순서**이고, 삭제 블록은 있던 자리에 끼워 넣는다
   * (그래야 "여기서 뭐가 없어졌다"를 그 자리에서 말할 수 있다).
   */
  function computeDocDiff(oldSrc, newSrc, options) {
    var opts = {};
    for (var k in OPTS) opts[k] = OPTS[k];
    if (options) for (var k2 in options) opts[k2] = options[k2];

    var md = global.__diffdocMarkdownIt;
    if (!md) throw new Error('markdown-it 인스턴스 미설정');

    var olds = toBlocks(md, oldSrc), news = toBlocks(md, newSrc);
    var m = matchBlocks(olds, news, opts);

    var byNew = {};
    m.pairs.forEach(function (p) { byNew[p.n] = p; });

    var out = [], stats = { inserted: 0, deleted: 0, modified: 0, moved: 0 };

    // 삭제 블록을 "옛 순서상 그다음 블록이 새 문서에서 어디였나"에 매달아 끼워 넣는다.
    var pendingDel = {};
    for (var oi = 0; oi < olds.length; oi++) {
      if (m.usedO[oi]) continue;
      var anchor = news.length; // 기본은 문서 끝
      for (var p = 0; p < m.pairs.length; p++) {
        if (m.pairs[p].o > oi) { anchor = Math.min(anchor, m.pairs[p].n); }
      }
      (pendingDel[anchor] = pendingDel[anchor] || []).push(olds[oi]);
    }

    function flushDel(at) {
      (pendingDel[at] || []).forEach(function (b) {
        out.push({ kind: 'deleted', type: b.type, info: b.info, text: b.text,
                   listTag: b.listTag, listId: b.listId,
                   line: b.line, source: sliceSource(oldSrc, b) });
        stats.deleted++;
      });
    }

    for (var ni = 0; ni < news.length; ni++) {
      flushDel(ni);
      var b = news[ni], pair = byNew[ni];
      if (!pair) {
        out.push({ kind: 'inserted', type: b.type, info: b.info, text: b.text,
                   listTag: b.listTag, listId: b.listId,
                   line: b.line, source: sliceSource(newSrc, b) });
        stats.inserted++;
        continue;
      }
      if (pair.kind === 'same') {
        out.push({ kind: 'same', type: b.type, info: b.info, text: b.text,
                   listTag: b.listTag, listId: b.listId,
                   line: b.line, source: sliceSource(newSrc, b) });
        continue;
      }
      if (pair.kind === 'moved') {
        out.push({ kind: 'moved', type: b.type, info: b.info, text: b.text,
                   listTag: b.listTag, listId: b.listId,
                   line: b.line, fromLine: olds[pair.o].line, source: sliceSource(newSrc, b) });
        stats.moved++;
        continue;
      }
      // modified — 2·3층으로 내려가 스팬을 뽑는다. 코드블록은 어절 diff 대상이 아니다.
      // 코드·표는 어절 스팬을 쓰지 않는다 — 대신 각자의 내부 단위로 짚는다.
      // 코드는 **줄**, 표는 **칸**. 어절 오프셋을 그대로 쓰면 셀 경계를 넘어 엉뚱한 칸이 칠해진다.
      var spans;
      if (b.type === 'code') {
        spans = codeLineSpans(olds[pair.o].text, b.text);
        spans.codeLines = true;
      } else if (b.type === 'table') {
        var cells = tableCellSpans(olds[pair.o].cells, b.cells, opts);
        // 칸 매칭이 안 되면(행·열 구조 변경) 통짜 변경으로 물러선다 — 지어내지 않는다.
        spans = cells ? { ins: [], del: [], cells: cells } : { ins: [], del: [], wholeCode: true };
      } else {
        spans = textSpans(olds[pair.o].text, b.text, opts);
      }
      // 너무 잘게 쪼개졌으면 **옛 블록 통째 삭제 + 새 블록 통째 삽입**으로 보여준다.
      // 어느 단어가 바뀌었는지 못 읽는 화면보다, 두 판을 나란히 보는 쪽이 정직하다.
      if (spans.tooFragmented) {
        out.push({ kind: 'deleted', type: b.type, info: b.info, text: olds[pair.o].text,
                   listTag: b.listTag, listId: b.listId,
                   line: olds[pair.o].line, source: sliceSource(oldSrc, olds[pair.o]) });
        out.push({ kind: 'inserted', type: b.type, info: b.info, text: b.text,
                   listTag: b.listTag, listId: b.listId,
                   line: b.line, source: sliceSource(newSrc, b) });
        stats.deleted++; stats.inserted++;
        continue;
      }
      out.push({ kind: 'modified', type: b.type, info: b.info, text: b.text, line: b.line,
                 listTag: b.listTag, listId: b.listId,
                 oldText: olds[pair.o].text, source: sliceSource(newSrc, b),
                 oldSource: sliceSource(oldSrc, olds[pair.o]),
                 ins: spans.ins, del: spans.del, wholeCode: !!spans.wholeCode,
                 codeLines: !!spans.codeLines, cells: spans.cells || null });
      stats.modified++;
    }
    flushDel(news.length);

    return { blocks: out, stats: stats };
  }

  /** 블록의 원본 마크다운 조각 — shell이 이걸 다시 렌더한다(우리 파서가 만든 좌표라 안전하다). */
  function sliceSource(src, b) {
    var lines = String(src).split('\n');
    return lines.slice(b.line, b.endLine || b.line + 1).join('\n');
  }

  global.DiffDocCore = {
    computeDocDiff: computeDocDiff,
    // 테스트가 들여다보는 내부들 — 골든 픽스처가 층별로 검증한다.
    _toBlocks: toBlocks, _textSpans: textSpans, _similarity: similarity,
    _segmentsOf: segmentsOf, _matchBlocks: matchBlocks, _OPTS: OPTS
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
