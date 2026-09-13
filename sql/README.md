# SQL 版分析 —— 同一套业务问题，两种工具实现

> **为什么这个目录很重要**：数据分析岗位 JD 里 SQL 是硬性要求。本项目刻意把 Notebook 02 的每个业务问题都用 SQL 重写了一遍，面试时可以证明：**同一业务问题，pandas 能做，SQL 也能做，且知道各自的适用场景**。

## 文件说明

| 文件 | 内容 |
| --- | --- |
| `01_build_table.sql` | 建库建表 + `LOAD DATA` 导入清洗后的 `sales_clean.csv`（MySQL 8.0+，兼容 5.7 语法部分已注明） |
| `02_analysis_queries.sql` | Q1~Q7 全部业务问题的 SQL 实现（窗口函数：`NTILE` 打分、累计和求帕累托） |
| `verify_sqlite.py` | 用 SQLite（免安装）自动跑通核心查询，并与 pandas 结果比对 —— 保证 SQL 版本的正确性有据可查 |

## 快速开始

**方式 A：MySQL（推荐，与你的管理系统项目同一套技术栈）**

```bash
mysql -u root -p < 01_build_table.sql   # 先建表导数（注意改 LOAD DATA 的路径）
mysql -u root -p < 02_analysis_queries.sql
```

**方式 B：零安装验证（SQLite）**

```bash
python verify_sqlite.py
```

脚本会：① 把 `sales_clean.csv` 灌入内存 SQLite；② 跑 Q1 月度 GMV、Q2 RFM 分层汇总、Q3 次月留存三段核心查询；③ 与 pandas 计算结果逐行比对，输出 `PASS/FAIL`。

## SQL vs pandas 的取舍（面试口头禅）

1. **取数、聚合、排名、分箱**：SQL 一把梭，数据量大时是唯一解（计算下推到数据库）；
2. **复杂分层策略、可视化、快速试错**：pandas 更灵活；
3. **生产实践**：SQL 沉淀为数据管道/报表层，pandas 做探索性分析，两者是上下游关系而不是二选一。
