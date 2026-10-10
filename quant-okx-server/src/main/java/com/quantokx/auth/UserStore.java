package com.quantokx.auth;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.quantokx.config.QuantOkxProperties;
import com.quantokx.model.MembershipPlan;
import com.quantokx.model.TimeFormat;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.Optional;
import java.util.UUID;/**
 * 用户存储（多租户核心）：
 * users.json 存账号（userId / username / PBKDF2 口令哈希 / 会员等级与到期）；
 * data/users/{userId}/ 为每用户私有目录（config.json、orders.json）；
 * 会员规则：4 档套餐、同档顺延、12 个月 8 折。
 */
@Component
public class UserStore {

    private static final Logger log = LoggerFactory.getLogger(UserStore.class);
    private static final int ITERATIONS = 120000;
    private static final SecureRandom RNG = new SecureRandom();

    private final ObjectMapper mapper;
    private final Path dataDir;
    private final Path usersFile;

    private List<User> users = List.of();

    public UserStore(ObjectMapper mapper, QuantOkxProperties properties) {
        this.mapper = mapper;
        this.dataDir = Paths.get(properties.getDataDir());
        this.usersFile = this.dataDir.resolve("users.json");
    }

    // ------------------------------------------------------------------ 模型

    /** 会员（内嵌在用户记录里） */
    public record Membership(String level, String expiresAt) {
    }

    /** 用户（Jackson 直接读写公共字段） */
    public static class User {
        public String userId;
        public String username;
        public String passwordHash;
        public String createdAt;
        public Membership membership;

        public User() {
        }
    }

    /** GET /api/membership/status 的元素（按用户） */
    public record MemberStatus(String level, String planName, String expiresAt, boolean active,
                               int daysLeft, MembershipPlan.Benefits benefits) {
    }

    /** 一条订单 */
    public record OrderRec(String orderId, String planId, String planName, int months,
                           double total, String createdAt, String status) {
    }

    /** 开通结果 */
    public record ActivateResult(OrderRec order, String expiresAt) {
    }// ------------------------------------------------------------------ 初始化

    @PostConstruct
    void init() {
        try {
            Files.createDirectories(dataDir);
        } catch (IOException e) {
            log.warn("创建数据目录失败：{}", e.getMessage());
        }
        if (Files.exists(usersFile)) {
            try {
                UsersFile f = mapper.readValue(usersFile.toFile(), UsersFile.class);
                users = f.users == null ? List.of() : f.users;
            } catch (IOException e) {
                log.warn("读取用户文件失败，视为无用户：{}", e.getMessage());
                users = List.of();
            }
        }
        log.info("用户存储：{} 个注册用户（{}）", users.size(), usersFile.toAbsolutePath().normalize());
    }

    /** 落盘外层结构 */
    private static class UsersFile {
        public List<User> users;
    }

    // ------------------------------------------------------------------ 注册 / 登录

    public synchronized User register(String username, String password) {
        String u = username == null ? "" : username.trim();
        if (!u.matches("[A-Za-z0-9_]{3,20}")) {
            throw new IllegalArgumentException("用户名须为 3-20 位字母/数字/下划线");
        }
        if (password == null || password.length() < 6) {
            throw new IllegalArgumentException("密码至少 6 位");
        }
        for (User x : users) {
            if (x.username.equalsIgnoreCase(u)) {
                throw new IllegalArgumentException("用户名已被注册");
            }
        }
        User user = new User();
        user.userId = UUID.randomUUID().toString();
        user.username = u;
        user.passwordHash = hash(password);
        user.createdAt = TimeFormat.isoNow();
        user.membership = new Membership("free", null);

        List<User> next = new ArrayList<>(users);
        next.add(user);
        users = List.copyOf(next);
        persist();

        try {
            Files.createDirectories(userDir(user.userId));
        } catch (IOException e) {
            log.warn("创建用户目录失败：{}", e.getMessage());
        }
        log.info("新用户注册：{}", user.username);
        return user;
    }

    public synchronized Optional<User> verifyLogin(String username, String password) {
        if (username == null || password == null) {
            return Optional.empty();
        }
        for (User x : users) {
            if (x.username.equalsIgnoreCase(username.trim()) && verify(password, x.passwordHash)) {
                return Optional.of(x);
            }
        }
        return Optional.empty();
    }

    public synchronized Optional<User> findById(String userId) {
        if (userId == null) {
            return Optional.empty();
        }
        return users.stream().filter(u -> userId.equals(u.userId)).findFirst();
    }

    public synchronized List<User> all() {
        return users;
    }// ------------------------------------------------------------------ 会员权益

    /** 当前生效套餐：付费档未过期 → 该档；否则 FREE */
    public MembershipPlan activePlanOf(String userId) {
        User u = findById(userId).orElse(null);
        if (u == null || u.membership == null) {
            return MembershipPlan.FREE;
        }
        MembershipPlan p = MembershipPlan.findByIdOrNull(u.membership.level());
        if (p == null || p == MembershipPlan.FREE) {
            return MembershipPlan.FREE;
        }
        if (expired(u.membership.expiresAt())) {
            return MembershipPlan.FREE;
        }
        return p;
    }

    public MembershipPlan.Benefits benefitsOf(String userId) {
        MembershipPlan p = activePlanOf(userId);
        return new MembershipPlan.Benefits(p.minPollSeconds(), p.aiEnabled());
    }

    public MemberStatus statusOf(String userId) {
        MembershipPlan active = activePlanOf(userId);
        boolean paid = active != MembershipPlan.FREE;
        String exp = null;
        int daysLeft = 0;
        if (paid) {
            User u = findById(userId).orElse(null);
            exp = u == null ? null : u.membership.expiresAt();
            if (exp != null) {
                try {
                    daysLeft = (int) Math.max(0, Instant.now().until(Instant.parse(exp), ChronoUnit.DAYS));
                } catch (Exception ignored) {
                    // 解析失败按 0
                }
            }
        }
        return new MemberStatus(active.id(), active.name(), paid ? exp : null, paid, daysLeft,
                new MembershipPlan.Benefits(active.minPollSeconds(), active.aiEnabled()));
    }

    /**
     * 开通/续费会员（真实支付回调与演示直通共用）。
     * 同档未过期从到期日顺延；升级从现在起算；12 个月 8 折。
     */
    public synchronized ActivateResult activateMembership(String userId, MembershipPlan plan,
                                                          int months, String status) {
        if (plan == null || plan == MembershipPlan.FREE) {
            throw new IllegalArgumentException("免费版无需订阅");
        }
        if (months != 1 && months != 3 && months != 12) {
            throw new IllegalArgumentException("订阅时长仅支持 1 / 3 / 12 个月");
        }
        User user = findById(userId).orElseThrow(() -> new IllegalArgumentException("用户不存在"));

        Instant base = Instant.now();
        Membership cur = user.membership;
        if (cur != null && plan.id().equals(cur.level()) && !expired(cur.expiresAt())) {
            try {
                Instant e = Instant.parse(cur.expiresAt());
                if (e.isAfter(base)) {
                    base = e;
                }
            } catch (Exception ignored) {
                // 解析失败从现在起算
            }
        }
        Instant newExp = base.plus(months * 30L, ChronoUnit.DAYS);
        double total = plan.pricePerMonth() * months * (months == 12 ? 0.8 : 1.0);
        total = Math.round(total * 100.0) / 100.0;

        String orderId = "M" + LocalDateTime.now()
                .format(DateTimeFormatter.ofPattern("yyyyMMddHHmmss"))
                + String.format("%03d", RNG.nextInt(1000));

        OrderRec order = new OrderRec(orderId, plan.id(), plan.name(), months, total,
                TimeFormat.isoNow(), status);

        List<User> next = new ArrayList<>(users);
        User copy = copyOf(user);
        copy.membership = new Membership(plan.id(), newExp.toString());
        next.set(next.indexOf(user), copy);
        users = List.copyOf(next);
        persist();

        appendOrder(userId, order);
        log.info("会员开通：用户 {} → {} × {} 个月，总价 {}，到期 {}（{}）",
                user.username, plan.name(), months, total, newExp, status);
        return new ActivateResult(order, newExp.toString());
    }// ------------------------------------------------------------------ 订单

    public synchronized List<OrderRec> ordersOf(String userId) {
        Path f = userDir(userId).resolve("orders.json");
        if (!Files.exists(f)) {
            return List.of();
        }
        try {
            OrdersFile o = mapper.readValue(f.toFile(), OrdersFile.class);
            return o.orders == null ? List.of() : o.orders;
        } catch (IOException e) {
            log.warn("读取订单失败：{}", e.getMessage());
            return List.of();
        }
    }

    private void appendOrder(String userId, OrderRec order) {
        try {
            Files.createDirectories(userDir(userId));
            List<OrderRec> list = new ArrayList<>(ordersOf(userId));
            list.add(0, order);
            if (list.size() > 100) {
                list = new ArrayList<>(list.subList(0, 100));
            }
            OrdersFile f = new OrdersFile();
            f.orders = list;
            mapper.writerWithDefaultPrettyPrinter()
                    .writeValue(userDir(userId).resolve("orders.json").toFile(), f);
        } catch (IOException e) {
            log.error("订单写入失败：{}", e.getMessage());
        }
    }

    private static class OrdersFile {
        public List<OrderRec> orders;
    }

    // ------------------------------------------------------------------ 工具

    /** 用户私有目录：data/users/{userId} */
    public Path userDir(String userId) {
        return dataDir.resolve("users").resolve(userId);
    }

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

    private static User copyOf(User u) {
        User c = new User();
        c.userId = u.userId;
        c.username = u.username;
        c.passwordHash = u.passwordHash;
        c.createdAt = u.createdAt;
        c.membership = u.membership;
        return c;
    }

    private void persist() {
        Path tmp = dataDir.resolve("users.json.tmp");
        try {
            Files.createDirectories(dataDir);
            UsersFile f = new UsersFile();
            f.users = users;
            mapper.writerWithDefaultPrettyPrinter().writeValue(tmp.toFile(), f);
            try {
                Files.move(tmp, usersFile, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException e) {
                Files.move(tmp, usersFile, StandardCopyOption.REPLACE_EXISTING);
            }
            try {
                Files.setPosixFilePermissions(usersFile, PosixFilePermissions.fromString("rw-------"));
            } catch (UnsupportedOperationException | IOException e) {
                log.warn("无法设置权限 600：{}", e.getMessage());
            }
        } catch (IOException e) {
            log.error("用户数据持久化失败：{}", e.getMessage());
        }
    }

    // ------------------------------------------------------------------ 口令哈希

    private static String hash(String password) {
        try {
            byte[] salt = new byte[16];
            RNG.nextBytes(salt);
            PBEKeySpec spec = new PBEKeySpec(password.toCharArray(), salt, ITERATIONS, 256);
            byte[] hash = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                    .generateSecret(spec).getEncoded();
            return Base64.getEncoder().encodeToString(salt) + ":"
                    + Base64.getEncoder().encodeToString(hash);
        } catch (Exception e) {
            throw new IllegalStateException("口令哈希失败", e);
        }
    }

    private static boolean verify(String password, String stored) {
        try {
            String[] parts = stored.split(":");
            byte[] salt = Base64.getDecoder().decode(parts[0]);
            byte[] expect = Base64.getDecoder().decode(parts[1]);
            PBEKeySpec spec = new PBEKeySpec(password.toCharArray(), salt, ITERATIONS, 256);
            byte[] got = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                    .generateSecret(spec).getEncoded();
            return MessageDigest.isEqual(expect, got);
        } catch (Exception e) {
            return false;
        }
    }
}