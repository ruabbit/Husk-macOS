package org.husk.nativeboot;
public class Provider extends android.content.ContentProvider {
    public boolean onCreate() { if (Bootstrap.stage != 1) throw new AssertionError("provider before application attach"); Bootstrap.stage=2; return true; }
    public android.database.Cursor query(android.net.Uri u,String[] p,String s,String[] a,String o) { return null; }
    public String getType(android.net.Uri u) { return null; }
    public android.net.Uri insert(android.net.Uri u,android.content.ContentValues v) { return null; }
    public int delete(android.net.Uri u,String s,String[] a) { return 0; }
    public int update(android.net.Uri u,android.content.ContentValues v,String s,String[] a) { return 0; }
}
