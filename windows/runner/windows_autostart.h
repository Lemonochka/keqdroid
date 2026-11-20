#ifndef RUNNER_WINDOWS_AUTOSTART_H_
#define RUNNER_WINDOWS_AUTOSTART_H_

// задача планировщика с HighestAvailable осталась от настройки запуска с правами, TUN без прав теперь поднимает служба;
// новых задач приложение не заводит, старую снимает запущенное ею же, оба вида разом не включаются

// allow_elevation снят на старте приложения. false: задачу не создали или не удалили, ключ Run уже выставлен
bool KeqdroidApplyAutostart(bool enabled, bool elevated, bool allow_elevation);

// перенесли папку, и задача на старый путь уже не автозапуск
bool KeqdroidIsAutostartElevated();

bool KeqdroidIsAutostartEnabled();

// ключ Run на месте, но выключен в Диспетчере задач, и Windows его не запустит
bool KeqdroidIsAutostartBlocked();
// только по нажатию в настройках: на старте приложения выбор пользователя в Диспетчере задач не трогаем
void KeqdroidUnblockAutostart();

// в реестре, а не аргументом в команде автозапуска: задачу планировщика без UAC не переписать
void KeqdroidSetAutostartInTray(bool enabled);
bool KeqdroidAutostartInTray();

// автозапуск портабельной копии мог остаться на другом пути, его не трогаем
void KeqdroidRemoveAutostartOfThisExe();

// задача от портабельной смотрит на её exe, а приложение без UAC её не перепишет
void KeqdroidAdoptElevatedAutostart();

#endif  // RUNNER_WINDOWS_AUTOSTART_H_
