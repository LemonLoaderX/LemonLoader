package net.dot.android.crypto;

public final class LemonLoaderCryptoBootstrap {
    private LemonLoaderCryptoBootstrap() {
    }

    public static void load(String absolutePath) {
        System.load(absolutePath);
    }
}
