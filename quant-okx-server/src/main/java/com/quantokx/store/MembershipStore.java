package com.quantokx.store;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quantokx.config.QuantOkxProperties;
import com.quantokx.model.MembershipPlan;
import com.quantokx.model.TimeFormat;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;

/**
 * 会员存储（单租户）：
 * - 状态持久化到 ./data/membership.json（权限 600，原子写，与 ConfigStore 同一套路）；
 * - 订阅为演示语义：付款即开通（status=PAID_DEMO），不接真实支付；
 * - 引擎轮询线程与 HTTP 线程都会读写，方法统一 synchronized。
 */
@Component
public class MembershipStore {

    private static final Logger log = LoggerFactory.getLogger(MembershipStore.class);

    private final ObjectMapper mapper;
    private final Path dataDir;
    private final Path stateFile;

    private State state = new State("free", null, List.of());

    public MembershipStore(ObjectMapper mapper, QuantOkxProperties properties) {
        this.mapper = mapper;
        this.dataDir = Paths.get(properties.getDataDir());
        this.stateFile = this.dataDir.resolve("membership.json");
    }

    // ------------------------------------------------------------------ 持久化模型

    /** 一条演示订单 */
    public record Order(String orderId, String planId, String planName, int months,
                        double total, String createdAt, String status) {
    }

    /** 会员状态（落盘格式） */
    public record State(String level, String expiresAt, List<Order> orders) {
    }

    // ------------------------------------------------------------------ 对外视图

    /** GET /api/membership/plans 的元素 */
    public record PlanView(String id, String name, double pricePerMonth, String badge,
                           int minPollSeconds, boolean aiEnabled, List<String> features,
                           boolean highlight) {
    }

    /** GET /api/membership/status */
    public record StatusView(String level, String planName, String expiresAt, boolean active,
                             int daysLeft, MembershipPlan.Benefits benefits) {
    }

    /** GET /api/membership/orders 的元素 */
    public record OrderView(String orderId, String planId, String planName, int months,
                            double total, String createdAt, String status) {
    }

    /** POST /api/membership/subscribe 的返回 */
    public record SubscribeView(String orderId, String level, String planName,
                                String expiresAt, double total) {
    }

    // ------------------------------------------------------------------ 生命周期

    @PostConstruct
    void init() {
        try {
            Files.createDirectories(dataDir);
        } catch (IOException e) {
            log.warn("创建数据目录 {} 失败：{}", dataDir, e.getMessage());
        }
        if (Files.exists(stateFile)) {
            try {
                state = mapper.readValue(stateFile.toFile(), State.class);
            } catch (IOException e) {
                log.warn("读取 {} 失败，回退免费版：{}", stateFile, e.getMessage());
                state = new State("free", null, List.of());
            }
        }
        if (state == null || state.level() == null) {
            state = new State("free", null, List.of());
        }
        MembershipPlan active = activePlan();
        log.info("会员状态：{}（生效套餐：{}，轮询下限 {}s，AI {}）",
                state.level(), active.name(), active.minPollSeconds(),
                active.aiEnabled() ? "已解锁" : "未开通");
    }

    // ------------------------------------------------------------------ 查询

    public synchronized State state() {
        return state;
    }

    /** 当前生效套餐：付费档未过期 → 该档；否则 FREE */
    public synchronized MembershipPlan activePlan() {
        MembershipPlan cur = MembershipPlan.findByIdOrNull(state.level());
        if (cur == null) {
            return MembershipPlan.FREE;
        }
        if (cur != MembershipPlan.FREE && !expired(state.expiresAt())) {
            return cur;
        }
        return MembershipPlan.FREE;
    }

    /** 当前生效权益（引擎钳制 / PUT /api/config 校验都用它） */
    public synchronized MembershipPlan.Benefits effectiveBenefits() {
        MembershipPlan plan = activePlan();
        return new MembershipPlan.Benefits(plan.minPollSeconds(), plan.aiEnabled());
    }

    public List<PlanView> plans() {
        List<PlanView> out = new ArrayList<>();
        for (MembershipPlan p : MembershipPlan.PLANS) {
            out.add(new PlanView(p.id(), p.name(), p.pricePerMonth(), p.badge(),
                    p.minPollSeconds(), p.aiEnabled(), p.features(), p.highlight()));
        }
        return out;
    }

    public synchronized StatusView statusView() {
        MembershipPlan active = activePlan();
        boolean paid = active != MembershipPlan.FREE;
        int daysLeft = 0;
        if (paid && state.expiresAt() != null) {
            try {
                Instant e = Instant.parse(state.expiresAt());
                daysLeft = (int) Math.max(0, Instant.now().until(e, ChronoUnit.DAYS));
            } catch (Exception ignored) {
                // 解析失败按 0 处理
            }
        }
        return new StatusView(active.id(), active.name(),
                paid ? state.expiresAt() : null,
                paid, daysLeft,
                new MembershipPlan.Benefits(active.minPollSeconds(), active.aiEnabled()));
    }

    public synchronized List<OrderView> orders() {
        List<OrderView> out = new ArrayList<>();
        for (Order o : state.orders()) {
            out.add(new OrderView(o.orderId(), o.planId(), o.planName(), o.months(),
                    o.total(), o.createdAt(), o.status()));
        }
        return out;
    }

    // ------------------------------------------------------------------ 订阅（演示）

    /**
     * 演示订阅：不接真实支付，直接开通。
     * 规则：free 不可订阅；时长仅 1/3/12；低于当前有效等级拒绝；
     * 同档续费从 max(now, 当前到期) 顺延；升级从 now 起算；12 个月 8 折。
     */
    public synchronized SubscribeView subscribe(String planId, int months) {
        MembershipPlan plan = MembershipPlan.findByIdOrNull(planId);
        if (plan == null) {
            throw new IllegalArgumentException("套餐不存在：" + planId);
        }
        if (plan == MembershipPlan.FREE) {
            throw new IllegalArgumentException("免费版无需订阅");
        }
        if (months != 1 && months != 3 && months != 12) {
            throw new IllegalArgumentException("订阅时长仅支持 1 / 3 / 12 个月");
        }

        MembershipPlan current = activePlan();
        if (plan.rank() < current.rank()) {
            throw new IllegalArgumentException("当前会员等级更高（" + current.name() + "），无法降级订阅");
        }

        Instant base = Instant.now();
        if (current == plan && state.expiresAt() != null) {
            try {
                Instant e = Instant.parse(state.expiresAt());
                if (e.isAfter(base)) {
                    base = e; // 同档续费顺延
                }
            } catch (Exception ignored) {
                // 到期时间解析失败则从现在起算
            }
        }
        Instant newExp = base.plus(months * 30L, ChronoUnit.DAYS);
        double total = plan.pricePerMonth() * months * (months == 12 ? 0.8 : 1.0);
        total = Math.round(total * 100.0) / 100.0;

        String orderId = "M" + LocalDateTime.now()
                .format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"))
                + String.format("%03d", (int) (Math.random() * 1000));

        Order order = new Order(orderId, plan.id(), plan.name(), months, total,
                TimeFormat.isoNow(), "PAID_DEMO");
        List<Order> orders = new ArrayList<>(state.orders());
        orders.add(0, order);
        if (orders.size() > 100) {
            orders = new ArrayList<>(orders.subList(0, 100));
        }
        state = new State(plan.id(), newExp.toString(), List.copyOf(orders));
        persist(state);

        log.info("会员订阅：{} × {} 个月，总价 {}，到期 {}", plan.name(), months, total, newExp);
        return new SubscribeView(orderId, state.level(), plan.name(), newExp.toString(), total);
    }

    // ------------------------------------------------------------------ 内部工具

    private static boolean expired(String iso) {
        if (iso == null || iso.isBlank()) {
            return true;
        }
        try {
            return Instant.parse(iso).isBefore(Instant.now());
        } catch (Exception e) {
            return true;
        }
    }

    private void persist(State s) {
        Path tmp = dataDir.resolve("membership.json.tmp");
        try {
            Files.createDirectories(dataDir);
            mapper.writerWithDefaultPrettyPrinter().writeValue(tmp.toFile(), s);
            try {
                Files.move(tmp, stateFile, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException e) {
                Files.move(tmp, stateFile, StandardCopyOption.REPLACE_EXISTING);
            }
            try {
                Files.setPosixFilePermissions(stateFile, PosixFilePermissions.fromString("rw-------"));
            } catch (UnsupportedOperationException | IOException e) {
                log.warn("无法把 {} 权限设置为 600：{}", stateFile, e.getMessage());
            }
        } catch (IOException e) {
            log.error("会员状态持久化失败（内存中已生效，重启会丢失）：{}", e.getMessage());
        }
    }
}
