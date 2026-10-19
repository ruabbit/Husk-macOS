package husk;

import android.app.Activity;
import android.content.ClipData;
import android.content.ContentProvider;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.util.ArrayList;

/**
 * The system's file picker (GET_CONTENT, OPEN_DOCUMENT, PICK): the host shows its document picker and copies what the user
 * picks into the app's cache; the caller gets content://husk.documents/document/<path> URIs, which this provider opens and
 * describes (display name, size, MIME type) like Android's documents providers do.
 */
public final class Documents extends ContentProvider {
    public static final String AUTHORITY = "husk.documents";
    private static final Documents sSelf = new Documents();
    private static Activity sCaller;
    private static int sRequest;
    private static final ArrayList<String> sPicked = new ArrayList<>();
    private static final java.util.HashSet<String> sGranted = new java.util.HashSet<>();

    static { ContentResolver.register(AUTHORITY, sSelf); }

    /** Whether the intent asks for the system's file picker. */
    public static boolean handles(Intent i) {
        String a = i.getAction();
        if (Intent.ACTION_GET_CONTENT.equals(a) || Intent.ACTION_OPEN_DOCUMENT.equals(a)) return true;
        if (!Intent.ACTION_PICK.equals(a)) return false;
        // PICK from the gallery (images, videos) or with only a type; contacts and other pickers are not files
        Uri d = i.getData();
        String t = i.getType();
        return d == null ? t != null && (t.startsWith("image/") || t.startsWith("video/") || t.startsWith("audio/") || t.equals("*/*"))
                         : "media".equals(d.getAuthority());
    }

    /** Opens the host's picker for the caller's request; the answer comes back through deliver(). */
    public static void pick(Activity caller, Intent i, int request) {
        // The shared host ABI has no request IDs. Keep the first request alive so
        // its eventual answer cannot be delivered to a different Activity.
        if (sCaller != null) {
            if (caller != null && request >= 0) caller.huskActivityResult(request, Activity.RESULT_CANCELED, null);
            return;
        }
        if (caller == null) return;
        sCaller = caller;
        sRequest = request;
        sPicked.clear();
        StringBuilder types = new StringBuilder();
        String[] extra = i.getStringArrayExtra(Intent.EXTRA_MIME_TYPES);
        if (extra != null) for (String t : extra) { if (types.length() > 0) types.append(','); types.append(t); }
        if (types.length() == 0) types.append(i.getType() != null ? i.getType() : "*/*");
        boolean multiple = i.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false);
        android.util.Log.d("Husk", "file picker for " + types + (multiple ? " (several)" : ""));
        Native.pickDocuments(types.toString(), multiple);
    }

    /** One item of the host's answer: "f<path>" a picked file, "F" the picker closed. */
    static void deliver(String item) {
        if (sCaller == null || item == null || item.isEmpty()) return;
        if (item.charAt(0) == 'f') sPicked.add(item.substring(1));
        else finishPick(true);
    }

    private static void finishPick(boolean answer) {
        Activity caller = sCaller;
        int request = sRequest;
        sCaller = null;
        ArrayList<String> picked = new ArrayList<>(sPicked);
        sPicked.clear();
        if (caller == null || request < 0) return;
        if (!answer || picked.isEmpty()) { caller.huskActivityResult(request, Activity.RESULT_CANCELED, null); return; }
        synchronized (sGranted) { for (String path : picked) sGranted.add(canonical(new File(path))); }
        Intent data = new Intent();
        Uri first = uriFor(new File(picked.get(0)));
        data.setData(first);
        ClipData clip = ClipData.newRawUri(null, first);
        for (int k = 1; k < picked.size(); k++) clip.addItem(new ClipData.Item(uriFor(new File(picked.get(k)))));
        data.setClipData(clip);
        data.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        sPicked.clear();
        caller.huskActivityResult(request, Activity.RESULT_OK, data);
    }

    public static Uri uriFor(File f) {
        return new Uri.Builder().scheme(ContentResolver.SCHEME_CONTENT).authority(AUTHORITY).appendPath("document").appendPath(f.getAbsolutePath()).build();
    }
    static void cancel() { finishPick(false); }
    static void cancelFor(Activity activity) { if (sCaller == activity) finishPick(false); }
    private static String canonical(File f) {
        try { return f.getCanonicalPath(); } catch (java.io.IOException e) { throw new SecurityException("Invalid document", e); }
    }
    private static File fileOf(Uri u) {
        java.util.List<String> seg = u.getPathSegments();
        if (!ContentResolver.SCHEME_CONTENT.equals(u.getScheme()) || !AUTHORITY.equals(u.getAuthority()) ||
                seg.size() != 2 || !"document".equals(seg.get(0))) throw new SecurityException("Invalid document URI");
        File file = new File(seg.get(1));
        synchronized (sGranted) { if (!sGranted.contains(canonical(file))) throw new SecurityException("Document was not selected"); }
        return file;
    }

    // ---- the provider
    @Override public boolean onCreate() { return true; }
    @Override public Cursor query(Uri u, String[] proj, String sel, String[] args, String sort) {
        File f = fileOf(u);
        String[] cols = proj != null ? proj : new String[] { "_display_name", "_size", "mime_type", "document_id", "last_modified", "flags" };
        MatrixCursor c = new MatrixCursor(cols);
        if (!f.exists()) return c;
        Object[] row = new Object[cols.length];
        for (int k = 0; k < cols.length; k++) {
            switch (cols[k]) {
            case "_display_name": row[k] = f.getName(); break;
            case "_size": row[k] = f.length(); break;
            case "mime_type": row[k] = getType(u); break;
            case "document_id": case "_id": row[k] = f.getAbsolutePath(); break;
            case "last_modified": case "date_modified": row[k] = f.lastModified(); break;
            case "flags": row[k] = 0; break; // copies are exposed through a read-only grant
            case "_data": row[k] = f.getAbsolutePath(); break;
            default: row[k] = null;
            }
        }
        c.addRow(row);
        return c;
    }
    @Override public String getType(Uri u) {
        String t = java.net.URLConnection.guessContentTypeFromName(fileOf(u).getName());
        return t != null ? t : "application/octet-stream";
    }
    @Override public ParcelFileDescriptor openFile(Uri u, String mode) throws java.io.FileNotFoundException {
        if (!"r".equals(mode)) throw new java.io.FileNotFoundException("Document grant is read-only");
        return ParcelFileDescriptor.open(fileOf(u), ParcelFileDescriptor.parseMode(mode));
    }
    @Override public Uri insert(Uri u, ContentValues v) { return null; }
    @Override public int delete(Uri u, String sel, String[] args) { fileOf(u); return 0; }
    @Override public int update(Uri u, ContentValues v, String sel, String[] args) { return 0; }
}
