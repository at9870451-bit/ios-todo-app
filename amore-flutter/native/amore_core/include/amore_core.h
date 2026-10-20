#ifndef AMORE_CORE_H
#define AMORE_CORE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Dart → Rust：统一 JSON 总线。返回 heap 字符串（UTF-8 JSON 信封），用 amore_free 释放。 */
extern char *amore_call(const char *method, const char *payload);

/* 释放 amore_call 返回的内存 */
extern void amore_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* AMORE_CORE_H */
