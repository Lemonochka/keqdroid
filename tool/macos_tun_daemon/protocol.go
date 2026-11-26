package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
)

const (
	protocolVersion = 1
	maxFrameBytes   = 64 << 20
)

type StartRequest struct {
	Kind   string
	AppDir string
	GeoDir string
	Config string
}

func ParseStartRequest(payload string) (StartRequest, bool) {
	parts := splitLinesN(payload, 5)
	if len(parts) != 5 || parts[0] != "start" {
		return StartRequest{}, false
	}
	req := StartRequest{
		Kind:   parts[1],
		AppDir: parts[2],
		GeoDir: parts[3],
		Config: parts[4],
	}
	if req.Kind != "xray" && req.Kind != "mihomo" {
		return StartRequest{}, false
	}
	return req, true
}

func splitLinesN(s string, maxParts int) []string {
	parts := make([]string, 0, maxParts)
	start := 0
	for len(parts)+1 < maxParts {
		nl := strings.IndexByte(s[start:], '\n')
		if nl < 0 {
			break
		}
		parts = append(parts, s[start:start+nl])
		start += nl + 1
	}
	parts = append(parts, s[start:])
	return parts
}

type FrameConn struct {
	rw      io.ReadWriteCloser
	writeMu sync.Mutex
}

func NewFrameConn(rw io.ReadWriteCloser) *FrameConn {
	return &FrameConn{rw: rw}
}

func (c *FrameConn) ReadFrame() (string, error) {
	var hdr [4]byte
	if _, err := io.ReadFull(c.rw, hdr[:]); err != nil {
		return "", err
	}
	n := binary.LittleEndian.Uint32(hdr[:])
	if n > maxFrameBytes {
		return "", errors.New("frame exceeds maximum size")
	}
	if n == 0 {
		return "", nil
	}
	buf := make([]byte, n)
	if _, err := io.ReadFull(c.rw, buf); err != nil {
		return "", err
	}
	return string(buf), nil
}

func (c *FrameConn) WriteFrame(frame string) error {
	if len(frame) > maxFrameBytes {
		return errors.New("frame exceeds maximum size")
	}
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	buf := make([]byte, 4+len(frame))
	binary.LittleEndian.PutUint32(buf[:4], uint32(len(frame)))
	copy(buf[4:], frame)
	_, err := c.rw.Write(buf)
	return err
}

func (c *FrameConn) Close() error {
	return c.rw.Close()
}

type RunningCore interface {
	PID() int
	StartStreaming(onLine func(string), onExit func(int))
	Stop(graceful bool)
	Wait()
}

type CoreStarter interface {
	VersionInfo() (xraySHA, mihomoSHA string)
	Start(req StartRequest) (RunningCore, error)
}

type ServerState struct {
	starter  CoreStarter
	coreBusy atomic.Bool
}

func NewServerState(starter CoreStarter) *ServerState {
	return &ServerState{starter: starter}
}

func (s *ServerState) ServeClient(raw io.ReadWriteCloser) {
	fc := NewFrameConn(raw)
	var (
		ownsCore  atomic.Bool
		activeMu  sync.Mutex
		active    RunningCore
		activeGen uint64
	)
	releaseBusy := func() {
		if ownsCore.Swap(false) {
			s.coreBusy.Store(false)
		}
	}
	getActive := func() RunningCore {
		activeMu.Lock()
		defer activeMu.Unlock()
		return active
	}
	for {
		frame, err := fc.ReadFrame()
		if err != nil {
			break
		}
		switch {
		case frame == "version":
			xSHA, mSHA := s.starter.VersionInfo()
			_ = fc.WriteFrame(fmt.Sprintf("version\n%d\n%s\n%s", protocolVersion, xSHA, mSHA))
		case strings.HasPrefix(frame, "start\n"):
			req, ok := ParseStartRequest(frame)
			if !ok {
				_ = fc.WriteFrame("error\nbad start request")
				continue
			}
			if ownsCore.Load() || !s.coreBusy.CompareAndSwap(false, true) {
				_ = fc.WriteFrame("error\nthe core is already running")
				continue
			}
			ownsCore.Store(true)
			core, err := s.starter.Start(req)
			if err != nil {
				ownsCore.Store(false)
				s.coreBusy.Store(false)
				_ = fc.WriteFrame("error\n" + err.Error())
				continue
			}
			activeMu.Lock()
			activeGen++
			myGen := activeGen
			active = core
			activeMu.Unlock()
			if err := fc.WriteFrame("ok\n" + strconv.Itoa(core.PID())); err != nil {
				break
			}
			core.StartStreaming(
				func(line string) { _ = fc.WriteFrame("out\n" + line) },
				func(code int) {
					activeMu.Lock()
					if activeGen == myGen {
						active = nil
					}
					activeMu.Unlock()
					// reconnect по новому сокету не должен упираться в coreBusy после завершения прошлого ядра
					releaseBusy()
					_ = fc.WriteFrame("exit\n" + strconv.Itoa(code))
				},
			)
		case frame == "stop":
			if cur := getActive(); cur != nil {
				go cur.Stop(true)
			}
		case frame == "kill":
			if cur := getActive(); cur != nil {
				go cur.Stop(false)
			}
		default:
			_ = fc.WriteFrame("error\nunknown command")
		}
	}

	// сокет закрываем до Wait, чтобы поток чтения stdout ядра не завис на записи ушедшему клиенту
	cur := getActive()
	if cur != nil {
		cur.Stop(false)
	}
	_ = fc.Close()
	if cur != nil {
		cur.Wait()
	}
	releaseBusy()
}
