package com.quantokx.model;

import java.util.List;

/**
 * 会员套餐（固定 4 档，硬编码）。单租户系统：会员相当于账号套餐等级。
 * 生效权益由 MembershipStore#effectiveBenefits 计算（付费档未过期才生效）。
 */
public record MembershipPlan(
        String id,
        String name,
        double pricePerMonth,
        String badge,
        int minPollSeconds,
        boolean aiEnabled,
        List<String> features,
        boolean highlight) {

    public static final MembershipPlan FREE =
            new MembershipPlan("free", "免费版", 0, "基础", 30, false,
                    List.of("基础策略 4 种", "轮询最低 30 秒", "单交易对"), false);

    public static final MembershipPlan GOLD =
            new MembershipPlan("gold", "黄金会员", 29, "热门", 10, true,
                    List.of("全部策略 + AI 决策", "轮询最低 10 秒", "单交易对"), false);

    public static final MembershipPlan DIAMOND =
            new MembershipPlan("diamond", "钻石会员", 99, "推荐", 5, true,
                    List.of("AI 决策", "轮询最低 5 秒", "多交易对（预留）"), true);

    public static final MembershipPlan ULTIMATE =
            new MembershipPlan("ultimate", "至尊会员", 299, "旗舰", 5, true,
                    List.of("钻石全部权益", "多交易对", "优先支持"), false);

    public static final List<MembershipPlan> PLANS = List.of(FREE, GOLD, DIAMOND, ULTIMATE);

    /** 套餐等级：free(0) < gold(1) < diamond(2) < ultimate(3) */
    public int rank() {
        if (this == ULTIMATE) {
            return 3;
        }
        if (this == DIAMOND) {
            return 2;
        }
        if (this == GOLD) {
            return 1;
        }
        return 0;
    }

    /** 按 id 查套餐，找不到返回 null */
    public static MembershipPlan findByIdOrNull(String id) {
        if (id == null) {
            return null;
        }
        for (MembershipPlan p : PLANS) {
            if (p.id().equals(id)) {
                return p;
            }
        }
        return null;
    }

    /** 一档套餐当前生效的权益 */
    public record Benefits(int minPollSeconds, boolean aiEnabled) {
    }
}
