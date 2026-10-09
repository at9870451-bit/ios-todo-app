package com.quantokx.web;

/**
 * 统一响应信封（契约：所有接口都是 {"code":0,"msg":"ok","data":...}）。
 * code == 0 表示成功；非 0 时 msg 直接给用户看。
 */
public record ApiResponse<T>(int code, String msg, T data) {

    public static <T> ApiResponse<T> ok(T data) {
        return new ApiResponse<>(0, "ok", data);
    }

    public static <T> ApiResponse<T> error(int code, String msg) {
        return new ApiResponse<>(code, msg, null);
    }
}
