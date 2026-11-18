#include "windows_screen_capture.h"

#include <windows.h>

bool KeqdroidCaptureScreenGray(std::vector<uint8_t>* gray, int* width,
                               int* height) {
  // процесс PerMonitorV2 (runner.exe.manifest), поэтому метрики в физических пикселях всех мониторов
  const int left = ::GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int top = ::GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int w = ::GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int h = ::GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (w <= 0 || h <= 0) return false;

  HDC screen = ::GetDC(nullptr);
  if (screen == nullptr) return false;
  HDC memory = ::CreateCompatibleDC(screen);

  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = w;
  info.bmiHeader.biHeight = -h;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP bitmap = ::CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits,
                                      nullptr, 0);

  bool ok = false;
  if (memory != nullptr && bitmap != nullptr && bits != nullptr) {
    HGDIOBJ previous = ::SelectObject(memory, bitmap);
    // без CAPTUREBLT в кадр не попадают слоистые окна, а предпросмотр картинки в Telegram как раз такой
    ok = ::BitBlt(memory, 0, 0, w, h, screen, left, top,
                  SRCCOPY | CAPTUREBLT) != 0;
    ::SelectObject(memory, previous);
    if (ok) {
      const size_t count = static_cast<size_t>(w) * static_cast<size_t>(h);
      gray->resize(count);
      const auto* bgra = static_cast<const uint8_t*>(bits);
      // как RGBLuminanceSource у zxing и grayFromRgba в Dart: (r + 2g + b) / 4
      for (size_t i = 0; i < count; ++i) {
        const uint8_t* p = bgra + i * 4;
        (*gray)[i] = static_cast<uint8_t>((p[2] + 2 * p[1] + p[0]) >> 2);
      }
      *width = w;
      *height = h;
    }
  }

  if (bitmap != nullptr) ::DeleteObject(bitmap);
  if (memory != nullptr) ::DeleteDC(memory);
  ::ReleaseDC(nullptr, screen);
  return ok;
}
