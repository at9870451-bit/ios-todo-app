<?php
declare(strict_types=1);
namespace app\service;

use app\model\PaymentOrder;
use app\model\SystemSetting;
use app\model\User;
use RuntimeException;
use Throwable;

/**
 * 易支付（通用彩虹易支付协议）对接。
 *
 * 流程：
 *   1. 用户在前端选套餐 → createOrder() 生成本地订单（pending）→ 跳转易支付收银台（submit.php）；
 *   2. 支付完成后易支付异步回调 /api/pay/notify → verifySign() 验签 → markPaid() 幂等入账并升级会员 → 返回 success；
 *   3. 浏览器同步跳回 /api/pay/return → 跳转到「我的订单」。
 *
 * 签名规则（易支付通用）：
 *   除 sign、sign_type 与空值外的参数按参数名升序拼接为 a=b&c=d...，末尾直接拼接商户 KEY，
 *   MD5 取 32 位小写。
 *
 * 配置存于 qb_system_settings（user_id=0, setting_key=payment_config）：
 *   { api_url, pid, key, enabled, channels:[alipay,wxpay,qqpay], site_name, notify_base }
 */
final class PaymentService
{
    public const SETTING_KEY = 'payment_config';

    public const CHANNELS = ['alipay' => '支付宝', 'wxpay' => '微信支付', 'qqpay' => 'QQ 钱包'];

    /* ---------------- 配置 ---------------- */

    public static function config(): array
    {
        $default = [
            'api_url' => '', 'pid' => '', 'key' => '', 'enabled' => 0, 'demo_direct' => 1,
            'channels' => ['alipay', 'wxpay'], 'site_name' => 'QuantOKX 会员', 'notify_base' => '',
        ];
        try {
            $row = SystemSetting::where('user_id', 0)->where('setting_key', self::SETTING_KEY)->find();
            $data = is_array($row?->value_json) ? $row->value_json : [];
            return array_merge($default, $data);
        } catch (Throwable $e) {
            return $default;
        }
    }

    public static function saveConfig(array $input): array
    {
        $apiUrl = rtrim(trim((string) ($input['api_url'] ?? '')), '/');
        if ($apiUrl !== '' && !preg_match('#^https?://#i', $apiUrl)) {
            throw new RuntimeException('易支付接口地址必须以 http:// 或 https:// 开头');
        }
        $pid = trim((string) ($input['pid'] ?? ''));
        $key = trim((string) ($input['key'] ?? ''));
        $channels = array_values(array_intersect(
            array_map('strval', (array) ($input['channels'] ?? ['alipay', 'wxpay'])),
            array_keys(self::CHANNELS)
        ));
        if (!$channels) $channels = ['alipay'];

        $row = SystemSetting::where('user_id', 0)->where('setting_key', self::SETTING_KEY)->find();
        if (!$row) {
            $row = new SystemSetting();
            $row->user_id = 0;
            $row->setting_key = self::SETTING_KEY;
        }
        $current = is_array($row->value_json) ? $row->value_json : [];
        $row->value_json = array_merge($current, [
            'api_url' => $apiUrl,
            'pid' => $pid,
            'key' => $key,
            'enabled' => !empty($input['enabled']) ? 1 : 0,
            'channels' => $channels,
            'site_name' => mb_substr(trim((string) ($input['site_name'] ?? 'QuantOKX 会员')), 0, 50) ?: 'QuantOKX 会员',
            'notify_base' => rtrim(trim((string) ($input['notify_base'] ?? '')), '/'),
        ]);
        $row->save();
        SafeLogger::info('更新易支付配置', ['enabled' => !empty($input['enabled']), 'channels' => implode(',', $channels)]);
        return self::config();
    }

    public static function isConfigured(): bool
    {
        $c = self::config();
        return !empty($c['enabled']) && $c['api_url'] !== '' && $c['pid'] !== '' && $c['key'] !== '';
    }

    /* ---------------- 签名 ---------------- */

    /** 生成签名（32 位小写 MD5） */
    public static function buildSign(array $params, string $key): string
    {
        unset($params['sign'], $params['sign_type']);
        $params = array_filter($params, static fn ($v) => $v !== null && $v !== '');
        ksort($params);
        $pairs = [];
        foreach ($params as $k => $v) $pairs[] = $k . '=' . $v;
        return md5(implode('&', $pairs) . $key);
    }

    /** 校验回调签名 */
    public static function verifySign(array $params, string $key): bool
    {
        $sign = (string) ($params['sign'] ?? '');
        if ($sign === '' || $key === '') return false;
        $calc = self::buildSign($params, $key);
        return hash_equals($calc, strtolower($sign));
    }

    /* ---------------- 下单 ---------------- */

    /** 可购周期：月 / 季 / 年 */
    public static function periods(): array
    {
        return [
            ['months' => 1, 'label' => '1 个月', 'discount' => ''],
            ['months' => 3, 'label' => '3 个月', 'discount' => '约 9 折'],
            ['months' => 12, 'label' => '12 个月', 'discount' => '约 8.3 折'],
        ];
    }

    /**
     * 创建支付订单（本地 pending）+ 计算收银台跳转地址。
     * @return array{order:PaymentOrder, pay_url:string}
     */
    public static function createOrder(User $user, string $level, int $months, string $channel, string $baseUrl = ''): array
    {
        $config = self::config();
        if (!self::isConfigured()) {
            /* 演示模式：未配置易支付时直接开通（便于测试与内部使用；正式收款请在支付设置配置易支付） */
            if (!empty($config['demo_direct'])) {
                $m = in_array($months, [1, 3, 12], true) ? $months : 1;
                $order = new PaymentOrder();
                $order->trade_no = 'QB' . date('YmdHis') . random_int(1000, 9999);
                $order->user_id = $user->id;
                $order->level = $level;
                $order->months = $m;
                $order->amount = number_format(MembershipService::priceFor($level, $m), 2, '.', '');
                $order->channel = $channel;
                $order->status = 'paid';
                $order->paid_at = date('Y-m-d H:i:s');
                $order->pay_url = '';
                $order->save();
                MembershipService::upgrade($user, $level, $m);
                SafeLogger::info('演示模式直接开通', [
                    'user_id' => $user->id, 'level' => $level, 'months' => $m, 'trade_no' => $order->trade_no,
                ]);
                return ['order' => $order, 'pay_url' => ''];
            }
            throw new RuntimeException('支付未配置：请联系管理员在「管理端 → 支付设置」中填写易支付信息');
        }
        if (!in_array($channel, (array) $config['channels'], true)) {
            throw new RuntimeException('该支付方式未开启，请选择其他方式');
        }
        $months = in_array($months, [1, 3, 12], true) ? $months : 1;
        $amount = MembershipService::priceFor($level, $months);
        if ($amount <= 0) throw new RuntimeException('该套餐无需支付');

        $order = new PaymentOrder();
        $order->trade_no = 'QB' . date('YmdHis') . random_int(1000, 9999);
        $order->user_id = $user->id;
        $order->level = $level;
        $order->months = $months;
        $order->amount = number_format($amount, 2, '.', '');
        $order->channel = $channel;
        $order->status = 'pending';

        $base = rtrim($baseUrl, '/');
        if (!empty($config['notify_base'])) $base = rtrim((string) $config['notify_base'], '/');
        $notifyUrl = $base . '/api/pay/notify';
        $returnUrl = $base . '/api/pay/return';

        $params = [
            'pid' => (string) $config['pid'],
            'type' => $channel,
            'out_trade_no' => $order->trade_no,
            'notify_url' => $notifyUrl,
            'return_url' => $returnUrl,
            'name' => mb_substr($config['site_name'] . ' ' . (MembershipService::LEVEL_NAMES[$level] ?? $level) . ' ' . $months . ' 个月', 0, 100),
            'money' => $order->amount,
            'sign' => '',
            'sign_type' => 'MD5',
        ];
        $params['sign'] = self::buildSign($params, (string) $config['key']);

        $submit = self::submitUrl((string) $config['api_url']);
        $order->pay_url = $submit . '?' . http_build_query($params);
        $order->save();

        SafeLogger::info('创建支付订单', [
            'trade_no' => $order->trade_no, 'user_id' => $user->id,
            'level' => $level, 'months' => $months, 'amount' => $order->amount, 'channel' => $channel,
        ]);
        return ['order' => $order, 'pay_url' => (string) $order->pay_url];
    }

    /** 兼容 api_url 填写「站点根」或「完整 submit.php/mapi.php 地址」两种形态 */
    public static function submitUrl(string $apiUrl): string
    {
        $apiUrl = rtrim($apiUrl, '/');
        if (preg_match('#/(submit|mapi)\.php$#i', $apiUrl)) return $apiUrl;
        return $apiUrl . '/submit.php';
    }

    /* ---------------- 回调 ---------------- */

    /**
     * 处理异步通知（幂等）：验签 → 校验金额与状态 → 入账升级。
     * @return array{ok:bool, message:string, order:?PaymentOrder}
     */
    public static function handleNotify(array $params): array
    {
        $config = self::config();
        $key = (string) $config['key'];
        $tradeNo = trim((string) ($params['out_trade_no'] ?? ''));
        if ($tradeNo === '') return ['ok' => false, 'message' => '缺少 out_trade_no', 'order' => null];

        $order = PaymentOrder::where('trade_no', $tradeNo)->find();
        if (!$order) return ['ok' => false, 'message' => '订单不存在', 'order' => null];

        if (!self::verifySign($params, $key)) {
            SafeLogger::warning('易支付回调验签失败', ['trade_no' => $tradeNo]);
            return ['ok' => false, 'message' => '验签失败', 'order' => $order];
        }
        if ((string) ($params['pid'] ?? '') !== (string) $config['pid']) {
            return ['ok' => false, 'message' => 'pid 不匹配', 'order' => $order];
        }
        $status = strtoupper((string) ($params['trade_status'] ?? ''));
        if (!in_array($status, ['TRADE_SUCCESS', 'TRADE_FINISHED'], true)) {
            return ['ok' => false, 'message' => '未支付成功（' . $status . '）', 'order' => $order];
        }
        $money = (float) ($params['money'] ?? 0);
        if (abs($money - (float) $order->amount) > 0.01) {
            SafeLogger::warning('易支付回调金额不符', ['trade_no' => $tradeNo, 'notify' => $money, 'order' => (float) $order->amount]);
            return ['ok' => false, 'message' => '金额不符', 'order' => $order];
        }

        self::markPaid($order, 'notify', $params);
        return ['ok' => true, 'message' => 'success', 'order' => $order];
    }

    /** 入账（幂等）：仅 pending 订单会升级会员 */
    public static function markPaid(PaymentOrder $order, string $source, array $payload = []): bool
    {
        if ((string) $order->status === 'paid') return false;
        $user = User::find((int) $order->user_id);
        if (!$user) throw new RuntimeException('订单用户不存在');

        $order->status = 'paid';
        $order->paid_at = date('Y-m-d H:i:s');
        $order->paid_source = $source;
        try {
            $order->notify_payload = mb_substr(json_encode($payload, JSON_UNESCAPED_UNICODE) ?: '', 0, 2000);
        } catch (Throwable $e) {
            $order->notify_payload = '';
        }
        $order->save();

        MembershipService::upgrade($user, (string) $order->level, (int) $order->months);
        SafeLogger::info('支付订单入账', [
            'trade_no' => $order->trade_no, 'user_id' => $user->id,
            'level' => $order->level, 'months' => $order->months, 'source' => $source,
        ]);
        return true;
    }

    /* ---------------- 查询 ---------------- */

    public static function userOrders(User $user, int $limit = 50): array
    {
        return PaymentOrder::where('user_id', $user->id)
            ->order('id desc')->limit($limit)->select()->toArray();
    }

    public static function findUserOrder(User $user, int $id): ?PaymentOrder
    {
        return PaymentOrder::where('user_id', $user->id)->where('id', $id)->find();
    }
}
