<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

const ru = {
  aria: 'Что измеряет каждый способ проверки',
  nodes: ['устройство', 'сервер', 'сайт проверки'],
  rows: [
    { name: 'TCP, ICMP', note: 'отвечает ли адрес сервера' },
    { name: 'HTTP через прокси', note: 'запрос через сервер до сайта и обратно' },
    { name: 'Тест скорости', note: 'скачать 2 МБ через сервер' },
  ],
}

const en: typeof ru = {
  aria: 'What each check method measures',
  nodes: ['device', 'server', 'test site'],
  rows: [
    { name: 'TCP, ICMP', note: 'whether the server address responds' },
    { name: 'HTTP via proxy', note: 'a request through the server to the site and back' },
    { name: 'Speed test', note: 'download 2 MB through the server' },
  ],
}

const { lang } = useData()
const t = computed(() => (lang.value.startsWith('en') ? en : ru))

const nodeX = [70, 360, 630]
const rowTo = [360, 630, 630]
const nodes = computed(() => t.value.nodes.map((label, i) => ({ x: nodeX[i], label })))
const rows = computed(() => t.value.rows.map((r, i) => ({ ...r, to: rowTo[i] })))
</script>

<template>
  <figure class="kq-figure">
    <svg viewBox="0 0 700 300" role="img" :aria-label="t.aria">
      <defs>
        <marker id="kq-p" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M0,0 L10,5 L0,10 z" class="mark" />
        </marker>
      </defs>

      <g v-for="n in nodes" :key="n.label">
        <circle :cx="n.x" cy="40" r="22" class="node" />
        <text :x="n.x" y="84" text-anchor="middle" class="node-t">{{ n.label }}</text>
        <line :x1="n.x" y1="96" :x2="n.x" y2="290" class="guide" />
      </g>

      <g v-for="(r, i) in rows" :key="r.name">
        <text x="78" :y="128 + i * 62" class="row-t">{{ r.name }}</text>
        <line x1="70" :y1="146 + i * 62" :x2="r.to - 4" :y2="146 + i * 62" class="arrow" marker-end="url(#kq-p)" marker-start="url(#kq-p)" />
        <text :x="r.to === 360 ? 380 : 78" :y="r.to === 360 ? 150 + i * 62 : 166 + i * 62" class="note">{{ r.note }}</text>
      </g>
    </svg>
  </figure>
</template>

<style scoped>
.node { fill: var(--vp-c-bg-soft); stroke: var(--vp-c-text-3); stroke-width: 1.5; }
.node-t { fill: var(--vp-c-text-1); font-size: 14px; font-weight: 500; }
.guide { stroke: var(--vp-c-divider); stroke-width: 1; stroke-dasharray: 3 5; }
.row-t { fill: var(--vp-c-text-1); font-size: 14px; font-weight: 600; }
.arrow { stroke: var(--kq-proxy); stroke-width: 2.5; }
.mark { fill: var(--kq-proxy); }
.note { fill: var(--vp-c-text-2); font-size: 13px; }
</style>
