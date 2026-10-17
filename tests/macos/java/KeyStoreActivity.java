// SPDX-License-Identifier: GPL-2.0-or-later
package org.husk.keystore;

import android.app.Activity;
import android.os.Bundle;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProtection;
import android.security.keystore.KeyProperties;
import android.security.keystore.WrappedKeyEntry;
import java.io.File;
import java.nio.file.Files;
import java.security.Key;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Date;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Synthetic keys only. No Play credentials, protected APKs, network or visible window. */
public final class KeyStoreActivity extends Activity {
    private static int result;
    private static final byte[] MESSAGE = { 7, 10, 18, 20, 26 }, AAD = { 4, 8, 16 };
    private static void check(boolean condition, String reason) {
        if (!condition) throw new IllegalStateException(reason);
    }
    private static KeyProtection.Builder policy(int purposes) {
        return new KeyProtection.Builder(purposes).setBlockModes("GCM").setEncryptionPaddings("NoPadding").setDigests("SHA-256");
    }
    private static KeyStore load() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null); return store;
    }
    private static void importKey(KeyStore store, String alias, SecretKey key, KeyProtection protection) throws Exception {
        store.setEntry(alias, new KeyStore.SecretKeyEntry(key), protection);
    }
    private static byte[] decrypt(Key key, byte[] iv, byte[] encrypted) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, iv));
        cipher.updateAAD(AAD); return cipher.doFinal(encrypted);
    }
    private static void forbiddenInit(Key key, String transformation, int op, GCMParameterSpec params) throws Exception {
        Cipher cipher = Cipher.getInstance(transformation, "AndroidKeyStoreBCWorkaround");
        boolean refused = false;
        try { if (params == null) cipher.init(op, key); else cipher.init(op, key, params); }
        catch (java.security.InvalidKeyException expected) { refused = true; }
        check(refused, "cipher operation must be refused");
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        try { run(System.getenv("HUSK_KEYSTORE_PHASE")); result = 1; }
        catch (Throwable e) { e.printStackTrace(); result = -1; }
    }
    private void run(String phase) throws Exception {
        File root = getFilesDir().getParentFile(), storeFile = new File(root, ".husk_keystore");
        if ("corrupt".equals(phase)) {
            for (int i = 0; i < 2; ++i) {
                boolean refused = false;
                try { load(); } catch (java.io.IOException expected) { refused = true; }
                check(refused, "damaged key store must not become an empty store");
            }
            return;
        }
        KeyStore store = load();
        if ("empty".equals(phase)) { check(store.size() == 0, "isolated or deleted store must be empty"); return; }
        if ("delete".equals(phase)) {
            for (String alias : new String[] { "imported", "legacy" }) store.deleteEntry(alias);
            check(store.size() == 0, "delete entries"); return;
        }
        if ("write-failed".equals(phase)) {
            SecretKey before = (SecretKey)store.getKey("imported", null);
            byte[] oldFile = Files.readAllBytes(storeFile.toPath());
            File saved = new File(root, "key-test-previous");
            check(storeFile.renameTo(saved) && storeFile.mkdir(), "create replacement failure fixture");
            Files.write(new File(storeFile, "nonempty").toPath(), new byte[] { 1 });
            try {
                boolean refused = false;
                try { importKey(store, "imported", new SecretKeySpec(new byte[32], "AES"), policy(3).build()); }
                catch (KeyStoreException expected) { refused = true; }
                check(refused, "failed persistence must fail import");
                refused = false;
                try { store.deleteEntry("imported"); } catch (KeyStoreException expected) { refused = true; }
                check(refused && store.containsAlias("imported"), "failed persistence must not delete cached key");
                check(Arrays.equals(decrypt(before, Files.readAllBytes(new File(root, "iv").toPath()),
                        Files.readAllBytes(new File(root, "ciphertext").toPath())), MESSAGE), "failed overwrite must keep usable old key");
            } finally {
                check(new File(storeFile, "nonempty").delete() && storeFile.delete() && saved.renameTo(storeFile), "restore fixture file");
            }
            check(Arrays.equals(oldFile, Files.readAllBytes(storeFile.toPath())), "previous on-disk bytes retained");
            return;
        }
        if ("reopen".equals(phase)) {
            Key key = store.getKey("imported", null);
            check(key != null && key.getEncoded() == null && key.getFormat() == null, "opaque key after process restart");
            check(Arrays.equals(decrypt(key, Files.readAllBytes(new File(root, "iv").toPath()),
                    Files.readAllBytes(new File(root, "ciphertext").toPath())), MESSAGE), "reopened key decrypts earlier ciphertext");
            check(store.getKey("legacy", null) != null, "previous raw-key entry format remains readable");
            return;
        }
        check("import".equals(phase), "known phase");
        byte[] bytes = new byte[32]; new SecureRandom().nextBytes(bytes);
        SecretKey raw = new SecretKeySpec(bytes, "AES");
        KeyProtection protection = policy(3).build();
        check(protection.getMaxUsageCount() == -1 && protection.isRandomizedEncryptionRequired(), "Android policy defaults");
        importKey(store, "imported", raw, protection);
        Key key = store.getKey("imported", null);
        check(key != null && key.getEncoded() == null && key.getFormat() == null, "import does not expose raw key bytes");
        check(store.getEntry("imported", null) instanceof KeyStore.SecretKeyEntry, "getEntry type");
        Cipher encrypt = Cipher.getInstance("AES/GCM/NoPadding"); encrypt.init(Cipher.ENCRYPT_MODE, key); encrypt.updateAAD(AAD);
        byte[] encrypted = encrypt.doFinal(MESSAGE), iv = encrypt.getIV();
        check(Arrays.equals(decrypt(raw, iv, encrypted), MESSAGE), "actual AES GCM with imported key");
        check(Arrays.equals(decrypt(key, iv, encrypted), MESSAGE), "opaque key decrypts");
        encrypted[0] ^= 1; boolean rejected = false;
        try { decrypt(key, iv, encrypted); } catch (javax.crypto.AEADBadTagException expected) { rejected = true; }
        check(rejected, "authentication tag validated"); encrypted[0] ^= 1;
        Files.write(new File(root, "iv").toPath(), iv); Files.write(new File(root, "ciphertext").toPath(), encrypted);
        forbiddenInit(key, "AES/GCM/NoPadding", Cipher.ENCRYPT_MODE, new GCMParameterSpec(128, iv));
        forbiddenInit(key, "AES/CBC/NoPadding", Cipher.DECRYPT_MODE, null);
        importKey(store, "decrypt-only", raw, policy(KeyProperties.PURPOSE_DECRYPT).build());
        forbiddenInit(store.getKey("decrypt-only", null), "AES/GCM/NoPadding", Cipher.ENCRYPT_MODE, null);
        importKey(store, "expired", raw, policy(3).setKeyValidityEnd(new Date(1)).build());
        forbiddenInit(store.getKey("expired", null), "AES/GCM/NoPadding", Cipher.DECRYPT_MODE, new GCMParameterSpec(128, iv));
        Key deleted = store.getKey("decrypt-only", null); store.deleteEntry("decrypt-only"); store.deleteEntry("expired");
        forbiddenInit(deleted, "AES/GCM/NoPadding", Cipher.DECRYPT_MODE, new GCMParameterSpec(128, iv));
        for (KeyProtection unsupported : new KeyProtection[] { policy(3).setUserAuthenticationRequired(true).build(),
                policy(3).setIsStrongBoxBacked(true).build(), policy(3).setMaxUsageCount(1).build() }) {
            rejected = false;
            try { importKey(store, "imported", raw, unsupported); } catch (KeyStoreException expected) { rejected = true; }
            check(rejected, "unsupported security promise rejected without replacing existing key");
        }
        rejected = false;
        try { store.setEntry("wrapped", new WrappedKeyEntry(new byte[] { 1 }, "wrapping", "RSA/ECB/OAEPPadding", null), null); }
        catch (KeyStoreException expected) { rejected = true; }
        check(rejected && !store.containsAlias("wrapped"), "hardware wrapped import is not simulated");
        check(!getPackageManager().hasSystemFeature("android.hardware.hardware_keystore"), "no fake hardware capability");
        rejected = false;
        try { store.setKeyEntry("imported", key, null, null); } catch (KeyStoreException expected) { rejected = true; }
        check(rejected, "reimporting a handle cannot discard its policy");
        check(Arrays.equals(decrypt(key, iv, encrypted), MESSAGE), "failed import preserves handle");
        KeyGenerator legacy = KeyGenerator.getInstance("AES", "AndroidKeyStore");
        legacy.init(new KeyGenParameterSpec.Builder("legacy", 3).setKeySize(128).build()); legacy.generateKey();
    }
    public static int result() { return result; }
}
