#ifndef KEQDROID_TUN_CONFIG_CHECK_H_
#define KEQDROID_TUN_CONFIG_CHECK_H_

#include <string>

// ядро от имени SYSTEM исполняет конфиг любого процесса этого пользователя. пропускаем только разделы,
// которые пишет само приложение: файлы лога, geodata, env, api, script, webhook и чтение ключей с диска выпадают.
// encoding/json сверяет ключи без учёта регистра, поэтому сравнение такое же, а не-ASCII в ключах отклоняется
bool XrayConfigIsSafe(const std::string& json);

// mihomo держит пути внутри своего дома сам; отклоняем то, что меняет систему или открывает сокет на диске
bool MihomoConfigIsSafe(const std::string& json);

#endif  // KEQDROID_TUN_CONFIG_CHECK_H_
