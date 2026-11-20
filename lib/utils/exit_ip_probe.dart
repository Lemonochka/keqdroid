// Без особого правила запрос шёл бы по правилам пользователя, и при всём остальном напрямую флаг показывал
// домашний адрес. Сам сайт Cloudflare, а не one.one.one.one: тот ещё и DNS, и правило задело бы Частный DNS Android
const kExitIpProbeHost = 'www.cloudflare.com';

const kExitIpProbeUrl = 'https://$kExitIpProbeHost/cdn-cgi/trace';
