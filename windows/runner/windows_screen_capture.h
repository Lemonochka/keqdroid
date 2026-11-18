#ifndef RUNNER_WINDOWS_SCREEN_CAPTURE_H_
#define RUNNER_WINDOWS_SCREEN_CAPTURE_H_

#include <cstdint>
#include <vector>

// всё виртуальное пространство мониторов в оттенках серого: QR может лежать на любом из них
bool KeqdroidCaptureScreenGray(std::vector<uint8_t>* gray, int* width,
                               int* height);

#endif  // RUNNER_WINDOWS_SCREEN_CAPTURE_H_
