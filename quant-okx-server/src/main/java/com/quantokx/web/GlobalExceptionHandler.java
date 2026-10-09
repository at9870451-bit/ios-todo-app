package com.quantokx.web;

import com.quantokx.config.SecretScrubber;
import com.quantokx.okx.OkxException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.NoHandlerFoundException;

/**
 * 全局异常处理：任何错误都以统一信封返回，msg 已脱敏、可直接展示。
 * 惯例：业务/参数错误 code=400；未预期错误 code=500；两者 HTTP 状态都保持 200，
 * 以便前端统一解析信封（401 由 AuthInterceptor 单独处理，是唯一的非 200 状态码）。
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private final SecretScrubber scrubber;

    public GlobalExceptionHandler(SecretScrubber scrubber) {
        this.scrubber = scrubber;
    }

    /** OKX / 交易业务异常（未配置密钥、网络错误、OKX 业务码等） */
    @ExceptionHandler(OkxException.class)
    public ApiResponse<Object> handleOkx(OkxException e) {
        String msg = scrubber.scrub(e.getMessage());
        log.warn("业务异常 [{}]：{}", e.code(), msg);
        return ApiResponse.error(400, msg == null ? "OKX 调用失败" : msg);
    }

    /** 配置校验等参数错误 */
    @ExceptionHandler(IllegalArgumentException.class)
    public ApiResponse<Object> handleIllegalArgument(IllegalArgumentException e) {
        String msg = scrubber.scrub(e.getMessage());
        return ApiResponse.error(400, msg == null ? "参数错误" : msg);
    }

    /** 请求体不是合法 JSON / 类型不匹配 */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ApiResponse<Object> handleUnreadable(HttpMessageNotReadableException e) {
        return ApiResponse.error(400, "请求体不是合法 JSON 或字段类型不匹配");
    }

    /** 缺少必填 query 参数 */
    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ApiResponse<Object> handleMissingParam(MissingServletRequestParameterException e) {
        return ApiResponse.error(400, "缺少参数：" + e.getParameterName());
    }

    /** query 参数类型不匹配（如 limit=abc） */
    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ApiResponse<Object> handleTypeMismatch(MethodArgumentTypeMismatchException e) {
        return ApiResponse.error(400, "参数类型错误：" + e.getName());
    }

    /** 路径不存在 */
    @ExceptionHandler(NoHandlerFoundException.class)
    public ApiResponse<Object> handleNotFound(NoHandlerFoundException e) {
        return ApiResponse.error(404, "接口不存在：" + e.getHttpMethod() + " " + e.getRequestURL());
    }

    /** 方法不支持 */
    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ApiResponse<Object> handleMethodNotSupported(HttpRequestMethodNotSupportedException e) {
        return ApiResponse.error(405, "请求方法不支持：" + e.getMethod());
    }

    /** 兜底 */
    @ExceptionHandler(Exception.class)
    public ApiResponse<Object> handleOther(Exception e) {
        String detail = scrubber.scrub(e.getMessage());
        log.error("未处理异常：{}", scrubber.scrub(e.toString()));
        return ApiResponse.error(500, "服务器内部错误：" + (detail == null ? e.getClass().getSimpleName() : detail));
    }
}
