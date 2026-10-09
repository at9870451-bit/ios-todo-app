package com.quantokx.okx;

/**
 * OKX 调用异常（也是本后端统一的业务异常）。
 * message 已经组织成可直接展示给用户的文案（且绝不包含任何密钥），内部 code 对应：
 * - OKX 业务错误码（字符串，如 "51000"）
 * - "no-credentials" / "network" / "decode" / "encode" / "param" / "bad-url" 等本地错误
 */
public class OkxException extends RuntimeException {

    private static final long serialVersionUID = 1L;

    private final String code;

    public OkxException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String code() {
        return code;
    }
}
