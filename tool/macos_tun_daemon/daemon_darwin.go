//go:build darwin

package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

const (
	serviceLabel = "com.keqdroid.tun"
	plistPath    = "/Library/LaunchDaemons/com.keqdroid.tun.plist"
	installDir   = "/Library/Application Support/keqdroid-tun"
	binDir       = installDir + "/bin"
	runDir       = installDir + "/run"
	uidPath      = installDir + "/allowed_uid"
	sockDir      = "/var/run/keqdroid-tun"
	sockPath     = sockDir + "/tun.sock"
	tunIfName    = "utun99"

	maxCoreBytes = 256 << 20
	maxGeoBytes  = 256 << 20
)

const launchdPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.keqdroid.tun</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Library/Application Support/keqdroid-tun/bin/keqdroid-tun</string>
		<string>--daemon</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
`

func installDaemon(uid int, bundleBinDir string) error {
	if os.Geteuid() != 0 {
		return errors.New("install requires root privileges")
	}
	if len(xraySHA256) != 64 || len(mihomoSHA256) != 64 {
		return errors.New("this service was built without the cores")
	}
	selfPath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("resolve executable: %w", err)
	}
	selfBytes, err := readRegularLimited(selfPath, maxCoreBytes)
	if err != nil {
		return fmt.Errorf("read daemon binary: %w", err)
	}
	xrayBytes, err := readRegularLimited(filepath.Join(bundleBinDir, "xray"), maxCoreBytes)
	if err != nil {
		return fmt.Errorf("read xray binary: %w", err)
	}
	if sha256Hex(xrayBytes) != xraySHA256 {
		return errors.New("xray next to the app does not match this service binary")
	}
	mihomoBytes, err := readRegularLimited(filepath.Join(bundleBinDir, "mihomo"), maxCoreBytes)
	if err != nil {
		return fmt.Errorf("read mihomo binary: %w", err)
	}
	if sha256Hex(mihomoBytes) != mihomoSHA256 {
		return errors.New("mihomo next to the app does not match this service binary")
	}

	stopLaunchdJob()
	waitForDisappearance(sockPath, 3*time.Second)
	waitForTunDetach(2 * time.Second)

	unlockImmutableTree()
	if err := ensureRootDir(installDir, 0o700); err != nil {
		return err
	}
	if err := ensureRootDir(binDir, 0o755); err != nil {
		return err
	}
	if err := ensureRootDir(runDir, 0o700); err != nil {
		return err
	}

	for _, item := range []struct {
		name string
		data []byte
	}{
		{"keqdroid-tun", selfBytes},
		{"xray", xrayBytes},
		{"mihomo", mihomoBytes},
	} {
		dst := filepath.Join(binDir, item.name)
		if err := writeFreshFile(dst, item.data, 0o755); err != nil {
			return fmt.Errorf("stage %s: %w", item.name, err)
		}
		if err := unix.Chflags(dst, unix.UF_IMMUTABLE); err != nil {
			return fmt.Errorf("lock %s: %w", item.name, err)
		}
	}
	// POST /upgrade у mihomo переименовывает бинарник в его каталоге: UF_IMMUTABLE на папке и файлах закрывает запись даже root
	if err := unix.Chflags(binDir, unix.UF_IMMUTABLE); err != nil {
		return fmt.Errorf("lock bin directory: %w", err)
	}

	if err := writeFreshFile(uidPath, []byte(strconv.Itoa(uid)+"\n"), 0o600); err != nil {
		return fmt.Errorf("write allowed uid: %w", err)
	}
	if err := writeFreshFile(plistPath, []byte(launchdPlist), 0o644); err != nil {
		return fmt.Errorf("write launchd plist: %w", err)
	}

	if err := startLaunchdJob(); err != nil {
		return err
	}
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if st, err := os.Lstat(sockPath); err == nil && st.Mode()&os.ModeSocket != 0 {
			return nil
		}
		time.Sleep(50 * time.Millisecond)
	}
	return errors.New("service started, but socket did not appear")
}

func uninstallDaemon() error {
	if os.Geteuid() != 0 {
		return errors.New("uninstall requires root privileges")
	}
	stopLaunchdJob()
	_ = os.Remove(plistPath)
	_ = os.RemoveAll(sockDir)
	waitForTunDetach(2 * time.Second)
	unlockImmutableTree()
	if err := os.RemoveAll(installDir); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func stopLaunchdJob() {
	_ = exec.Command("/bin/launchctl", "bootout", "system", plistPath).Run()
	_ = exec.Command("/bin/launchctl", "bootout", "system/"+serviceLabel).Run()
	_ = exec.Command("/bin/launchctl", "unload", "-w", plistPath).Run()
}

func startLaunchdJob() error {
	if out, err := exec.Command("/bin/launchctl", "bootstrap", "system", plistPath).CombinedOutput(); err != nil {
		if out2, err2 := exec.Command("/bin/launchctl", "load", "-w", plistPath).CombinedOutput(); err2 != nil {
			msg := strings.TrimSpace(string(out))
			if msg == "" {
				msg = strings.TrimSpace(string(out2))
			}
			return fmt.Errorf("launchctl bootstrap failed: %s (%w)", msg, err)
		}
	}
	_ = exec.Command("/bin/launchctl", "kickstart", "-k", "system/"+serviceLabel).Run()
	return nil
}

func unlockImmutableTree() {
	_ = unix.Chflags(binDir, 0)
	for _, name := range []string{"keqdroid-tun", "xray", "mihomo"} {
		_ = unix.Chflags(filepath.Join(binDir, name), 0)
	}
}

func runDaemon() error {
	if os.Geteuid() != 0 {
		return errors.New("--daemon requires root privileges")
	}
	allowedUID, err := readAllowedUID()
	if err != nil {
		return err
	}
	if err := ensureRootDir(sockDir, 0o755); err != nil {
		return err
	}
	_ = os.Remove(sockPath)

	oldMask := unix.Umask(0o177)
	ln, err := net.Listen("unix", sockPath)
	unix.Umask(oldMask)
	if err != nil {
		return fmt.Errorf("listen %s: %w", sockPath, err)
	}
	if err := os.Chown(sockPath, allowedUID, 0); err != nil {
		_ = ln.Close()
		return fmt.Errorf("chown socket: %w", err)
	}
	if err := os.Chmod(sockPath, 0o600); err != nil {
		_ = ln.Close()
		return fmt.Errorf("chmod socket: %w", err)
	}

	starter := &darwinCoreStarter{allowedUID: uint32(allowedUID)}
	server := NewServerState(starter)

	var (
		clientsWg sync.WaitGroup
		connsMu   sync.Mutex
		conns     = make(map[net.Conn]struct{})
	)
	sigCh := make(chan os.Signal, 2)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-sigCh
		_ = ln.Close()
		connsMu.Lock()
		for c := range conns {
			_ = c.Close()
		}
		connsMu.Unlock()
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				break
			}
			continue
		}
		if !peerIsAllowed(conn, uint32(allowedUID)) {
			_ = conn.Close()
			continue
		}
		connsMu.Lock()
		conns[conn] = struct{}{}
		connsMu.Unlock()

		clientsWg.Add(1)
		go func(c net.Conn) {
			defer clientsWg.Done()
			defer func() {
				connsMu.Lock()
				delete(conns, c)
				connsMu.Unlock()
			}()
			server.ServeClient(c)
		}(conn)
	}

	done := make(chan struct{})
	go func() {
		clientsWg.Wait()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(6 * time.Second):
	}
	_ = os.Remove(sockPath)
	return nil
}

func peerIsAllowed(conn net.Conn, allowedUID uint32) bool {
	uc, ok := conn.(*net.UnixConn)
	if !ok {
		return false
	}
	raw, err := uc.SyscallConn()
	if err != nil {
		return false
	}
	const xucredVersion = 0 // <sys/ucred.h> XUCRED_VERSION
	var allowed bool
	if err := raw.Control(func(fd uintptr) {
		cred, err := unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
		if err == nil && cred.Version == xucredVersion && cred.Uid == allowedUID {
			allowed = true
		}
	}); err != nil {
		return false
	}
	return allowed
}

func readAllowedUID() (int, error) {
	raw, err := readRegularLimited(uidPath, 64)
	if err != nil {
		return 0, fmt.Errorf("read allowed_uid: %w", err)
	}
	uid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil || uid <= 0 {
		return 0, errors.New("invalid allowed_uid")
	}
	return uid, nil
}

type darwinCoreStarter struct {
	allowedUID uint32
}

func (d *darwinCoreStarter) VersionInfo() (string, string) {
	return xraySHA256, mihomoSHA256
}

func (d *darwinCoreStarter) Start(req StartRequest) (RunningCore, error) {
	xray := req.Kind == "xray"
	wantSHA := mihomoSHA256
	if xray {
		wantSHA = xraySHA256
	}
	if len(wantSHA) != 64 {
		return nil, errors.New("this service was built without the cores")
	}
	safe := false
	if xray {
		safe = XrayConfigIsSafe(req.Config)
	} else {
		safe = MihomoConfigIsSafe(req.Config)
	}
	if !safe {
		return nil, errors.New("the config has sections the service does not run as root: log files, env, geodata, api, scripts, webhooks, key files or system clock changes")
	}

	corePath := filepath.Join(binDir, req.Kind)
	coreBytes, err := readRegularLimited(corePath, maxCoreBytes)
	if err != nil {
		return nil, errors.New("could not read staged core, reinstall the TUN service")
	}
	if sha256Hex(coreBytes) != wantSHA {
		return nil, errors.New("the staged core does not match this service, update the service")
	}

	if err := ensureRootDir(runDir, 0o700); err != nil {
		return nil, errors.New("could not prepare run directory")
	}
	home := filepath.Join(runDir, req.Kind)
	if err := ensureRootDir(home, 0o700); err != nil {
		return nil, errors.New("could not prepare core home directory")
	}

	geoSrc := req.GeoDir
	if geoSrc == "" {
		geoSrc = req.AppDir
	}
	if geoSrc != "" {
		for _, name := range []string{"geoip.dat", "geosite.dat"} {
			stageGeoFile(filepath.Join(geoSrc, name), filepath.Join(home, name), d.allowedUID)
		}
	}

	cfgName := "session.yaml"
	if xray {
		cfgName = "session.json"
	}
	cfgPath := filepath.Join(home, cfgName)
	if err := writeFreshFile(cfgPath, []byte(req.Config), 0o600); err != nil {
		return nil, errors.New("could not write core config")
	}

	outR, outW, err := os.Pipe()
	if err != nil {
		return nil, errors.New("could not create output pipe")
	}
	inR, inW, err := os.Pipe()
	if err != nil {
		_ = outR.Close()
		_ = outW.Close()
		return nil, errors.New("could not create input pipe")
	}

	var args []string
	if xray {
		args = []string{"run", "-c", cfgPath}
	} else {
		args = []string{"-d", home, "-f", cfgPath}
	}
	cmd := exec.Command(corePath, args...)
	cmd.Dir = binDir
	cmd.Stdin = inR
	cmd.Stdout = outW
	cmd.Stderr = outW
	cmd.Env = buildCoreEnv(home, xray)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	if err := cmd.Start(); err != nil {
		_ = outR.Close()
		_ = outW.Close()
		_ = inR.Close()
		_ = inW.Close()
		return nil, fmt.Errorf("could not start the core: %w", err)
	}
	_ = outW.Close()
	_ = inR.Close()

	return &darwinRunningCore{
		cmd:     cmd,
		pid:     cmd.Process.Pid,
		stdinW:  inW,
		stdoutR: outR,
		doneCh:  make(chan struct{}),
	}, nil
}

func buildCoreEnv(home string, xray bool) []string {
	// чистое окружение: SAFE_PATHS и SKIP_SAFE_PATH_CHECK у mihomo открыли бы пути вне дома
	env := []string{
		"PATH=/usr/sbin:/usr/bin:/sbin:/bin",
		"HOME=" + home,
		"TMPDIR=" + home,
	}
	if xray {
		env = append(env,
			"XRAY_LOCATION_ASSET="+home,
			"KEQ_STOP_ON_STDIN_EOF=1",
		)
	}
	return env
}

type darwinRunningCore struct {
	cmd        *exec.Cmd
	pid        int
	stdinW     *os.File
	stdoutR    *os.File
	stdinOnce  sync.Once
	streamOnce sync.Once
	doneCh     chan struct{}
	streamWg   sync.WaitGroup
	started    atomic.Bool
}

func (c *darwinRunningCore) PID() int { return c.pid }

func (c *darwinRunningCore) StartStreaming(onLine func(string), onExit func(int)) {
	c.streamOnce.Do(func() {
		c.started.Store(true)
		c.streamWg.Add(2)
		go func() {
			defer c.streamWg.Done()
			defer c.stdoutR.Close()
			sc := bufio.NewScanner(c.stdoutR)
			sc.Buffer(make([]byte, 64*1024), 1024*1024)
			for sc.Scan() {
				line := strings.TrimRight(sc.Text(), "\r")
				onLine(line)
			}
		}()
		go func() {
			defer c.streamWg.Done()
			err := c.cmd.Wait()
			close(c.doneCh)
			code := 0
			if err != nil {
				var exitErr *exec.ExitError
				if errors.As(err, &exitErr) {
					code = exitErr.ExitCode()
				} else {
					code = 1
				}
			}
			onExit(code)
		}()
	})
}

func (c *darwinRunningCore) closeStdin() {
	c.stdinOnce.Do(func() {
		if c.stdinW != nil {
			_ = c.stdinW.Close()
		}
	})
}

func (c *darwinRunningCore) Stop(graceful bool) {
	if !c.started.Load() {
		c.StartStreaming(func(string) {}, func(int) {})
	}
	c.closeStdin()
	_ = unix.Kill(-c.pid, unix.SIGTERM)
	waitDur := 400 * time.Millisecond
	if graceful {
		waitDur = 5 * time.Second
	}
	select {
	case <-c.doneCh:
		return
	case <-time.After(waitDur):
	}
	_ = unix.Kill(-c.pid, unix.SIGKILL)
}

func (c *darwinRunningCore) Wait() {
	if !c.started.Load() {
		c.StartStreaming(func(string) {}, func(int) {})
	}
	<-c.doneCh
	c.streamWg.Wait()
	waitForTunDetach(2 * time.Second)
}

func waitForTunDetach(timeout time.Duration) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if _, err := net.InterfaceByName(tunIfName); err != nil {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
}

func waitForDisappearance(path string, timeout time.Duration) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if _, err := os.Lstat(path); errors.Is(err, os.ErrNotExist) {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
}

func ensureRootDir(path string, perm os.FileMode) error {
	st, err := os.Lstat(path)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return err
		}
		if err := os.MkdirAll(path, perm); err != nil {
			return err
		}
	} else {
		if st.Mode()&os.ModeSymlink != 0 || !st.IsDir() {
			return fmt.Errorf("%s is not a directory", path)
		}
	}
	if err := os.Chown(path, 0, 0); err != nil {
		return err
	}
	return os.Chmod(path, perm)
}

// на Apple Silicon ядро кэширует подпись Mach-O на vnode: перезапись поверх O_TRUNC роняет запуск с SIGKILL, нужен новый inode
func writeFreshFile(dst string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(dst)
	tmp, err := os.CreateTemp(dir, ".tmp-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	ok := false
	defer func() {
		if !ok {
			_ = os.Remove(tmpPath)
		}
	}()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Chown(0, 0); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Chmod(perm); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	_ = os.Remove(dst)
	if err := os.Rename(tmpPath, dst); err != nil {
		return err
	}
	ok = true
	return nil
}

func readRegularLimited(path string, limit int64) ([]byte, error) {
	fd, err := unix.Open(path, unix.O_RDONLY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	f := os.NewFile(uintptr(fd), path)
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, err
	}
	if !st.Mode().IsRegular() {
		return nil, errors.New("not a regular file")
	}
	if st.Size() < 0 || st.Size() > limit {
		return nil, errors.New("file exceeds size limit")
	}
	buf := make([]byte, st.Size())
	if _, err := io.ReadFull(f, buf); err != nil {
		return nil, err
	}
	return buf, nil
}

// geo-база приходит по пути от пользователя: берём только обычный файл без симлинков, доступный ему самому на чтение
func stageGeoFile(src, dst string, allowedUID uint32) {
	if !dirTraversableByUser(filepath.Dir(src), allowedUID) {
		return
	}
	fd, err := unix.Open(src, unix.O_RDONLY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if err != nil {
		return
	}
	f := os.NewFile(uintptr(fd), src)
	defer f.Close()

	st, err := f.Stat()
	if err != nil || !st.Mode().IsRegular() || st.Size() <= 0 || st.Size() > maxGeoBytes {
		return
	}
	sys, ok := st.Sys().(*syscall.Stat_t)
	if !ok {
		return
	}
	if sys.Uid != allowedUID && (st.Mode().Perm()&0o004) == 0 {
		return
	}

	stampPath := dst + ".stamp"
	stamp := fmt.Sprintf("%d:%d", st.Size(), st.ModTime().UnixNano())
	if curSt, err := os.Lstat(dst); err == nil && curSt.Mode().IsRegular() && curSt.Size() == st.Size() {
		if prev, err := os.ReadFile(stampPath); err == nil && string(prev) == stamp {
			return
		}
	}

	data := make([]byte, st.Size())
	if _, err := io.ReadFull(f, data); err != nil {
		return
	}
	if err := writeFreshFile(dst, data, 0o600); err == nil {
		_ = writeFreshFile(stampPath, []byte(stamp), 0o600)
	}
}

func dirTraversableByUser(dir string, allowedUID uint32) bool {
	clean := filepath.Clean(dir)
	if !filepath.IsAbs(clean) {
		return false
	}
	resolved, err := filepath.EvalSymlinks(clean)
	if err != nil {
		return false
	}
	for cur := resolved; ; {
		st, err := os.Lstat(cur)
		if err != nil || !st.IsDir() {
			return false
		}
		sys, ok := st.Sys().(*syscall.Stat_t)
		if !ok {
			return false
		}
		if sys.Uid != allowedUID && (st.Mode().Perm()&0o001) == 0 {
			return false
		}
		parent := filepath.Dir(cur)
		if parent == cur {
			return true
		}
		cur = parent
	}
}

func sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
