import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'ru-RU',
  title: 'keqdroid',
  description: 'Как устроен keqdroid: маршрутизация, DNS, ядра, подписки',
  base: '/keqdroid/',
  cleanUrls: true,
  lastUpdated: true,
  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: '/keqdroid/logo.svg' }]],
  markdown: { math: true },

  themeConfig: {
    logo: { light: '/logo.svg', dark: '/logo-dark.svg' },
    siteTitle: 'keqdroid',

    nav: [
      { text: 'Релизы', link: 'https://github.com/Lemonochka/keqdroid/releases' },
    ],

    sidebar: [
      {
        text: 'Начало',
        items: [{ text: 'О документации', link: '/' }],
      },
      {
        text: 'Приложение',
        items: [
          { text: 'Подписки и серверы', link: '/servers' },
          { text: 'Платформы', link: '/platforms' },
          { text: 'Обновления и подпись релизов', link: '/updates' },
        ],
      },
      {
        text: 'Как устроено',
        items: [
          { text: 'Маршрутизация', link: '/routing' },
          { text: 'DNS', link: '/dns' },
          { text: 'Режимы и раздельное туннелирование', link: '/modes' },
          { text: 'Xray или mihomo', link: '/xray-or-mihomo' },
          { text: 'Группы mihomo', link: '/mihomo-groups' },
          { text: 'Авто', link: '/auto' },
          { text: 'Проверки серверов', link: '/ping' },
          { text: 'Правки в ядрах', link: '/cores' },
        ],
      },
      {
        text: 'Провайдерам',
        items: [
          { text: 'Заголовки подписки', link: '/provider/headers' },
          { text: 'Ссылки', link: '/provider/links' },
        ],
      },
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/Lemonochka/keqdroid' },
      { icon: 'telegram', link: 'https://t.me/keqdroid' },
    ],

    editLink: {
      pattern: 'https://github.com/Lemonochka/keqdroid/edit/master/wiki/:path',
      text: 'Поправить страницу',
    },
    lastUpdated: { text: 'Обновлено' },
    outline: { label: 'На странице', level: [2, 3] },
    docFooter: { prev: 'Назад', next: 'Дальше' },
    darkModeSwitchLabel: 'Тема',
    lightModeSwitchTitle: 'Светлая тема',
    darkModeSwitchTitle: 'Тёмная тема',
    sidebarMenuLabel: 'Меню',
    returnToTopLabel: 'Наверх',
    notFound: { title: 'Такой страницы нет', quote: '', linkText: 'На главную' },

    search: {
      provider: 'local',
      options: {
        translations: {
          button: { buttonText: 'Поиск', buttonAriaLabel: 'Поиск' },
          modal: {
            noResultsText: 'Ничего не нашлось',
            resetButtonTitle: 'Сбросить',
            footer: { selectText: 'открыть', navigateText: 'выбрать', closeText: 'закрыть' },
          },
        },
      },
    },
  },
})
