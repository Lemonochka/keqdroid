#include "config_check.h"

#include <cstddef>
#include <initializer_list>

namespace {

struct Policy {
  // пусто: разделы верхнего уровня любые
  std::initializer_list<const char*> top_allowed;
  std::initializer_list<const char*> denied_anywhere;
  bool xray_log;
  bool ascii_keys_only;
};

// разделы, которые пишут config_gen.dart и withXrayDesktopSession; custom_xray_config.dart режет до них же
const Policy kXray = {
    {"log", "inbounds", "outbounds", "routing", "dns", "policy", "stats",
     "metrics", "fakedns", "observatory", "burstobservatory", "version"},
    // script читает файл и гоняет Lua, webhook шлёт наружу, certificateFile и keyFile отдают в TLS любой файл
    {"script", "webhook", "certificatefile", "keyfile"},
    true,
    true,
};

// write-to-system переводит системные часы, сокеты API на диске ложатся по любому пути
const Policy kMihomo = {
    {},
    {"write-to-system", "external-controller-unix", "external-controller-pipe"},
    false,
    false,
};

class Scanner {
 public:
  Scanner(const std::string& text, const Policy& policy)
      : s_(text), policy_(policy) {}

  bool Check() {
    SkipSpace();
    if (Peek() != '{') return false;
    if (!Object(0, true)) return false;
    SkipSpace();
    return i_ == s_.size();
  }

 private:
  bool Object(int depth, bool top) {
    if (depth > 512 || !Consume('{')) return false;
    SkipSpace();
    if (Consume('}')) return true;
    while (true) {
      std::string key;
      bool ascii = true;
      if (!String(&key, &ascii)) return false;
      if (!ascii && policy_.ascii_keys_only) return false;
      const std::string name = Lower(key);
      if (Listed(policy_.denied_anywhere, name)) return false;
      if (top && policy_.top_allowed.size() > 0 &&
          !Listed(policy_.top_allowed, name)) {
        return false;
      }
      SkipSpace();
      if (!Consume(':')) return false;
      SkipSpace();
      const bool ok = top && policy_.xray_log && name == "log"
                          ? LogValue(depth + 1)
                          : Value(depth + 1);
      if (!ok) return false;
      SkipSpace();
      if (Consume(',')) {
        SkipSpace();
        continue;
      }
      return Consume('}');
    }
  }

  // путь в access и error был бы файлом, который SYSTEM запишет где угодно
  bool LogValue(int depth) {
    if (Peek() != '{') return Value(depth);
    ++i_;
    SkipSpace();
    if (Consume('}')) return true;
    while (true) {
      std::string key;
      bool ascii = true;
      if (!String(&key, &ascii) || !ascii) return false;
      const std::string name = Lower(key);
      if (Listed(policy_.denied_anywhere, name)) return false;
      SkipSpace();
      if (!Consume(':')) return false;
      SkipSpace();
      if (name == "access" || name == "error") {
        if (Peek() == 'n') {
          if (!Literal("null")) return false;
        } else {
          std::string value;
          bool value_ascii = true;
          if (!String(&value, &value_ascii)) return false;
          if (!value.empty() && Lower(value) != "none") return false;
        }
      } else if (!Value(depth + 1)) {
        return false;
      }
      SkipSpace();
      if (Consume(',')) {
        SkipSpace();
        continue;
      }
      return Consume('}');
    }
  }

  bool Value(int depth) {
    if (depth > 512) return false;
    const char c = Peek();
    if (c == '{') return Object(depth, false);
    if (c == '[') {
      ++i_;
      SkipSpace();
      if (Consume(']')) return true;
      while (true) {
        if (!Value(depth + 1)) return false;
        SkipSpace();
        if (Consume(',')) {
          SkipSpace();
          continue;
        }
        return Consume(']');
      }
    }
    if (c == '"') {
      std::string ignored;
      bool ascii = true;
      return String(&ignored, &ascii);
    }
    if (c == 't') return Literal("true");
    if (c == 'f') return Literal("false");
    if (c == 'n') return Literal("null");
    return Number();
  }

  bool String(std::string* out, bool* ascii) {
    if (!Consume('"')) return false;
    while (i_ < s_.size()) {
      const unsigned char c = static_cast<unsigned char>(s_[i_++]);
      if (c == '"') return true;
      if (c < 0x20) return false;
      if (c >= 0x80) {
        *ascii = false;
        out->push_back(static_cast<char>(c));
        continue;
      }
      if (c != '\\') {
        out->push_back(static_cast<char>(c));
        continue;
      }
      if (i_ >= s_.size()) return false;
      const char e = s_[i_++];
      switch (e) {
        case '"':
        case '\\':
        case '/':
          out->push_back(e);
          break;
        case 'b':
        case 'f':
        case 'n':
        case 'r':
        case 't':
          out->push_back(' ');
          break;
        case 'u': {
          if (i_ + 4 > s_.size()) return false;
          unsigned code = 0;
          for (int k = 0; k < 4; ++k) {
            const char h = s_[i_++];
            code <<= 4;
            if (h >= '0' && h <= '9') {
              code |= static_cast<unsigned>(h - '0');
            } else if (h >= 'a' && h <= 'f') {
              code |= static_cast<unsigned>(h - 'a' + 10);
            } else if (h >= 'A' && h <= 'F') {
              code |= static_cast<unsigned>(h - 'A' + 10);
            } else {
              return false;
            }
          }
          if (code >= 0x80) {
            *ascii = false;
            out->push_back('?');
          } else {
            out->push_back(static_cast<char>(code));
          }
          break;
        }
        default:
          return false;
      }
    }
    return false;
  }

  bool Number() {
    const std::size_t start = i_;
    while (i_ < s_.size()) {
      const char c = s_[i_];
      if ((c >= '0' && c <= '9') || c == '.' || c == 'e' || c == 'E' ||
          c == '+' || c == '-') {
        ++i_;
      } else {
        break;
      }
    }
    return i_ > start;
  }

  bool Literal(const char* word) {
    for (const char* p = word; *p != '\0'; ++p) {
      if (i_ >= s_.size() || s_[i_] != *p) return false;
      ++i_;
    }
    return true;
  }

  // комментарии xray понимает, но генератор приложения их не пишет: с ними конфиг не пропускаем
  void SkipSpace() {
    while (i_ < s_.size()) {
      const char c = s_[i_];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        ++i_;
      } else {
        break;
      }
    }
  }

  bool Consume(char c) {
    if (i_ < s_.size() && s_[i_] == c) {
      ++i_;
      return true;
    }
    return false;
  }

  char Peek() const { return i_ < s_.size() ? s_[i_] : '\0'; }

  static bool Listed(std::initializer_list<const char*> list,
                     const std::string& name) {
    for (const char* item : list) {
      if (name == item) return true;
    }
    return false;
  }

  static std::string Lower(const std::string& v) {
    std::string out = v;
    for (char& c : out) {
      if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    }
    return out;
  }

  const std::string& s_;
  const Policy& policy_;
  std::size_t i_ = 0;
};

std::string WithoutBom(const std::string& json) {
  if (json.size() >= 3 && static_cast<unsigned char>(json[0]) == 0xEF &&
      static_cast<unsigned char>(json[1]) == 0xBB &&
      static_cast<unsigned char>(json[2]) == 0xBF) {
    return json.substr(3);
  }
  return json;
}

}  // namespace

bool XrayConfigIsSafe(const std::string& json) {
  const std::string body = WithoutBom(json);
  return Scanner(body, kXray).Check();
}

bool MihomoConfigIsSafe(const std::string& json) {
  const std::string body = WithoutBom(json);
  return Scanner(body, kMihomo).Check();
}
