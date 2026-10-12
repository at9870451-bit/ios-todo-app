<?php
namespace app\service;

use think\Response;

/** 统一 API 响应，避免控制器重复拼接 JSON。 */
final class ApiResponse
{
    public static function success(mixed $data = [], string $message = 'success', int $status = 200): Response
    {
        return Response::create([
            'code' => 0,
            'message' => $message,
            'data' => $data,
        ], 'json', $status);
    }

    public static function error(string $message, string|int $code = 400, int $status = 400, array $data = []): Response
    {
        return Response::create([
            'code' => $code,
            'message' => $message,
            /* 空数据用 null（对象）而非 []（数组），避免客户端把业务报错解码成"响应格式异常" */
            'data' => $data === [] ? null : $data,
        ], 'json', $status);
    }
}
