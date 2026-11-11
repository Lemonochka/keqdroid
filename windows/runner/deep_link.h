#ifndef RUNNER_DEEP_LINK_H_
#define RUNNER_DEEP_LINK_H_

#include <windows.h>

#include <string>

// без регистрации кнопка добавить в клиент на странице панели ничего не открывает. HKCU, без админа
void KeqdroidRegisterUrlProtocols();

// только схемы, ведущие в этот exe: портабельная копия могла перехватить их на себя
void KeqdroidUnregisterUrlProtocols();

std::string KeqdroidDeepLinkFromCommandLine();

bool KeqdroidForwardDeepLinkToRunningInstance(HWND target,
                                              const std::string& url);

// пропуск через UIPI: в TUN приложение перезапускается админом, а браузер нет, и его WM_COPYDATA пропал бы молча
void KeqdroidAllowDeepLinkMessages(HWND hwnd);

// false: сообщение чужое, его надо пропустить дальше
bool KeqdroidDeepLinkFromCopyData(LPARAM lparam, std::string* url);

#endif  // RUNNER_DEEP_LINK_H_
