#ifndef RUNNER_WINDOWS_AUTOSTART_H_
#define RUNNER_WINDOWS_AUTOSTART_H_

// обычный автозапуск через HKCU Run стартует без прав, и для TUN пришлось бы жать UAC после каждого входа.
// задача планировщика с HighestAvailable стартует с правами, платится одним UAC при создании. оба вида разом не включаются

// allow_elevation снят на старте приложения. false: задачу не создали или не удалили, ключ Run уже выставлен
bool KeqdroidApplyAutostart(bool enabled, bool elevated, bool allow_elevation);

// перенесли папку, и задача на старый путь уже не автозапуск
bool KeqdroidIsAutostartElevated();

bool KeqdroidIsAutostartEnabled();

// в реестре, а не аргументом в команде автозапуска: задачу планировщика без UAC не переписать
void KeqdroidSetAutostartInTray(bool enabled);
bool KeqdroidAutostartInTray();

// автозапуск портабельной копии мог остаться на другом пути, его не трогаем
void KeqdroidRemoveAutostartOfThisExe();

// задача от портабельной смотрит на её exe, а приложение без UAC её не перепишет
void KeqdroidAdoptElevatedAutostart();

#endif  // RUNNER_WINDOWS_AUTOSTART_H_
