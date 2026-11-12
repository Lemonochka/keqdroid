<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

const ru = {
  aria: 'Три DNS-запроса: обычный сайт через VPN, адрес сервера напрямую и ответ Fake IP из самого ядра',
  caption: 'Три запроса, когда «Всё остальное» идёт через VPN, а DNS-серверы стоят по умолчанию. Пустой кружок – запрос проходит мимо этой точки.',
  cols: ['Программа', 'Ядро', 'Сервер VPN', 'Резолвер'],
  rows: [
    { why: 'обычный сайт', result: 'настоящий адрес, запрос шёл через VPN' },
    { why: 'адрес вашего сервера', result: 'напрямую – через сам сервер его адрес не узнать' },
    { why: 'с Fake IP', result: 'ядро сразу отвечает 198.18.0.7' },
  ],
}

const en: typeof ru = {
  aria: 'Three DNS queries: a regular site through the VPN, the server address directly, and a Fake IP answer from the core itself',
  caption: 'Three queries when “Everything else” goes through the VPN and the DNS servers are left at their defaults. An empty circle means the query skips that point.',
  cols: ['Program', 'Core', 'VPN server', 'Resolver'],
  rows: [
    { why: 'regular site', result: 'real address, the query went through the VPN' },
    { why: 'your server address', result: 'direct – the server can’t look up its own address' },
    { why: 'with Fake IP', result: 'the core answers 198.18.0.7 right away' },
  ],
}

const shape = [
  { site: 'youtube.com', hops: [0, 1, 2, 3], resolver: '1.1.1.1', cls: 'proxy' },
  { site: 'vpn.example', hops: [1, 3], resolver: '1.1.1.1', cls: 'direct' },
  { site: 'youtube.com', hops: [0, 1], resolver: '', cls: 'fake' },
]

const { lang } = useData()
const t = computed(() => (lang.value.startsWith('en') ? en : ru))
const cols = computed(() => t.value.cols)
const rows = computed(() => shape.map((r, i) => ({ ...r, ...t.value.rows[i] })))

const top = 44
const rowH = 92
const colX = (i: number) => 250 + i * 130
const rowY = (r: number) => top + r * rowH
const height = top + shape.length * rowH + 6
</script>

<template>
  <figure class="kq-figure">
    <svg :viewBox="`0 0 720 ${height}`" role="img" :aria-label="t.aria">
      <text v-for="(c, i) in cols" :key="c" :x="colX(i)" y="22" text-anchor="middle" class="col">{{ c }}</text>

      <g v-for="(r, j) in rows" :key="j">
        <rect x="0" :y="rowY(j)" width="720" :height="rowH" :class="j % 2 ? 'band' : 'band alt'" />
        <text x="14" :y="rowY(j) + 32" class="site">{{ r.site }}</text>
        <text x="14" :y="rowY(j) + 52" class="why">{{ r.why }}</text>

        <line
          :x1="colX(r.hops[0])" :y1="rowY(j) + 30"
          :x2="colX(r.hops[r.hops.length - 1])" :y2="rowY(j) + 30"
          :class="['path', r.cls]"
        />
        <template v-for="(c, i) in cols" :key="'g' + i">
          <circle v-if="!r.hops.includes(i)" :cx="colX(i)" :cy="rowY(j) + 30" r="6" class="ghost" />
        </template>
        <circle v-for="h in r.hops" :key="'h' + h" :cx="colX(h)" :cy="rowY(j) + 30" r="7" :class="['dot', r.cls]" />
        <text v-if="r.resolver" :x="colX(3)" :y="rowY(j) + 56" text-anchor="middle" class="res">{{ r.resolver }}</text>
        <text :x="colX(0) - 8" :y="rowY(j) + 80" :class="['result', r.cls]">{{ r.result }}</text>
      </g>
    </svg>
    <figcaption>{{ t.caption }}</figcaption>
  </figure>
</template>

<style scoped>
.band { fill: transparent; }
.band.alt { fill: var(--vp-c-bg-soft); }
.col { fill: var(--vp-c-text-2); font-size: 13px; }
.site { fill: var(--vp-c-text-1); font-size: 14px; font-weight: 600; font-family: var(--vp-font-family-mono); }
.why { fill: var(--vp-c-text-2); font-size: 12.5px; }
.res { fill: var(--vp-c-text-2); font-size: 12.5px; font-family: var(--vp-font-family-mono); }
.ghost { fill: var(--vp-c-bg); stroke: var(--vp-c-divider); stroke-width: 1.5; }
.path { stroke-width: 3; stroke-linecap: round; }
.result { font-size: 14px; font-weight: 600; }
.path.proxy, .dot.proxy { stroke: var(--kq-proxy); fill: var(--kq-proxy); }
.path.direct, .dot.direct { stroke: var(--kq-direct); fill: var(--kq-direct); }
.path.fake, .dot.fake { stroke: var(--kq-accent); fill: var(--kq-accent); }
.result.proxy { fill: var(--kq-proxy); }
.result.direct { fill: var(--kq-direct); }
.result.fake { fill: var(--kq-accent); }
</style>
