/*
 * diffdoc/paint.js — 모델을 화면에 그린다. **DOM 전담**(계산은 core.js).
 *
 * 두 채널을 쓴다:
 *   ① CSS Custom Highlight API — 삽입·수정 배경 틴트. DOM을 안 건드리고 Range만 칠하므로
 *      태그 경계를 넘는 변경(`**굵게** 중간부터`)도 그냥 된다.
 *   ② DOM — 삭제 텍스트·블록 레일·이동 마커·접힌 칩. Highlight API가 못 하는 둘이 정확히
 *      이것이다: 없는 텍스트는 못 칠하고, 레이아웃 속성은 금지다.
 *
 * **실측 주의** — WKWebView는 `::highlight()`에서 `background-color`·`color`만 그린다.
 * 스펙이 허용하는 `text-decoration`·`outline`·`text-shadow`는 페인트되지 않는다.
 * 그래서 취소선 같은 "모양"은 전부 ①이 아니라 ②로 간다.
 */
(function (global) {
  'use strict';

  var md = null;
  var state = { model: null, density: 'full' };

  function ensureMd() {
    if (md) return md;
    md = markdownit({ html: true, linkify: true, typographer: false,
      highlight: function (str, lang) {
        if (lang && global.hljs && hljs.getLanguage(lang)) {
          try { return hljs.highlight(str, { language: lang }).value; } catch (e) {}
        }
        return '';
      }
    });
    global.__diffdocMarkdownIt = md; // core와 **같은 인스턴스** — 좌표계가 하나여야 한다
    return md;
  }

  /** 블록 하나를 렌더해 요소로. 원본 마크다운 조각을 우리 파서로 다시 그린다. */
  function renderBlock(source) {
    var wrap = document.createElement('div');
    wrap.innerHTML = ensureMd().render(source || '');
    // 한 겹 벗겨 문단·헤딩이 바로 앉게 한다(div 중첩이 조판을 흔든다).
    if (wrap.children.length === 1) return wrap.firstElementChild;
    var frag = document.createElement('div');
    while (wrap.firstChild) frag.appendChild(wrap.firstChild);
    return frag;
  }

  /** 텍스트 노드 인덱스 — 오프셋을 {node, offset}으로 되돌리기 위한 역인덱스. */
  function textIndex(root) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    var idx = [], total = 0, n;
    while ((n = walker.nextNode())) {
      idx.push({ node: n, at: total, len: n.data.length });
      total += n.data.length;
    }
    return { idx: idx, total: total };
  }

  /** 전역 오프셋 → {node, offset}. 못 찾으면 null. */
  function locate(ti, offset) {
    for (var i = 0; i < ti.idx.length; i++) {
      var e = ti.idx[i];
      if (offset <= e.at + e.len) return { node: e.node, offset: Math.max(0, offset - e.at) };
    }
    var last = ti.idx[ti.idx.length - 1];
    return last ? { node: last.node, offset: last.len } : null;
  }

  var hlSupported = (typeof CSS !== 'undefined' && CSS.highlights);

  /** 삽입·수정 스팬을 칠한다. Highlight API가 있으면 Range로, 없으면 span 삽입으로 강등. */
  function paintSpans(el, spans, kind, registry) {
    if (!spans || !spans.length) return;
    var ti = textIndex(el);
    if (!ti.idx.length) return;

    if (hlSupported) {
      for (var i = 0; i < spans.length; i++) {
        var a = locate(ti, spans[i].start), b = locate(ti, spans[i].end);
        if (!a || !b) continue;
        try {
          registry[kind].push(new StaticRange({
            startContainer: a.node, startOffset: a.offset,
            endContainer: b.node, endOffset: b.offset
          }));
        } catch (e) { /* 경계가 어긋나면 그 스팬만 건너뛴다 — 화면 전체를 죽이지 않는다 */ }
      }
      return;
    }

    // 폴백: 뒤에서 앞으로 감싼다(앞부터 하면 이후 오프셋이 무효화된다).
    var cls = kind === 'd-ins' ? 'd-insfallback' : 'd-modfallback';
    for (var j = spans.length - 1; j >= 0; j--) {
      var s = locate(ti, spans[j].start), e2 = locate(ti, spans[j].end);
      if (!s || !e2 || s.node !== e2.node) continue; // 노드를 걸치면 폴백에선 포기(정직한 누락)
      try {
        var r = document.createRange();
        r.setStart(s.node, s.offset); r.setEnd(e2.node, e2.offset);
        var sp = document.createElement('span'); sp.className = cls;
        r.surroundContents(sp);
      } catch (e) {}
    }
  }

  /** 삭제 조각을 본문 흐름 안에 되살린다(짧은 것만 — 길면 블록 칩으로). */
  function insertDeletions(el, dels) {
    if (!dels || !dels.length) return;
    var ti = textIndex(el);
    // 뒤에서 앞으로 — 앞부터 넣으면 뒤 오프셋이 밀린다.
    for (var i = dels.length - 1; i >= 0; i--) {
      var d = dels[i];
      var at = locate(ti, d.at);
      if (!at) continue;
      var span = document.createElement('del');
      span.className = 'd-deltext';
      span.textContent = d.text;
      try {
        var node = at.node;
        var rest = node.splitText(Math.min(at.offset, node.data.length));
        node.parentNode.insertBefore(span, rest);
      } catch (e) {}
    }
  }

  /** 삭제된 블록 — 2개 이하면 그 자리에 펼쳐 두고, 그 이상이면 접힌 칩으로 묶는다. */
  function renderDeletedRun(run) {
    var chars = run.reduce(function (n, b) { return n + (b.text || '').length; }, 0);
    if (run.length <= 2) {
      return run.map(function (b) {
        var el = renderBlock(b.source || b.text);
        el.classList.add('d-blk', 'd-del', 'd-delblock');
        el.setAttribute('data-change', 'deleted');
        stampAnchor(el, b, 'del');
        return el;
      });
    }
    var chip = document.createElement('div');
    chip.className = 'd-delchip';
    chip.setAttribute('data-change', 'deleted');
    chip.textContent = '삭제된 블록 ' + run.length + '개 · ' + chars + '자';
    chip.addEventListener('click', function () {
      var frag = document.createDocumentFragment();
      run.forEach(function (b) {
        var el = renderBlock(b.source || b.text);
        el.classList.add('d-blk', 'd-del', 'd-delblock');
        stampAnchor(el, b, 'del');
        frag.appendChild(el);
      });
      chip.parentNode.replaceChild(frag, chip);
    });
    return [chip];
  }

  /** 코멘트 앵커 스탬프 — 기존 diff 뷰어와 **같은 키 공간**(file·side·line·text)을 쓴다. */
  function stampAnchor(el, block, side) {
    el.setAttribute('data-line', String((block.line || 0) + 1)); // core는 0-based
    el.setAttribute('data-text', (block.text || '').slice(0, 400));
    el.setAttribute('data-side', side || 'add');
  }

  /**
   * 모델을 그린다.
   * @param model  core.computeDocDiff 결과
   * @param density 'clean' | 'marks' | 'full'
   */
  function paint(model, density) {
    state.model = model; state.density = density || 'full';
    var doc = document.getElementById('doc');
    doc.innerHTML = '';
    document.body.className = 'density-' + state.density + (document.body.classList.contains('dark') ? ' dark' : '');

    var registry = { 'd-ins': [], 'd-mod': [] };
    var pendingDel = [];

    // 연속 리스트 항목을 하나의 `<ul>`/`<ol>`로 묶는다. 항목마다 따로 붙이면 리스트가
    // 항목 수만큼 쪼개지고, 순서 리스트는 **번호가 전부 1로 초기화된다**.
    var listEl = null, listKey = null;
    function container(b) {
      var k = b.listId;
      if (!k) { listEl = null; listKey = null; return doc; }
      if (k !== listKey) {
        listEl = document.createElement(b.listTag || 'ul');
        listKey = k;
        doc.appendChild(listEl);
      }
      return listEl;
    }

    /** 리스트 항목이면 렌더 결과에서 `<li>`만 꺼내 공용 리스트에 넣는다. */
    function place(b, el) {
      var host = container(b);
      if (host === doc) { doc.appendChild(el); return el; }
      var li = el.tagName === 'LI' ? el : el.querySelector('li');
      if (!li) { host.appendChild(el); return el; }
      // 원래 클래스·속성을 li로 옮긴다(레일·앵커가 항목에 붙어야 한다).
      li.className = el.className;
      ['data-line', 'data-text', 'data-side', 'data-change'].forEach(function (a) {
        if (el.hasAttribute(a)) li.setAttribute(a, el.getAttribute(a));
      });
      host.appendChild(li);
      return li;
    }

    /** 표의 바뀐 칸에 하이라이트를 건다. 행·열 좌표로 찾는다(헤더가 0행). */
    function paintCells(tableEl, cells, reg) {
      var rows = tableEl.tagName === 'TABLE' ? tableEl.rows : (tableEl.querySelector('table') || {}).rows;
      if (!rows) return;
      cells.forEach(function (c) {
        var tr = rows[c.row];
        if (!tr) return;
        var cell = tr.cells[c.col];
        if (!cell) return;
        cell.classList.add('d-cell');
        insertDeletions(cell, c.del);
        paintSpans(cell, c.ins, 'd-mod', reg);
      });
    }

    function flushDeletions() {
      if (!pendingDel.length) return;
      renderDeletedRun(pendingDel).forEach(function (el) { doc.appendChild(el); });
      pendingDel = [];
      listEl = null; listKey = null; // 삭제 묶음이 끼면 리스트가 끊긴다
    }

    (model.blocks || []).forEach(function (b) {
      if (b.kind === 'deleted') { pendingDel.push(b); return; }
      flushDeletions();

      var el = renderBlock(b.source || b.text);
      el.classList.add('d-blk');
      stampAnchor(el, b, 'add');

      if (b.kind === 'inserted') el.classList.add('d-ins');
      else if (b.kind === 'modified') el.classList.add('d-mod');
      else if (b.kind === 'moved') el.classList.add('d-mov');
      if (b.kind !== 'same') el.setAttribute('data-change', b.kind);

      // 리스트 항목이면 여기서 `<li>`로 바뀌어 공용 리스트에 들어간다 —
      // 이후 하이라이트·삭제 삽입은 **실제로 화면에 붙은 요소**에 걸어야 한다.
      var placed = place(b, el);

      if (b.kind === 'inserted') {
        // 통째 삽입이면 블록 전체를 칠한다.
        var ti = textIndex(placed);
        if (ti.total) paintSpans(placed, [{ start: 0, end: ti.total }], 'd-ins', registry);
      } else if (b.kind === 'modified') {
        if (b.codeLines) {
          // 코드블록 — **바뀐 줄만** 칠한다. `<code>`의 textContent가 소스와 같으므로
          // 같은 오프셋 기계(textIndex/locate)를 그대로 쓴다.
          var codeEl = placed.querySelector('code') || placed;
          insertDeletions(codeEl, b.del);
          paintSpans(codeEl, b.ins, 'd-mod', registry);
        } else if (b.cells) {
          // 표 — **바뀐 칸만** 칠한다. 칸 좌표로 찾아 그 안에서만 오프셋을 쓴다
          // (표 전체 텍스트 오프셋을 쓰면 셀 경계를 넘어 엉뚱한 칸이 칠해진다).
          paintCells(placed, b.cells, registry);
        } else if (b.wholeCode) {
          var badge = document.createElement('div');
          badge.className = 'd-atombadge';
          badge.textContent = b.type === 'table' ? '표 구조 변경됨' : '코드 변경됨';
          placed.insertBefore(badge, placed.firstChild);
        } else {
          insertDeletions(placed, b.del);
          paintSpans(placed, b.ins, 'd-mod', registry);
        }
      } else if (b.kind === 'moved') {
        var mark = document.createElement('span');
        mark.className = 'd-movemark';
        mark.textContent = '↕ 위치 변경';
        placed.appendChild(mark);
      }
    });
    flushDeletions();

    if (hlSupported) {
      CSS.highlights.clear();
      Object.keys(registry).forEach(function (k) {
        if (!registry[k].length) return;
        var h = new Highlight();
        registry[k].forEach(function (r) { h.add(r); });
        CSS.highlights.set(k, h);
      });
    }

    // **하이라이터를 여기서 다시 돌리지 않는다.** markdown-it의 `highlight` 옵션이 렌더 시점에
    // 이미 처리하고, 여기서 `hljs.highlightElement`를 또 부르면 `<code>`의 innerHTML을 통째로
    // 갈아엎어 방금 넣은 삭제 표시와 Highlight Range가 함께 날아간다(실측으로 확인했다).

    // 변경 위치 레일 — 밀도가 바뀔 때마다 다시 그린다(접힌 삭제가 펼쳐지면 높이가 변한다).
    if (global.MuxaMinimap) {
      try {
        MuxaMinimap.watch('[data-change]', function (el) {
          var k = el.getAttribute('data-change');
          return k === 'inserted' ? 'add' : k === 'deleted' ? 'del' : k === 'moved' ? 'mov' : 'mod';
        });
      } catch (e) {}
    }
    return { blocks: (model.blocks || []).length, highlight: !!hlSupported };
  }

  /** Swift 진입점 — base64로 받는다(문자열 이스케이핑 사고를 원천 차단). */
  function renderDocDiff(payload) {
    ensureMd();
    var dec = function (b64) { return decodeURIComponent(escape(atob(b64))); };
    var oldSrc = dec(payload.old64 || ''), newSrc = dec(payload.new64 || '');

    if (payload.theme) {
      var root = document.documentElement;
      Object.keys(payload.theme).forEach(function (k) { root.style.setProperty('--' + k, payload.theme[k]); });
    }
    document.body.classList.toggle('dark', !!payload.dark);
    var link = document.getElementById('hl-theme');
    if (link) link.href = payload.dark ? '../mdviewer/hl-dark.css' : '../mdviewer/hl-light.css';

    var t0 = Date.now();
    var model = DiffDocCore.computeDocDiff(oldSrc, newSrc);
    var res = paint(model, payload.density);
    return JSON.stringify({
      ok: true, ms: Date.now() - t0, stats: model.stats,
      blocks: res.blocks, highlight: res.highlight
    });
  }

  /** 밀도만 바꾼다 — 다시 계산하지 않는다(모델은 그대로). */
  function setDensity(density) {
    if (!state.model) return JSON.stringify({ ok: false });
    var res = paint(state.model, density);
    return JSON.stringify({ ok: true, blocks: res.blocks });
  }

  global.renderDocDiff = renderDocDiff;
  global.setDocDiffDensity = setDensity;
})(typeof globalThis !== 'undefined' ? globalThis : this);
