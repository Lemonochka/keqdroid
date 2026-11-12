<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

const ru = {
  aria: 'Четыре соединения проходят маршруты сверху вниз и останавливаются на первом подходящем',
  caption: 'Каждое соединение идёт по строкам сверху вниз и останавливается на первой, которая ему подходит. Ниже оно уже не смотрит.',
  steps: ['Блокировка', 'Ваш сервер', 'Отдельные приложения', 'Напрямую', 'Локальная сеть', 'Другой сервер', 'Через VPN', 'Всё остальное'],
  examples: [
    { site: 'ads.example', why: 'в списке рекламы', stop: 0, result: 'не откроется', cls: 'block' },
    { site: 'vk.com', why: 'в «Напрямую»', stop: 3, result: 'мимо VPN', cls: 'direct' },
    { site: '192.168.1.1', why: 'роутер', stop: 4, result: 'мимо VPN', cls: 'direct' },
    { site: 'youtube.com', why: 'нет в маршрутах', stop: 7, result: 'через VPN', cls: 'proxy' },
  ],
}

const en: typeof ru = {
  aria: 'Four connections go through the routes from top to bottom and stop at the first one that fits',
  caption: 'Each connection goes down the rows from top to bottom and stops at the first one that fits. It doesn’t look any further.',
  steps: ['Blocking', 'Your server', 'Specific apps', 'Direct', 'Local network', 'Another server', 'Via VPN', 'Everything else'],
  examples: [
    { site: 'ads.example', why: 'on the ad list', stop: 0, result: 'blocked', cls: 'block' },
    { site: 'vk.com', why: 'in “Direct”', stop: 3, result: 'bypasses VPN', cls: 'direct' },
    { site: '192.168.1.1', why: 'router', stop: 4, result: 'bypasses VPN', cls: 'direct' },
    { site: 'youtube.com', why: 'not in routes', stop: 7, result: 'via VPN', cls: 'proxy' },
  ],
}

const { lang } = useData()
const t = computed(() => (lang.value.startsWith('en') ? en : ru))
const steps = computed(() => t.value.steps)
const examples = computed(() => t.value.examples)

const top = 70
const rowH = 44
const labelW = 210
const colW = 125
const height = top + ru.steps.length * rowH + 50
const rowY = (i: number) => top + i * rowH
const colX = (j: number) => labelW + 20 + j * colW + colW / 2
</script>

<template>
  <figure class="kq-figure">
    <svg :viewBox="`0 0 720 ${height}`" role="img" :aria-label="t.aria">
      <g v-for="(e, j) in examples" :key="e.site">
        <text :x="colX(j)" y="22" text-anchor="middle" class="site">{{ e.site }}</text>
        <text :x="colX(j)" y="42" text-anchor="middle" class="why">{{ e.why }}</text>
      </g>

      <g v-for="(s, i) in steps" :key="s">
        <rect x="0" :y="rowY(i)" width="720" :height="rowH" :class="i % 2 ? 'band' : 'band alt'" />
        <text x="14" :y="rowY(i) + 28" class="step">{{ s }}</text>
      </g>

      <g v-for="(e, j) in examples" :key="'p' + e.site">
        <line :x1="colX(j)" :y1="top - 8" :x2="colX(j)" :y2="rowY(e.stop) + rowH / 2" :class="['path', e.cls]" />
        <line v-if="e.stop < steps.length - 1" :x1="colX(j)" :y1="rowY(e.stop) + rowH / 2 + 10" :x2="colX(j)" :y2="top + steps.length * rowH" class="ghost" />
        <circle :cx="colX(j)" :cy="rowY(e.stop) + rowH / 2" r="7" :class="['dot', e.cls]" />
        <text :x="colX(j)" :y="top + steps.length * rowH + 30" text-anchor="middle" :class="['result', e.cls]">{{ e.result }}</text>
      </g>
    </svg>
    <figcaption>{{ t.caption }}</figcaption>
  </figure>
</template>

<style scoped>
.band { fill: transparent; }
.band.alt { fill: var(--vp-c-bg-soft); }
.step { fill: var(--vp-c-text-1); font-size: 15px; }
.site { fill: var(--vp-c-text-1); font-size: 14px; font-weight: 600; font-family: var(--vp-font-family-mono); }
.why { fill: var(--vp-c-text-2); font-size: 12.5px; }
.path { stroke-width: 3; stroke-linecap: round; }
.ghost { stroke: var(--vp-c-divider); stroke-width: 1.5; stroke-dasharray: 3 5; }
.result { font-size: 14px; font-weight: 600; }
.path.block, .dot.block { stroke: var(--kq-block); fill: var(--kq-block); }
.path.direct, .dot.direct { stroke: var(--kq-direct); fill: var(--kq-direct); }
.path.proxy, .dot.proxy { stroke: var(--kq-proxy); fill: var(--kq-proxy); }
.result.block { fill: var(--kq-block); }
.result.direct { fill: var(--kq-direct); }
.result.proxy { fill: var(--kq-proxy); }
</style>
