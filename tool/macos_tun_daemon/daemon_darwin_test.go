//go:build darwin

package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestStageGeoFileRemovesStaleWhenSourceMissing(t *testing.T) {
	tmp := t.TempDir()
	srcDir := filepath.Join(tmp, "src")
	dstDir := filepath.Join(tmp, "dst")
	if err := os.MkdirAll(srcDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(dstDir, 0o755); err != nil {
		t.Fatal(err)
	}

	dst := filepath.Join(dstDir, "geoip.dat")
	stamp := dst + ".stamp"
	if err := os.WriteFile(dst, []byte("stale"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(stamp, []byte("5:1"), 0o600); err != nil {
		t.Fatal(err)
	}

	uid := uint32(os.Getuid())
	stageGeoFile(filepath.Join(srcDir, "geoip.dat"), dst, uid)

	if _, err := os.Lstat(dst); !os.IsNotExist(err) {
		t.Fatalf("expected stale staged file to be removed, err=%v", err)
	}
	if _, err := os.Lstat(stamp); !os.IsNotExist(err) {
		t.Fatalf("expected stale stamp file to be removed, err=%v", err)
	}

	// Also verify stale cleanup when the entire source directory was deleted.
	if err := os.WriteFile(dst, []byte("stale2"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(stamp, []byte("6:2"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(srcDir); err != nil {
		t.Fatal(err)
	}

	stageGeoFile(filepath.Join(srcDir, "geoip.dat"), dst, uid)
	if _, err := os.Lstat(dst); !os.IsNotExist(err) {
		t.Fatalf("expected stale staged file to be removed when srcDir missing, err=%v", err)
	}
	if _, err := os.Lstat(stamp); !os.IsNotExist(err) {
		t.Fatalf("expected stale stamp to be removed when srcDir missing, err=%v", err)
	}
}

func TestUserCanAccessMode(t *testing.T) {
	uid := uint32(os.Getuid())
	gid := uint32(os.Getgid())
	otherUID := uid + 10000

	// Owner bit takes precedence over other bit.
	if !userCanAccessMode(uid, uid, gid, 0o400, 0o400, 0o040, 0o004) {
		t.Fatal("owner should be allowed when owner bit is set")
	}
	if userCanAccessMode(uid, uid, gid, 0o044, 0o400, 0o040, 0o004) {
		t.Fatal("owner must be denied when owner bit is clear even if group/other bits are set")
	}

	// Non-owner in matching primary group gets group bit (0o640 / 0o750).
	if !userCanAccessMode(uid, otherUID, gid, 0o640, 0o400, 0o040, 0o004) {
		t.Fatal("group member should be allowed on 0640")
	}
	if userCanAccessMode(uid, otherUID, gid, 0o604, 0o400, 0o040, 0o004) {
		t.Fatal("group member must be denied on 0604 when group bit is clear")
	}

	// Fast paths for uniform group/other permissions.
	if !userCanAccessMode(uid, otherUID, gid, 0o755, 0o100, 0o010, 0o001) {
		t.Fatal("non-owner should be allowed on 0755")
	}
	if userCanAccessMode(uid, otherUID, gid, 0o700, 0o100, 0o010, 0o001) {
		t.Fatal("non-owner must be denied on 0700")
	}
}

func TestDirTraversableByUser(t *testing.T) {
	tmp := t.TempDir()
	uid := uint32(os.Getuid())

	if !dirTraversableByUser(tmp, uid) {
		t.Fatalf("expected temp dir %s to be traversable by current user", tmp)
	}
	if dirTraversableByUser("relative/path", uid) {
		t.Fatal("relative path must not be treated as traversable")
	}

	locked := filepath.Join(tmp, "locked")
	if err := os.Mkdir(locked, 0o000); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o700) })

	if dirTraversableByUser(locked, uid) {
		t.Fatal("0000 directory must not be traversable")
	}
}
