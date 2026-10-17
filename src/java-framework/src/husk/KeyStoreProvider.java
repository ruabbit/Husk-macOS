package husk;

import java.io.*;
import java.math.BigInteger;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.*;
import java.security.cert.Certificate;
import java.security.spec.AlgorithmParameterSpec;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.RSAKeyGenParameterSpec;
import java.util.*;
import javax.crypto.KeyGeneratorSpi;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

/**
 * Software compatibility provider for AndroidKeyStore. Key material lives in the app's private data,
 * not secure hardware. Imported AES/GCM keys have opaque handles and software-enforced usage policy;
 * hardware, authentication and wrapped-key import requests are not advertised or emulated.
 */
public final class KeyStoreProvider extends Provider {
    public static final String NAME = "AndroidKeyStore";
    public KeyStoreProvider() {
        super(NAME, 1.0, "Husk's AndroidKeyStore");
        put("KeyStore.AndroidKeyStore", Store.class.getName());
        put("Cipher.AES/GCM/NoPadding", ImportedGCM.class.getName());
        put("Cipher.AES/GCM/NoPadding SupportedKeyClasses", KeyStoreImport.Handle.class.getName());
        for (String a : new String[] { "AES", "HmacSHA1", "HmacSHA224", "HmacSHA256", "HmacSHA384", "HmacSHA512", "DESede" }) put("KeyGenerator." + a, SecretGen.class.getName() + "$" + a.replace("Hmac", "H"));
        put("KeyPairGenerator.RSA", PairGen.class.getName() + "$RSA");
        put("KeyPairGenerator.EC", PairGen.class.getName() + "$EC");
    }

    private static boolean sInstalled;
    /** At start: the provider in the list, where KeyStore.getInstance("AndroidKeyStore") finds it. */
    public static synchronized void install() {
        if (sInstalled) return;
        sInstalled = true;
        try { Security.addProvider(new KeyStoreProvider()); } catch (Throwable t) { android.util.Log.w("Husk", "AndroidKeyStore not installed: " + t); }
        try { Security.addProvider(new BCWorkaround()); } catch (Throwable t) { android.util.Log.w("Husk", "AndroidKeyStoreBCWorkaround not installed: " + t); }
    }

    // ---- the keys: alias -> key (and for a pair, its public key), kept in a file of the app's
    static final class Entry implements Serializable {
        private static final long serialVersionUID = 1;
        Key secretOrPrivate;
        PublicKey publicKey;
        KeyStoreImport.Policy policy;
        long created = System.currentTimeMillis();
    }
    private static LinkedHashMap<String, Entry> sKeys;
    private static File file() { return new File(Native.dataDir(), ".husk_keystore"); }
    static synchronized LinkedHashMap<String, Entry> huskKeys() {
        if (sKeys != null) return sKeys;
        LinkedHashMap<String, Entry> loaded = new LinkedHashMap<>();
        File f = file();
        if (!Files.notExists(f.toPath())) {
            try (ObjectInputStream in = new ObjectInputStream(new FileInputStream(f))) {
                Object value = in.readObject();
                if (!(value instanceof LinkedHashMap)) throw new IOException("invalid key store");
                for (Map.Entry<?, ?> item : ((LinkedHashMap<?, ?>)value).entrySet()) {
                    if (!(item.getKey() instanceof String) || !(item.getValue() instanceof Entry))
                        throw new IOException("invalid key store entry");
                    loaded.put((String)item.getKey(), (Entry)item.getValue());
                }
            } catch (Exception e) {
                // A damaged or unreadable store must not become an empty, writable one.
                throw new ProviderException("Cannot read AndroidKeyStore; existing file preserved", e);
            }
        }
        sKeys = loaded;
        return sKeys;
    }
    private static void persist(LinkedHashMap<String, Entry> next) {
        File temporary = null;
        try {
            temporary = Files.createTempFile(file().getParentFile().toPath(), ".husk_keystore-", ".tmp",
                    PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------"))).toFile();
            try (FileOutputStream stream = new FileOutputStream(temporary);
                 ObjectOutputStream out = new ObjectOutputStream(stream)) {
                out.writeObject(next);
                out.flush();
                stream.getFD().sync();
            }
            Files.move(temporary.toPath(), file().toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            throw new ProviderException("Cannot persist AndroidKeyStore; previous entries preserved", e);
        } finally {
            if (temporary != null && temporary.exists()) temporary.delete();
        }
        sKeys = next; // Publish only after the file was committed.
    }
    static synchronized void put(String alias, Entry e) {
        if (alias == null) throw new NullPointerException("alias");
        LinkedHashMap<String, Entry> next = new LinkedHashMap<>(huskKeys());
        next.put(alias, e);
        persist(next);
    }
    static synchronized Entry entry(String alias) { return huskKeys().get(alias); }
    private static synchronized void delete(String alias) {
        LinkedHashMap<String, Entry> next = new LinkedHashMap<>(huskKeys());
        if (next.remove(alias) != null) persist(next);
    }

    /** A certificate that carries only its public key (Android's are self-signed X.509; what apps read is the key). */
    static final class KeyCertificate extends Certificate {
        private final PublicKey mKey;
        KeyCertificate(PublicKey k) { super("X.509"); mKey = k; }
        @Override public byte[] getEncoded() { return mKey.getEncoded(); }
        @Override public void verify(PublicKey key) {}
        @Override public void verify(PublicKey key, String sigProvider) {}
        @Override public String toString() { return "Husk key certificate (" + mKey.getAlgorithm() + ")"; }
        @Override public PublicKey getPublicKey() { return mKey; }
    }

    public static final class Store extends KeyStoreSpi {
        @Override public Key engineGetKey(String alias, char[] password) { Entry e = entry(alias); return e == null ? null : e.policy == null ? e.secretOrPrivate : new KeyStoreImport.Handle(alias, e); }
        @Override public Certificate[] engineGetCertificateChain(String alias) { Certificate c = engineGetCertificate(alias); return c == null ? null : new Certificate[] { c }; }
        @Override public Certificate engineGetCertificate(String alias) { Entry e = entry(alias); return e == null || e.publicKey == null ? null : new KeyCertificate(e.publicKey); }
        @Override public Date engineGetCreationDate(String alias) { Entry e = entry(alias); return e == null ? null : new Date(e.created); }
        @Override public void engineSetEntry(String alias, KeyStore.Entry entry, KeyStore.ProtectionParameter protection) throws KeyStoreException {
            if (entry instanceof KeyStore.SecretKeyEntry && protection instanceof android.security.keystore.KeyProtection) {
                KeyStoreImport.importKey(alias, ((KeyStore.SecretKeyEntry)entry).getSecretKey(),
                        (android.security.keystore.KeyProtection)protection);
                return;
            }
            // The superclass rejects unsupported protection parameters and WrappedKeyEntry.
            super.engineSetEntry(alias, entry, protection);
        }
        @Override public void engineSetKeyEntry(String alias, Key key, char[] password, Certificate[] chain) throws KeyStoreException {
            if (key instanceof KeyStoreImport.Handle)
                throw new KeyStoreException("An imported key handle cannot be reimported without its original policy");
            Entry e = new Entry();
            e.secretOrPrivate = key;
            if (chain != null && chain.length > 0) e.publicKey = chain[0].getPublicKey();
            try { put(alias, e); } catch (ProviderException ex) { throw new KeyStoreException(ex); }
        }
        @Override public void engineSetKeyEntry(String alias, byte[] key, Certificate[] chain) throws KeyStoreException { throw new KeyStoreException("not supported"); }
        @Override public void engineSetCertificateEntry(String alias, Certificate cert) throws KeyStoreException {
            Entry e = new Entry();
            e.publicKey = cert.getPublicKey();
            try { put(alias, e); } catch (ProviderException ex) { throw new KeyStoreException(ex); }
        }
        @Override public void engineDeleteEntry(String alias) throws KeyStoreException {
            try { delete(alias); } catch (ProviderException ex) { throw new KeyStoreException(ex); }
        }
        @Override public Enumeration<String> engineAliases() { synchronized (KeyStoreProvider.class) { return Collections.enumeration(new ArrayList<>(huskKeys().keySet())); } }
        @Override public boolean engineContainsAlias(String alias) { return huskKeys().containsKey(alias); }
        @Override public int engineSize() { return huskKeys().size(); }
        @Override public boolean engineIsKeyEntry(String alias) { Entry e = entry(alias); return e != null && e.secretOrPrivate != null; }
        @Override public boolean engineIsCertificateEntry(String alias) { Entry e = entry(alias); return e != null && e.secretOrPrivate == null; }
        @Override public String engineGetCertificateAlias(Certificate cert) {
            for (Map.Entry<String, Entry> e : huskKeys().entrySet()) if (e.getValue().publicKey != null && e.getValue().publicKey.equals(cert.getPublicKey())) return e.getKey();
            return null;
        }
        @Override public void engineStore(OutputStream stream, char[] password) {}
        @Override public void engineLoad(InputStream stream, char[] password) throws IOException {
            try { huskKeys(); } catch (ProviderException e) { throw new IOException(e); }
        }
        @Override public void engineLoad(KeyStore.LoadStoreParameter param) throws IOException { engineLoad(null, null); }
    }

    private static String aliasOf(AlgorithmParameterSpec spec) {
        if (spec instanceof android.security.keystore.KeyGenParameterSpec) return ((android.security.keystore.KeyGenParameterSpec) spec).getKeystoreAlias();
        return null;
    }
    private static int sizeOf(AlgorithmParameterSpec spec, int dflt) {
        if (spec instanceof android.security.keystore.KeyGenParameterSpec) { int s = ((android.security.keystore.KeyGenParameterSpec) spec).getKeySize(); if (s > 0) return s; }
        return dflt;
    }

    public static class SecretGen extends KeyGeneratorSpi {
        private final String mAlgorithm; private final int mDefaultSize;
        private String mAlias; private int mSize;
        SecretGen(String algorithm, int defaultSize) { mAlgorithm = algorithm; mDefaultSize = defaultSize; mSize = defaultSize; }
        @Override protected void engineInit(SecureRandom random) { throw new IllegalStateException("AndroidKeyStore keys need a KeyGenParameterSpec"); }
        @Override protected void engineInit(AlgorithmParameterSpec params, SecureRandom random) throws InvalidAlgorithmParameterException {
            mAlias = aliasOf(params);
            if (mAlias == null) throw new InvalidAlgorithmParameterException("expected a KeyGenParameterSpec");
            mSize = sizeOf(params, mDefaultSize);
        }
        @Override protected void engineInit(int keysize, SecureRandom random) { mSize = keysize; }
        @Override protected SecretKey engineGenerateKey() {
            byte[] b = new byte[Math.max(1, mSize / 8)];
            new SecureRandom().nextBytes(b);
            SecretKey k = new SecretKeySpec(b, mAlgorithm);
            if (mAlias != null) { Entry e = new Entry(); e.secretOrPrivate = k; put(mAlias, e); }
            return k;
        }
        public static final class AES extends SecretGen { public AES() { super("AES", 256); } }
        public static final class HSHA1 extends SecretGen { public HSHA1() { super("HmacSHA1", 160); } }
        public static final class HSHA224 extends SecretGen { public HSHA224() { super("HmacSHA224", 224); } }
        public static final class HSHA256 extends SecretGen { public HSHA256() { super("HmacSHA256", 256); } }
        public static final class HSHA384 extends SecretGen { public HSHA384() { super("HmacSHA384", 384); } }
        public static final class HSHA512 extends SecretGen { public HSHA512() { super("HmacSHA512", 512); } }
        public static final class DESede extends SecretGen { public DESede() { super("DESede", 168); } }
    }

    public static class PairGen extends KeyPairGeneratorSpi {
        private final String mAlgorithm;
        private String mAlias; private AlgorithmParameterSpec mSpec; private int mSize;
        PairGen(String algorithm) { mAlgorithm = algorithm; mSize = "EC".equals(algorithm) ? 256 : 2048; }
        @Override public void initialize(int keysize, SecureRandom random) { mSize = keysize; }
        @Override public void initialize(AlgorithmParameterSpec params, SecureRandom random) throws InvalidAlgorithmParameterException {
            mAlias = aliasOf(params);
            if (mAlias == null) throw new InvalidAlgorithmParameterException("expected a KeyGenParameterSpec");
            mSize = sizeOf(params, mSize);
            mSpec = params instanceof android.security.keystore.KeyGenParameterSpec ? ((android.security.keystore.KeyGenParameterSpec) params).getAlgorithmParameterSpec() : null;
        }
        @Override public KeyPair generateKeyPair() {
            try {
                KeyPairGenerator g = null;
                for (Provider p : Security.getProviders()) {
                    if (p instanceof KeyStoreProvider) continue;
                    try { g = KeyPairGenerator.getInstance(mAlgorithm, p); break; } catch (NoSuchAlgorithmException e) {}
                }
                if (g == null) throw new ProviderException("no " + mAlgorithm + " key pair generator");
                if (mSpec != null) g.initialize(mSpec);
                else if ("EC".equals(mAlgorithm)) g.initialize(new ECGenParameterSpec(mSize == 384 ? "secp384r1" : mSize == 521 ? "secp521r1" : "secp256r1"));
                else g.initialize(new RSAKeyGenParameterSpec(mSize, RSAKeyGenParameterSpec.F4));
                KeyPair kp = g.generateKeyPair();
                if (mAlias != null) { Entry e = new Entry(); e.secretOrPrivate = kp.getPrivate(); e.publicKey = kp.getPublic(); put(mAlias, e); }
                return kp;
            } catch (GeneralSecurityException e) {
                throw new ProviderException(e);
            }
        }
        public static final class RSA extends PairGen { public RSA() { super("RSA"); } }
        public static final class EC extends PairGen { public EC() { super("EC"); } }
    }

    /**
     * "AndroidKeyStoreBCWorkaround": the provider Android pairs with AndroidKeyStore for using its keys (Cipher.getInstance(t,
     * "AndroidKeyStoreBCWorkaround"), as flutter_secure_storage and others ask for by name). The keys are ordinary ones here, so each
     * cipher is the default providers' own, PKCS7Padding spelled as they spell it.
     */
    public static final class BCWorkaround extends Provider {
        static final String[] CIPHERS = { "AES/GCM/NoPadding", "AES/CBC/NoPadding", "AES/CBC/PKCS7Padding", "AES/CTR/NoPadding", "AES/ECB/NoPadding",
            "AES/ECB/PKCS7Padding", "RSA/ECB/NoPadding", "RSA/ECB/PKCS1Padding", "RSA/ECB/OAEPPadding", "RSA/ECB/OAEPWithSHA-1AndMGF1Padding",
            "RSA/ECB/OAEPWithSHA-224AndMGF1Padding", "RSA/ECB/OAEPWithSHA-256AndMGF1Padding", "RSA/ECB/OAEPWithSHA-384AndMGF1Padding",
            "RSA/ECB/OAEPWithSHA-512AndMGF1Padding", "DESede/CBC/NoPadding", "DESede/CBC/PKCS7Padding", "DESede/ECB/NoPadding", "DESede/ECB/PKCS7Padding" };
        public BCWorkaround() {
            super("AndroidKeyStoreBCWorkaround", 1.0, "Husk's AndroidKeyStore ciphers");
            for (int i = 0; i < CIPHERS.length; i++) put("Cipher." + CIPHERS[i], Delegate.class.getName() + "$C" + i);
        }
    }
    public static final class ImportedGCM extends Delegate { public ImportedGCM() { super(0); } }
    /** A cipher of the default providers, for a transformation fixed by the subclass. */
    public static class Delegate extends javax.crypto.CipherSpi {
        private final String mTransformation;
        private javax.crypto.Cipher mCipher;
        Delegate(int i) { mTransformation = BCWorkaround.CIPHERS[i].replace("PKCS7Padding", "PKCS5Padding"); }
        private javax.crypto.Cipher c() {
            if (mCipher == null) {
                try {
                    for (Provider provider : Security.getProviders()) {
                        if (provider instanceof KeyStoreProvider || provider instanceof BCWorkaround) continue;
                        try { mCipher = javax.crypto.Cipher.getInstance(mTransformation, provider); break; }
                        catch (GeneralSecurityException ignored) {}
                    }
                    if (mCipher == null) throw new NoSuchAlgorithmException(mTransformation);
                }
                catch (GeneralSecurityException e) { throw new ProviderException("no " + mTransformation + ": " + e); }
            }
            return mCipher;
        }
        @Override protected void engineSetMode(String m) {}
        @Override protected void engineSetPadding(String p) {}
        @Override protected int engineGetBlockSize() { return c().getBlockSize(); }
        @Override protected int engineGetOutputSize(int n) { return c().getOutputSize(n); }
        @Override protected byte[] engineGetIV() { return c().getIV(); }
        @Override protected AlgorithmParameters engineGetParameters() { return c().getParameters(); }
        @Override protected void engineInit(int op, Key k, SecureRandom r) throws InvalidKeyException { c().init(op, KeyStoreImport.forCipher(k, op, mTransformation, false), r); }
        @Override protected void engineInit(int op, Key k, AlgorithmParameterSpec p, SecureRandom r) throws InvalidKeyException, InvalidAlgorithmParameterException { c().init(op, KeyStoreImport.forCipher(k, op, mTransformation, p != null), p, r); }
        @Override protected void engineInit(int op, Key k, AlgorithmParameters p, SecureRandom r) throws InvalidKeyException, InvalidAlgorithmParameterException { c().init(op, KeyStoreImport.forCipher(k, op, mTransformation, p != null), p, r); }
        @Override protected byte[] engineUpdate(byte[] in, int off, int len) { return c().update(in, off, len); }
        @Override protected int engineUpdate(byte[] in, int off, int len, byte[] out, int outOff) throws javax.crypto.ShortBufferException { return c().update(in, off, len, out, outOff); }
        @Override protected void engineUpdateAAD(byte[] src, int off, int len) { c().updateAAD(src, off, len); }
        @Override protected byte[] engineDoFinal(byte[] in, int off, int len) throws javax.crypto.IllegalBlockSizeException, javax.crypto.BadPaddingException { return c().doFinal(in, off, len); }
        @Override protected int engineDoFinal(byte[] in, int off, int len, byte[] out, int outOff) throws javax.crypto.ShortBufferException, javax.crypto.IllegalBlockSizeException, javax.crypto.BadPaddingException { return c().doFinal(in, off, len, out, outOff); }
        @Override protected byte[] engineWrap(Key k) throws javax.crypto.IllegalBlockSizeException, InvalidKeyException { return c().wrap(k); }
        @Override protected Key engineUnwrap(byte[] w, String alg, int type) throws InvalidKeyException, NoSuchAlgorithmException { return c().unwrap(w, alg, type); }
        public static final class C0 extends Delegate { public C0() { super(0); } }
        public static final class C1 extends Delegate { public C1() { super(1); } }
        public static final class C2 extends Delegate { public C2() { super(2); } }
        public static final class C3 extends Delegate { public C3() { super(3); } }
        public static final class C4 extends Delegate { public C4() { super(4); } }
        public static final class C5 extends Delegate { public C5() { super(5); } }
        public static final class C6 extends Delegate { public C6() { super(6); } }
        public static final class C7 extends Delegate { public C7() { super(7); } }
        public static final class C8 extends Delegate { public C8() { super(8); } }
        public static final class C9 extends Delegate { public C9() { super(9); } }
        public static final class C10 extends Delegate { public C10() { super(10); } }
        public static final class C11 extends Delegate { public C11() { super(11); } }
        public static final class C12 extends Delegate { public C12() { super(12); } }
        public static final class C13 extends Delegate { public C13() { super(13); } }
        public static final class C14 extends Delegate { public C14() { super(14); } }
        public static final class C15 extends Delegate { public C15() { super(15); } }
        public static final class C16 extends Delegate { public C16() { super(16); } }
        public static final class C17 extends Delegate { public C17() { super(17); } }
    }
}
