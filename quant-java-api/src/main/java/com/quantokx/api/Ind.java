package com.quantokx.api;
import java.util.*;

public final class Ind {
    public record Bar(double open, double high, double low, double close, double volume) {}
    public static List<Bar> bars(List<List<Object>> data) {
        List<Bar> out = new ArrayList<>();
        if (data == null) return out;
        for (List<Object> r : data) {
            if (r == null || r.size() < 5) continue;
            double c = num(r.get(4));
            out.add(new Bar(num(r.get(1), c), num(r.get(2), c), num(r.get(3), c), c, num(r.get(5), 0)));
        }
        return out;
    }
    public static List<Double> closes(List<Bar> bars) { List<Double> o = new ArrayList<>(); for (Bar b : bars) o.add(b.close()); return o; }
    public static List<Double> sma(List<Double> v, int p) {
        List<Double> o = new ArrayList<>(Collections.nCopies(v.size(), (Double)null));
        double s = 0;
        for (int i = 0; i < v.size(); i++) { s += v.get(i); if (i >= p) s -= v.get(i-p); if (i >= p-1) o.set(i, s/p); }
        return o;
    }
    public static List<Double> ema(List<Double> v, int p) {
        List<Double> o = new ArrayList<>(Collections.nCopies(v.size(), (Double)null));
        if (v.size() < p) return o;
        double k = 2.0/(p+1), e = 0;
        for (int i = 0; i < p; i++) e += v.get(i);
        e /= p; o.set(p-1, e);
        for (int i = p; i < v.size(); i++) { e = v.get(i)*k + e*(1-k); o.set(i, e); }
        return o;
    }
    public static List<Double> rsi(List<Double> v, int p) {
        List<Double> o = new ArrayList<>(Collections.nCopies(v.size(), (Double)null));
        if (v.size() <= p) return o;
        double g = 0, l = 0;
        for (int i = 1; i <= p; i++) { double d = v.get(i)-v.get(i-1); if (d>0) g += d; else l -= d; }
        g /= p; l /= p;
        o.set(p, l == 0 ? 100.0 : 100 - 100.0/(1+g/l));
        for (int i = p+1; i < v.size(); i++) {
            double d = v.get(i)-v.get(i-1);
            g = (g*(p-1) + Math.max(d,0))/p; l = (l*(p-1) + Math.max(-d,0))/p;
            o.set(i, l == 0 ? 100.0 : 100 - 100.0/(1+g/l));
        }
        return o;
    }
    public static Map<String, List<Double>> macd(List<Double> v, int f, int s, int sig) {
        var ef = ema(v, f); var es = ema(v, s);
        List<Double> dif = new ArrayList<>(Collections.nCopies(v.size(), (Double)null));
        for (int i = 0; i < v.size(); i++) if (ef.get(i) != null && es.get(i) != null) dif.set(i, ef.get(i)-es.get(i));
        List<Double> dc = new ArrayList<>(); for (Double x : dif) if (x != null) dc.add(x);
        var dea = ema(dc, sig);
        List<Double> deaF = new ArrayList<>(Collections.nCopies(v.size(), (Double)null));
        int base = v.size() - dc.size();
        for (int i = 0; i < dea.size(); i++) deaF.set(base+i, dea.get(i));
        List<Double> hist = new ArrayList<>(Collections.nCopies(v.size(), (Double)null));
        for (int i = 0; i < v.size(); i++) if (dif.get(i) != null && deaF.get(i) != null) hist.set(i, (dif.get(i)-deaF.get(i))*2);
        return Map.of("dif", dif, "dea", deaF, "hist", hist);
    }
    public static Map<String, List<Double>> boll(List<Double> v, int p, double k) {
        var mid = sma(v, p);
        List<Double> up = new ArrayList<>(Collections.nCopies(v.size(), (Double)null));
        List<Double> lo = new ArrayList<>(Collections.nCopies(v.size(), (Double)null));
        for (int i = p-1; i < v.size(); i++) {
            double m = mid.get(i), sq = 0;
            for (int j = i-p+1; j <= i; j++) sq += Math.pow(v.get(j)-m, 2);
            double sd = Math.sqrt(sq/p);
            up.set(i, m+k*sd); lo.set(i, m-k*sd);
        }
        return Map.of("mid", mid, "upper", up, "lower", lo);
    }
    public static List<Double> atr(List<Bar> bars, int p) {
        List<Double> o = new ArrayList<>(Collections.nCopies(bars.size(), (Double)null));
        List<Double> tr = new ArrayList<>();
        for (int i = 0; i < bars.size(); i++) {
            if (i == 0) { tr.add(bars.get(i).high()-bars.get(i).low()); continue; }
            Bar b = bars.get(i), pr = bars.get(i-1);
            tr.add(Math.max(b.high()-b.low(), Math.max(Math.abs(b.high()-pr.close()), Math.abs(b.low()-pr.close()))));
        }
        if (bars.size() <= p) return o;
        double a = 0;
        for (int i = 1; i <= p; i++) a += tr.get(i);
        a /= p; o.set(p, a);
        for (int i = p+1; i < bars.size(); i++) { a = (a*(p-1)+tr.get(i))/p; o.set(i, a); }
        return o;
    }
    public static Map<String, List<Double>> kdj(List<Bar> bars, int p) {
        List<Double> k = new ArrayList<>(Collections.nCopies(bars.size(), (Double)null));
        List<Double> d = new ArrayList<>(Collections.nCopies(bars.size(), (Double)null));
        List<Double> j = new ArrayList<>(Collections.nCopies(bars.size(), (Double)null));
        double kv = 50, dv = 50;
        for (int i = 0; i < bars.size(); i++) {
            if (i < p-1) continue;
            double hh = -Double.MAX_VALUE, ll = Double.MAX_VALUE;
            for (int x = i-p+1; x <= i; x++) { hh = Math.max(hh, bars.get(x).high()); ll = Math.min(ll, bars.get(x).low()); }
            double rsv = hh == ll ? 50 : (bars.get(i).close()-ll)/(hh-ll)*100;
            kv = rsv/3 + kv*2/3; dv = kv/2 + dv*2/3;
            j.set(i, 3*kv-2*dv); k.set(i, kv); d.set(i, dv);
        }
        return Map.of("k", k, "d", d, "j", j);
    }
    public static Map<String, List<Double>> donchian(List<Bar> bars, int p) {
        List<Double> up = new ArrayList<>(Collections.nCopies(bars.size(), (Double)null));
        List<Double> lo = new ArrayList<>(Collections.nCopies(bars.size(), (Double)null));
        for (int i = p-1; i < bars.size(); i++) {
            double hh = -Double.MAX_VALUE, ll = Double.MAX_VALUE;
            for (int x = i-p+1; x <= i; x++) { hh = Math.max(hh, bars.get(x).high()); ll = Math.min(ll, bars.get(x).low()); }
            up.set(i, hh); lo.set(i, ll);
        }
        return Map.of("upper", up, "lower", lo);
    }
    public static List<Double> supertrend(List<Bar> bars, int p, double mult) {
        var a = atr(bars, p);
        List<Double> o = new ArrayList<>(Collections.nCopies(bars.size(), (Double)null));
        Double trend = null; double upper = 0, lower = 0;
        for (int i = p; i < bars.size(); i++) {
            if (a.get(i) == null) continue;
            double mid = (bars.get(i).high()+bars.get(i).low())/2;
            double ub = mid+mult*a.get(i), lb = mid-mult*a.get(i);
            double c = bars.get(i).close();
            if (trend == null) { upper = ub; lower = lb; trend = c >= mid ? lb : ub; o.set(i, trend); continue; }
            if (c > upper) trend = lb; else if (c < lower) trend = ub;
            else { upper = Math.min(upper, ub); lower = Math.max(lower, lb); }
            o.set(i, trend);
        }
        return o;
    }
    public static List<Double> momentum(List<Double> v, int p) {
        List<Double> o = new ArrayList<>(Collections.nCopies(v.size(), (Double)null));
        for (int i = p; i < v.size(); i++) o.set(i, v.get(i)-v.get(i-p));
        return o;
    }
    public static double last(List<Double> v) { for (int i = v.size()-1; i >= 0; i--) if (v.get(i) != null) return v.get(i); return 0; }
    private Ind() {}
}
