<?php
declare(strict_types=1);
namespace app\controller\api;

use app\controller\BaseController;
use app\service\AdminService;
use app\service\MembershipService;
use app\service\PaymentService;
use Throwable;

/** 会员中心 API：套餐、下单支付、我的订单与用量。 */
class Member extends BaseController
{
    /** 套餐列表 + 当前会员状态 + 支付方式（前端渲染用） */
    public function plans()
    {
        try {
            $user = $this->currentUser();
            $config = PaymentService::config();
            return $this->ok([
                'plans' => array_values(MembershipService::plans()),
                'level_names' => MembershipService::LEVEL_NAMES,
                'periods' => PaymentService::periods(),
                'badge' => MembershipService::badge($user),
                'limits' => MembershipService::limits($user),
                'usage' => [
                    'backtest_today' => MembershipService::usageToday($user, 'backtest'),
                    'ai_today' => MembershipService::usageToday($user, 'ai'),
                ],
                'payment' => [
                    'configured' => PaymentService::isConfigured(),
                    'channels' => PaymentService::isConfigured() ? array_values((array) $config['channels']) : [],
                    'channel_names' => PaymentService::CHANNELS,
                ],
                'site' => AdminService::siteConfig(),
            ]);
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'MEMBER_PLANS_ERROR', 422);
        }
    }

    /** 创建支付订单，返回收银台跳转地址 */
    public function pay()
    {
        try {
            $input = $this->payload();
            $level = (string) ($input['level'] ?? '');
            $months = (int) ($input['months'] ?? 1);
            $channel = (string) ($input['channel'] ?? 'alipay');
            if (!in_array($level, MembershipService::LEVELS, true) || $level === 'free') {
                return $this->fail('请选择要购买的会员等级', 'INVALID_LEVEL', 422);
            }
            $result = PaymentService::createOrder(
                $this->currentUser(), $level, $months, $channel, (string) $this->request->domain()
            );
            $order = $result['order'];
            $payUrl = (string) ($result['pay_url'] ?? '');
            return $this->ok([
                'trade_no' => $order ? (string) $order->trade_no : '',
                'amount' => $order ? (string) $order->amount : '',
                'pay_url' => $payUrl,
            ], $payUrl === '' ? '已直接开通（演示模式）' : '订单已创建，正在跳转支付');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'MEMBER_PAY_ERROR', 422);
        }
    }

    /** 我的订单 */
    public function orders()
    {
        try {
            $rows = PaymentService::userOrders($this->currentUser());
            $items = array_map(static fn ($o) => [
                'id' => (int) $o['id'],
                'trade_no' => $o['trade_no'],
                'level' => $o['level'],
                'level_name' => MembershipService::LEVEL_NAMES[$o['level']] ?? $o['level'],
                'months' => (int) $o['months'],
                'amount' => (string) $o['amount'],
                'channel' => $o['channel'],
                'channel_name' => PaymentService::CHANNELS[$o['channel']] ?? $o['channel'],
                'status' => $o['status'],
                'pay_url' => $o['status'] === 'pending' ? (string) $o['pay_url'] : '',
                'paid_at' => $o['paid_at'] ?? null,
                'created_at' => $o['created_at'] ?? null,
            ], $rows);
            return $this->ok(['items' => $items]);
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'MEMBER_ORDERS_ERROR', 422);
        }
    }

    /** 我的会员状态（徽章 + 限制 + 用量） */
    public function status()
    {
        try {
            $user = $this->currentUser();
            return $this->ok([
                'badge' => MembershipService::badge($user),
                'limits' => MembershipService::limits($user),
                'usage' => [
                    'backtest_today' => MembershipService::usageToday($user, 'backtest'),
                    'ai_today' => MembershipService::usageToday($user, 'ai'),
                ],
                'counts' => [
                    'strategies' => \app\model\Strategy::where('user_id', $user->id)->count(),
                    'ai_configs' => \app\model\AiConfig::where('user_id', $user->id)->count(),
                    'accounts' => \app\model\OkxAccount::where('user_id', $user->id)->count(),
                ],
            ]);
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'MEMBER_STATUS_ERROR', 422);
        }
    }
}
