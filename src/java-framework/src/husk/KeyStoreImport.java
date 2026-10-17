package husk;

import android.security.keystore.KeyProtection;
import android.security.keystore.KeyProperties;
import java.io.Serializable;
import java.security.InvalidKeyException;
import java.security.Key;
import java.security.KeyStoreException;
import java.security.ProviderException;
import java.util.Arrays;
import java.util.Date;
import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

/** Software AES/GCM import. It consumes real key bytes supplied by the caller; it does not obtain Play keys. */
final class KeyStoreImport {
    private KeyStoreImport() {}

    static final class Policy implements Serializable {
        private static final long serialVersionUID = 1;
        final int purposes;
        final boolean randomized;
        final Long start, encryptEnd, decryptEnd;
        Policy(KeyProtection p) {
            purposes = p.getPurposes(); randomized = p.isRandomizedEncryptionRequired();
            start = time(p.getKeyValidityStart());
            encryptEnd = time(p.getKeyValidityForOriginationEnd());
            decryptEnd = time(p.getKeyValidityForConsumptionEnd());
        }
        private static Long time(Date date) { return date == null ? null : date.getTime(); }
    }

    static final class Handle implements SecretKey {
        private static final long serialVersionUID = 1;
        private final String alias;
        private final transient KeyStoreProvider.Entry entry;
        Handle(String alias, KeyStoreProvider.Entry entry) { this.alias = alias; this.entry = entry; }
        public String getAlgorithm() { return "AES"; }
        public String getFormat() { return null; }
        public byte[] getEncoded() { return null; }
    }

    static void importKey(String alias, SecretKey key, KeyProtection p) throws KeyStoreException {
        if (p.isStrongBoxBacked() || p.isUserAuthenticationRequired() || p.isUserPresenceRequired() ||
            p.isUserConfirmationRequired() || p.isUnlockedDeviceRequired() || p.isRollbackResistant() ||
            p.isCriticalToDeviceEncryption() || p.getBoundToSpecificSecureUserId() != 0 || p.getMaxUsageCount() != -1)
            throw new KeyStoreException("Requested protection requires unavailable Android security services");
        int purposes = p.getPurposes();
        if (purposes == 0 || (purposes & ~(KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)) != 0 ||
            !Arrays.equals(p.getBlockModes(), new String[] { "GCM" }) ||
            !Arrays.equals(p.getEncryptionPaddings(), new String[] { "NoPadding" }) ||
            !"AES".equalsIgnoreCase(key.getAlgorithm()))
            throw new KeyStoreException("Software key import currently supports AES/GCM/NoPadding encrypt/decrypt only");
        if (p.getSignaturePaddings() != null && p.getSignaturePaddings().length != 0)
            throw new KeyStoreException("Signature padding is not supported for AES");
        byte[] bytes = key.getEncoded();
        if (bytes == null || (bytes.length != 16 && bytes.length != 24 && bytes.length != 32))
            throw new KeyStoreException("Expected an encodable AES key of 128, 192 or 256 bits");
        KeyStoreProvider.Entry entry = new KeyStoreProvider.Entry();
        entry.secretOrPrivate = new SecretKeySpec(bytes, "AES");
        entry.policy = new Policy(p);
        try { KeyStoreProvider.put(alias, entry); }
        catch (ProviderException e) { throw new KeyStoreException("AES key import was not persisted", e); }
    }

    static Key forCipher(Key key, int op, String transformation, boolean parameters) throws InvalidKeyException {
        if (!(key instanceof Handle)) return key;
        Handle handle = (Handle)key;
        KeyStoreProvider.Entry entry = KeyStoreProvider.entry(handle.alias);
        if (entry == null || entry != handle.entry) throw new InvalidKeyException("Key was deleted or replaced");
        Policy p = entry.policy;
        if (!"AES/GCM/NoPadding".equals(transformation)) throw new InvalidKeyException("Key permits AES/GCM/NoPadding only");
        int purpose = op == Cipher.ENCRYPT_MODE ? KeyProperties.PURPOSE_ENCRYPT :
                      op == Cipher.DECRYPT_MODE ? KeyProperties.PURPOSE_DECRYPT : 0;
        if (purpose == 0 || (p.purposes & purpose) == 0) throw new InvalidKeyException("Key does not permit this operation");
        if (op == Cipher.ENCRYPT_MODE && parameters && p.randomized)
            throw new InvalidKeyException("Caller-provided IV is prohibited for randomized encryption");
        long now = System.currentTimeMillis();
        Long end = op == Cipher.ENCRYPT_MODE ? p.encryptEnd : p.decryptEnd;
        if ((p.start != null && now < p.start) || (end != null && now > end))
            throw new InvalidKeyException("Key is outside its validity period");
        return entry.secretOrPrivate;
    }
}
