<script setup lang="ts">
import { withBase } from 'vitepress'

const marks = [
  { x: 482, y: 100, header: 'profile-title', what: 'имя подписки, если вы не задали своё' },
  { x: 833, y: 152, header: 'announce', what: 'объявление провайдера' },
  { x: 497, y: 404, header: 'subscription-userinfo', what: 'израсходовано и сколько всего: upload + download из total' },
  { x: 282, y: 530, header: 'subscription-userinfo', what: 'сколько осталось до конца: expire' },
  { x: 208, y: 585, header: 'profile-update-interval', what: 'как часто обновлять подписку' },
  { x: 650, y: 585, header: 'profile-web-page-url', what: 'кнопка «Страница подписки»' },
  { x: 335, y: 675, header: 'support-url', what: 'кнопка «Поддержка»' },
]
</script>

<template>
  <figure class="kq-anatomy">
    <div class="shot">
      <img class="only-light" :src="withBase('/img/card-light.png')" alt="Карточка подписки в приложении" />
      <img class="only-dark" :src="withBase('/img/card-dark.png')" alt="Карточка подписки в приложении" />
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
