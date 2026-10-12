package com.quantokx.api;
import java.util.*;

public final class StrategyEngine {
    public record Decision(String signal, double confidence, double price, String reason, Map<String, Object> indicators) {}
    public record Bar(double open, double high, double low, double close, double volume) {}

    public static List<Map<String, Object>> meta() {
        List<Map<String, Object>> out = new ArrayList<>();
        String[][] types = {
            {"ma","双均线交叉 MA","趋势","spot,swap","短期均线上穿长期均线做多，下穿做空。","short:7,long:25"},
            {"ema","EMA 指数均线","趋势","spot,swap","指数加权双均线。","short:12,long:26"},
            {"macd","MACD 动能","趋势","spot,swap","DIF 与 DEA 金叉死叉。","fast:12,slow:26,signal:9"},
            {"rsi","RSI 相对强弱","震荡","spot,swap","RSI 超卖做多、超买做空。","period:14,oversold:30,overbought:70"},
            {"boll","布林带 BOLL","震荡","spot,swap","触及下轨做多、触及上轨做空。","period:20,k:2"},
            {"kdj","KDJ 随机指标","震荡","swap","K 上穿 D 做多，K 下穿 D 做空。","period:9"},
            {"atr","ATR 波动突破","趋势","swap","以 ATR 为通道的波动突破。","period:14,mult:2"},
            {"donchian","唐奇安通道","趋势","swap","突破 N 周期最高价做多。","period:20"},
            {"supertrend","SuperTrend 超级趋势","趋势","swap","ATR 自适应趋势线翻转。","period:10,mult:3"},
            {"momentum","动量 Momentum","趋势","spot,swap","N 周期动量转正做多。","period:10"},
            {"grid","网格交易 Grid","震荡","spot,swap","按价格区间自动挂网格买卖单。","grid_num:10,range_pct:10"},
            {"dca","定投 DCA","长期","spot","定期定额买入。","period:60"},
            {"volume","量价确认 Volume","量价","spot,swap","放量确认的价格突破。","vol_mult:2"},
            {"macd_rsi","MACD+RSI 双确认","复合","swap","MACD 金叉且 RSI 未超买。","fast:12,slow:26,rsi_period:14"},
            {"signal","手动信号","工具","spot,swap","人工指定方向执行。","dummy:0"},
            {"martin","马丁格尔 Martin","震荡","swap","逆势加仓摊低成本。","step_mult:2,max_add:5"},
            {"dip","抄底 Dip","震荡","spot,swap","大幅回落后抄底做多。","dip_pct:5"},
            {"range_grid","区间网格 RangeGrid","震荡","swap","在固定价格区间内高抛低吸。","upper_pct:5,lower_pct:5"},
            {"fvg","公允价值缺口 FVG","形态","swap","三根K线构成的公允价值缺口回补。","min_gap:0.3"},
            {"ob","订单块 OB","形态","swap","机构订单块回踩确认交易。","confirm_bars:3"},
            {"sweep","流动性扫单 Sweep","形态","swap","扫过前低/前高后反转的流动性猎取。","lookback:20"}
        };
        for (String[] t : types) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("key", t[0]); m.put("name", t[1]); m.put("group", t[2]);
            m.put("markets", Arrays.asList(t[3].split(","))); m.put("desc", t[4]);
            List<Map<String, Object>> ps = new ArrayList<>();
            for (String p : t[5].split(",")) {
                String[] kv = p.split(":");
                Map<String, Object> pm = new LinkedHashMap<>();
                pm.put("key", kv[0]); pm.put("label", kv[0]); pm.put("type", "float");
                pm.put("default", Double.parseDouble(kv[1])); pm.put("min", 1.0); pm.put("max", 500.0);
                ps.add(pm);
            }
            m.put("params", ps);
            out.add(m);
        }
        return out;
    }

    public static Decision evaluate(String className, Map<String, Object> P, List<Ind.Bar> bars) {
        double price = bars.isEmpty() ? 0 : bars.get(bars.size()-1).close();
        Map<String, Double> p = new HashMap<>();
        if (P != null) for (var e : P.entrySet()) p.put(e.getKey(), Svc.num(e.getValue()));
        try {
            Decision d = switch (className) {
                case "ma" -> evalMa(bars, (int)p.getOrDefault("short", 7.0), (int)p.getOrDefault("long", 25.0));
                case "ema" -> evalEma(bars, (int)p.getOrDefault("short", 12.0), (int)p.getOrDefault("long", 26.0));
                case "macd" -> evalMacd(bars, (int)p.getOrDefault("fast", 12.0), (int)p.getOrDefault("slow", 26.0), (int)p.getOrDefault("signal", 9.0));
                case "rsi" -> evalRsi(bars, (int)p.getOrDefault("period", 14.0), p.getOrDefault("oversold", 30.0), p.getOrDefault("overbought", 70.0));
                case "boll" -> evalBoll(bars, (int)p.getOrDefault("period", 20.0), p.getOrDefault("k", 2.0));
                case "kdj" -> evalKdj(bars, (int)p.getOrDefault("period", 9.0));
                case "atr" -> evalAtr(bars, (int)p.getOrDefault("period", 14.0), p.getOrDefault("mult", 2.0));
                case "donchian" -> evalDonchian(bars, (int)p.getOrDefault("period", 20.0));
                case "supertrend" -> evalSupertrend(bars, (int)p.getOrDefault("period", 10.0), p.getOrDefault("mult", 3.0));
                case "momentum" -> evalMomentum(bars, (int)p.getOrDefault("period", 10.0));
                case "grid", "range_grid" -> evalRange(bars, p.getOrDefault("range_pct", 5.0), p.getOrDefault("upper_pct", 5.0), p.getOrDefault("lower_pct", 5.0));
                case "dca" -> new Decision("BUY", 1.0, price, "定投买入", Map.of());
                case "volume" -> evalVolume(bars, p.getOrDefault("vol_mult", 2.0));
                case "macd_rsi" -> evalMacdRsi(bars, (int)p.getOrDefault("fast", 12.0), (int)p.getOrDefault("slow", 26.0), (int)p.getOrDefault("rsi_period", 14.0));
                case "martin" -> evalRange(bars, 3.0, 3.0, 3.0);
                case "dip" -> evalDip(bars, p.getOrDefault("dip_pct", 5.0));
                case "fvg" -> evalFvg(bars, p.getOrDefault("min_gap", 0.3));
                case "ob" -> evalOb(bars, (int)p.getOrDefault("confirm_bars", 3.0));
                case "sweep" -> evalSweep(bars, (int)p.getOrDefault("lookback", 20.0));
                default -> new Decision("HOLD", 0.0, price, "未知策略 " + className, Map.of());
            };
            return new Decision(d.signal(), Math.max(0, Math.min(1, d.confidence())), price, d.reason(), d.indicators());
        } catch (Exception e) {
            return new Decision("HOLD", 0.0, price, "策略计算异常：" + e.getMessage(), Map.of());
        }
    }

    private static Decision evalMa(List<Ind.Bar> bars, int sp, int lp) {
        var c = Ind.closes(bars); var s = Ind.sma(c, sp); var l = Ind.sma(c, lp);
        int i = bars.size()-1;
        if (s.get(i)==null || l.get(i)==null || s.get(i-1)==null) return hold(bars, "数据不足");
        if (s.get(i-1)<=l.get(i-1) && s.get(i)>l.get(i)) return new Decision("BUY", 0.62, c.get(i), "MA金叉", Map.of("short",s.get(i),"long",l.get(i)));
        if (s.get(i-1)>=l.get(i-1) && s.get(i)<l.get(i)) return new Decision("SELL", 0.62, c.get(i), "MA死叉", Map.of("short",s.get(i),"long",l.get(i)));
        return new Decision("HOLD", 0.3, c.get(i), "MA无交叉", Map.of("short",s.get(i),"long",l.get(i)));
    }
    private static Decision evalEma(List<Ind.Bar> bars, int sp, int lp) {
        var c = Ind.closes(bars); var s = Ind.ema(c, sp); var l = Ind.ema(c, lp);
        int i = bars.size()-1;
        if (s.get(i)==null || l.get(i)==null || s.get(i-1)==null) return hold(bars, "数据不足");
        if (s.get(i-1)<=l.get(i-1) && s.get(i)>l.get(i)) return new Decision("BUY", 0.62, c.get(i), "EMA金叉", Map.of());
        if (s.get(i-1)>=l.get(i-1) && s.get(i)<l.get(i)) return new Decision("SELL", 0.62, c.get(i), "EMA死叉", Map.of());
        return new Decision("HOLD", 0.3, c.get(i), "EMA持续", Map.of());
    }
    private static Decision evalMacd(List<Ind.Bar> bars, int f, int s, int sig) {
        var c = Ind.closes(bars); var m = Ind.macd(c, f, s, sig);
        int i = bars.size()-1;
        if (m.get("dif").get(i)==null || m.get("dea").get(i)==null || m.get("dif").get(i-1)==null) return hold(bars, "数据不足");
        if (m.get("dif").get(i-1)<=m.get("dea").get(i-1) && m.get("dif").get(i)>m.get("dea").get(i)) return new Decision("BUY", 0.65, c.get(i), "MACD金叉", Map.of("dif",m.get("dif").get(i),"dea",m.get("dea").get(i)));
        if (m.get("dif").get(i-1)>=m.get("dea").get(i-1) && m.get("dif").get(i)<m.get("dea").get(i)) return new Decision("SELL", 0.65, c.get(i), "MACD死叉", Map.of("dif",m.get("dif").get(i),"dea",m.get("dea").get(i)));
        return new Decision("HOLD", 0.3, c.get(i), "MACD无交叉", Map.of());
    }
    private static Decision evalRsi(List<Ind.Bar> bars, int p, double os, double ob) {
        var c = Ind.closes(bars); var r = Ind.rsi(c, p);
        int i = bars.size()-1;
        if (r.get(i)==null) return hold(bars, "数据不足");
        double v = r.get(i);
        if (v<=os) return new Decision("BUY", 0.6+(os-v)/100, c.get(i), "RSI超卖 "+fmt(v), Map.of("rsi",v));
        if (v>=ob) return new Decision("SELL", 0.6+(v-ob)/100, c.get(i), "RSI超买 "+fmt(v), Map.of("rsi",v));
        return new Decision("HOLD", 0.3, c.get(i), "RSI中性", Map.of("rsi",v));
    }
    private static Decision evalBoll(List<Ind.Bar> bars, int p, double k) {
        var c = Ind.closes(bars); var b = Ind.boll(c, p, k);
        int i = bars.size()-1;
        if (b.get("mid").get(i)==null) return hold(bars, "数据不足");
        double up = b.get("upper").get(i), lo = b.get("lower").get(i), cl = c.get(i);
        if (cl<=lo) return new Decision("BUY", 0.62, cl, "触及布林下轨", Map.of("lower",lo,"upper",up));
        if (cl>=up) return new Decision("SELL", 0.62, cl, "触及布林上轨", Map.of("lower",lo,"upper",up));
        return new Decision("HOLD", 0.3, cl, "通道内", Map.of());
    }
    private static Decision evalKdj(List<Ind.Bar> bars, int p) {
        var d = Ind.kdj(bars, p);
        int i = bars.size()-1;
        if (d.get("k").get(i)==null || d.get("k").get(i-1)==null) return hold(bars, "数据不足");
        double k = d.get("k").get(i), dv = d.get("d").get(i), kP = d.get("k").get(i-1), dP = d.get("d").get(i-1);
        if (kP<=dP && k>dv) return new Decision("BUY", 0.6, bars.get(i).close(), "KDJ金叉", Map.of("k",k,"d",dv));
        if (kP>=dP && k<dv) return new Decision("SELL", 0.6, bars.get(i).close(), "KDJ死叉", Map.of("k",k,"d",dv));
        return new Decision("HOLD", 0.3, bars.get(i).close(), "KDJ无交叉", Map.of());
    }
    private static Decision evalAtr(List<Ind.Bar> bars, int p, double mult) {
        var a = Ind.atr(bars, p);
        int i = bars.size()-1;
        if (a.get(i)==null || a.get(i-1)==null) return hold(bars, "数据不足");
        double c = bars.get(i).close(), mid = (bars.get(i).high()+bars.get(i).low())/2;
        double up = mid+mult*a.get(i), lo = mid-mult*a.get(i);
        if (c>up) return new Decision("BUY", 0.6, c, "突破ATR上轨", Map.of("up",up,"lo",lo));
        if (c<lo) return new Decision("SELL", 0.6, c, "跌破ATR下轨", Map.of("up",up,"lo",lo));
        return new Decision("HOLD", 0.3, c, "ATR通道内", Map.of());
    }
    private static Decision evalDonchian(List<Ind.Bar> bars, int p) {
        var d = Ind.donchian(bars, p);
        int i = bars.size()-1;
        if (d.get("upper").get(i)==null || d.get("upper").get(i-1)==null) return hold(bars, "数据不足");
        double c = bars.get(i).close(), up = d.get("upper").get(i-1), lo = d.get("lower").get(i-1);
        if (c>up) return new Decision("BUY", 0.63, c, "突破Donchian上轨", Map.of());
        if (c<lo) return new Decision("SELL", 0.63, c, "跌破Donchian下轨", Map.of());
        return new Decision("HOLD", 0.3, c, "通道内", Map.of());
    }
    private static Decision evalSupertrend(List<Ind.Bar> bars, int p, double mult) {
        var st = Ind.supertrend(bars, p, mult);
        int i = bars.size()-1;
        if (st.get(i)==null || st.get(i-1)==null) return hold(bars, "数据不足");
        double c = bars.get(i).close();
        boolean flipUp = st.get(i)<c && st.get(i-1)>bars.get(i-1).close();
        boolean flipDn = st.get(i)>c && st.get(i-1)<bars.get(i-1).close();
        if (flipUp) return new Decision("BUY", 0.64, c, "Supertrend翻多", Map.of("st",st.get(i)));
        if (flipDn) return new Decision("SELL", 0.64, c, "Supertrend翻空", Map.of("st",st.get(i)));
        return new Decision("HOLD", 0.3, c, "Supertrend持续", Map.of("st",st.get(i)));
    }
    private static Decision evalMomentum(List<Ind.Bar> bars, int p) {
        var c = Ind.closes(bars); var m = Ind.momentum(c, p);
        int i = bars.size()-1;
        if (m.get(i)==null || m.get(i-1)==null) return hold(bars, "数据不足");
        if (m.get(i)>0 && m.get(i-1)<=0) return new Decision("BUY", 0.6, c.get(i), "动量转正", Map.of("mom",m.get(i)));
        if (m.get(i)<0 && m.get(i-1)>=0) return new Decision("SELL", 0.6, c.get(i), "动量转负", Map.of("mom",m.get(i)));
        return new Decision("HOLD", 0.3, c.get(i), "动量持续", Map.of("mom",m.get(i)));
    }
    private static Decision evalRange(List<Ind.Bar> bars, double rangePct, double upperPct, double lowerPct) {
        int i = bars.size()-1;
        if (i<5) return hold(bars, "数据不足");
        double c = bars.get(i).close();
        double sum = 0; int n = 0;
        for (int x = Math.max(0,i-20); x <= i; x++) { sum += bars.get(x).close(); n++; }
        double base = sum/n, upper = base*(1+upperPct/100), lower = base*(1-lowerPct/100);
        if (c<=lower) return new Decision("BUY", 0.6, c, "触及区间下沿", Map.of("lower",lower,"upper",upper));
        if (c>=upper) return new Decision("SELL", 0.6, c, "触及区间上沿", Map.of("lower",lower,"upper",upper));
        return new Decision("HOLD", 0.3, c, "区间中", Map.of());
    }
    private static Decision evalVolume(List<Ind.Bar> bars, double volMult) {
        int i = bars.size()-1;
        if (i<20) return hold(bars, "数据不足");
        double vol = bars.get(i).volume(), avg = 0; int n = 0;
        for (int x = i-20; x < i; x++) { avg += bars.get(x).volume(); n++; }
        avg /= Math.max(n,1);
        double chg = bars.get(i).close()-bars.get(i-1).close();
        if (vol>avg*volMult && chg>0) return new Decision("BUY", 0.61, bars.get(i).close(), "放量上涨", Map.of());
        if (vol>avg*volMult && chg<0) return new Decision("SELL", 0.61, bars.get(i).close(), "放量下跌", Map.of());
        return new Decision("HOLD", 0.3, bars.get(i).close(), "量能平淡", Map.of());
    }
    private static Decision evalMacdRsi(List<Ind.Bar> bars, int f, int s, int rsiP) {
        var c = Ind.closes(bars); var m = Ind.macd(c, f, s, 9); var r = Ind.rsi(c, rsiP);
        int i = bars.size()-1;
        if (m.get("dif").get(i)==null || m.get("dif").get(i-1)==null || r.get(i)==null) return hold(bars, "数据不足");
        boolean golden = m.get("dif").get(i-1)<=m.get("dea").get(i-1) && m.get("dif").get(i)>m.get("dea").get(i);
        boolean dead = m.get("dif").get(i-1)>=m.get("dea").get(i-1) && m.get("dif").get(i)<m.get("dea").get(i);
        if (golden && r.get(i)<70) return new Decision("BUY", 0.66, c.get(i), "MACD金叉+RSI确认", Map.of("rsi",r.get(i)));
        if (dead && r.get(i)>30) return new Decision("SELL", 0.66, c.get(i), "MACD死叉+RSI确认", Map.of("rsi",r.get(i)));
        return new Decision("HOLD", 0.3, c.get(i), "双确认未满足", Map.of());
    }
    private static Decision evalDip(List<Ind.Bar> bars, double dipPct) {
        int i = bars.size()-1;
        if (i<20) return hold(bars, "数据不足");
        double c = bars.get(i).close(), hh = -Double.MAX_VALUE;
        for (int x = Math.max(0,i-20); x < i; x++) hh = Math.max(hh, bars.get(x).close());
        double drop = (hh-c)/hh*100;
        if (drop>=dipPct) return new Decision("BUY", 0.62, c, "回撤抄底", Map.of("drop",drop));
        return new Decision("HOLD", 0.3, c, "未达回撤阈值", Map.of("drop",drop));
    }
    private static Decision evalFvg(List<Ind.Bar> bars, double minGapPct) {
        int i = bars.size()-1;
        if (i<3) return hold(bars, "数据不足");
        Ind.Bar a = bars.get(i-2), b = bars.get(i-1), c = bars.get(i);
        double ref = a.high();
        double gapUp = a.high()-b.low(), gapDn = a.low()-b.high();
        if (gapUp>0 && gapUp/ref*100>=minGapPct) {
            double mid = (a.high()+b.low())/2;
            if (c.close()>=mid) return new Decision("SELL", 0.61, c.close(), "看涨FVG缺口回补", Map.of("gap",gapUp));
        }
        if (gapDn>0 && gapDn/ref*100>=minGapPct) {
            double mid = (a.low()+b.high())/2;
            if (c.close()<=mid) return new Decision("BUY", 0.61, c.close(), "看跌FVG缺口回补", Map.of("gap",gapDn));
        }
        return new Decision("HOLD", 0.3, c.close(), "无有效FVG", Map.of());
    }
    private static Decision evalOb(List<Ind.Bar> bars, int confirmBars) {
        int i = bars.size()-1;
        if (i<confirmBars+3) return hold(bars, "数据不足");
        double obHigh = -Double.MAX_VALUE, obLow = Double.MAX_VALUE;
        for (int x = i-confirmBars-2; x <= i-confirmBars; x++) { obHigh = Math.max(obHigh, bars.get(x).high()); obLow = Math.min(obLow, bars.get(x).low()); }
        double c = bars.get(i).close();
        if (c>=obLow && c<=obHigh) {
            boolean bull = bars.get(i).close()>bars.get(i).open();
            if (bull) return new Decision("BUY", 0.6, c, "回踩看涨订单块做多", Map.of("obLow",obLow,"obHigh",obHigh));
            return new Decision("SELL", 0.6, c, "回踩看空订单块做空", Map.of("obLow",obLow,"obHigh",obHigh));
        }
        return new Decision("HOLD", 0.3, c, "未回踩订单块", Map.of());
    }
    private static Decision evalSweep(List<Ind.Bar> bars, int lookback) {
        int i = bars.size()-1;
        if (i<lookback+1) return hold(bars, "数据不足");
        double c = bars.get(i).close(), prevC = bars.get(i-1).close();
        double prevLow = Double.MAX_VALUE, prevHigh = -Double.MAX_VALUE;
        for (int x = Math.max(0,i-lookback); x < i-1; x++) { prevLow = Math.min(prevLow, bars.get(x).low()); prevHigh = Math.max(prevHigh, bars.get(x).high()); }
        if (bars.get(i-1).low()<prevLow && c>prevC) return new Decision("BUY", 0.62, c, "扫前低后收回做多", Map.of("prevLow",prevLow));
        if (bars.get(i-1).high()>prevHigh && c<prevC) return new Decision("SELL", 0.62, c, "扫前高后回落做空", Map.of("prevHigh",prevHigh));
        return new Decision("HOLD", 0.3, c, "无扫单", Map.of());
    }
    private static Decision hold(List<Ind.Bar> bars, String reason) {
        double p = bars.isEmpty() ? 0 : bars.get(bars.size()-1).close();
        return new Decision("HOLD", 0.0, p, reason, Map.of());
    }
    private static String fmt(double v) { return String.format("%.2f", v); }
    private StrategyEngine() {}

    public static String strategyName(String key) {
        return META_NAMES.getOrDefault(key, key.toUpperCase());
    }
    public static String strategyDesc(String key) {
        return META_DESC.getOrDefault(key, "");
    }
    public static List<Map<String, Object>> paramsFor(String key) {
        return META_PARAMS.getOrDefault(key, new ArrayList<>());
    }
    static final Map<String, String> META_NAMES = Map.ofEntries(
        Map.entry("ma","双均线交叉 MA"), Map.entry("ema","EMA 指数均线"), Map.entry("macd","MACD 动能"),
        Map.entry("rsi","RSI 相对强弱"), Map.entry("boll","布林带 BOLL"), Map.entry("kdj","KDJ 随机指标"),
        Map.entry("atr","ATR 平均真实波幅"), Map.entry("donchian","唐奇安通道"), Map.entry("supertrend","超级趋势"),
        Map.entry("momentum","动量"), Map.entry("grid","网格交易"), Map.entry("dca","定投 DCA"),
        Map.entry("volume","成交量"), Map.entry("macd_rsi","MACD+RSI"), Map.entry("signal","信号"),
        Map.entry("martin","马丁格尔"), Map.entry("dip","抄底"), Map.entry("range_grid","区间网格"),
        Map.entry("fvg","公平价值缺口 FVG"), Map.entry("ob","订单块 OB"), Map.entry("sweep","流动性扫单")
    );
    static final Map<String, String> META_DESC = Map.ofEntries(
        Map.entry("ma","短期均线上穿长期均线做多"), Map.entry("fvg","公平价值缺口回填策略"),
        Map.entry("martin","马丁格尔加仓策略"), Map.entry("sweep","流动性扫单策略")
    );
    static final Map<String, List<Map<String, Object>>> META_PARAMS = Map.of();

}
