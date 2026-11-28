# keqdroid

Xray-core ve mihomo üzerine kurulu Android, Android TV, Windows, Linux ve macOS için proxy ve VPN istemcisi. keqdroid; abonelikleri, sunucu yapılandırmalarını ve trafik yönlendirmesini tek bir uygulamada yönetir.

[![Release](https://img.shields.io/github/v/release/Lemonochka/keqdroid?label=release)](https://github.com/Lemonochka/keqdroid/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/Lemonochka/keqdroid/ci.yml?branch=master&label=build)](https://github.com/Lemonochka/keqdroid/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-chat-26A5E4?logo=telegram&logoColor=white)](https://t.me/keqdroid)

[English](README.md) | [Русский](README.ru.md) | Türkçe

keqdroid sunucu sağlamaz. Seçtiğiniz bir sağlayıcıdan bir abonelik veya sunucu yapılandırması gerektirir. Ülkenizin yasalarına uymaktan siz sorumlusunuz.

https://github.com/user-attachments/assets/e1f899dd-4f2c-4ca2-896c-1da64a3a5645

## İndirme

Derlemeler [Releases](https://github.com/Lemonochka/keqdroid/releases) sayfasında yayımlanır.

| Platform | Paket |
|----------|-------|
| Android 7.0 ve üzeri, Android TV | `keqdroid-<version>-android.apk` |
| Android 7.0 ve üzeri, 32-bit yazılım | `keqdroid-<version>-armeabi-v7a-android.apk` |
| Windows x64 | `keqdroid-windows-x64-<version>-setup.exe` (kurulum dosyası) |
| Windows x64 | `keqdroid-windows-x64-<version>.zip` (taşınabilir) |
| Linux x86_64 | `.AppImage`, `.deb`, `.rpm`, `.tar.gz`, `PKGBUILD` |
| macOS 13 ve üzeri, Apple Silicon | `keqdroid-<version>-macos-arm64.dmg` |
| macOS 13 ve üzeri, Intel | `keqdroid-<version>-macos-x86_64.dmg` |

Her sürümde tüm dosyaların karma değerlerini içeren `SHA256SUMS` ve imzasını içeren `SHA256SUMS.sig` dosyaları bulunur. Yerleşik güncelleyici bir güncellemeyi yüklemeden önce her ikisini de doğrular.

## Özellikler

**Sunucular ve abonelikler**

- URL ile veya bir sağlayıcı panelinden `keqdroid://` bağlantısı aracılığıyla eklenen, zamanlanmış güncellemelere sahip abonelikler
- Bağlantılardan, dosyalardan, panodan veya QR koddan eklenen sunucular
- Belirli bir sırayla birden fazla sunucu üzerinden proxy zincirleri
- Hariç tutulabilecek sunucularla birlikte bir abonelik içinde otomatik sunucu seçimi
- Her abonelik için ayrı cihaz kimliği
- Sağlayıcı taşıdığında aboneliği yeni adrese takip eder ve ana adres kullanılamadığında sağlayıcının yedek adresini kullanır
- TCP, HTTP ve ICMP gecikme testleri ile hız testleri

**Yönlendirme**

- Bir hedefi engelleyen, doğrudan gönderen, tünelden geçiren veya başka bir sunucu üzerinden yönlendiren kurallar
- Alan adı, IP adresi, yerleşik liste veya URL üzerinden AdBlock ya da hosts listesiyle tanımlanan hedefler
- Seçili uygulamalar, TCP veya UDP ve bağlantı noktalarıyla sınırlandırılmış kurallar
- Sağlayıcı tarafından sağlanan profiller dahil olmak üzere abonelik başına yönlendirme profilleri
- Bağlantı veya QR kod olarak paylaşılan profiller; Happ ve Incy yönlendirme bağlantıları kabul edilir
- Android'de uygulamaya göre, Windows, Linux ve macOS'ta programa göre bölünmüş tünelleme (split tunneling)
- Her birine uygulanan kuralla birlikte canlı bağlantı listesi

**Uygulama**

- Açık ve koyu temalar, renk ön ayarları ve Android'de Material You
- %70'ten %140'a kadar arayüz ölçeği; tabletler ve yatay görünüm için uyarlanabilir düzen
- Ayarların, sunucuların ve aboneliklerin şifreli yedekleri ve QR kod ile başka bir cihaza aktarım
- LAN üzerinden yerel proxy paylaşımı
- Ana eylemler için kısayol tuşları
- GitHub Releases üzerinden imzalı güncellemeler
- İngilizce, Rusça, Almanca, Çince ve Farsça

## Desteklenen biçimler

| Protokol veya biçim | İçe aktarma | Çekirdek |
|---------------------|-------------|----------|
| VLESS | `vless://` | Xray, mihomo |
| VMess | `vmess://` | Xray, mihomo |
| Trojan | `trojan://` | Xray, mihomo |
| Shadowsocks | `ss://` | Xray, mihomo |
| Hysteria 2 | `hysteria2://`, `hy2://` | Xray, mihomo |
| SOCKS5 | `socks://`, `socks5://`, `socks5h://` | Xray, mihomo |
| ShadowsocksR | `ssr://` | mihomo |
| TUIC | `tuic://` | mihomo |
| AnyTLS | `anytls://` | mihomo |
| Mieru | `mierus://` | mihomo |
| WireGuard, AmneziaWG | `.conf` dosyası; `wg://`, `awg://`, `wireguard://` | mihomo |
| Xray yapılandırması | JSON dosyası, yapıştırma veya abonelik | Xray |
| Clash veya mihomo yapılandırması | YAML dosyası, yapıştırma veya abonelik | mihomo |

Her iki çekirdeğin de desteklediği sunucular için çekirdek Settings → About altından seçilir; varsayılan Xray'dir. Yalnızca bir çekirdekte bulunan bir aktarım türünü kullanan sunucu o çekirdekte çalışır.

Clash ve sing-box yapılandırmaları tek tek sunucular olarak içe aktarılır. Proxy grupları içeren bir mihomo şablonu sağlayan abonelikler bu grupları korur ve mihomo üzerinde çalışır.

Hazır bir yapılandırma kendi yönlendirme, DNS ve giden (outbound) ayarlarını korur. Gelen (inbound) bağlantılar ve günlük kaydı uygulama tarafından yönetilir ve bağlantıdan ziyade cihaza etki eden bölümler kaldırılır.

## Platformlar

| Platform | Mod | Açıklama | İzinler |
|----------|-----|----------|---------|
| Android | VPN | Tüm cihaz trafiği tünelden geçer | İlk bağlantıda VPN izni |
| Android | Proxy | `127.0.0.1` üzerinde yerel SOCKS ve HTTP proxy | Yok |
| Windows | Proxy | Sistem proxy'si | Yok |
| Windows | TUN | Tüm trafik sanal bir bağdaştırıcıdan geçer | keqdroid servisini kurmak için bir kez Yönetici izni |
| Linux | Proxy | GNOME ve KDE'de sistem proxy'si; diğerlerinde elle kurulum | Yok |
| Linux | TUN | Tüm trafik sanal bir bağdaştırıcıdan geçer | `pkexec` ile Root veya Settings → Advanced → Permissions altında Parolasız TUN |
| macOS | Proxy | `networksetup` aracılığıyla sistem proxy'si | Yok |
| macOS | TUN | Tüm trafik bir `utun` bağdaştırıcısından geçer | keqdroid servisini kurmak için bir kez Yönetici izni |

**Android.** Bağlantı bildirimden, Hızlı Ayarlar kutucuğundan, ana ekran aracından ve başlatıcı kısayollarından kontrol edilebilir. Uygulama bazlı yönlendirme ve DNS yakalama için VPN modu gerekir. Etkin bir VPN oturumu uygulama güncellemesinden veya cihaz yeniden başlatıldıktan sonra devam eder.

**Android TV.** Uygulama uzaktan kumanda ile kullanılır. TV'deki bir QR kod taranarak telefondaki keqdroid'den abonelik gönderilebilir.

**Windows.** Kurulum programı uygulamayı Program Files içine yerleştirir ve verileriyle birlikte kaldırabilir; taşınabilir sürüm herhangi bir klasörden çalışır. Uygulama sistemle birlikte başlayabilir, otomatik bağlanabilir ve sistem tepsisinde kalabilir. Ayarlar `%APPDATA%\com.keqdroid\keqdroid\` konumunda saklanır ve her iki sürüm tarafından paylaşılır.

**Linux.** Uygulama oturum açılışında başlayabilir ve otomatik bağlanabilir. Arch Linux'ta sürümdeki `PKGBUILD` dosyasını kullanarak `makepkg -si` ile kurun. NixOS'ta flake girdilerine `github:Lemonochka/keqdroid/nix` ekleyin, `inputs.keqdroid.nixosModules.default` modülünü içe aktarın ve `programs.keqdroid.enable = true` ayarını yapın (Hyprland veya Sway gibi bağımsız Wayland bileştiricilerinde TUN modu için bir polkit kimlik doğrulama aracısını da çalışır durumda tutun).

**macOS.** Apple Silicon ve Intel için ayrı derlemeler sağlanır. Uygulama oturum açılışında başlayabilir, otomatik bağlanabilir ve menü çubuğunda kalabilir.

## Başlarken

1. **Subscriptions** bölümünü açın, abonelik URL'sini yapıştırın ve **Add & Fetch** seçeneğini seçin.
2. **Servers** bölümünü açın ve bir sunucu seçin.
3. Bağlan düğmesine basın.

Yönlendirme, bölünmüş tünelleme, bağlantı modu ve diğer seçenekler **Settings** içinde yer alır.

## Belgeler

Ayrıntılı belgelere [kequinq.art/docs/keqdroid](https://kequinq.art/docs/keqdroid/en/) adresinden ulaşabilirsiniz:

- [Yönlendirme](https://kequinq.art/docs/keqdroid/en/routing) ve [DNS](https://kequinq.art/docs/keqdroid/en/dns)
- [Bağlantı modları ve bölünmüş tünelleme](https://kequinq.art/docs/keqdroid/en/modes)
- [Xray veya mihomo](https://kequinq.art/docs/keqdroid/en/xray-or-mihomo) ve [mihomo grupları](https://kequinq.art/docs/keqdroid/en/mihomo-groups)
- [Otomatik sunucu seçimi](https://kequinq.art/docs/keqdroid/en/auto) ve [sunucu kontrolleri](https://kequinq.art/docs/keqdroid/en/ping)
- Sağlayıcılar için: [abonelik üstbilgileri](https://kequinq.art/docs/keqdroid/en/provider/headers) ve [bağlantılar](https://kequinq.art/docs/keqdroid/en/provider/links)

## Gizlilik

keqdroid'in kendi sunucusu yoktur ve kullanım istatistiği toplamaz. Şuralara bağlanır:

- **eklediğiniz abonelikler, sunucular ve kural listeleri.** Bir abonelik isteği; abonelik panellerinin cihaz sayısını sınırlamak için kullandığı bir cihaz kimliği, işletim sistemi adı/sürümü ve cihaz modelini taşır. Bunu Settings → Advanced → *Share device HWID* altından kapatabilirsiniz;
- **GitHub** (`api.github.com`, `github.com`): uygulama başladığında veya ön plana geldiğinde güncelleme kontrolleri, güncelleme indirmeleri ve istediğinizde Android'deki tam coğrafi konum veritabanı için;
- **`www.cloudflare.com/cdn-cgi/trace`**: çıkış ülkesini göstermek için bağlı sunucu üzerinden;
- **`ipv6.google.com`**: TUN ayarlarında IPv6 *Through the VPN* olarak ayarlandığında, IPv6 destekli sunucuları bulmak için bir gecikme testinden sonra ve günde en fazla bir kez her sunucu üzerinden;
- **gecikme testi adresi** sunucular test edildiğinde: varsayılan olarak `connectivitycheck.gstatic.com`, ayarlardan değiştirilebilir; hız testi çalıştırdığınızda **`speed.cloudflare.com`**.

Çökme raporları hiçbir yere gönderilmez: hatalar yalnızca cihazdaki uygulama günlüğüne yazılır.

## Kod imzalama politikası

Ücretsiz kod imzalama [SignPath.io](https://signpath.io) tarafından, sertifika ise [SignPath Foundation](https://signpath.org) tarafından sağlanmaktadır. İmzalama kurulum aşamasındadır; etkinleştirilene kadar Windows derlemeleri imzalanmamıştır.

macOS derlemeleri ad-hoc olarak imzalanmıştır ve Apple tarafından noter onaylı değildir.

- Katkı yapanlar ve inceleyenler: [Lemonochka](https://github.com/Lemonochka)
- Onaylayanlar: [Lemonochka](https://github.com/Lemonochka)

0.35.0 sonrası sürümler bu depodan [GitHub Actions](.github/workflows/release.yml) tarafından derlenir. `gh attestation verify <file> --repo Lemonochka/keqdroid` komutu bir dosyanın o derlemeden geldiğini doğrular. İmzalama `keqdroid.exe` ve kurulum dosyasını kapsar; paketlenmiş `xray.exe` ve `mihomo.exe` dosyaları yukarı akış Xray-core ve mihomo derlemeleridir.

## Güvenlik

Güvenlik açıklarını [SECURITY.md](SECURITY.md) dosyasında açıklandığı şekilde bildirin.

## Kaynak koddan derleme

```bash
flutter pub get
flutter build apk --debug        # Android
flutter build windows --release  # Windows
flutter build linux --release    # Linux
flutter build macos --release    # macOS; önce macOS çekirdeklerini derleyin
```

Bir yayın APK'sı için `android/key.properties` içinde bir imzalama anahtarı gerekir. Android, Windows ve Linux için önceden derlenmiş çekirdekler dahildir; macOS çekirdeklerini `tool/build_macos_cores.sh` ile derleyin. Linux ve macOS derlemeleri, çekirdeklerin yeniden derlenmesi, testler ve yayın süreci [docs/BUILD.md](docs/BUILD.md) dosyasında açıklanmıştır.

## Topluluk

Sorular ve tartışmalar için: [Telegram sohbeti](https://t.me/keqdroid).

## Lisans

keqdroid [AGPL-3.0](LICENSE) altında lisanslanmıştır. Paketlenmiş çekirdekler kendi yukarı akış lisanslarını korur: Xray-core (MPL-2.0) ve mihomo (GPL-3.0).
