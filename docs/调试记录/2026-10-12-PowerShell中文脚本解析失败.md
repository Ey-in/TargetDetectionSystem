# 调试记录：PowerShell 脚本含中文时报语法错误，但报错行本身没有语法问题

| 项 | 内容 |
|---|---|
| 日期 | 2026-10-12 |
| 记录人 | 仓库脚手架搭建阶段 |
| 关联 Issue | —（脚手架自测时发现，早于 Issue 流程启用） |
| 关联 PR | `chore/repo-bootstrap` |
| 严重程度 | P0（四个脚本全部无法运行） |
| 涉及模块 | `scripts/` |

---

## 1. 现象

运行 `.\scripts\worklog.ps1`，抛出一连串语法错误：

```
At F:\se\TargetDetectionSystem\scripts\worklog.ps1:68 char:27
+     if ($line.StartsWith("@@@")) {
+                           ~
Unrecognized token in source text.
+                               ~
No characters are allowed after a here-string header but before the end of the line.
```

报错行 `$line.StartsWith("@@@")` 本身语法完全正常。而且报错不止一处，
从第 68 行一路报到 220 行，**整个文件像是整体坏掉了**。

## 2. 复现步骤

1. `Set-Location F:\se\TargetDetectionSystem`
2. `.\scripts\worklog.ps1`
3. 必然复现

## 3. 定位过程 ⭐

| 步骤 | 我的假设 | 验证方式 | 结果 | 结论 |
|---|---|---|---|---|
| 1 | 第 68 行代码写错了 | 单独看这一行：`if ($line.StartsWith("@@@")) {` | 语法正确，`@@@` 作为普通字符串没任何问题 | 排除"这一行有错" |
| 2 | 报错行号可能具有误导性，是**前面**某处破坏了语法结构 | 从文件开头逐段检查 | 未发现括号或引号不配对 | 排除普通的括号/引号不匹配 |
| 3 | ⭐ 关键线索：**报错信息里的中文是乱码** —— 模板里的"本项目采用 Squash 合并…"显示成了 `鏈」鐩噰鐢?Squash 鍚堝苟锛宮ain` | 观察报错文本本身 | 中文全部乱码 | 说明 PowerShell **读取文件时的解码方式**不对，而不是代码逻辑问题 |
| 4 | 文件编码导致解码错误 | 检查文件头字节，确认是 UTF-8 **无 BOM** | 无 BOM | 与 PS 5.1 的默认行为吻合 |
| 5 | 加 BOM 后是否恢复 | 用 `UTF8Encoding($true)` 重写文件后重跑 | 立即正常运行 | 假设成立 |

**走过的弯路**：前两步都在代码逻辑里找问题，浪费了时间。真正的转折点是**注意到报错文本
自身是乱码** —— 报错信息都乱码了，问题必然在"文件怎么被读进来"，而不在"代码写了什么"。

> 教训：报错信息里的乱码本身就是线索，不要因为"看不懂"就跳过它。

## 4. 根因

**PowerShell 5.1 对不带 BOM 的 `.ps1` 文件，按系统 ANSI 代码页（中文 Windows 下为 GBK）
解码，而不是按 UTF-8 解码。**

由此产生的连锁反应解释了"为什么报错行号完全对不上"：

1. 文件是 UTF-8 无 BOM，其中的中文注释与字符串被用 GBK 强行解码；
2. 一个中文字符的 3 个 UTF-8 字节被 GBK 拆成 1.5 个字符，字节序列整体错位；
3. 错位后的字节流中**恰好凑出了 `@"` 这两个字符**；
4. PowerShell 把 `@"` 识别为 **here-string 的起始标记**；
5. 于是后面的 `"@@@"` 被当成 here-string 的头部，解析器报出
   "No characters are allowed after a here-string header"；
6. 从这里开始引号配对关系全乱，剩余 150 行被连锁报错。

**所以报错行（68 行）与真正的原因（文件编码）在完全不同的层面。**
这也是为什么单纯盯着第 68 行永远查不出来。

## 5. 修复方案

把四个 `.ps1` 脚本统一改写为 **UTF-8 with BOM**：

```powershell
$utf8bom = New-Object System.Text.UTF8Encoding($true)
foreach ($f in $files) {
    $content = Get-Content -Path $f -Raw -Encoding UTF8
    [System.IO.File]::WriteAllText($f, $content, $utf8bom)
}
```

**备选方案及未采用的原因**：

| 方案 | 未采用原因 |
|---|---|
| 把脚本输出改成纯 ASCII（去掉所有中文） | 全组是中文团队，报错信息必须中文才有用；且会掩盖真正的问题 |
| 要求所有人改用 PowerShell 7 | PS7 默认按 UTF-8 读取，确实能解决，但组员机器上预装的是 5.1，强推会增加环境差异风险 |
| 每个文件开头写 `# -*- coding: utf-8 -*-` | Python 的写法，PowerShell 不认，无效 |
| **改为 UTF-8 with BOM** ✅ | 一行代码解决，对 PS 5.1 与 PS 7 都兼容，无额外要求 |

## 6. 验证

- [x] 重跑 `.\scripts\worklog.ps1`，正常输出统计表格，中文显示正确
- [x] 逐个确认四个脚本均已带 BOM
- [x] 确认 `.githooks/commit-msg` **不需要**加 BOM —— 它是 shell 脚本，
      BOM 会破坏 `#!/bin/sh` 这一行导致 shebang 失效（已实测该钩子工作正常）
- [x] 把该坑写进 `CONTRIBUTING.md` 第八节「常见坑」

## 7. 经验

**任何含中文的 `.ps1` 文件，必须保存为 UTF-8 with BOM。**

已加入 `CONTRIBUTING.md` 的常见坑清单。此外记住那条更通用的经验：

> 当报错信息本身出现乱码时，先怀疑编码，不要怀疑逻辑。
