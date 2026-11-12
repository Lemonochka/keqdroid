import { defineConfig, type DefaultTheme } from 'vitepress'

const repo = 'https://github.com/Lemonochka/keqdroid'

const ruSidebar: DefaultTheme.SidebarItem[] = [
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
]

const enSidebar: DefaultTheme.SidebarItem[] = [
  {
    text: 'Start',
    items: [{ text: 'About these docs', link: '/en/' }],
  },
  {
    text: 'The app',
    items: [
      { text: 'Subscriptions and servers', link: '/en/servers' },
      { text: 'Platforms', link: '/en/platforms' },
      { text: 'Updates and release signing', link: '/en/updates' },
    ],
  },
  {
    text: 'How it works',
    items: [
      { text: 'Routing', link: '/en/routing' },
      { text: 'DNS', link: '/en/dns' },
      { text: 'Modes and split tunneling', link: '/en/modes' },
      { text: 'Xray or mihomo', link: '/en/xray-or-mihomo' },
      { text: 'mihomo groups', link: '/en/mihomo-groups' },
      { text: 'Auto', link: '/en/auto' },
      { text: 'Server checks', link: '/en/ping' },
      { text: 'Core patches', link: '/en/cores' },
    ],
  },
  {
    text: 'For providers',
    items: [
      { text: 'Subscription headers', link: '/en/provider/headers' },
      { text: 'Links', link: '/en/provider/links' },
    ],
  },
]

export default defineConfig({
  title: 'keqdroid',
  base: '/docs/keqdroid/',
  cleanUrls: true,
  lastUpdated: true,
  head: [['link', { rel: 'icon', type: 'image/svg+xml', href: '/docs/keqdroid/logo.svg' }]],
  markdown: { math: true },

  themeConfig: {
    logo: { light: '/logo.svg', dark: '/logo-dark.svg' },
    siteTitle: 'keqdroid',

    socialLinks: [
      { icon: 'github', link: repo },
      { icon: 'telegram', link: 'https://t.me/keqdroid' },
    ],

    search: {
      provider: 'local',
      options: {
        locales: {
          root: {
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
    },
  },

  locales: {
    root: {
      label: 'Русский',
      lang: 'ru-RU',
      description: 'Как устроен keqdroid: маршрутизация, DNS, ядра, подписки',
      themeConfig: {
        nav: [{ text: 'Релизы', link: `${repo}/releases` }],
        sidebar: ruSidebar,
        editLink: { pattern: `${repo}/edit/master/wiki/:path`, text: 'Поправить страницу' },
        lastUpdated: { text: 'Обновлено' },
        outline: { label: 'На странице', level: [2, 3] },
        docFooter: { prev: 'Назад', next: 'Дальше' },
        darkModeSwitchLabel: 'Тема',
        lightModeSwitchTitle: 'Светлая тема',
        darkModeSwitchTitle: 'Тёмная тема',
        sidebarMenuLabel: 'Меню',
        returnToTopLabel: 'Наверх',
        langMenuLabel: 'Язык',
        notFound: { title: 'Такой страницы нет', quote: '', linkText: 'На главную' },
      },
    },
    en: {
      label: 'English',
      lang: 'en-US',
      link: '/en/',
      description: 'How keqdroid works: routing, DNS, cores, subscriptions',
      themeConfig: {
        nav: [{ text: 'Releases', link: `${repo}/releases` }],
        sidebar: enSidebar,
        editLink: { pattern: `${repo}/edit/master/wiki/:path`, text: 'Edit this page' },
        lastUpdated: { text: 'Updated' },
        outline: { label: 'On this page', level: [2, 3] },
        docFooter: { prev: 'Previous', next: 'Next' },
        langMenuLabel: 'Language',
        notFound: { title: 'Page not found', quote: '', linkText: 'Back to home' },
      },
    },
  },
})
