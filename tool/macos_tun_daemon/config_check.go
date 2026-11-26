package main

import "strings"

type configPolicy struct {
	topAllowed     map[string]struct{}
	deniedAnywhere map[string]struct{}
	xrayLog        bool
	asciiKeysOnly  bool
}

// те же правила, что в windows/tun_service/config_check.cpp
var xrayPolicy = configPolicy{
	topAllowed: setOf(
		"log", "inbounds", "outbounds", "routing", "dns", "policy",
		"stats", "metrics", "fakedns", "observatory", "burstobservatory", "version",
	),
	deniedAnywhere: setOf("script", "webhook", "certificatefile", "keyfile"),
	xrayLog:        true,
	asciiKeysOnly:  true,
}

var mihomoPolicy = configPolicy{
	deniedAnywhere: setOf(
		"write-to-system",
		"external-controller-unix",
		"external-controller-pipe",
	),
}

func setOf(items ...string) map[string]struct{} {
	m := make(map[string]struct{}, len(items))
	for _, it := range items {
		m[it] = struct{}{}
	}
	return m
}

func XrayConfigIsSafe(raw string) bool {
	s := scanner{s: withoutBOM(raw), policy: xrayPolicy}
	return s.check()
}

func MihomoConfigIsSafe(raw string) bool {
	s := scanner{s: withoutBOM(raw), policy: mihomoPolicy}
	return s.check()
}

func withoutBOM(s string) string {
	if len(s) >= 3 && s[0] == 0xEF && s[1] == 0xBB && s[2] == 0xBF {
		return s[3:]
	}
	return s
}

type scanner struct {
	s      string
	policy configPolicy
	i      int
}

func (sc *scanner) check() bool {
	sc.skipSpace()
	if sc.peek() != '{' {
		return false
	}
	if !sc.object(0, true) {
		return false
	}
	sc.skipSpace()
	return sc.i == len(sc.s)
}

func (sc *scanner) object(depth int, top bool) bool {
	if depth > 512 || !sc.consume('{') {
		return false
	}
	sc.skipSpace()
	if sc.consume('}') {
		return true
	}
	for {
		key, ascii, ok := sc.readString()
		if !ok || (!ascii && sc.policy.asciiKeysOnly) {
			return false
		}
		name := asciiLower(key)
		if _, denied := sc.policy.deniedAnywhere[name]; denied {
			return false
		}
		if top && len(sc.policy.topAllowed) > 0 {
			if _, allowed := sc.policy.topAllowed[name]; !allowed {
				return false
			}
		}
		sc.skipSpace()
		if !sc.consume(':') {
			return false
		}
		sc.skipSpace()
		if top && sc.policy.xrayLog && name == "log" {
			ok = sc.logValue(depth + 1)
		} else {
			ok = sc.value(depth + 1)
		}
		if !ok {
			return false
		}
		sc.skipSpace()
		if sc.consume(',') {
			sc.skipSpace()
			continue
		}
		return sc.consume('}')
	}
}

func (sc *scanner) logValue(depth int) bool {
	if sc.peek() != '{' {
		return sc.value(depth)
	}
	sc.i++
	sc.skipSpace()
	if sc.consume('}') {
		return true
	}
	for {
		key, ascii, ok := sc.readString()
		if !ok || !ascii {
			return false
		}
		name := asciiLower(key)
		if _, denied := sc.policy.deniedAnywhere[name]; denied {
			return false
		}
		sc.skipSpace()
		if !sc.consume(':') {
			return false
		}
		sc.skipSpace()
		if name == "access" || name == "error" {
			if sc.peek() == 'n' {
				if !sc.literal("null") {
					return false
				}
			} else {
				val, _, ok := sc.readString()
				if !ok || (val != "" && asciiLower(val) != "none") {
					return false
				}
			}
		} else if !sc.value(depth + 1) {
			return false
		}
		sc.skipSpace()
		if sc.consume(',') {
			sc.skipSpace()
			continue
		}
		return sc.consume('}')
	}
}

func (sc *scanner) value(depth int) bool {
	if depth > 512 {
		return false
	}
	switch sc.peek() {
	case '{':
		return sc.object(depth, false)
	case '[':
		sc.i++
		sc.skipSpace()
		if sc.consume(']') {
			return true
		}
		for {
			if !sc.value(depth + 1) {
				return false
			}
			sc.skipSpace()
			if sc.consume(',') {
				sc.skipSpace()
				continue
			}
			return sc.consume(']')
		}
	case '"':
		_, _, ok := sc.readString()
		return ok
	case 't':
		return sc.literal("true")
	case 'f':
		return sc.literal("false")
	case 'n':
		return sc.literal("null")
	default:
		return sc.number()
	}
}

func (sc *scanner) readString() (string, bool, bool) {
	if !sc.consume('"') {
		return "", false, false
	}
	var out strings.Builder
	ascii := true
	for sc.i < len(sc.s) {
		c := sc.s[sc.i]
		sc.i++
		if c == '"' {
			return out.String(), ascii, true
		}
		if c < 0x20 {
			return "", false, false
		}
		if c >= 0x80 {
			ascii = false
			out.WriteByte(c)
			continue
		}
		if c != '\\' {
			out.WriteByte(c)
			continue
		}
		if sc.i >= len(sc.s) {
			return "", false, false
		}
		e := sc.s[sc.i]
		sc.i++
		switch e {
		case '"', '\\', '/':
			out.WriteByte(e)
		case 'b', 'f', 'n', 'r', 't':
			out.WriteByte(' ')
		case 'u':
			if sc.i+4 > len(sc.s) {
				return "", false, false
			}
			var code uint32
			for k := 0; k < 4; k++ {
				h := sc.s[sc.i]
				sc.i++
				code <<= 4
				switch {
				case h >= '0' && h <= '9':
					code |= uint32(h - '0')
				case h >= 'a' && h <= 'f':
					code |= uint32(h - 'a' + 10)
				case h >= 'A' && h <= 'F':
					code |= uint32(h - 'A' + 10)
				default:
					return "", false, false
				}
			}
			if code >= 0x80 {
				ascii = false
				out.WriteByte('?')
			} else {
				out.WriteByte(byte(code))
			}
		default:
			return "", false, false
		}
	}
	return "", false, false
}

func (sc *scanner) number() bool {
	start := sc.i
	for sc.i < len(sc.s) {
		c := sc.s[sc.i]
		if (c >= '0' && c <= '9') || c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-' {
			sc.i++
		} else {
			break
		}
	}
	return sc.i > start
}

func (sc *scanner) literal(word string) bool {
	if len(sc.s)-sc.i < len(word) || sc.s[sc.i:sc.i+len(word)] != word {
		return false
	}
	sc.i += len(word)
	return true
}

func (sc *scanner) skipSpace() {
	for sc.i < len(sc.s) {
		switch sc.s[sc.i] {
		case ' ', '\t', '\n', '\r':
			sc.i++
		default:
			return
		}
	}
}

func (sc *scanner) consume(c byte) bool {
	if sc.i < len(sc.s) && sc.s[sc.i] == c {
		sc.i++
		return true
	}
	return false
}

func (sc *scanner) peek() byte {
	if sc.i < len(sc.s) {
		return sc.s[sc.i]
	}
	return 0
}

func asciiLower(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		b.WriteByte(c)
	}
	return b.String()
}
