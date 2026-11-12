<script setup lang="ts">
const steps = [
  { name: 'Служебные правила', owner: 'приложение' },
  { name: 'Правила шаблона', owner: 'провайдер' },
  { name: 'Ваши маршруты', owner: 'вы' },
  { name: 'Всё остальное шаблона', owner: 'провайдер' },
]

const examples = [
  { site: 'youtube.com', why: 'есть в шаблоне', stop: 1, result: 'группа YouTube:', result2: 'Нидерланды', cls: 'server' },
  { site: 'vk.com', why: 'у вас в «Напрямую»', stop: 2, result: 'мимо VPN', result2: '', cls: 'direct' },
  { site: 'example.org', why: 'нигде нет', stop: 3, result: 'главная группа:', result2: 'Германия', cls: 'proxy' },
]

const top = 70
const rowH = 56
const labelW = 230
const colW = 160
const height = top + steps.length * rowH + 64
const rowY = (i: number) => top + i * rowH
const colX = (j: number) => labelW + j * colW + colW / 2
</script>

<template>
  <figure class="kq-figure">
    <svg :viewBox="`0 0 720 ${height}`" role="img" aria-label="Три сайта проходят правила при шаблоне с группами и останавливаются на первом подходящем">
      <g v-for="(e, j) in examples" :key="e.site">
        <text :x="colX(j)" y="22" text-anchor="middle" class="site">{{ e.site }}</text>
        <text :x="colX(j)" y="42" text-anchor="middle" class="why">{{ e.why }}</text>
      </g>

      <g v-for="(s, i) in steps" :key="s.name">
        <rect x="0" :y="rowY(i)" width="720" :height="rowH" :class="i % 2 ? 'band' : 'band alt'" />
        <text x="14" :y="rowY(i) + 25" class="step">{{ s.name }}</text>
        <text x="14" :y="rowY(i) + 43" :class="['owner', s.owner === 'провайдер' ? 'prov' : '']">{{ s.owner }}</text>
      </g>

      <g v-for="(e, j) in examples" :key="'p' + e.site">
        <line :x1="colX(j)" :y1="top - 8" :x2="colX(j)" :y2="rowY(e.stop) + rowH / 2" :class="['path', e.cls]" />
        <line v-if="e.stop < steps.length - 1" :x1="colX(j)" :y1="rowY(e.stop) + rowH / 2 + 10" :x2="colX(j)" :y2="top + steps.length * rowH" class="ghost" />
        <circle :cx="colX(j)" :cy="rowY(e.stop) + rowH / 2" r="7" :class="['dot', e.cls]" />
        <text :x="colX(j)" :y="top + steps.length * rowH + 28" text-anchor="middle" :class="['result', e.cls]">{{ e.result }}</text>
        <text v-if="e.result2" :x="colX(j)" :y="top + steps.length * rowH + 48" text-anchor="middle" :class="['result', e.cls]">{{ e.result2 }}</text>
      </g>
    </svg>
    <figcaption>В шаблоне правило отправляет YouTube в группу «YouTube», а MATCH – в главную группу. В группе «YouTube» выбраны Нидерланды, а в списке серверов нажата Германия.</figcaption>
  </figure>
</template>

<style scoped>
.band { fill: transparent; }
.band.alt { fill: var(--vp-c-bg-soft); }
.step { fill: var(--vp-c-text-1); font-size: 15px; }
.owner { fill: var(--vp-c-text-2); font-size: 12.5px; }
.owner.prov { fill: var(--kq-accent); }
.site { fill: var(--vp-c-text-1); font-size: 14px; font-weight: 600; font-family: var(--vp-font-family-mono); }
.why { fill: var(--vp-c-text-2); font-size: 12.5px; }
.path { stroke-width: 3; stroke-linecap: round; }
.ghost { stroke: var(--vp-c-divider); stroke-width: 1.5; stroke-dasharray: 3 5; }
.result { font-size: 14px; font-weight: 600; }
.path.server, .dot.server { stroke: var(--kq-server); fill: var(--kq-server); }
.path.direct, .dot.direct { stroke: var(--kq-direct); fill: var(--kq-direct); }
.path.proxy, .dot.proxy { stroke: var(--kq-proxy); fill: var(--kq-proxy); }
.result.server { fill: var(--kq-server); }
.result.direct { fill: var(--kq-direct); }
.result.proxy { fill: var(--kq-proxy); }
</style>
