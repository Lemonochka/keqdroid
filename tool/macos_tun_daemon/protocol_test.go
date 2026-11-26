package main

import (
	"errors"
	"net"
	"sync"
	"testing"
	"time"
)

type fakeCore struct {
	pid        int
	lines      []string
	exitCode   int
	gracefulCh chan bool
	done       chan struct{}
	once       sync.Once
}

func (f *fakeCore) PID() int { return f.pid }

func (f *fakeCore) StartStreaming(onLine func(string), onExit func(int)) {
	go func() {
		for _, l := range f.lines {
			onLine(l)
		}
		<-f.done
		onExit(f.exitCode)
	}()
}

func (f *fakeCore) Stop(graceful bool) {
	f.once.Do(func() {
		f.gracefulCh <- graceful
		close(f.done)
	})
}

func (f *fakeCore) Wait() {
	<-f.done
}

type fakeStarter struct {
	mu      sync.Mutex
	lastReq StartRequest
	nextErr error
	core    *fakeCore
}

func (s *fakeStarter) VersionInfo() (string, string) {
	return "xray-sha", "mihomo-sha"
}

func (s *fakeStarter) Start(req StartRequest) (RunningCore, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastReq = req
	if s.nextErr != nil {
		return nil, s.nextErr
	}
	return s.core, nil
}

func TestProtocolSessionLifecycleAndBusyGuard(t *testing.T) {
	core := &fakeCore{
		pid:        777,
		lines:      []string{"utun99 up"},
		exitCode:   0,
		gracefulCh: make(chan bool, 1),
		done:       make(chan struct{}),
	}
	starter := &fakeStarter{core: core}
	state := NewServerState(starter)

	c1Client, c1Server := net.Pipe()
	defer c1Client.Close()
	go state.ServeClient(c1Server)

	fc1 := NewFrameConn(c1Client)
	if err := fc1.WriteFrame("version"); err != nil {
		t.Fatal(err)
	}
	ver, err := fc1.ReadFrame()
	if err != nil || ver != "version\n1\nxray-sha\nmihomo-sha" {
		t.Fatalf("unexpected version reply: %q, %v", ver, err)
	}

	if err := fc1.WriteFrame("start\nxray\n/app/bin\n/app/geo\n{\"log\":{}}\n"); err != nil {
		t.Fatal(err)
	}
	first, err := fc1.ReadFrame()
	if err != nil || first != "ok\n777" {
		t.Fatalf("expected ok\\n777 first, got %q, %v", first, err)
	}
	out, err := fc1.ReadFrame()
	if err != nil || out != "out\nutun99 up" {
		t.Fatalf("expected core output, got %q, %v", out, err)
	}

	// второе подключение может спросить версию, но не может поднять второе ядро поверх первого
	c2Client, c2Server := net.Pipe()
	defer c2Client.Close()
	go state.ServeClient(c2Server)
	fc2 := NewFrameConn(c2Client)
	if err := fc2.WriteFrame("start\nmihomo\n/app/bin\n/app/geo\n{}"); err != nil {
		t.Fatal(err)
	}
	busy, err := fc2.ReadFrame()
	if err != nil || busy != "error\nthe core is already running" {
		t.Fatalf("expected busy error, got %q, %v", busy, err)
	}

	if err := fc1.WriteFrame("stop"); err != nil {
		t.Fatal(err)
	}
	select {
	case graceful := <-core.gracefulCh:
		if !graceful {
			t.Fatal("expected graceful=true on stop")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for Stop")
	}
	exitFrame, err := fc1.ReadFrame()
	if err != nil || exitFrame != "exit\n0" {
		t.Fatalf("expected exit\\n0, got %q, %v", exitFrame, err)
	}
}

func TestProtocolClientDisconnectKillsCoreAndReleasesBusy(t *testing.T) {
	core := &fakeCore{
		pid:        888,
		exitCode:   1,
		gracefulCh: make(chan bool, 1),
		done:       make(chan struct{}),
	}
	starter := &fakeStarter{core: core}
	state := NewServerState(starter)

	cClient, cServer := net.Pipe()
	doneServe := make(chan struct{})
	go func() {
		state.ServeClient(cServer)
		close(doneServe)
	}()

	fc := NewFrameConn(cClient)
	if err := fc.WriteFrame("start\nmihomo\n/app/bin\n\n{}"); err != nil {
		t.Fatal(err)
	}
	if reply, err := fc.ReadFrame(); err != nil || reply != "ok\n888" {
		t.Fatalf("unexpected start reply: %q, %v", reply, err)
	}

	_ = cClient.Close()
	select {
	case graceful := <-core.gracefulCh:
		if graceful {
			t.Fatal("expected forceful stop on client EOF")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("core was not stopped on client disconnect")
	}
	<-doneServe
	if state.coreBusy.Load() {
		t.Fatal("expected coreBusy to reset after client disconnect")
	}
}

func TestProtocolStartFailureReleasesBusy(t *testing.T) {
	starter := &fakeStarter{nextErr: errors.New("bad config")}
	state := NewServerState(starter)

	cClient, cServer := net.Pipe()
	defer cClient.Close()
	go state.ServeClient(cServer)

	fc := NewFrameConn(cClient)
	_ = fc.WriteFrame("start\nxray\n/app\n\n{}")
	reply, err := fc.ReadFrame()
	if err != nil || reply != "error\nbad config" {
		t.Fatalf("unexpected reply: %q, %v", reply, err)
	}
	if state.coreBusy.Load() {
		t.Fatal("coreBusy remained set after start failure")
	}
}
