//go:build !darwin

package main

import "errors"

func runDaemon() error                    { return errors.New("supported on macOS only") }
func installDaemon(int, string) error     { return errors.New("supported on macOS only") }
func uninstallDaemon() error              { return errors.New("supported on macOS only") }
