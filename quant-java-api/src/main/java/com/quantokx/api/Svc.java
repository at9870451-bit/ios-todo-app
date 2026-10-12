package com.quantokx.api;
import java.util.*;

public final class Svc {
    public static List<String> normalizeSymbols(String raw, String marketType) {
        List<String> out = new ArrayList<>();
        if (raw == null) return out;
        String suffix = "swap".equalsIgnoreCase(marketType) ? "-USDT-SWAP" : "-USDT";
        for (String s : raw.split("[\\s,，;；、]+")) {
            s = s.trim().toUpperCase();
            if (s.isEmpty()) continue;
            String inst = normalizeInstId(s, "swap".equalsIgnoreCase(marketType) ? "SWAP" : "SPOT");
            if (inst.isEmpty() || out.contains(inst)) continue;
            out.add(inst);
            if (out.size() >= 12) break;
        }
        return out;
    }
    public static String normalizeInstId(String s, String instType) {
        s = s.trim().toUpperCase();
        if (s.isEmpty()) return "";
        if ("SPOT".equals(instType)) { if (s.endsWith("-SWAP")) s = s.substring(0, s.length()-5); return s; }
        if (s.endsWith("-SWAP")) return s;
        if (s.endsWith("-USDT") || s.endsWith("-USD")) return s + "-SWAP";
        return s + "-USDT-SWAP";
    }
    public static record Conv(String qty, boolean converted) {}
    public static Conv coinsToContracts(double qty, Okx.Inst spec) {
        if (spec.ctVal() <= 0) return new Conv(String.valueOf(qty), false);
        double contracts = qty / spec.ctVal();
        double aligned = alignTo(contracts, spec.lotSz());
        return new Conv(Okx.fmtPx(aligned), true);
    }
    public static double alignTo(double v, double step) { if (step <= 0) return v; return Math.floor(v / step + 1e-9) * step; }
    public static record TpSl(String sl, String tp, List<String> skipped) {}
    public static TpSl sanitizeTpSl(String side, double ref, String sl, String tp, double slPct, double tpPct) {
        List<String> sk = new ArrayList<>();
        boolean buy = "BUY".equalsIgnoreCase(side);
        double slV = parse(sl), tpV = parse(tp);
        if (slV <= 0 && ref > 0) slV = buy ? ref * (1 - slPct/100) : ref * (1 + slPct/100);
        if (tpV <= 0 && ref > 0) tpV = buy ? ref * (1 + tpPct/100) : ref * (1 - tpPct/100);
        if (slV <= 0 || tpV <= 0 || ref <= 0) return new TpSl("", "", sk);
        if (buy) { if (slV >= ref) sk.add("SL>H"); if (tpV <= ref) sk.add("TP<L"); }
        else { if (slV <= ref) sk.add("SL<L"); if (tpV >= ref) sk.add("TP>H"); }
        if (!sk.isEmpty()) return new TpSl("", "", sk);
        return new TpSl(Okx.fmtPx(slV), Okx.fmtPx(tpV), sk);
    }
    public static double parse(String s) { try { return Double.parseDouble(s); } catch (Exception e) { return 0; } }
    public static List<Map<String, Object>> mapTickers(List<Map<String, Object>> raw) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (var t : raw) {
            double last = num(t.get("last")), open = num(t.get("open24h"));
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("symbol", str(t.get("instId")));
            m.put("lastPrice", String.valueOf(last));
            m.put("highPrice", str(t.get("high24h")));
            m.put("lowPrice", str(t.get("low24h")));
            m.put("volume", str(t.get("vol24h")));
            m.put("priceChangePercent", String.valueOf(Math.round(open > 0 ? ((last-open)/open)*10000.0 : 0) / 10000.0));
            out.add(m);
        }
        return out;
    }
    public static String bar(String interval) {
        return switch (interval) { case "1h"->"1H"; case "2h"->"2H"; case "4h"->"4H"; case "6h"->"6H"; case "12h"->"12H"; case "1d"->"1D"; case "1w"->"1W"; default->interval; };
    }
    public static String str(Object o) { return o == null ? "" : o.toString(); }
    public static double num(Object o) { return num(o, 0); }
    public static double num(Object o, double d) { if (o == null) return d; if (o instanceof Number n) return n.doubleValue(); try { return Double.parseDouble(o.toString()); } catch (Exception e) { return d; } }
    private Svc() {}
}
