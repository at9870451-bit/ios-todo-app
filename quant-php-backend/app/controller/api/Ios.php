<?php
declare(strict_types=1);
namespace app\controller\api;

use app\controller\BaseController;
use app\model\User;
use app\service\AdminService;
use app\service\MembershipService;
use app\service\SafeLogger;
use Throwable;
use think\facade\Cache;
use think\facade\Session;

/**
 * iOS 客户端 JSON 接口（与 Web 共用同一会话）。
 * 纯增量文件：不影响任何现有 Web / API 行为。
 *
 *   POST /api/ios/login     登录（JSON 入参）
 *   POST /api/ios/register  注册（JSON 入参）
 *   POST /api/ios/logout    退出（需登录）
 *   GET  /api/ios/me        当前用户 + 会员状态 + CSRF token（需登录）
 *   GET  /api/ios/ping      连通性自检（免登录）
 */
class Ios extends BaseController
{
    /** 登录：成功返回用户信息 + CSRF token，会话与 Web 共用 */
    public function login()
    {
        $input = $this->payload();
        $username = trim((string) ($input['username'] ?? ''));
        $password = (string) ($input['password'] ?? '');
        if ($username === '' || $password === '') {
            return $this->fail('请输入用户名和密码', 'INVALID_PARAM', 422);
        }

        $throttleKey = 'login_fail:' . sha1((string) $this->request->ip());
        $fails = $this->cacheGet($throttleKey);
        if ($fails >= 10) {
            return $this->fail('登录失败次数过多，请 15 分钟后重试', 'TOO_MANY_ATTEMPTS', 429);
        }

        try {
            $user = User::where('username', $username)->where('status', 1)->find();
        } catch (Throwable $e) {
            SafeLogger::error('iOS 登录数据库查询失败', ['message' => $e->getMessage()]);
            return $this->fail('数据库连接异常，请检查服务端', 'DB_ERROR', 500);
        }

        if (!$user || !password_verify($password, (string) $user->password_hash)) {
            $this->cacheSet($throttleKey, $fails + 1, 900);
            SafeLogger::warning('iOS 登录失败', ['username' => $username, 'ip' => $this->request->ip()]);
            return $this->fail('用户名或密码错误', 'AUTH_FAILED', 401);
        }

        $this->cacheDelete($throttleKey);
        Session::set('user_id', (int) $user->id);
        $user->last_login_at = date('Y-m-d H:i:s');
        $user->last_login_ip = $this->request->ip();
        $user->save();
        SafeLogger::info('iOS 用户登录', ['user_id' => $user->id]);

        return $this->ok($this->sessionPayload($user), '登录成功');
    }

    /** 注册：成功后直接登录（与 Web 注册规则一致） */
    public function register()
    {
        $site = AdminService::siteConfig();
        if (empty($site['register_enabled'])) {
            return $this->fail('当前未开放注册，请联系管理员开通账号', 'REGISTER_CLOSED', 422);
        }

        $input = $this->payload();
        $username = trim((string) ($input['username'] ?? ''));
        $email = trim((string) ($input['email'] ?? ''));
        $password = (string) ($input['password'] ?? '');
        $confirm = (string) ($input['password_confirmation'] ?? $password);

        $throttleKey = 'register:' . sha1((string) $this->request->ip());
        $count = $this->cacheGet($throttleKey);
        if ($count >= 5) {
            return $this->fail('注册过于频繁，请 15 分钟后再试', 'TOO_MANY_ATTEMPTS', 429);
        }

        try {
            if (!preg_match('/^[A-Za-z0-9_@.-]{3,32}$/', $username)) {
                throw new \RuntimeException('用户名需为 3~32 位字母、数字、下划线、点、短横线或 @');
            }
            if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
                throw new \RuntimeException('邮箱格式无效');
            }
            if (!empty($site['register_need_email']) && $email === '') {
                throw new \RuntimeException('请填写邮箱');
            }
            if (strlen($password) < 8) throw new \RuntimeException('密码至少 8 位');
            if ($password !== $confirm) throw new \RuntimeException('两次输入的密码不一致');
            if (User::where('username', $username)->find()) throw new \RuntimeException('用户名已被注册');
            if ($email !== '' && User::where('email', $email)->find()) throw new \RuntimeException('邮箱已被注册');

            $user = new User();
            $user->username = $username;
            $user->nickname = $username;
            $user->email = $email !== '' ? $email : null;
            $user->password_hash = password_hash($password, PASSWORD_DEFAULT);
            $user->role = 'user';
            $user->membership_level = 'free';
            $user->status = 1;
            $user->register_ip = (string) $this->request->ip();
            $user->save();
        } catch (\RuntimeException $e) {
            return $this->fail($e->getMessage(), 'REGISTER_FAILED', 422);
        } catch (Throwable $e) {
            SafeLogger::error('iOS 注册失败', ['message' => $e->getMessage()]);
            return $this->fail('注册失败，请稍后再试或联系管理员', 'REGISTER_FAILED', 500);
        }

        $this->cacheSet($throttleKey, $count + 1, 900);
        SafeLogger::info('iOS 用户注册', ['user_id' => $user->id, 'username' => $username, 'ip' => $this->request->ip()]);

        Session::set('user_id', (int) $user->id);
        $user->last_login_at = date('Y-m-d H:i:s');
        $user->last_login_ip = $this->request->ip();
        $user->save();

        return $this->ok($this->sessionPayload($user), '注册成功');
    }

    /** 退出登录 */
    public function logout()
    {
        SafeLogger::info('iOS 用户退出', ['user_id' => Session::get('user_id')]);
        Session::clear();
        return $this->ok([], '已退出登录');
    }

    /** 当前登录用户 + 会员徽章 + CSRF token */
    public function me()
    {
        $user = $this->currentUser();
        if (!$user) {
            return $this->fail('未登录或会话已过期', 'UNAUTHORIZED', 401);
        }
        return $this->ok($this->sessionPayload($user));
    }

    /** 连通性自检（免登录）：同时下发 CSRF token，供后续写请求使用 */
    public function ping()
    {
        if (!Session::has('_csrf_token')) {
            Session::set('_csrf_token', bin2hex(random_bytes(32)));
        }
        return $this->ok([
            'app' => 'QuantOKX',
            'version' => 'v3.7',
            'php' => PHP_VERSION,
            'time' => date('c'),
            'host' => $this->request->host(),
            'csrf_token' => (string) Session::get('_csrf_token'),
        ]);
    }

    /** 会话载荷：用户信息 + CSRF token + 会员徽章 */
    private function sessionPayload(User $user): array
    {
        if (!Session::has('_csrf_token')) {
            Session::set('_csrf_token', bin2hex(random_bytes(32)));
        }
        return [
            'user' => [
                'id' => (int) $user->id,
                'username' => (string) $user->username,
                'nickname' => (string) $user->nickname,
                'email' => $user->email,
                'role' => (string) $user->role,
                'membership_level' => (string) $user->membership_level,
                'live_trading_enabled' => (bool) $user->live_trading_enabled,
            ],
            'csrf_token' => (string) Session::get('_csrf_token'),
            'badge' => MembershipService::badge($user),
        ];
    }

    private function cacheGet(string $key): int
    {
        try { return (int) Cache::get($key, 0); }
        catch (Throwable $e) { SafeLogger::warning('iOS 限流缓存不可用', ['message' => $e->getMessage()]); return 0; }
    }

    private function cacheSet(string $key, int $value, int $ttl): void
    {
        try { Cache::set($key, $value, $ttl); }
        catch (Throwable $e) { SafeLogger::warning('iOS 限流写入失败', ['message' => $e->getMessage()]); }
    }

    private function cacheDelete(string $key): void
    {
        try { Cache::delete($key); }
        catch (Throwable $e) { SafeLogger::warning('iOS 限流清理失败', ['message' => $e->getMessage()]); }
    }
}
