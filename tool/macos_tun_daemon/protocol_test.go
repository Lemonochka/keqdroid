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

type blockingStopCore struct {
	pid        int
	gracefulIn chan struct{}
	killIn     chan struct{}
	done       chan struct{}
	killOnce   sync.Once
}

func (b *blockingStopCore) PID() int { return b.pid }

func (b *blockingStopCore) StartStreaming(onLine func(string), onExit func(int)) {
	go func() {
		<-b.done
		onExit(137)
	}()
}

func (b *blockingStopCore) Stop(graceful bool) {
	if graceful {
		select {
		case b.gracefulIn <- struct{}{}:
		default:
		}
		// Simulate a 5s graceful shutdown that hangs until killed.
		<-b.done
		return
	}
	b.killOnce.Do(func() {
		close(b.killIn)
		close(b.done)
	})
}

func (b *blockingStopCore) Wait() {
	<-b.done
}

type queuedStarter struct {
	mu    sync.Mutex
	cores []RunningCore
}

func (s *queuedStarter) VersionInfo() (string, string) { return "x", "m" }

func (s *queuedStarter) Start(req StartRequest) (RunningCore, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.cores) == 0 {
		return nil, errors.New("no queued core")
	}
	c := s.cores[0]
	s.cores = s.cores[1:]
	return c, nil
}

func TestProtocolQuickReconnectAfterExitDoesNotRaceBusy(t *testing.T) {
	core1 := &fakeCore{
		pid:        101,
		exitCode:   0,
		gracefulCh: make(chan bool, 1),
		done:       make(chan struct{}),
	}
	core2 := &fakeCore{
		pid:        202,
		exitCode:   0,
		gracefulCh: make(chan bool, 1),
		done:       make(chan struct{}),
	}
	state := NewServerState(&queuedStarter{cores: []RunningCore{core1, core2}})

	c1Client, c1Server := net.Pipe()
	c1Done := make(chan struct{})
	go func() {
		state.ServeClient(c1Server)
		close(c1Done)
	}()
	fc1 := NewFrameConn(c1Client)

	if err := fc1.WriteFrame("start\nxray\n/app\n\n{}"); err != nil {
		t.Fatal(err)
	}
	if reply, err := fc1.ReadFrame(); err != nil || reply != "ok\n101" {
		t.Fatalf("unexpected first start reply: %q, %v", reply, err)
	}
	if err := fc1.WriteFrame("stop"); err != nil {
		t.Fatal(err)
	}
	if exitFrame, err := fc1.ReadFrame(); err != nil || exitFrame != "exit\n0" {
		t.Fatalf("expected exit\\n0, got %q, %v", exitFrame, err)
	}

	// Reconnect on a second socket while client 1 has not closed yet.
	c2Client, c2Server := net.Pipe()
	defer c2Client.Close()
	go state.ServeClient(c2Server)
	fc2 := NewFrameConn(c2Client)

	if err := fc2.WriteFrame("start\nxray\n/app\n\n{}"); err != nil {
		t.Fatal(err)
	}
	if reply, err := fc2.ReadFrame(); err != nil || reply != "ok\n202" {
		t.Fatalf("expected immediate reconnect to succeed with ok\\n202, got %q, %v", reply, err)
	}

	// Closing client 1 now must not clear coreBusy held by client 2.
	_ = c1Client.Close()
	<-c1Done
	if !state.coreBusy.Load() {
		t.Fatal("closing previous client cleared coreBusy while new core is running")
	}
	_ = fc2.WriteFrame("stop")
	if exitFrame, err := fc2.ReadFrame(); err != nil || exitFrame != "exit\n0" {
		t.Fatalf("expected second core exit\\n0, got %q, %v", exitFrame, err)
	}
}

func TestProtocolKillInterruptsSlowGracefulStop(t *testing.T) {
	core := &blockingStopCore{
		pid:        303,
		gracefulIn: make(chan struct{}, 1),
		killIn:     make(chan struct{}),
		done:       make(chan struct{}),
	}
	state := NewServerState(&queuedStarter{cores: []RunningCore{core}})

	cClient, cServer := net.Pipe()
	defer cClient.Close()
	go state.ServeClient(cServer)
	fc := NewFrameConn(cClient)

	if err := fc.WriteFrame("start\nxray\n/app\n\n{}"); err != nil {
		t.Fatal(err)
	}
	if reply, err := fc.ReadFrame(); err != nil || reply != "ok\n303" {
		t.Fatalf("unexpected start reply: %q, %v", reply, err)
	}

	if err := fc.WriteFrame("stop"); err != nil {
		t.Fatal(err)
	}
	select {
	case <-core.gracefulIn:
	case <-time.After(time.Second):
		t.Fatal("graceful stop was not dispatched")
	}

	// Sending kill while stop is still blocked must run immediately.
	if err := fc.WriteFrame("kill"); err != nil {
		t.Fatal(err)
	}
	select {
	case <-core.killIn:
	case <-time.After(time.Second):
		t.Fatal("kill was blocked by in-flight graceful stop")
	}
	if exitFrame, err := fc.ReadFrame(); err != nil || exitFrame != "exit\n137" {
		t.Fatalf("expected exit\\n137, got %q, %v", exitFrame, err)
	}
}
