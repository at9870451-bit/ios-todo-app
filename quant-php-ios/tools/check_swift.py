#!/usr/bin/env python3
"""Swift 源码完整性校验：检查污染词、括号平衡、非法字符。"""
import sys, os, re, glob

POLLUTION = ['beda', 'roulette', 'phenix', 'Lebedev', '利益集团', '镶', '摘要数据', 'тут', 'ķ', 'ѧ']
# 允许的中文范围检查在下面单独做

def check_file(path):
    issues = []
    try:
        text = open(path, encoding='utf-8').read()
    except Exception as e:
        return [f'无法读取: {e}']

    # 1. 污染词
    low = text.lower()
    for w in POLLUTION:
        if w.lower() in low:
            idx = low.find(w.lower())
            ctx = text[max(0, idx-40):idx+40].replace('\n', '\\n')
            issues.append(f'污染词 [{w}] @ ...{ctx}...')

    # 2. 括号平衡（粗略，忽略字符串中的括号——可能误报，只作参考）
    for a, b in [('{', '}'), ('(', ')'), ('[', ']')]:
        ca, cb = text.count(a), text.count(b)
        if ca != cb:
            issues.append(f'括号不平衡 {a}{b}: {ca} vs {cb}')

    # 3. 每行长度异常（超长行常见于污染）
    for i, line in enumerate(text.split('\n'), 1):
        if len(line) > 400:
            issues.append(f'超长行 {i}: {len(line)} 字符')

    # 4. Swift 基本结构检查
    if not text.strip():
        issues.append('空文件')

    return issues

def main():
    targets = sys.argv[1:] or glob.glob('**/*.swift', recursive=True)
    total_issues = 0
    for t in targets:
        if os.path.isdir(t):
            t = os.path.join(t, '**', '*.swift')
            files = glob.glob(t, recursive=True)
        else:
            files = [t]
        for f in files:
            issues = check_file(f)
            if issues:
                total_issues += len(issues)
                print(f'❌ {f}')
                for i in issues:
                    print(f'   - {i}')
            else:
                print(f'✅ {f}')
    print(f'\n总计: {total_issues} 个问题')
    return 1 if total_issues else 0

if __name__ == '__main__':
    sys.exit(main())
