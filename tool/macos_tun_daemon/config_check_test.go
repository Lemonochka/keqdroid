package main

import "testing"

func TestXrayConfigIsSafe(t *testing.T) {
	valid := `{
		"log": {"loglevel": "warning", "access": "none", "error": ""},
		"inbounds": [{"tag": "tun-in", "protocol": "tun", "port": 0}],
		"outbounds": [{"tag": "proxy", "protocol": "vless"}],
		"routing": {"domainStrategy": "AsIs", "rules": []},
		"dns": {"servers": ["1.1.1.1"]},
		"fakedns": [{"ipPool": "198.18.0.0/15", "poolSize": 65535}],
		"policy": {"levels": {"1": {"connIdle": 60}}}
	}`
	if !XrayConfigIsSafe(valid) {
		t.Fatal("expected valid xray config to pass")
	}
	if !XrayConfigIsSafe("\xEF\xBB\xBF" + valid) {
		t.Fatal("expected UTF-8 BOM to be accepted")
	}

	cases := []struct {
		name string
		cfg  string
	}{
		{"log access file", `{"log": {"access": "/tmp/a.log"}}`},
		{"log error file", `{"log": {"Error": "/etc/shadow"}}`},
		{"top-level env", `{"env": {"XRAY_LOCATION_ASSET": "/etc"}}`},
		{"top-level api", `{"api": {"tag": "api"}}`},
		{"top-level geodata", `{"geodata": {"file": "/tmp/x"}}`},
		{"routing script", `{"routing": {"script": "a.lua"}}`},
		{"rule webhook", `{"routing": {"rules": [{"webhook": {"url": "http://x"}}]}}`},
		{"tls keyFile", `{"outbounds": [{"streamSettings": {"tlsSettings": {"certificates": [{"keyFile": "/etc/k"}]}}}]}`},
		{"tls certificateFile", `{"outbounds": [{"streamSettings": {"tlsSettings": {"certificates": [{"CertificateFile": "/etc/c"}]}}}]}`},
		{"escaped denied key", `{"outbounds": [{"\u006beyFile": "/etc/k"}]}`},
		{"non-ascii key", `{"\u0430pi": {}}`},
		{"json comment", "{\"log\": {} // comment\n}"},
		{"trailing bytes", `{"log": {}} extra`},
		{"array root", `[]`},
	}
	for _, tc := range cases {
		if XrayConfigIsSafe(tc.cfg) {
			t.Errorf("%s should be rejected: %s", tc.name, tc.cfg)
		}
	}
}

func TestMihomoConfigIsSafe(t *testing.T) {
	valid := `{
		"socks-port": 2080,
		"port": 2081,
		"tun": {"enable": true, "device": "utun99", "stack": "gvisor", "dns-mode": "hijack"},
		"proxies": [{"name": "Тест узел", "type": "vless"}]
	}`
	if !MihomoConfigIsSafe(valid) {
		t.Fatal("expected valid mihomo config to pass")
	}

	for _, bad := range []string{
		`{"ntp": {"write-to-system": true}}`,
		`{"external-controller-unix": "/var/run/x.sock"}`,
		`{"External-Controller-Pipe": "\\\\.\\pipe\\x"}`,
		`{"\u0077rite-to-system": true}`,
	} {
		if MihomoConfigIsSafe(bad) {
			t.Errorf("expected unsafe mihomo config to be rejected: %s", bad)
		}
	}
}
