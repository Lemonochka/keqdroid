/// Готовые значения для подмены идентичности при загрузке подписки.
///
/// Списки нужны не ради полноты, а ради попадания: панели с привязкой по HWID
/// сверяют связку «User-Agent + device-заголовки» с тем, что присылают
/// официальные клиенты. Вводить такую строку руками — верный способ ошибиться
/// в пробеле или регистре, поэтому типовые варианты лежат готовыми.
///
/// Про версии в этих строках: панели почти всегда смотрят на ИМЯ клиента, а
/// номер версии остаётся антуражем — здесь он правдоподобный, а не выверенный
/// по релизам каждого проекта. Если конкретная панель придирается к точной
/// версии, нужную строку можно вписать руками прямо в списке выбора.
library;

/// User-Agent сторонних клиентов, разложенные по платформе, на которой клиент
/// чаще всего встречается.
///
/// Платформенных вариантов одной строки здесь нет намеренно: ОС, модель и
/// версия системы задаются отдельными полями идентичности, и дублировать их
/// ещё и в скобках User-Agent значит разложить одну настройку по двум местам.
/// Нужен UA с конкретной версией ОС внутри — он вписывается руками.
abstract final class ClientUaPresets {
  static const android = [
    'Happ/3.20.4',
    'v2rayNG/1.10.5',
    'v2rayNG/1.9.28',
    'NekoBox/1.3.9',
    'husi/1.0.5',
    'ClashMetaForAndroid/2.11.5',
    'FlClash/0.8.84',
    'SFA/1.11.0 (5011; sing-box 1.11.0)',
    'HiddifyNext/2.0.5 (android)',
    'V2rayTun/6.5.0',
    'Karing/1.1.5.0',
  ];

  static const ios = [
    'Shadowrocket/2.2.65',
    'Streisand/1.6.44',
    'Quantumult%20X/1.0.30',
    'Loon/3.2.3',
    'Stash/2.9.0',
    'Surge/5.9.0',
    'SFI/1.11.0 (1; sing-box 1.11.0)',
    'V2Box/1.0.0',
    'FoXray/1.5.0',
    'HiddifyNext/2.0.5 (ios)',
  ];

  static const desktop = [
    'v2rayN/7.12.5',
    'clash-verge/v2.2.2',
    'Nekoray/4.0.1',
    'Throne/1.0.3',
    'Hiddify/2.5.7',
    'Mihomo Party/1.6.5',
    'Furious/0.3.2',
    'ClashforWindows/0.20.39',
    'SFM/1.11.0 (1; sing-box 1.11.0)',
  ];

  /// Голые ядра и обычные http-клиенты. Нужны для панелей, которые не столько
  /// ищут «свой» клиент, сколько отсекают браузер: им достаточно любого UA,
  /// не похожего на Chrome.
  static const cores = [
    'sing-box',
    'sing-box 1.11.0',
    'mihomo/1.19.0',
    'Xray/25.3.6',
    'v2ray/5.28.0',
    'curl/8.9.1',
    'Go-http-client/2.0',
  ];

  /// Подмножество для АВТОМАТИЧЕСКОГО перебора, когда панель отказала нашему
  /// UA. Оно намеренно короткое: каждый вариант — отдельный http-запрос, и
  /// полный каталог превратил бы неудачную загрузку в полминуты ожидания.
  /// Порядок — по частоте, с которой панели на них настроены.
  static const rotation = [
    'Happ/3.20.4',
    'v2rayNG/1.9.28',
    'NekoBox/1.3.9',
    'ClashMetaForAndroid/2.11.5',
    'clash-verge/v2.2.2',
    'Streisand/1.6.44',
    'sing-box',
    'QuantumultX',
    'Shadowrocket',
  ];
}

/// Значения заголовка `x-device-model`.
abstract final class DeviceModelPresets {
  static const android = [
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
    'iPhone 17 Pro Max',
    'iPhone 17 Pro',
    'iPhone 17 Air',
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

  /// На десктопе панели видят имя машины, а не модель — здесь оно и подменяется.
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

/// Значения заголовка `x-ver-os`. Панели принимают и короткий номер релиза, и
/// build-ID прошивки — какой именно ждут, снаружи не видно, поэтому есть оба.
abstract final class OsVersionPresets {
  static const androidRelease = [
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

/// Значения заголовка `x-device-os`.
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
