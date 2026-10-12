<?php
declare(strict_types=1);
namespace app\controller\api;

use app\controller\BaseController;
use app\model\Strategy as StrategyModel;
use app\service\BacktestService;
use app\service\BackgroundTaskService;
use app\service\PlanKeyService;
use app\service\StrategyRunner;
use app\service\StrategyService;
use Throwable;

class Strategy extends BaseController
{
    /** 策略类型元数据（供前端动态渲染参数表单） */
    public function meta()
    {
        return $this->ok(StrategyService::meta());
    }

    /** 策略列表 */
    public function index()
    {
        /* 显式字段映射：原始行里 enabled 是 0/1 整数、id 可能是字符串，
           App 端 StrategyRow 要求 id/leverage 整数、enabled 布尔、百分比浮点。 */
        $rows = StrategyModel::where('user_id', $this->currentUser()->id)->order('id desc')->select()->toArray();
        $items = array_map(static fn ($o) => [
            'id' => (int) $o['id'],
            'name' => (string) ($o['name'] ?? ''),
            'class_name' => (string) ($o['class_name'] ?? ''),
            'symbol' => (string) ($o['symbol'] ?? ''),
            'symbols' => (string) ($o['symbols'] ?? ''),
            'market_type' => (string) ($o['market_type'] ?? 'swap'),
            'direction_mode' => (string) ($o['direction_mode'] ?? 'long_only'),
            'interval' => (string) ($o['interval'] ?? '15m'),
            'mode' => (string) ($o['mode'] ?? 'paper'),
            'enabled' => !empty($o['enabled']),
            'leverage' => (int) ($o['leverage'] ?? 1),
            'position_percent' => (float) ($o['position_percent'] ?? 0),
            'min_confidence' => (float) ($o['min_confidence'] ?? 0.6),
        ], $rows);
        return $this->ok($items);
    }

    /** 运行监控：策略 + 最近一次运行状态 */
    public function monitor()
    {
        try {
            return $this->ok(StrategyRunner::monitor($this->currentUser()));
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_MONITOR_ERROR', 422);
        }
    }

    public function create()
    {
        try {
            return $this->ok(StrategyService::create($this->currentUser(), $this->payload())->toArray(), '策略已创建');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_ERROR', 422);
        }
    }

    public function update()
    {
        try {
            $input = $this->payload();
            $id = (int) ($input['id'] ?? 0);
            if ($id <= 0) return $this->fail('策略 ID 必填', 'INVALID_PARAM', 422);
            return $this->ok(StrategyService::update($this->currentUser(), $id, $input)->toArray(), '策略已更新');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_UPDATE_ERROR', 422);
        }
    }

    public function delete()
    {
        try {
            $id = (int) ($this->payload()['id'] ?? $this->request->param('id', 0));
            if ($id <= 0) return $this->fail('策略 ID 必填', 'INVALID_PARAM', 422);
            StrategyService::delete($this->currentUser(), $id);
            return $this->ok([], '策略已删除');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_DELETE_ERROR', 422);
        }
    }

    public function analyze()
    {
        try {
            return $this->ok(StrategyService::analyze($this->currentUser(), $this->payload()));
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_ANALYZE_ERROR', 422);
        }
    }

    public function backtest()
    {
        try {
            $user = $this->currentUser();
            /* 会员限制：每日回测次数 */
            \app\service\MembershipService::assertDaily($user, 'backtest', '回测');
            $result = BacktestService::run($user, $this->payload());
            \app\service\MembershipService::bumpUsage($user, 'backtest');
            return $this->ok($result, '回测完成');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'BACKTEST_ERROR', 422);
        }
    }

    public function start()
    {
        try {
            $id = (int) ($this->payload()['id'] ?? 0);
            if ($id <= 0) return $this->fail('策略 ID 必填', 'INVALID_PARAM', 422);
            $row = StrategyService::setEnabled($this->currentUser(), $id, true);
            return $this->ok(['id' => $id, 'enabled' => true, 'leverage' => (int) $row->leverage], '策略已启动');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_START_ERROR', 422);
        }
    }

    public function stop()
    {
        try {
            $id = (int) ($this->payload()['id'] ?? 0);
            if ($id <= 0) return $this->fail('策略 ID 必填', 'INVALID_PARAM', 422);
            StrategyService::setEnabled($this->currentUser(), $id, false);
            return $this->ok(['id' => $id, 'enabled' => false], '策略已停止');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_STOP_ERROR', 422);
        }
    }

    /** 手动跑一轮（调试/立即执行） */
    public function run()
    {
        try {
            $id = (int) ($this->payload()['id'] ?? 0);
            if ($id <= 0) return $this->fail('策略 ID 必填', 'INVALID_PARAM', 422);
            $row = StrategyModel::where('user_id', $this->currentUser()->id)->where('id', $id)->find();
            if (!$row) return $this->fail('策略不存在', 'NOT_FOUND', 404);
            return $this->ok(StrategyRunner::runOnce($row, true), '策略执行完成');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_RUN_ERROR', 422);
        }
    }

    /** 页面轮询：非强制跑一轮所有启用策略（未到运行间隔自动跳过，不会重复下单） */
    public function tick()
    {
        try {
            return $this->ok(['results' => StrategyRunner::tick((int) $this->currentUser()->id, false)], '已轮询');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_TICK_ERROR', 422);
        }
    }

    /** 计划任务入口（免登录，key 校验；与 AI 自动交易共用同一个「计划任务 key」） */
    public function cron()
    {
        try {
            $key = trim((string) $this->request->param('key', ''));
            $userId = PlanKeyService::verify($key);
            if ($userId === null) return $this->fail('无效的 key', 'INVALID_KEY', 403);
            $results = StrategyRunner::tick($userId, false);
            BackgroundTaskService::heartbeat("strategy", ["count" => count($results)], "cron");
            return $this->ok(['results' => $results, 'ticked_at' => date('c')], 'ok');
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_CRON_ERROR', 422);
        }
    }

    /** 计划任务地址（策略页「定时自动跑一轮」展示/复制用） */
    public function cronUrl()
    {
        try {
            return $this->ok(['url' => '/api/strategy/cron?key=' . PlanKeyService::forUser($this->currentUser())]);
        } catch (Throwable $e) {
            return $this->fail($e->getMessage(), 'STRATEGY_CRON_URL_ERROR', 422);
        }
    }
}
