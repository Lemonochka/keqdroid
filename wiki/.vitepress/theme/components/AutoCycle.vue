<script setup lang="ts">
const x0 = 30
const x1 = 700
const span = 30
const tx = (t: number) => x0 + ((x1 - x0) * t) / span

type Seg = { from: number; to: number; text: string; cls: string; at?: number }
type Ev = { t: number; lines: string[]; up: boolean }

const scenes: { title: string; y: number; segs: Seg[]; evs: Ev[]; note?: { from: number; to: number; text: string } }[] = [
  {
    title: 'Сервер перестал отвечать',
    y: 0,
    segs: [
      { from: 0, to: 8, text: 'Финляндия', cls: 'a' },
      { from: 8, to: 23, text: 'Нидерланды', cls: 'b' },
      { from: 23, to: 30, text: 'Финляндия', cls: 'a' },
    ],
    evs: [
      { t: 8, lines: ['Финляндия молчит', '→ Нидерланды'], up: true },
      { t: 13, lines: ['проверка:', 'Финляндия молчит'], up: false },
      { t: 18, lines: ['Финляндия ответила,', '1 раз из 2'], up: true },
      { t: 23, lines: ['ответила снова', '→ обратно'], up: false },
    ],
  },
  {
    title: 'Пропала сеть',
    y: 200,
    segs: [{ from: 0, to: 30, text: 'Финляндия', cls: 'a', at: 23 }],
    note: { from: 6, to: 16, text: 'нет сети' },
    evs: [
      { t: 6, lines: ['молчат все, соседние', 'подписки тоже → остаёмся'], up: true },
      { t: 16, lines: ['сеть вернулась,', 'всё как было'], up: false },
    ],
  },
]

const laneY = 104
const laneH = 28
</script>

<template>
  <figure class="kq-figure">
    <svg viewBox="0 0 720 400" role="img" aria-label="Как Авто ведёт себя во времени: сервер упал и вернулся, пропала сеть">
      <defs>
        <pattern id="kq-hatch" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
          <rect width="8" height="8" class="hatch-bg" />
          <line x1="0" y1="0" x2="0" y2="8" class="hatch" />
        </pattern>
      </defs>

      <g v-for="s in scenes" :key="s.title" :transform="`translate(0, ${s.y})`">
        <text :x="x0" y="14" class="title">{{ s.title }}</text>

        <rect v-for="g in s.segs" :key="g.from" :x="tx(g.from) + 1" :y="laneY" :width="tx(g.to) - tx(g.from) - 2" :height="laneH" rx="4" :class="['seg', g.cls]" />
        <text v-for="g in s.segs" :key="'t' + g.from" :x="g.at !== undefined ? tx(g.at) : (tx(g.from) + tx(g.to)) / 2" :y="laneY + 19" text-anchor="middle" class="seg-t">{{ g.text }}</text>

        <template v-if="s.note">
          <rect :x="tx(s.note.from)" :y="laneY" :width="tx(s.note.to) - tx(s.note.from)" :height="laneH" fill="url(#kq-hatch)" />
          <text :x="(tx(s.note.from) + tx(s.note.to)) / 2" :y="laneY + 19" text-anchor="middle" class="note-t">{{ s.note.text }}</text>
          <text :x="(tx(s.note.from) + tx(s.note.to)) / 2" :y="laneY + laneH + 50" text-anchor="middle" class="small">проверки через 15 с, 30 с, 1 мин, 2 мин…</text>
        </template>

        <g v-for="e in s.evs" :key="e.t">
          <line :x1="tx(e.t)" :y1="e.up ? 58 : 92" :x2="tx(e.t)" :y2="laneY - 2" class="tick" />
          <circle :cx="tx(e.t)" :cy="laneY - 2" r="3" class="tick-dot" />
          <text v-for="(l, i) in e.lines" :key="l" :x="tx(e.t)" :y="(e.up ? 36 : 70) + i * 16" text-anchor="middle" class="ev">{{ l }}</text>
        </g>

        <line :x1="x0" :y1="laneY + laneH + 8" :x2="x1" :y2="laneY + laneH + 8" class="axis" />
        <g v-for="m in [0, 5, 10, 15, 20, 25, 30]" :key="m">
          <line :x1="tx(m)" :y1="laneY + laneH + 4" :x2="tx(m)" :y2="laneY + laneH + 12" class="axis" />
          <text :x="tx(m)" :y="laneY + laneH + 26" text-anchor="middle" class="axis-t">{{ m }} мин</text>
        </g>
      </g>
    </svg>
    <figcaption>Полоса показывает, через какой сервер идёт соединение. Если сервер молчит, а другие отвечают, «Авто» переключается на другой и потом возвращается. Если молчат все, значит, пропала сеть, и «Авто» ничего не трогает.</figcaption>
  </figure>
</template>

<style scoped>
.title { fill: var(--vp-c-text-1); font-size: 15px; font-weight: 600; }
.seg.a { fill: var(--kq-proxy); opacity: 0.85; }
.seg.b { fill: var(--kq-server); opacity: 0.85; }
.seg-t { fill: #fff; font-size: 13.5px; font-weight: 600; }
.dark .seg-t { fill: #1b1b1f; }
.note-t { fill: var(--vp-c-text-1); font-size: 13px; font-weight: 600; paint-order: stroke; stroke: var(--vp-c-bg); stroke-width: 4px; }
.hatch-bg { fill: var(--vp-c-bg-soft); }
.hatch { stroke: var(--vp-c-text-3); stroke-width: 2; }
.tick { stroke: var(--vp-c-text-3); stroke-width: 1.2; }
.tick-dot { fill: var(--vp-c-text-2); }
.ev { fill: var(--vp-c-text-1); font-size: 13px; }
.small { fill: var(--vp-c-text-2); font-size: 12.5px; }
.axis { stroke: var(--vp-c-divider); stroke-width: 1.2; }
.axis-t { fill: var(--vp-c-text-3); font-size: 11.5px; }
</style>
