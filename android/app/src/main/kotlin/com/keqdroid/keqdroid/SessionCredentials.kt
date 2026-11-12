package com.keqdroid.keqdroid

data class ProxyCredentials(val username: String, val password: String) {
    val isComplete: Boolean get() = username.isNotEmpty() && password.isNotEmpty()
}

// пароль, вписанный Dart в конфиг, важнее сгенерированного здесь: в режиме прокси с паролем это пароль из настроек,
// и сервис запоминал бы случайный, которого ядро не знает
fun startCredentials(fromDart: ProxyCredentials?, pending: ProxyCredentials?): ProxyCredentials? = when {
    fromDart?.isComplete == true -> fromDart
    pending?.isComplete == true -> pending
    else -> null
}

// приложению отдаём пароль запущенного ядра, а не последнего старта: старт поверх живой сессии ядро не перезапускает,
// и с паролем старта приложение получало 407 от своего же прокси до перезапуска (Pixel 6a, 12.11.2026)
fun activeCredentials(fromService: ProxyCredentials?, saved: ProxyCredentials?): ProxyCredentials? = when {
    fromService?.isComplete == true -> fromService
    saved?.isComplete == true -> saved
    else -> null
}
