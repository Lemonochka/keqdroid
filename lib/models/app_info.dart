class AppInfo {
  final String packageName;
  final String appName;
  final bool isSystem;
  final String? iconBase64;
  /// Windows: процесс сейчас запущен.
  final bool isRunning;
  /// Полный путь к exe (Windows), для отображения.
  final String? installPath;

  const AppInfo({
    required this.packageName,
    required this.appName,
    this.isSystem = false,
    this.iconBase64,
    this.isRunning = false,
    this.installPath,
  });

  // .toString() вместо as String — нативка иногда шлёт int вместо строки
  factory AppInfo.fromJson(Map<String, dynamic> json) => AppInfo(
    packageName: json['packageName']?.toString() ?? '',
    appName: json['appName']?.toString() ?? '',
    isSystem: json['isSystem'] as bool? ?? false,
    iconBase64: json['iconBase64'] as String?,
    isRunning: json['isRunning'] as bool? ?? false,
    installPath: json['installPath']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'appName': appName,
    'isSystem': isSystem,
    if (iconBase64 != null) 'iconBase64': iconBase64,
    'isRunning': isRunning,
    if (installPath != null) 'installPath': installPath,
  };

  AppInfo copyWith({
    String? packageName,
    String? appName,
    bool? isSystem,
    String? iconBase64,
    bool? isRunning,
    String? installPath,
  }) =>
      AppInfo(
        packageName: packageName ?? this.packageName,
        appName: appName ?? this.appName,
        isSystem: isSystem ?? this.isSystem,
        iconBase64: iconBase64 ?? this.iconBase64,
        isRunning: isRunning ?? this.isRunning,
        installPath: installPath ?? this.installPath,
      );

  // сравниваем по packageName — это уникальный ключ пакета.
  // iconBase64 не берём: тяжёлый и на идентичность не влияет
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is AppInfo &&
              runtimeType == other.runtimeType &&
              packageName == other.packageName;

  @override
  int get hashCode => packageName.hashCode;

  @override
  String toString() => 'AppInfo($appName, $packageName)';
}