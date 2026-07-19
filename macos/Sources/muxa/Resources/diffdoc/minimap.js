/*
 * minimap.js — 스크롤바 옆 **변경 위치 레일**. 세 diff 뷰어(통합·나란히·문서)가 공유한다.
 *
 * **왜 네이티브 스크롤바를 안 쓰나** — macOS 오버레이 스크롤바는 `::-webkit-scrollbar`·
 * `scrollbar-color` 스타일을 무시한다. 그래서 별도 레일 div를 띄운다.
 *
 * 스크롤 시작 전에 "얼마나·어디가 바뀌었나"를 알려주는 게 목적이다. 긴 문서에서 변경을 찾아
 * 스크롤을 헤매는 비용이 리뷰의 실제 부담이라, 규모를 먼저 보여주고 클릭으로 점프시킨다.
 */
(function (global) {
  'use strict';

  var RAIL_ID = 'muxa-minimap';

  function ensureRail() {
    var rail = document.getElementById(RAIL_ID);
    if (rail) return rail;
    rail = document.createElement('div');
    rail.id = RAIL_ID;
    document.body.appendChild(rail);
    return rail;
  }

  /**
   * 변경 위치 레일을 그린다.
   * @param selector 변경 요소 셀렉터(뷰어마다 다르다)
   * @param kindOf   요소 → 'add'|'del'|'mod'|'mov' 판정
   */
  function build(selector, kindOf) {
    var rail = ensureRail();
    rail.innerHTML = '';
    var nodes = Array.prototype.slice.call(document.querySelectorAll(selector));
    if (!nodes.length) { rail.style.display = 'none'; return 0; }
    rail.style.display = 'block';

    var docH = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight, 1);
    // 같은 픽셀 줄에 여러 변경이 겹치면 틱을 하나로 — 촘촘한 변경이 레일을 통째로 칠하는 걸 막는다.
    var seen = {};
    var count = 0;
    nodes.forEach(function (el) {
      var top = 0, n = el;
      while (n && n !== document.body) { top += n.offsetTop || 0; n = n.offsetParent; }
      var ratio = Math.min(1, Math.max(0, top / docH));
      var bucket = Math.round(ratio * 400); // 0.25% 해상도
      var kind = kindOf ? kindOf(el) : 'mod';
      var k = bucket + ':' + kind;
      if (seen[k]) return;
      seen[k] = true;
      count++;
      var tick = document.createElement('i');
      tick.className = 'mm-' + kind;
      tick.style.top = (ratio * 100).toFixed(3) + '%';
      tick.title = '변경 위치로 이동';
      tick.addEventListener('click', function (e) {
        e.stopPropagation();
        // `<details>` 안이면 먼저 펼친다 — 안 그러면 스크롤이 닿지 않는다.
        var d = el.closest ? el.closest('details') : null;
        if (d) d.open = true;
        el.scrollIntoView({
          behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth',
          block: 'center'
        });
      });
      rail.appendChild(tick);
    });
    return count;
  }

  /** 폰트·이미지 로딩 뒤 높이가 바뀌므로 다시 계산한다(안 그러면 틱이 어긋난다). */
  function watch(selector, kindOf) {
    var rebuild = function () { build(selector, kindOf); };
    rebuild();
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(rebuild);
    if (global.ResizeObserver) {
      var ro = new ResizeObserver(function () { rebuild(); });
      ro.observe(document.body);
    }
    global.addEventListener('resize', rebuild);
    return rebuild;
  }

  global.MuxaMinimap = { build: build, watch: watch };
})(typeof globalThis !== 'undefined' ? globalThis : this);
