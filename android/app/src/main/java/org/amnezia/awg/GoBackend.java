package org.amnezia.awg;

/**
 * Thin JNI bridge to amneziawg-go (libwg-go.so).
 *
 * The native symbols inside libwg-go.so are bound to the fully-qualified name
 * {@code org.amnezia.awg.GoBackend}, so this class MUST keep this exact package
 * and name. Built from amnezia-vpn/amneziawg-android (Apache-2.0) via
 * tool/build_amneziawg.ps1.
 */
public final class GoBackend {
    static {
        System.loadLibrary("wg-go");
    }

    private GoBackend() {}

    public static native String awgGetConfig(int handle);

    public static native int awgGetSocketV4(int handle);

    public static native int awgGetSocketV6(int handle);

    public static native void awgTurnOff(int handle);

    public static native int awgTurnOn(String ifName, int tunFd, String settings);

    public static native String awgVersion();
}
