// Версии сверены с релизами клиентов 13.09.2026. Часть панелей отдаёт старому клиенту заглушку, поэтому
// список стареет. Порядок по популярности у русскоязычных, мёртвых клиентов тут нет
library;

abstract final class ClientUaPresets {
  static const android = [
    'Happ/4.1.0',
    'INCY/3.6.5',
    'v2RayTun/5.25.82',
    'v2rayNG/2.2.6',
    'FlClashX/0.4.2',
    'ClashMetaForAndroid/2.11.33',
    'FlClash/0.8.97',
    'Surfboard/2.34.4',
    'Hiddify/4.1.1 (android)',
    'husi/2.1.2',
    'NekoBox/1.4.2',
    'Exclave/0.17.56',
    'SFA/1.14.0 (5014; sing-box 1.14.0)',
    'Karing/1.2.25.2802',
    'VPN4TV/5.2.6',
  ];

  static const ios = [
    // у Happ и INCY на каждой платформе своя нумерация, это не опечатка
    'Happ/5.5.0',
    'INCY/2.6.1',
    'Streisand/1.6.76',
    'Shadowrocket/2.2.92',
    'ClashMi/1.0.29.1503',
    'RabbitHole/1.5.0',
    'V2Box/10.1.7',
    'Hiddify/4.1.1 (ios)',
    'SFI/1.14.0 (1; sing-box 1.14.0)',
    'Quantumult%20X/1.7.0',
    'Loon/3.5.0',
    'Stash/3.4.1',
    'Surge/5.22.0',
  ];

  static const desktop = [
    'Happ/3.3.6',
    'INCY/3.8.6',
    'clash-verge/v2.5.2',
    'Koala Clash/1.4.1',
    'Prizrak-Box/1.0.21',
    'Mihomo Party/2.0.2',
    'Sparkle/1.26.8',
    'ClashX Meta/1.4.44',
    'v2rayN/7.24.9',
    'v2RayTun/3.10.15',
    'Hiddify/4.1.1 (windows)',
    'Throne/1.2.4',
    'SFM/1.14.0 (1; sing-box 1.14.0)',
  ];

  static const cores = [
    'sing-box',
    'sing-box 1.14.0',
    'mihomo/1.19.30',
    'Xray/26.9.9',
    'v2ray/5.53.0',
    'curl/8.22.0',
    'Go-http-client/2.0',
  ];

  static const rotation = [
    'Happ/4.1.0',
    'INCY/3.6.5',
    'v2RayTun/5.25.82',
    'v2rayNG/2.2.6',
    'Streisand/1.6.76',
    'Shadowrocket/2.2.92',
    'FlClashX/0.4.2',
    'ClashMetaForAndroid/2.11.33',
    'clash-verge/v2.5.2',
    'sing-box',
  ];
}

abstract final class DeviceModelPresets {
  static const android = [
    'Google Pixel 11 Pro XL',
    'Google Pixel 11 Pro',
    'Google Pixel 11',
    'Google Pixel 10 Pro XL',
    'Google Pixel 10 Pro',
    'Google Pixel 10',
    'Google Pixel 9 Pro',
    'Google Pixel 9',
    'Google Pixel 9a',
    'Google Pixel 8 Pro',
    'Google Pixel 8',
    'Google Pixel 7 Pro',
    'Google Pixel 6a',
    'Samsung Galaxy S26 Ultra',
    'Samsung Galaxy S26+',
    'Samsung Galaxy S26',
    'Samsung Galaxy S25 Ultra',
    'Samsung Galaxy S25+',
    'Samsung Galaxy S25',
    'Samsung Galaxy S24 Ultra',
    'Samsung Galaxy S24',
    'Samsung Galaxy S23 Ultra',
    'Samsung Galaxy Z Fold7',
    'Samsung Galaxy Z Flip7',
    'Samsung Galaxy Z Fold5',
    'Samsung Galaxy A56',
    'Samsung Galaxy A55',
    'Xiaomi 15 Ultra',
    'Xiaomi 15',
    'Xiaomi 14 Ultra',
    'Xiaomi 14',
    'Xiaomi 13T Pro',
    'Redmi Note 14 Pro+',
    'Redmi Note 13 Pro',
    'POCO F7 Pro',
    'POCO F6',
    'OnePlus 13',
    'OnePlus 12',
    'OnePlus Nord 4',
    'Honor Magic7 Pro',
    'Honor Magic6 Pro',
    'Huawei P60 Pro',
    'OPPO Find X8 Pro',
    'OPPO Find X7 Ultra',
    'vivo X200 Pro',
    'vivo X100 Pro',
    'realme GT 7 Pro',
    'realme GT 6',
    'Motorola Edge 60 Pro',
    'Motorola Edge 50 Pro',
    'Nothing Phone (3)',
    'Nothing Phone (2)',
    'ASUS ROG Phone 9',
    'ASUS ROG Phone 8',
  ];

  static const ios = [
    'iPhone 18 Pro Max',
    'iPhone 18 Pro',
    'iPhone 17 Pro Max',
    'iPhone 17 Pro',
    'iPhone Air',
    'iPhone 17',
    'iPhone 16 Pro Max',
    'iPhone 16 Pro',
    'iPhone 16 Plus',
    'iPhone 16',
    'iPhone 16e',
    'iPhone 15 Pro Max',
    'iPhone 15 Pro',
    'iPhone 15 Plus',
    'iPhone 15',
    'iPhone 14 Pro Max',
    'iPhone 14 Pro',
    'iPhone 14',
    'iPhone 13 Pro Max',
    'iPhone 13 Pro',
    'iPhone 13',
    'iPhone 13 mini',
    'iPhone SE (3rd generation)',
    'iPad Pro 13-inch (M4)',
    'iPad Pro 11-inch (M4)',
    'iPad Pro 12.9-inch (6th generation)',
    'iPad Air 13-inch (M2)',
    'iPad Air (5th generation)',
    'iPad mini (A17 Pro)',
    'iPad mini (6th generation)',
  ];

  static const desktop = [
    'MacBook Pro',
    'MacBook Air',
    'Mac mini',
    'iMac',
    'Windows PC',
    'DESKTOP-7K2M9QX',
    'LAPTOP-3F8D2A1',
  ];

  static const all = [...android, ...ios, ...desktop];
}

abstract final class OsVersionPresets {
  static const androidRelease = [
    '17',
    '16',
    '15',
    '14',
    '13',
    '12',
    '11',
    '10',
    '9',
  ];

  static const androidBuilds = [
    'CP2A.260805.005',
    'CP2A.260705.006',
    'CP2A.260605.012',
    'BP2A.250605.031',
    'BP1A.250505.005',
    'AP4A.250105.002',
    'AP3A.241005.015',
    'AP2A.240905.003',
    'UP1A.231005.007',
    'UD1A.231105.004',
    'TP1A.220624.014',
    'TQ3A.230805.001',
    'SP1A.210812.016',
    'RKQ1.211119.001',
  ];

  static const iosRelease = [
    '27.0',
    '26.1',
    '26.0',
    '18.6',
    '18.5',
    '18.4',
    '18.3',
    '18.2',
    '18.1',
    '18.0',
    '17.6',
    '17.4',
    '17.0',
    '16.6',
    '16.0',
    '15.8',
  ];

  static const iosBuilds = [
    '23B81',
    '23A344',
    '22G86',
    '22F76',
    '22E240',
    '22D63',
    '22C161',
    '22B91',
    '22A3354',
    '21G93',
    '21E236',
    '20H343',
  ];

  static const desktop = [
    'Windows 10.0.26200',
    'Windows 10.0.26100',
    'Windows 10.0.22631',
    'Windows 10.0.19045',
    'macOS 27.0',
    'macOS 26.0',
    'macOS 15.6',
    'macOS 14.0',
    'macOS 13.6',
    'Linux 6.12',
    'Linux 6.8',
  ];

  static const all = [
    ...androidRelease,
    ...androidBuilds,
    ...iosRelease,
    ...iosBuilds,
    ...desktop,
  ];
}

abstract final class DeviceOsPresets {
  static const all = [
    'Android',
    'iOS',
    'iPadOS',
    'Windows',
    'macOS',
    'Linux',
    'Android TV',
  ];
}
