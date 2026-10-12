package com.quantokx.api;
import java.util.*;

public final class Resp {
    public final int code; public final String message; public final Object data;
    public Resp(int c, String m, Object d) { code=c; message=m; data=d; }
    public static Resp ok(Object d) { return new Resp(0, "success", d); }
    public static Resp ok(String m, Object d) { return new Resp(0, m, d); }
    public static Map<String, Object> map(Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (int i = 0; i + 1 < kv.length; i += 2) m.put((String) kv[i], kv[i + 1]);
        return m;
    }
    public static Map<String, Object> eo() { return new LinkedHashMap<>(); }
}
