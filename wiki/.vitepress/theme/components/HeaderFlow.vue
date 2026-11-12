<script setup lang="ts">
import { computed } from 'vue'
import { useData, withBase } from 'vitepress'

const ru = {
  alt: 'Карточка подписки в приложении',
  what: [
    'имя подписки, если вы не задали своё',
    'объявление провайдера',
    'израсходовано и сколько всего: upload + download из total',
    'сколько осталось до конца: expire',
    'как часто обновлять подписку',
    'кнопка «Страница подписки»',
    'кнопка «Поддержка»',
  ],
}

const en: typeof ru = {
  alt: 'Subscription card in the app',
  what: [
    'subscription name, unless you set your own',
    'provider announcement',
    'used and total: upload + download out of total',
    'time left until the end: expire',
    'how often to update the subscription',
    '“Subscription page” button',
    '“Support” button',
  ],
}

const spots = [
  { x: 482, y: 100, header: 'profile-title' },
  { x: 833, y: 152, header: 'announce' },
  { x: 497, y: 404, header: 'subscription-userinfo' },
  { x: 282, y: 530, header: 'subscription-userinfo' },
  { x: 208, y: 585, header: 'profile-update-interval' },
  { x: 650, y: 585, header: 'profile-web-page-url' },
  { x: 335, y: 675, header: 'support-url' },
]

const { lang } = useData()
const t = computed(() => (lang.value.startsWith('en') ? en : ru))
const marks = computed(() => spots.map((s, i) => ({ ...s, what: t.value.what[i] })))
</script>

<template>
  <figure class="kq-anatomy">
    <div class="shot">
      <img class="only-light" :src="withBase('/img/card-light.png')" :alt="t.alt" />
      <img class="only-dark" :src="withBase('/img/card-dark.png')" :alt="t.alt" />
      <svg viewBox="0 0 880 800" aria-hidden="true">
        <g v-for="(m, i) in marks" :key="i">
          <circle :cx="m.x" :cy="m.y" r="26" class="badge" />
          <text :x="m.x" :y="m.y + 10" text-anchor="middle" class="badge-t">{{ i + 1 }}</text>
        </g>
      </svg>
    </div>
    <ol class="legend">
      <li v-for="(m, i) in marks" :key="i">
        <code>{{ m.header }}</code>
        <span>{{ m.what }}</span>
      </li>
    </ol>
  </figure>
</template>

<style scoped>
.kq-anatomy {
  display: flex;
  flex-wrap: wrap;
  gap: 24px;
  align-items: center;
  margin: 24px 0;
}
.shot {
  position: relative;
  flex: 0 1 300px;
  min-width: 240px;
}
.shot img {
  display: block;
  width: 100%;
  border-radius: 18px;
}
.shot svg {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
}
.dark .only-light,
html:not(.dark) .only-dark {
  display: none;
}
.badge {
  fill: var(--kq-accent);
  stroke: var(--vp-c-bg);
  stroke-width: 5;
}
.badge-t {
  fill: var(--vp-c-bg);
  font-size: 28px;
  font-weight: 700;
  font-family: var(--vp-font-family-base);
}
.legend {
  flex: 1 1 220px;
  margin: 0;
  padding-left: 22px;
}
.legend li {
  margin: 6px 0;
  line-height: 1.45;
}
.legend li::marker {
  color: var(--kq-accent);
  font-weight: 700;
}
.legend code {
  display: block;
  width: fit-content;
}
.legend span {
  color: var(--vp-c-text-2);
  font-size: 14px;
}
</style>
