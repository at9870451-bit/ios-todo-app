<?php
namespace app\service;

use app\model\AiConfig;
use app\model\AiSignal;
use app\model\OkxAccount;
use app\model\User;
use RuntimeException;
use Throwable;

/**
 * AI 分析服务：把 K 线与策略描述交给大模型，只接受严格 JSON 结构化信号。
 * AI 永不直接接触交易所；自动执行统一交给 AiAutoTraderService -> TradingEngine。
 */
final class AiService
{
    /** 输出 token 上限（思考型模型的思考过程也占输出 token，建议 4000~8000） */
    public const MAX_OUTPUT_TOKENS = 8000;

    /** 单次分析（可携带 trade_mode/leverage 直接执行，也可仅分析） */
    public static function analyze(User $user, array $input): array
    {
        $configId = (int) ($input['ai_config_id'] ?? 0);
        $config = self::config($user, $configId);
        $symbol = strtoupper(trim((string) ($input['symbol'] ?? 'BTC-USDT-SWAP')));
        $marketType = (string) ($input['market_type'] ?? 'swap');
        $interval = (string) ($input['interval'] ?? '15m');
        $mode = (string) ($input['mode'] ?? $config['mode'] ?? 'auto');
        if ($mode === 'auto') {
            MembershipService::assertCan($user, 'auto_trade', '自动交易为黄金版及以上功能');
        }
        $capitalUsdt = min(1000000000, max(0, (float) ($input['capital_usdt'] ?? ($config['capital_usdt'] ?? 0))));
        $marketData = $input['market_data'] ?? null;
        if (!is_array($marketData) || count($marketData) < 2) {
            $marketData = (new OkxService(null, $marketType))->klines($symbol, $interval, 200);
        }

        $prompt = self::prompt($symbol, $marketType, $interval, $marketData, (string) ($input['description'] ?? ''), $capitalUsdt);
        $isFreeAi = !empty($config['free_ai']);
        $prompt .= $isFreeAi ? '本次使用平台免费 AI，仅提供分析建议；请保持保守。' : '';
        $raw = self::request($config, $prompt);
        $raw['symbol'] = $raw['symbol'] ?? $symbol;
        $signal = SignalValidator::validate($raw, $symbol);
        $directionMode = DirectionMode::normalize(
            (string) ($input['direction_mode'] ?? ($config['direction_mode'] ?? DirectionMode::LONG_ONLY)),
            $marketType
        );
        $decision = DirectionMode::resolve($signal['signal'], $directionMode);
        $signal['direction_mode'] = $directionMode;
        $signal['direction_action'] = $decision['action'];
        $signal['direction_note'] = $decision['note'];

        $record = AiSignal::create([
            'user_id' => $user->id,
            'ai_config_id' => $config['id'] ?? null,
            'symbol' => $signal['symbol'],
            'market_type' => $marketType,
            'signal' => $signal['signal'],
            'confidence' => $signal['confidence'],
            'entry' => $signal['entry'],
            'stop_loss' => $signal['stop_loss'],
            'take_profit' => $signal['take_profit'],
            'position_percent' => $signal['position_percent'],
            'reason' => $signal['reason'],
            'validated' => 1,
            'executed' => 0,
            'request_summary' => mb_substr($prompt, 0, 2000),
            'response_json' => $signal,
        ]);

        $order = null;
        $riskGuard = ['allow' => false, 'reason' => ''];
        if ($mode === 'auto') {
            $riskGuard = AiRiskGuard::evaluate($user, $config, $symbol, $signal, (int) $record->id, $directionMode, false);
            if (!empty($riskGuard['decision'])) {
                $decision = $riskGuard['decision'];
                $signal['direction_action'] = $decision['action'];
                $signal['direction_note'] = $riskGuard['reason'] ?: $decision['note'];
            }
        }
        if ($mode === 'auto' && !empty($riskGuard['reason']) && empty($riskGuard['allow'])) {
            $record->reason = mb_substr((string) $riskGuard['reason'], 0, 1000);
            $record->response_json = $signal;
            $record->save();
        }
        $tradeMode = (string) ($input['trade_mode'] ?? ($config['trade_mode'] ?? 'demo'));
        if ($mode === 'auto' && !empty($riskGuard['allow']) && $decision['action'] !== 'hold' && $decision['action'] !== 'skip' && $signal['confidence'] >= 0.6) {
            $engineMode = $tradeMode === 'live' ? 'live' : ($tradeMode === 'local' ? 'paper' : 'testnet');
            $leverage = min(
                (int) RiskManager::config($user)->max_leverage,
                max(1, (int) ($input['leverage'] ?? ($config['leverage'] ?? 1)))
            );
            if ($marketType === 'spot') $leverage = 1;

            /* 合约下单前同步杠杆 */
            if ($marketType === 'swap' && $engineMode !== 'paper') {
                $account = OkxAccount::where('user_id', $user->id)->where('market_type', 'swap')->find();
                if ($account) {
                    try {
                        (new OkxService($account, 'swap'))->setLeverage($symbol, $leverage, 'cross');
                    } catch (Throwable $e) {
                        SafeLogger::warning('AI 分析设置杠杆失败', ['symbol' => $symbol, 'message' => $e->getMessage()]);
                    }
                }
            }

            $order = TradingEngine::execute($user, [
                'symbol' => $signal['symbol'],
                'market_type' => $marketType,
                'mode' => $engineMode,
                'side' => $decision['side'],
                'position_side' => $decision['pos_side'],
                'reduce_only' => $decision['reduce_only'],
                'order_type' => 'MARKET',
                'quantity' => (string) ($input['quantity'] ?? ($config['auto_quantity'] ?? '0.001')),
                'price' => $signal['entry'] ?? '',
                'stop_loss' => $signal['stop_loss'] ?? '',
                'take_profit' => $signal['take_profit'] ?? '',
                'position_percent' => $signal['position_percent'] ?: (float) ($config['auto_position_percent'] ?? 2),
                'leverage' => $leverage,
                'source' => 'AI',
                'ai_signal_id' => $record->id,
            ]);
            $record->executed = 1;
            $record->save();
        }

        return [
            'signal' => $signal,
            'ai_signal_id' => $record->id,
            'executed' => (bool) $record->executed,
            'trade_mode' => $tradeMode,
            'direction_mode' => $directionMode,
            'direction_action' => $decision['action'],
            'direction_note' => $decision['note'],
            'capital_usdt' => $capitalUsdt,
            'risk_guard' => $riskGuard,
            'order' => $order?->toArray(),
        ];
    }

    /** 自动复盘接口：返回任意 JSON 复盘结果，不计入用户主动 AI 分析次数。 */
    public static function reviewTrade(User $user, array $context, int $configId = 0): array
    {
        $config = self::config($user, $configId);
        if ($configId > 0) {
            $stored = AiConfig::where('user_id', $user->id)->where('id', $configId)->find();
            if ($stored && is_array($stored->provider_config) && !empty($stored->provider_config['strategy_note'])) {
                $context['strategy_note'] = (string) $stored->provider_config['strategy_note'];
            }
        }
        $prompt = '你是量化交易复盘助手，只能返回一个 JSON 对象，不得返回代码。'
            . '请根据以下已完成交易，判断盈亏原因并给出可执行的改进建议。'
            . '字段建议为 review（中文总结）、causes（数组）、improvements（数组）、risk_level（low/medium/high）、next_action（字符串）。'
            . '即使这笔交易盈利，也要指出风险；如果亏损，重点说明信号、止损、仓位和方向是否合理。'
            . '该配置的策略偏好：' . mb_substr((string) ($context['strategy_note'] ?? ''), 0, 1000) . '。交易数据：'
            . json_encode($context, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        return self::request($config, $prompt, true, true);
    }

    /* ---------------- 配置 CRUD ---------------- */

    public static function listConfigs(User $user): array
    {
        $rows = AiConfig::where('user_id', $user->id)->where('deleted_at', null)->order('id', 'desc')->select()->toArray();
        $out = array_map(static function ($row) {
            return [
                'id' => (int) $row['id'],
                'name' => $row['name'],
                'provider_type' => $row['provider_type'] ?? 'openai',
                'api_style' => (string) ($row['api_style'] ?? 'chat_completions'),
                'model' => $row['model'],
                'enabled' => (bool) $row['enabled'],
                'mode' => $row['mode'],
                'running' => (bool) ($row['running'] ?? 0),
                'trade_mode' => $row['trade_mode'] ?? 'demo',
                'leverage' => (int) ($row['leverage'] ?? 1),
                'auto_symbol' => $row['auto_symbol'] ?? '',
                'auto_symbols' => (string) ($row['auto_symbols'] ?? ''),
                'auto_market_type' => $row['auto_market_type'] ?? 'swap',
                'direction_mode' => DirectionMode::normalize((string) ($row['direction_mode'] ?? 'long_only'), (string) ($row['auto_market_type'] ?? 'swap')),
                'ai_risk' => AiRiskGuard::normalizePolicy(is_array($row['provider_config']['ai_risk'] ?? null) ? $row['provider_config']['ai_risk'] : []),
                'ai_runtime' => AiRiskGuard::runtime($row),
                'auto_interval' => $row['auto_interval'] ?? '15m',
                'auto_period_seconds' => (int) ($row['auto_period_seconds'] ?? 300),
                'auto_quantity' => (string) ($row['auto_quantity'] ?? '0'),
                'auto_position_percent' => (float) ($row['auto_position_percent'] ?? 2),
                'capital_usdt' => (float) ($row['capital_usdt'] ?? 0),
                'min_confidence' => (float) ($row['min_confidence'] ?? 0.6),
                'run_count' => (int) ($row['run_count'] ?? 0),
                'trade_count' => (int) ($row['trade_count'] ?? 0),
                'last_run_at' => $row['last_run_at'] ?? null,
                'last_signal' => $row['last_signal'] ?? null,
                'proxy_enabled' => (bool) ($row['proxy_enabled'] ?? 0),
                'test_status' => $row['test_status'] ?? null,
                'last_test_at' => $row['last_test_at'] ?? null,
                'created_at' => $row['created_at'] ?? null,
            ];
        }, $rows);
        if (FreeAiService::enabled()) array_unshift($out, FreeAiService::publicConfig());
        return $out;
    }

    public static function getConfig(User $user, int $id): array
    {
        $row = AiConfig::where('user_id', $user->id)->where('id', $id)->find();
        if (!$row) throw new RuntimeException('AI 配置不存在');
        return [
            'id' => $row->id,
            'name' => $row->name,
            'provider_type' => $row->provider_type,
            'api_style' => (string) ($row->api_style ?? 'chat_completions'),
            'api_url' => $row->api_url,
            'model' => $row->model,
            'temperature' => (float) $row->temperature,
            'max_tokens' => (int) $row->max_tokens,
            'mode' => $row->mode,
            'enabled' => (bool) $row->enabled,
            'provider_config' => $row->provider_config ?? [],
            'proxy_enabled' => (bool) $row->proxy_enabled,
            'proxy_type' => $row->proxy_type,
            'proxy_host' => $row->proxy_host,
            'proxy_port' => $row->proxy_port,
            'proxy_username' => $row->proxy_username,
            'test_status' => $row->test_status,
            'test_message' => $row->test_message,
            'last_test_at' => $row->last_test_at,
            /* 自动交易 */
            'trade_mode' => $row->trade_mode ?? 'demo',
            'leverage' => (int) ($row->leverage ?? 1),
            'auto_symbol' => $row->auto_symbol ?? '',
            'auto_symbols' => (string) ($row->auto_symbols ?? ''),
            'auto_market_type' => $row->auto_market_type ?? 'swap',
            'direction_mode' => DirectionMode::normalize((string) ($row->direction_mode ?? 'long_only'), (string) ($row->auto_market_type ?? 'swap')),
            'ai_risk' => AiRiskGuard::normalizePolicy(is_array($row->provider_config['ai_risk'] ?? null) ? $row->provider_config['ai_risk'] : []),
            'ai_runtime' => AiRiskGuard::runtime($row),
            'auto_interval' => $row->auto_interval ?? '15m',
            'auto_period_seconds' => (int) ($row->auto_period_seconds ?? 300),
            'auto_quantity' => (string) ($row->auto_quantity ?? ''),
            'auto_position_percent' => (float) ($row->auto_position_percent ?? 2),
            'capital_usdt' => (float) ($row->capital_usdt ?? 0),
            'min_confidence' => (float) ($row->min_confidence ?? 0.6),
            'running' => (bool) ($row->running ?? 0),
            'run_count' => (int) ($row->run_count ?? 0),
            'trade_count' => (int) ($row->trade_count ?? 0),
        ];
    }

    public static function saveConfig(User $user, array $input): AiConfig
    {
        $id = (int) ($input['id'] ?? 0);
        $config = $id > 0 ? AiConfig::where('user_id', $user->id)->where('id', $id)->find() : null;
        if ($id > 0 && !$config) throw new RuntimeException('AI 配置不存在');
        if (!$config) {
            /* 会员限制：AI 配置数量 */
            $current = AiConfig::where('user_id', $user->id)->count();
            MembershipService::assertQuota($user, 'ai_config', $current);
            $config = new AiConfig();
            $config->user_id = $user->id;
        }

        $config->name = trim((string) ($input['name'] ?? '默认 AI'));
        if ($config->name === '') throw new RuntimeException('配置名称不能为空');
        $config->provider_type = in_array(($input['provider_type'] ?? 'openai'), ['openai', 'azure', 'claude', 'gemini', 'custom'], true)
            ? $input['provider_type'] : 'openai';
        $style = (string) ($input['api_style'] ?? ($config->api_style ?: 'chat_completions'));
        $config->api_style = in_array($style, ['chat_completions', 'responses'], true) ? $style : 'chat_completions';

        $key = trim((string) ($input['api_key'] ?? ''));
        if ($key !== '') $config->api_key_ciphertext = CryptoService::encrypt($key);

        $config->api_url = trim((string) ($input['api_url'] ?? self::getDefaultUrl($config->provider_type)));
        $config->model = trim((string) ($input['model'] ?? ''));
        $config->temperature = min(1, max(0, (float) ($input['temperature'] ?? 0.2)));
        $config->max_tokens = min(self::MAX_OUTPUT_TOKENS, max(100, (int) ($input['max_tokens'] ?? 800)));
        $config->mode = 'auto';
        /* 新增配置时默认启用，编辑时保留用户选择 */
        $config->enabled = $id > 0 ? (!empty($input['enabled']) ? 1 : 0) : (isset($input['enabled']) ? (!empty($input['enabled']) ? 1 : 0) : 1);

        /* 会员限制：自动交易需要对应等级 */
        if ($config->mode === 'auto') {
            MembershipService::assertCan($user, 'auto_trade', '自动交易为黄金版及以上功能');
        }

        /* 提供商特定配置 */
        $providerConfig = is_array($config->provider_config) ? $config->provider_config : [];
        if ($config->provider_type === 'azure') {
            $providerConfig['api_version'] = trim((string) ($input['azure_api_version'] ?? '2024-02-15-preview'));
            $providerConfig['deployment_name'] = trim((string) ($input['azure_deployment'] ?? ($providerConfig['deployment_name'] ?? '')));
        } elseif ($config->provider_type === 'gemini') {
            $providerConfig['api_version'] = trim((string) ($input['gemini_api_version'] ?? 'v1'));
        }

        /* 自动交易参数 */
        $providerConfig['td_mode'] = in_array(($input['td_mode'] ?? ($providerConfig['td_mode'] ?? 'cross')), ['cross', 'isolated'], true)
            ? ($input['td_mode'] ?? ($providerConfig['td_mode'] ?? 'cross'))
            : 'cross';
        if (!empty($input['strategy_note'])) $providerConfig['strategy_note'] = mb_substr((string) $input['strategy_note'], 0, 1000);
        $providerConfig['ai_risk'] = AiRiskGuard::normalizePolicy([
            'cooldown_seconds' => $input['risk_cooldown_seconds'] ?? null,
            'confirm_rounds' => $input['risk_confirm_rounds'] ?? null,
            'max_trades_per_day' => $input['risk_max_trades_per_day'] ?? null,
            'max_daily_loss' => $input['risk_max_daily_loss'] ?? null,
            'max_consecutive_losses' => $input['risk_max_consecutive_losses'] ?? null,
            'max_error_streak' => $input['risk_max_error_streak'] ?? null,
            'circuit_breaker_enabled' => array_key_exists('risk_circuit_breaker_enabled', $input) ? $input['risk_circuit_breaker_enabled'] : null,
            'require_stop_loss' => array_key_exists('risk_require_stop_loss', $input) ? $input['risk_require_stop_loss'] : null,
            'require_take_profit' => array_key_exists('risk_require_take_profit', $input) ? $input['risk_require_take_profit'] : null,
            'min_risk_reward' => $input['risk_min_risk_reward'] ?? null,
            'allow_pyramiding' => array_key_exists('risk_allow_pyramiding', $input) ? $input['risk_allow_pyramiding'] : null,
        ], is_array($providerConfig['ai_risk'] ?? null) ? $providerConfig['ai_risk'] : []);
        $config->provider_config = $providerConfig;
        if (!$providerConfig['ai_risk']['circuit_breaker_enabled']) {
            /* 用户关闭开关后，历史暂停状态不应继续挡住下一轮。 */
            AiRiskGuard::resetRuntime($config);
        }

        $tradeMode = (string) ($input['trade_mode'] ?? 'demo');
        $config->trade_mode = in_array($tradeMode, ['demo', 'live', 'local'], true) ? $tradeMode : 'demo';
        /* 会员限制：实盘交易（含实盘自动交易）为至尊版功能 */
        if ($config->trade_mode === 'live') {
            MembershipService::assertCan($user, 'live_trade', '实盘交易为至尊版功能');
        }
        $config->leverage = min(125, max(1, (int) ($input['leverage'] ?? 1)));
        $memberLimits = MembershipService::limits($user);
        $config->auto_symbol = strtoupper(trim((string) ($input['auto_symbol'] ?? ($config->auto_symbol ?: 'BTC-USDT-SWAP'))));
        $config->auto_market_type = in_array(($input['auto_market_type'] ?? 'swap'), ['spot', 'swap'], true) ? ($input['auto_market_type'] ?? 'swap') : 'swap';
        $config->direction_mode = DirectionMode::normalize(
            (string) ($input['direction_mode'] ?? ($config->direction_mode ?? DirectionMode::LONG_ONLY)),
            $config->auto_market_type
        );
        $config->auto_interval = (string) ($input['auto_interval'] ?? '15m');
        $config->auto_period_seconds = min(86400, max(10, (int) ($input['auto_period_seconds'] ?? 300)));
        $quantity = trim((string) ($input['auto_quantity'] ?? ($config->auto_quantity ?: '0.001')));
        $config->auto_quantity = is_numeric($quantity) && (float) $quantity > 0 ? $quantity : '0.001';
        $config->auto_position_percent = min(100, max(0.1, (float) ($input['auto_position_percent'] ?? 2)));
        $config->capital_usdt = min(1000000000, max(0, (float) ($input['capital_usdt'] ?? ($config->capital_usdt ?? 0))));
        $config->min_confidence = min(1, max(0, (float) ($input['min_confidence'] ?? 0.6)));
        if ($config->auto_market_type === 'spot') $config->leverage = 1;
        /* 会员限制：杠杆上限（按最终市场类型校验） */
        if ($config->auto_market_type !== 'spot' && $config->leverage > $memberLimits['max_leverage']) {
            throw new RuntimeException(sprintf(
                '杠杆 %dx 超过当前会员（%s）上限 %dx，请升级会员或下调杠杆',
                $config->leverage, $memberLimits['name'], $memberLimits['max_leverage']
            ));
        }

        /* 多币种清单：以 auto_symbols 为准（逗号/空格分隔），单值向后兼容 */
        $listRaw = trim((string) ($input['auto_symbols'] ?? ''));
        $symbols = AiAutoTraderService::parseSymbols($listRaw !== '' ? $listRaw : (string) $config->auto_symbol, $config->auto_market_type);
        if (!$symbols) $symbols = [$config->auto_market_type === 'spot' ? 'BTC-USDT' : 'BTC-USDT-SWAP'];
        /* 会员限制：单配置币种数 */
        if (count($symbols) > $memberLimits['multi_symbol_limit']) {
            throw new RuntimeException(sprintf(
                '当前会员（%s）单个 AI 配置最多 %d 个币种，请升级会员或减少币种数量',
                $memberLimits['name'], $memberLimits['multi_symbol_limit']
            ));
        }
        $config->auto_symbols = implode(',', $symbols);
        $config->auto_symbol = $symbols[0];

        /* 代理配置 */
        $config->proxy_enabled = !empty($input['proxy_enabled']) ? 1 : 0;
        if ($config->proxy_enabled) {
            $config->proxy_type = in_array(($input['proxy_type'] ?? 'http'), ['http', 'socks5'], true) ? $input['proxy_type'] : 'http';
            $config->proxy_host = trim((string) ($input['proxy_host'] ?? ''));
            $config->proxy_port = (int) ($input['proxy_port'] ?? 0);
            $config->proxy_username = trim((string) ($input['proxy_username'] ?? ''));
            $proxyPass = trim((string) ($input['proxy_password'] ?? ''));
            if ($proxyPass !== '') $config->proxy_password_ciphertext = CryptoService::encrypt($proxyPass);
        } else {
            $config->proxy_type = null;
            $config->proxy_host = null;
            $config->proxy_port = null;
            $config->proxy_username = null;
            $config->proxy_password_ciphertext = null;
        }

        $config->save();
        return $config;
    }

    public static function deleteConfig(User $user, int $id): void
    {
        $row = AiConfig::where('user_id', $user->id)->where('id', $id)->find();
        if (!$row) throw new RuntimeException('AI 配置不存在');
        $row->delete();
    }

    public static function testConnection(User $user, int $id): array
    {
        $row = AiConfig::where('user_id', $user->id)->where('id', $id)->find();
        if (!$row) throw new RuntimeException('AI 配置不存在');

        $config = $row->getFullConfig();
        $testPrompt = '请用一个 JSON 对象回答：{"status":"ok","message":"连接成功"}';

        try {
            $start = microtime(true);
            $result = self::request($config, $testPrompt, true, true);
            $duration = round((microtime(true) - $start) * 1000);

            /* 连接测试：能解析出内容即算通，不要求必须是特定结构 */
            if (!is_array($result) || $result === []) {
                throw new RuntimeException('接口可达，但返回内容无法解析为结构化结果');
            }

            $row->test_status = 'success';
            $row->test_message = "连接成功，响应时间 {$duration}ms";
            $row->last_test_at = date('Y-m-d H:i:s');
            $row->save();

            return ['status' => 'success', 'message' => $row->test_message, 'duration_ms' => $duration, 'sample' => $result];
        } catch (Throwable $e) {
            $row->test_status = 'failed';
            $row->test_message = mb_substr($e->getMessage(), 0, 500);
            $row->last_test_at = date('Y-m-d H:i:s');
            $row->save();
            throw new RuntimeException('连接测试失败：' . $e->getMessage());
        }
    }

    /* ---------------- 内部 ---------------- */

    /**
     * AI 连接分步诊断：定位「AI 收不到」到底卡在哪一步。
     * 依次检查：配置完整性 → API Key 可解密 → 网络/代理 → HTTP 状态 → 内容解析。
     */
    public static function diagnose(User $user, int $configId = 0): array
    {
        $result = [
            'success' => false,
            'config_id' => $configId,
            'steps' => [],
        ];

        $row = $configId > 0
            ? AiConfig::where('user_id', $user->id)->where('id', $configId)->find()
            : AiConfig::where('user_id', $user->id)->where('enabled', 1)->order('id', 'desc')->find();

        if (!$row) {
            $result['steps'][] = self::step('配置', false, '未找到 AI 配置，请先在「AI 配置」页面新增并启用一个配置');
            return $result;
        }

        $result['config_id'] = (int) $row->id;
        $result['steps'][] = self::step('配置', true, '已加载配置 #' . $row->id . '：' . $row->name . '（' . $row->provider_type . '）');

        /* 1) API Key 能否解密 */
        $apiKey = '';
        try {
            $apiKey = $row->getApiKeyAttribute();
        } catch (Throwable $e) {
            $result['steps'][] = self::step('API Key', false, '密钥解密失败（APP_KEY 可能被更换过）：' . $e->getMessage() . '；请重新填写 API Key');
            return $result;
        }
        if ($apiKey === '') {
            $result['steps'][] = self::step('API Key', false, '未保存 API Key，请填写后保存');
            return $result;
        }
        $result['steps'][] = self::step('API Key', true, '已保存，长度 ' . strlen($apiKey) . '，前缀 ' . substr($apiKey, 0, 6) . '...');

        /* 2) 模型与地址 */
        $config = $row->getFullConfig();
        if (empty($config['model'])) {
            $result['steps'][] = self::step('模型', false, '未填写模型名（如 gpt-4o-mini / claude-3-5-sonnet）');
            return $result;
        }
        if (empty($config['api_url'])) {
            $result['steps'][] = self::step('接口地址', false, '未填写 API 地址');
            return $result;
        }
        $result['steps'][] = self::step('地址', true, $config['api_url'] . '  模型：' . $config['model'] . '  接口格式：'
            . (($config['api_style'] ?? 'chat_completions') === 'responses' ? 'Responses（/v1/responses）' : 'Chat Completions'));

        /* 3) 代理 */
        if (!empty($config['proxy'])) {
            $p = $config['proxy'];
            $result['steps'][] = self::step('代理', true, ($p['type'] ?? 'http') . '://' . ($p['host'] ?? '') . ':' . ($p['port'] ?? ''));
        } else {
            $result['steps'][] = self::step('代理', true, '未启用（境内服务器访问 OpenAI/Claude/Gemini 通常必须启用代理）');
        }

        /* 4) 域名解析（双栈：A 记录解析失败时回退 AAAA——纯 IPv6 服务器场景） */
        try {
            $host = parse_url($config['api_url'], PHP_URL_HOST) ?: '';
            if ($host === '') throw new RuntimeException('接口地址格式无效');
            $ip = gethostbyname($host);
            if ($ip === $host) {
                $ip6 = '';
                try {
                    $recs = dns_get_record($host, DNS_AAAA);
                    if (!empty($recs)) $ip6 = (string) ($recs[0]['ipv6'] ?? '');
                } catch (Throwable $ignore) { /* DNS 查询失败按无记录处理 */ }
                if ($ip6 !== '') {
                    $result['steps'][] = self::step('DNS', true, $host . ' 无 A 记录，但存在 AAAA（IPv6）：' . $ip6 . ' —— 纯 IPv6 服务器将通过 AAAA 连接');
                } else {
                    $result['steps'][] = self::step('DNS', false, '域名 ' . $host . ' 无法解析（A/AAAA 均无记录），请检查 DNS 或改用可直连的中转地址');
                    return $result;
                }
            } else {
                $result['steps'][] = self::step('DNS', true, $host . ' → ' . $ip);
            }
        } catch (Throwable $e) {
            $result['steps'][] = self::step('DNS', false, $e->getMessage());
            return $result;
        }

        /* 5) 真实请求（返回 HTTP 状态与原始片段） */
        try {
            $payload = self::buildPayload($config['provider_type'], $config, '只回复 JSON：{"status":"ok"}');
            $url = self::buildUrl($config['provider_type'], $config);
            $headers = self::buildHeaders($config['provider_type'], $config);

            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_POST => true,
                CURLOPT_POSTFIELDS => $payload,
                CURLOPT_HTTPHEADER => $headers,
                CURLOPT_CONNECTTIMEOUT => 10,
                CURLOPT_TIMEOUT => 60,
                CURLOPT_FOLLOWLOCATION => true,
            ]);
            if (!empty($config['proxy'])) {
                $p = $config['proxy'];
                curl_setopt($ch, CURLOPT_PROXY, ($p['host'] ?? '') . ':' . ($p['port'] ?? ''));
                curl_setopt($ch, CURLOPT_PROXYTYPE, ($p['type'] ?? 'http') === 'socks5' ? CURLPROXY_SOCKS5 : CURLPROXY_HTTP);
                if (!empty($p['username'])) {
                    curl_setopt($ch, CURLOPT_PROXYUSERPWD, $p['username'] . ':' . ($p['password'] ?? ''));
                }
            }
            $body = curl_exec($ch);
            $err = curl_error($ch);
            $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $total = (int) curl_getinfo($ch, CURLINFO_TOTAL_TIME);
            curl_close($ch);

            if ($body === false || $err !== '') {
                $hint = stripos($err, 'resolve') !== false ? '域名解析失败，可能是 DNS 污染'
                    : (stripos($err, 'timed out') !== false ? '连接超时，通常是网络被墙或该地址不可达'
                    : (stripos($err, 'refused') !== false ? '连接被拒绝，检查代理端口是否正确' : ''));
                $result['steps'][] = self::step('HTTP 请求', false, 'curl 错误：' . $err . ($hint ? '（' . $hint . '）' : ''));
                return $result;
            }

            $result['steps'][] = self::step('HTTP 请求', $status >= 200 && $status < 300, 'HTTP ' . $status . '，耗时 ' . $total . 's，返回 ' . strlen((string) $body) . ' 字节');

            $decoded = json_decode((string) $body, true);
            if (!is_array($decoded)) {
                $result['steps'][] = self::step('解析', false, '返回主体不是 JSON，原始片段：' . mb_substr((string) $body, 0, 300));
                return $result;
            }

            if ($status < 200 || $status >= 300) {
                $errMsg = $decoded['error']['message'] ?? $decoded['message'] ?? ('HTTP ' . $status);
                $result['steps'][] = self::step('接口响应', false, 'API 报错：' . mb_substr((string) $errMsg, 0, 300));
                return $result;
            }

            $content = trim(self::extractContent($config['provider_type'], $decoded, $status, $config));
            if ($content === '') {
                $content = trim(self::rescueContent($config['provider_type'], $decoded, $config));
            }
            $parsed = self::decodeJson($content);
            if ($parsed !== null) {
                $result['steps'][] = self::step('解析', true, '解析成功：' . mb_substr(json_encode($parsed, JSON_UNESCAPED_UNICODE), 0, 300));
            } elseif ($content === '') {
                $finish = self::finishReason($config['provider_type'], $decoded, $config);
                $result['steps'][] = self::step('解析', false, '模型没有返回内容'
                    . ($finish !== '' ? '（finish_reason=' . $finish . '）' : '')
                    . ($finish === 'length' ? '：输出被截断，请把 max_tokens 调大' : '：可能被中转站/内容策略拦截，请核对模型名与接口地址')
                    . '。原始返回片段：' . mb_substr((string) preg_replace('/\s+/', ' ', (string) $body), 0, 300));
            } else {
                $result['steps'][] = self::step('解析', false, '模型返回内容无法解析为 JSON，原始内容：' . mb_substr($content, 0, 300));
            }

            $result['success'] = true;
            $result['model_output'] = mb_substr($content, 0, 1000);
        } catch (Throwable $e) {
            $result['steps'][] = self::step('请求异常', false, $e->getMessage());
            return $result;
        }

        return $result;
    }

    private static function step(string $name, bool $ok, string $message): array
    {
        return ['name' => $name, 'status' => $ok ? 'passed' : 'failed', 'message' => $message];
    }

    private static function config(User $user, int $configId = 0): array
    {
        /* -1 专门表示用户主动选择的平台免费 AI。 */
        if ($configId === -1) {
            $free = FreeAiService::fullConfig();
            if ($free) return $free;
            throw new RuntimeException('平台免费 AI 尚未由管理员配置或当前已停用');
        }
        if ($configId > 0) {
            $row = AiConfig::where('user_id', $user->id)->where('id', $configId)->find();
            if ($row) return $row->getFullConfig();
        }
        $row = AiConfig::where('user_id', $user->id)->where('enabled', 1)->order('id', 'desc')->find();
        if ($row) return $row->getFullConfig();

        /* 没有个人配置时，优先使用管理端维护的免费 AI。 */
        $free = FreeAiService::fullConfig();
        if ($free) return $free;

        $env = static function (string $key, mixed $default = ''): mixed {
            if (function_exists('env')) return env($key, $default);
            $value = getenv($key);
            return $value === false ? $default : $value;
        };
        $key = (string) $env('AI_API_KEY', '');
        if ($key === '' || $env('AI_MODEL', '') === '') throw new RuntimeException('AI 配置未完成，请先使用平台免费 AI或在「AI 配置」页面添加并启用一个配置');
        return [
            'id' => null, 'provider_type' => 'openai', 'api_key' => $key,
            'api_url' => $env('AI_API_URL', 'https://api.openai.com/v1/chat/completions'),
            'model' => $env('AI_MODEL'), 'temperature' => (float) $env('AI_TEMPERATURE', 0.2),
            'max_tokens' => (int) $env('AI_MAX_TOKENS', 800), 'mode' => 'auto',
            'provider_config' => [], 'proxy' => null, 'capital_usdt' => 0,
        ];
    }

    private static function prompt(string $symbol, string $marketType, string $interval, array $marketData, string $description, float $capitalUsdt = 0.0): string
    {
        $safe = array_slice($marketData, -120);
        $capitalText = $capitalUsdt > 0 ? number_format($capitalUsdt, 2, '.', '') . ' USDT' : '未设置';
        return '你是量化分析器，只能返回一个 JSON 对象，不得返回 PHP、Shell、SQL、工具调用或代码。'
            . '字段必须为 symbol,signal,confidence,entry,stop_loss,take_profit,position_percent,reason。'
            . 'signal 只能 BUY/SELL/HOLD，confidence 为 0 到 1 的小数（越大越有把握），'
            . 'entry 为建议入场价，stop_loss 与 take_profit 为价格数字，position_percent 建议仓位百分比（0-100）。'
            . '用户可用资金规模约为：' . $capitalText . '。请严格按该资金规模设计仓位、止损和风险收益比，避免给出明显超出资金承受能力的策略；未设置资金时按保守小仓位处理。'
            . '交易对：' . $symbol . '，市场：' . $marketType . '，周期：' . $interval . '。'
            . '策略描述：' . mb_substr($description, 0, 1000) . '。'
            . 'K线：' . json_encode($safe, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    /**
     * 解析 AI 返回的内容为结构化信号。
     *
     * 真实世界里模型常出现：markdown 代码块、前后寒暄、尾随逗号、单引号、
     * 多段 JSON、BOM、全角标点。逐级降级尝试，最大化可解析率。
     */
    private static function decodeJson(string $content): ?array
    {
        $text = trim($content);
        if ($text === '') return null;

        /* 去 BOM */
        $text = preg_replace('/^\xEF\xBB\xBF/', '', $text);

        /* 1) 直接解析 */
        $r = json_decode($text, true);
        if (is_array($r)) return $r;

        /* 2) 去 markdown 围栏（```json ... ``` 或 ``` ... ```） */
        $stripped = preg_replace('/^```[a-zA-Z]*\s*/', '', $text);
        $stripped = preg_replace('/```\s*$/', '', $stripped);
        $stripped = trim($stripped);
        $r = json_decode($stripped, true);
        if (is_array($r)) return $r;

        /* 3) 截取第一个 { 到最后一个 } 之间的内容 */
        $start = strpos($stripped, '{');
        $end = strrpos($stripped, '}');
        if ($start !== false && $end !== false && $end > $start) {
            $slice = substr($stripped, $start, $end - $start + 1);
            $r = json_decode($slice, true);
            if (is_array($r)) return $r;

            /* 4) 常见修复：尾随逗号 / 全角标点 / 单引号 */
            $fixed = preg_replace('/,\s*([}\]])/', '$1', $slice);
            $fixed = str_replace(['：', '，', '“', '”', '‘', '’'], [':', ',', '"', '"', "'", "'"], $fixed);
            $r = json_decode($fixed, true);
            if (is_array($r)) return $r;

            /* 5) 单引号转双引号 */
            $r = json_decode(str_replace("'", '"', $fixed), true);
            if (is_array($r)) return $r;
        }

        return null;
    }

    /**
     * 把 AI 返回的任意形态（字符串 / 数组 / 嵌套）归一成信号数组。
     */
    private static function normalizeSignalPayload(array $result): ?array
    {
        /* 已经是扁平信号 */
        if (isset($result['signal'])) return $result;

        /* 形如 {"data": {...}} / {"result": {...}} / {"signal": {...}} */
        foreach (['data', 'result', 'output', 'analysis', 'response'] as $key) {
            if (isset($result[$key]) && is_array($result[$key]) && isset($result[$key]['signal'])) {
                return $result[$key];
            }
        }

        /* 形如 {"data": "{\"signal\":...}"} */
        foreach (['content', 'text', 'message', 'output_text', 'answer'] as $key) {
            if (isset($result[$key]) && is_string($result[$key])) {
                $inner = self::decodeJson((string) $result[$key]);
                if ($inner !== null && isset($inner['signal'])) return $inner;
            }
        }

        /* 形如 [{"signal":...}] */
        if (isset($result[0]) && is_array($result[0]) && isset($result[0]['signal'])) {
            return $result[0];
        }

        /* 宽松匹配：只要出现 signal 字段就带上默认值 */
        if (isset($result['signal'])) return $result;

        /* 没有任何 signal 字段时，尝试用 BUY/SELL/HOLD 关键词兜底 */
        $text = json_encode($result, JSON_UNESCAPED_UNICODE);
        if (is_string($text)) {
            foreach (['BUY', 'SELL', 'HOLD'] as $cand) {
                if (preg_match('/"(?:signal|action|direction)"\s*:\s*"?([A-Za-z]+)"?/i', $text, $m)) {
                    $result['signal'] = strtoupper($m[1]);
                    $result += ['symbol' => '', 'confidence' => 0.5, 'reason' => '模型返回字段名不标准，已自动归一'];
                    return $result;
                }
            }
        }

        return null;
    }

    private static function request(array $config, string $prompt, bool $lenient = false, bool $skipJsonCheck = false, bool $allowTokenRetry = true): array
    {
        $provider = $config['provider_type'] ?? 'openai';
        $payload = self::buildPayload($provider, $config, $prompt);
        $url = self::buildUrl($provider, $config);
        $headers = self::buildHeaders($provider, $config);

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_CONNECTTIMEOUT => 8,
            CURLOPT_TIMEOUT => 60,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_ENCODING => '',
        ]);

        if (!empty($config['proxy'])) {
            $proxy = $config['proxy'];
            curl_setopt($ch, CURLOPT_PROXY, "{$proxy['host']}:{$proxy['port']}");
            curl_setopt($ch, CURLOPT_PROXYTYPE, ($proxy['type'] ?? 'http') === 'socks5' ? CURLPROXY_SOCKS5 : CURLPROXY_HTTP);
            if (!empty($proxy['username'])) {
                curl_setopt($ch, CURLOPT_PROXYUSERPWD, "{$proxy['username']}:{$proxy['password']}");
            }
        }

        $body = curl_exec($ch);
        $error = curl_error($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($body === false || $error) {
            throw new RuntimeException('AI 网络请求失败：' . ($error ?: '未知错误') . '。若服务器在境内，请在 AI 配置中启用代理。');
        }

        $response = json_decode((string) $body, true);
        if (!is_array($response)) {
            throw new RuntimeException('AI 返回的主体不是 JSON（HTTP ' . $status . '）：' . mb_substr((string) $body, 0, 200));
        }

        $content = trim(self::extractContent($provider, $response, $status, $config));
        $result = self::decodeJson($content);
        $fromRescue = false;

        /* 正文为空：思考型模型（deepseek-reasoner / o 系列等）可能把内容全放进
           reasoning_content，先在思考内容里抢救一次 */
        if ($result === null && $content === '') {
            $rescued = trim(self::rescueContent($provider, $response, $config));
            if ($rescued !== '') {
                $content = $rescued;
                $fromRescue = true;
                $result = self::decodeJson($content);
            }
        }

        /* 输出被截断（finish_reason=length：思考占满 token / JSON 被截断）：
           只要内容不能解析成功（包括只抢救到思考内容的情况），就自动大幅调大
           max_tokens 重试一次（一次到位，避免多次慢速重试） */
        if ($result === null && $allowTokenRetry) {
            $finish = self::finishReason($provider, $response, $config);
            $maxTokens = (int) ($config['max_tokens'] ?? 0);
            if ($finish === 'length' && $maxTokens > 0 && $maxTokens < self::MAX_OUTPUT_TOKENS) {
                $retryConfig = $config;
                $retryConfig['max_tokens'] = min(self::MAX_OUTPUT_TOKENS, max(4000, $maxTokens * 4));
                SafeLogger::warning('AI 输出被截断，自动增大 max_tokens 重试', [
                    'from' => $maxTokens, 'to' => $retryConfig['max_tokens'],
                ]);
                return self::request($retryConfig, $prompt, $lenient, $skipJsonCheck, false);
            }
        }

        if ($skipJsonCheck) {
            if ($result === null) {
                if ($lenient && $status >= 200 && $status < 300 && $content !== '') {
                    return ['status' => 'ok', 'message' => $content];
                }
                throw new RuntimeException('AI 返回不是有效结构化 JSON：' . ($content === ''
                    ? '模型没有返回内容（请点「诊断」查看原始返回，或检查中转地址/模型名）'
                    : mb_substr($content, 0, 200)));
            }
            return $result;
        }

        if ($status < 200 || $status >= 300) {
            $errorMsg = $response['error']['message'] ?? $response['message'] ?? ('AI 接口返回 HTTP ' . $status);
            throw new RuntimeException('AI 接口错误：' . $errorMsg);
        }

        if ($result === null) {
            if ($content === '') {
                $finish = self::finishReason($provider, $response, $config);
                $usage = $response['usage'] ?? [];
                $msg = '模型没有返回任何内容';
                if ($finish !== '') $msg .= '（finish_reason=' . $finish . '）';
                if ($finish === 'length') {
                    $msg .= '：输出被截断，请把 AI 配置中的 max_tokens 调大到 4000~8000（当前 ' . (int) ($config['max_tokens'] ?? 0) . '），或改用非思考型模型';
                } elseif ($finish === 'content_filter') {
                    $msg .= '：内容被安全策略过滤，请调整「策略描述」或更换模型';
                } else {
                    $msg .= '：可能被中转站/内容策略拦截，或模型不支持该调用方式';
                }
                if (!empty($usage)) $msg .= '；usage=' . json_encode($usage, JSON_UNESCAPED_UNICODE);
                $msg .= '。原始返回片段：' . mb_substr((string) preg_replace('/\s+/', ' ', (string) $body), 0, 400);
                throw new RuntimeException('AI 返回不是有效结构化 JSON。' . $msg);
            }
            throw new RuntimeException(
                'AI 返回不是有效结构化 JSON。模型原始输出' . ($fromRescue ? '（取自 reasoning_content 思考内容）' : '') . '：' . mb_substr($content, 0, 300)
                . ($fromRescue ? '。这是思考型模型的中间过程、正文为空：其一，max_tokens 太小导致思考未结束（建议把 AI 配置的 max_tokens 调到 4000~8000）；其二，该模型/中转不支持输出正文——建议改用指令型模型（如 gpt-4o-mini / deepseek-chat / claude-3-5-sonnet）' : '')
            );
        }

        /* 归一化：兼容模型把信号包在外层对象/数组里的情况 */
        $normalized = self::normalizeSignalPayload($result);
        if ($normalized === null) {
            throw new RuntimeException(
                'AI 返回了 JSON 但缺少 signal 字段。原始内容：' . mb_substr($content, 0, 300)
            );
        }

        return $normalized;
    }

    private static function buildPayload(string $provider, array $config, string $prompt): string
    {
        $systemMsg = '只输出严格 JSON。';
        $userMsg = $prompt;

        switch ($provider) {
            case 'openai':
            case 'azure':
            case 'custom':
                if (($config['api_style'] ?? 'chat_completions') === 'responses') {
                    /* OpenAI Responses 接口（/v1/responses）：input 字符串 + max_output_tokens */
                    return json_encode([
                        'model' => $config['model'],
                        'input' => $systemMsg . "\n\n" . $userMsg,
                        'max_output_tokens' => (int) $config['max_tokens'],
                        'temperature' => $config['temperature'],
                    ], JSON_UNESCAPED_UNICODE);
                }
                return json_encode([
                    'model' => $config['model'],
                    'temperature' => $config['temperature'],
                    'max_tokens' => $config['max_tokens'],
                    'messages' => [
                        ['role' => 'system', 'content' => $systemMsg],
                        ['role' => 'user', 'content' => $userMsg],
                    ],
                ], JSON_UNESCAPED_UNICODE);

            case 'claude':
                return json_encode([
                    'model' => $config['model'],
                    'max_tokens' => $config['max_tokens'],
                    'temperature' => $config['temperature'],
                    'system' => $systemMsg,
                    'messages' => [['role' => 'user', 'content' => $userMsg]],
                ], JSON_UNESCAPED_UNICODE);

            case 'gemini':
                return json_encode([
                    'contents' => [['parts' => [['text' => $systemMsg . "\n\n" . $userMsg]]]],
                    'generationConfig' => [
                        'temperature' => $config['temperature'],
                        'maxOutputTokens' => $config['max_tokens'],
                    ],
                ], JSON_UNESCAPED_UNICODE);

            default:
                throw new RuntimeException('不支持的提供商');
        }
    }

    private static function buildUrl(string $provider, array $config): string
    {
        $baseUrl = rtrim((string) ($config['api_url'] ?? ''), '/');
        $style = (string) ($config['api_style'] ?? 'chat_completions');

        switch ($provider) {
            case 'openai':
            case 'custom':
                if ($style === 'responses') {
                    /* 自由地址智能补全：/chat/completions → /responses；/v1 → /v1/responses；裸域名 → /v1/responses */
                    if (substr($baseUrl, -17) === '/chat/completions') {
                        return substr($baseUrl, 0, -17) . '/responses';
                    }
                    if (substr($baseUrl, -10) === '/responses') {
                        return $baseUrl;
                    }
                    if (substr($baseUrl, -3) === '/v1') {
                        return $baseUrl . '/responses';
                    }
                    return $baseUrl . '/v1/responses';
                }
                /* 自由地址智能补全：/v1 → /v1/chat/completions；裸域名 → /v1/chat/completions；完整地址原样 */
                if (substr($baseUrl, -17) === '/chat/completions') {
                    return $baseUrl;
                }
                if (substr($baseUrl, -10) === '/responses') {
                    return substr($baseUrl, 0, -10) . '/chat/completions';
                }
                if (substr($baseUrl, -3) === '/v1') {
                    return $baseUrl . '/chat/completions';
                }
                return $baseUrl . '/v1/chat/completions';

            case 'azure':
                $deployment = $config['provider_config']['deployment_name'] ?? '';
                $apiVersion = $config['provider_config']['api_version'] ?? '2024-02-15-preview';
                if ($style === 'responses') {
                    return "{$baseUrl}/openai/responses?api-version={$apiVersion}";
                }
                return "{$baseUrl}/openai/deployments/{$deployment}/chat/completions?api-version={$apiVersion}";

            case 'claude':
                return $baseUrl;

            case 'gemini':
                $model = $config['model'];
                $apiVersion = $config['provider_config']['api_version'] ?? 'v1';
                $key = (string) ($config['api_key'] ?? '');
                return "{$baseUrl}/{$apiVersion}/models/{$model}:generateContent?key={$key}";

            default:
                return $baseUrl;
        }
    }

    private static function buildHeaders(string $provider, array $config): array
    {
        $headers = ['Content-Type: application/json', 'Accept: application/json'];

        switch ($provider) {
            case 'openai':
            case 'custom':
                $headers[] = 'Authorization: Bearer ' . ($config['api_key'] ?? '');
                break;
            case 'azure':
                $headers[] = 'api-key: ' . ($config['api_key'] ?? '');
                break;
            case 'claude':
                $headers[] = 'x-api-key: ' . ($config['api_key'] ?? '');
                $headers[] = 'anthropic-version: 2023-06-01';
                break;
            case 'gemini':
                /* key 通过 URL 参数传递 */
                break;
        }

        return $headers;
    }

    private static function extractContent(string $provider, array $response, int $status, array $config = []): string
    {
        if ($status >= 400) {
            throw new RuntimeException($response['error']['message'] ?? $response['message'] ?? ('API 错误 HTTP ' . $status));
        }

        switch ($provider) {
            case 'openai':
            case 'azure':
            case 'custom':
                if (($config['api_style'] ?? 'chat_completions') === 'responses') {
                    return self::extractResponsesContent($response);
                }
                $choice = $response['choices'][0] ?? [];
                $message = is_array($choice['message'] ?? null) ? $choice['message'] : [];
                $content = $message['content'] ?? ($choice['text'] ?? '');
                /* 新版模型 / 中转站可能返回数组形式的内容块：[{"type":"text","text":"..."}] */
                if (is_array($content)) {
                    $parts = [];
                    foreach ($content as $part) {
                        if (is_string($part)) $parts[] = $part;
                        elseif (is_array($part) && isset($part['text'])) $parts[] = (string) $part['text'];
                    }
                    $content = implode("\n", $parts);
                }
                return (string) $content;

            case 'claude':
                if (is_array($response['content'] ?? null)) {
                    $parts = [];
                    foreach ($response['content'] as $block) {
                        if (is_array($block) && ($block['type'] ?? '') === 'text') {
                            $parts[] = (string) ($block['text'] ?? '');
                        }
                    }
                    if ($parts) return implode("\n", $parts);
                }
                return (string) ($response['content'][0]['text'] ?? '');

            case 'gemini':
                $candidate = $response['candidates'][0] ?? null;
                if (!$candidate) {
                    $reason = (string) ($response['promptFeedback']['blockReason'] ?? '');
                    if ($reason !== '') {
                        throw new RuntimeException('Gemini 未返回内容：被安全策略拦截（blockReason=' . $reason . '），请调整输入或换模型');
                    }
                    return '';
                }
                $text = '';
                foreach ((array) ($candidate['content']['parts'] ?? []) as $part) {
                    if (isset($part['text'])) $text .= (string) $part['text'];
                }
                return $text;

            default:
                return '';
        }
    }

    /**
     * 解析 OpenAI Responses 接口（/v1/responses）的返回：
     *   output[].type=message → content[].type=output_text → text
     * 兼容部分中转直接给出的 output_text 字段。
     */
    private static function extractResponsesContent(array $response): string
    {
        if (isset($response['output_text']) && is_string($response['output_text']) && trim($response['output_text']) !== '') {
            return $response['output_text'];
        }
        $parts = [];
        foreach ((array) ($response['output'] ?? []) as $item) {
            if (!is_array($item)) continue;
            $type = (string) ($item['type'] ?? '');
            if ($type === 'message') {
                foreach ((array) ($item['content'] ?? []) as $block) {
                    if (is_array($block) && ($block['type'] ?? '') === 'output_text' && isset($block['text'])) {
                        $parts[] = (string) $block['text'];
                    } elseif (is_string($block)) {
                        $parts[] = $block;
                    }
                }
            } elseif ($type === 'output_text' && isset($item['text'])) {
                $parts[] = (string) $item['text'];
            }
        }
        return implode("\n", $parts);
    }

    /**
     * 统一取「结束原因」：
     *   Chat Completions → choices[0].finish_reason（length=被截断）
     *   Responses          → status=incomplete + incomplete_details.reason（max_output_tokens=被截断）
     */
    private static function finishReason(string $provider, array $response, array $config): string
    {
        if (in_array($provider, ['openai', 'azure', 'custom'], true)
            && ($config['api_style'] ?? 'chat_completions') === 'responses') {
            $status = (string) ($response['status'] ?? '');
            $reason = (string) ($response['incomplete_details']['reason'] ?? '');
            if ($status === 'incomplete') {
                return $reason === 'max_output_tokens' ? 'length' : ($reason !== '' ? $reason : 'incomplete');
            }
            if ($status === 'completed') return 'stop';
            return '';
        }
        return (string) ($response['choices'][0]['finish_reason'] ?? ($response['stop_reason'] ?? ''));
    }

    /**
     * 正文为空时的兜底：思考型模型（deepseek-reasoner / o 系列 / 部分中转）
     * 会把内容放在 reasoning_content / reasoning / Responses 的 reasoning.summary 里，这里再抢救一次。
     */
    private static function rescueContent(string $provider, array $response, array $config = []): string
    {
        $candidates = [];
        if (in_array($provider, ['openai', 'azure', 'custom'], true)) {
            $choice = $response['choices'][0] ?? [];
            $message = is_array($choice['message'] ?? null) ? $choice['message'] : [];
            $candidates[] = $message['reasoning_content'] ?? '';
            $candidates[] = $message['reasoning'] ?? '';
            $candidates[] = $choice['text'] ?? '';
            if (($config['api_style'] ?? 'chat_completions') === 'responses') {
                $candidates[] = $response['output_text'] ?? '';
                foreach ((array) ($response['output'] ?? []) as $item) {
                    if (!is_array($item) || ($item['type'] ?? '') !== 'reasoning') continue;
                    foreach ((array) ($item['summary'] ?? []) as $sum) {
                        if (is_array($sum) && isset($sum['text'])) $candidates[] = (string) $sum['text'];
                    }
                }
            }
        } elseif ($provider === 'claude') {
            $candidates[] = $response['completion'] ?? '';
        }
        foreach ($candidates as $c) {
            if (is_string($c) && trim($c) !== '') return $c;
        }
        return '';
    }

    private static function getDefaultUrl(string $provider): string
    {
        return match ($provider) {
            'openai' => 'https://api.openai.com/v1/chat/completions',
            'azure' => 'https://YOUR_RESOURCE.openai.azure.com',
            'claude' => 'https://api.anthropic.com/v1/messages',
            'gemini' => 'https://generativelanguage.googleapis.com',
            default => '',
        };
    }
}
