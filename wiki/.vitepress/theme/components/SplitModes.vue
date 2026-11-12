<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

const ru = {
  aria: 'Какие приложения идут через VPN в каждом режиме раздельного туннелирования',
  apps: ['Браузер', 'Telegram', 'Банк', 'Игра'],
  modes: ['Все приложения', 'Только выбранные', 'Все кроме выбранных'],
  vpn: 'через VPN',
  direct: 'напрямую',
  picked: 'отмечено в списке',
}

const en: typeof ru = {
  aria: 'Which apps go through the VPN in each split tunneling mode',
  apps: ['Browser', 'Telegram', 'Bank', 'Game'],
  modes: ['All apps', 'Selected only', 'All except selected'],
  vpn: 'via VPN',
  direct: 'direct',
  picked: 'checked in the list',
}

const { lang } = useData()
const t = computed(() => (lang.value.startsWith('en') ? en : ru))
const apps = computed(() => t.value.apps)

const layout = [
  { picked: [] as number[], vpn: [0, 1, 2, 3] },
  { picked: [0, 1], vpn: [0, 1] },
  { picked: [2], vpn: [0, 1, 3] },
]
const modes = computed(() => layout.map((m, i) => ({ ...m, name: t.value.modes[i] })))

const labelW = 200
const chipW = 112
const gap = 12
const rowH = 60
const top = 10
const x = (j: number) => labelW + j * (chipW + gap)
const y = (i: number) => top + i * rowH
</script>

<template>
  <figure class="kq-figure">
    <svg viewBox="0 0 700 250" role="img" :aria-label="t.aria">
      <g v-for="(m, i) in modes" :key="m.name">
        <text x="3" :y="y(i) + 26" class="mode">{{ m.name }}</text>
        <g v-for="(a, j) in apps" :key="a">
          <rect :x="x(j)" :y="y(i)" :width="chipW" height="40" rx="8" :class="['chip', m.vpn.includes(j) ? 'vpn' : 'direct']" />
          <text :x="x(j) + (m.picked.includes(j) ? 30 : chipW / 2)" :y="y(i) + 25" :text-anchor="m.picked.includes(j) ? 'start' : 'middle'" class="app">{{ a }}</text>
          <g v-if="m.picked.includes(j)">
            <circle :cx="x(j) + 16" :cy="y(i) + 20" r="8" class="check-bg" />
            <path :d="`M${x(j) + 12},${y(i) + 20} l3,3 l5,-6`" class="check" />
          </g>
        </g>
      </g>

      <g transform="translate(200, 205)">
        <rect x="0" y="0" width="18" height="18" rx="4" class="chip vpn" />
        <text x="26" y="14" class="legend">{{ t.vpn }}</text>
        <rect x="140" y="0" width="18" height="18" rx="4" class="chip direct" />
        <text x="166" y="14" class="legend">{{ t.direct }}</text>
        <circle cx="289" cy="9" r="8" class="check-bg" />
        <path d="M285,9 l3,3 l5,-6" class="check" />
        <text x="304" y="14" class="legend">{{ t.picked }}</text>
      </g>
    </svg>
  </figure>
</template>

<style scoped>
.mode { fill: var(--vp-c-text-1); font-size: 15px; font-weight: 500; }
.chip.vpn { fill: color-mix(in srgb, var(--kq-proxy) 22%, transparent); stroke: var(--kq-proxy); stroke-width: 1.5; }
.chip.direct { fill: color-mix(in srgb, var(--kq-direct) 22%, transparent); stroke: var(--kq-direct); stroke-width: 1.5; }
.app { fill: var(--vp-c-text-1); font-size: 14px; }
.check-bg { fill: var(--vp-c-text-1); }
.check { fill: none; stroke: var(--vp-c-bg); stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
.legend { fill: var(--vp-c-text-2); font-size: 13px; }
</style>
