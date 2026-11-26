package main

import (
	"fmt"
	"os"
	"strconv"
)

var (
	xraySHA256   string
	mihomoSHA256 string
)

func main() {
	if len(os.Args) < 2 {
		fatalf("usage: keqdroid-tun <--daemon | install <uid> <bin_dir> | uninstall>")
	}
	switch os.Args[1] {
	case "--daemon":
		if err := runDaemon(); err != nil {
			fatalf("%v", err)
		}
	case "install":
		if len(os.Args) != 4 {
			fatalf("usage: keqdroid-tun install <uid> <bin_dir>")
		}
		uid, err := strconv.Atoi(os.Args[2])
		if err != nil || uid <= 0 {
			fatalf("invalid uid: %s", os.Args[2])
		}
		if err := installDaemon(uid, os.Args[3]); err != nil {
			fatalf("%v", err)
		}
	case "uninstall":
		if err := uninstallDaemon(); err != nil {
			fatalf("%v", err)
		}
	default:
		fatalf("unknown command: %s", os.Args[1])
	}
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "keqdroid-tun: "+format+"\n", args...)
	os.Exit(1)
}
