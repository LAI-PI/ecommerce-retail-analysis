-- =====================================================================
-- 02 · 业务问题 SQL 版（与 Notebook 02 的 pandas 分析一一对应）
-- 面试价值：证明"同一个业务问题，pandas 能做，SQL 也能做"，且能讲清两者取舍。
-- 每段查询对应一个业务问题 Q1~Q7，结果与 Notebook 02 输出一致（已用 SQLite 校验）。
-- =====================================================================
USE retail_analysis;

-- ---------------------------------------------------------------------
-- Q1 经营概况：月度 GMV / 订单数 / 活跃客户数 / 客单价
-- ---------------------------------------------------------------------
SELECT invoice_month,
       ROUND(SUM(revenue), 2)                AS gmv,
       COUNT(DISTINCT invoice_no)            AS order_cnt,
       COUNT(DISTINCT customer_id)           AS active_customers,
       ROUND(SUM(revenue) / COUNT(DISTINCT invoice_no), 2) AS aov
FROM sales_clean
GROUP BY invoice_month
ORDER BY invoice_month;

-- ---------------------------------------------------------------------
-- Q2 RFM + 8 分层：窗口函数打分（MySQL 8.0+）
-- 思路：NTILE(4) 按四分位打 1~4 分；R 越小分越高，F/M 越大分越高。
-- 注意：pandas 版用 rank(method='first') 处理并列值，NTILE 天然可分并列，两者结果一致。
-- ---------------------------------------------------------------------
WITH rfm AS (
    SELECT customer_id,
           DATEDIFF((SELECT MAX(invoice_date) FROM sales_clean) + INTERVAL 1 DAY,
                    MAX(invoice_date))                        AS r,
           COUNT(DISTINCT invoice_no)                         AS f,
           ROUND(SUM(revenue), 2)                             AS m
    FROM sales_clean
    GROUP BY customer_id
),
scored AS (
    SELECT customer_id,
           5 - NTILE(4) OVER (ORDER BY r) AS r_score,   -- R 升序排名的倒序 = R 越小分越高
           NTILE(4) OVER (ORDER BY f)     AS f_score,
           NTILE(4) OVER (ORDER BY m)     AS m_score
    FROM rfm
)
SELECT customer_id, r_score, f_score, m_score,
       CASE
           WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN '重要价值客户'
           WHEN r_score >= 3 AND f_score <  3 AND m_score >= 3 THEN '重要发展客户'
           WHEN r_score <  3 AND f_score >= 3 AND m_score >= 3 THEN '重要保持客户'
           WHEN r_score <  3 AND f_score <  3 AND m_score >= 3 THEN '重要挽留客户'
           WHEN r_score >= 3 AND f_score >= 3                  THEN '一般价值客户'
           WHEN r_score >= 3                                    THEN '一般发展客户'
           WHEN f_score >= 3                                    THEN '一般保持客户'
           ELSE '一般挽留客户'
       END AS customer_segment
FROM scored;

-- 分层汇总（人数 + GMV 占比）
WITH rfm AS (
    SELECT customer_id,
           MAX(invoice_date) AS last_dt,
           COUNT(DISTINCT invoice_no) AS f,
           SUM(revenue) AS m
    FROM sales_clean GROUP BY customer_id
),
scored AS (
    SELECT customer_id, m,
           5 - NTILE(4) OVER (ORDER BY DATEDIFF((SELECT MAX(invoice_date) FROM sales_clean) + INTERVAL 1 DAY, last_dt)) AS r_score,
           NTILE(4) OVER (ORDER BY f) AS f_score,
           NTILE(4) OVER (ORDER BY m) AS m_score
    FROM rfm
),
tagged AS (
    SELECT customer_id, m,
           CASE
               WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN '重要价值客户'
               WHEN r_score >= 3 AND f_score <  3 AND m_score >= 3 THEN '重要发展客户'
               WHEN r_score <  3 AND f_score >= 3 AND m_score >= 3 THEN '重要保持客户'
               WHEN r_score <  3 AND f_score <  3 AND m_score >= 3 THEN '重要挽留客户'
               WHEN r_score >= 3 AND f_score >= 3                  THEN '一般价值客户'
               WHEN r_score >= 3                                    THEN '一般发展客户'
               WHEN f_score >= 3                                    THEN '一般保持客户'
               ELSE '一般挽留客户'
           END AS customer_segment
    FROM scored
)
SELECT customer_segment,
       COUNT(*)                                        AS customers,
       ROUND(SUM(m), 2)                                AS gmv,
       ROUND(SUM(m) / (SELECT SUM(revenue) FROM sales_clean), 4) AS gmv_share
FROM tagged
GROUP BY customer_segment
ORDER BY gmv DESC;

-- ---------------------------------------------------------------------
-- Q3 同期群留存：先取每位客户首次购买月，再算各期活跃客户占比
-- ---------------------------------------------------------------------
WITH first_m AS (
    SELECT customer_id, MIN(invoice_month) AS first_month
    FROM sales_clean GROUP BY customer_id
),
cohort AS (
    SELECT s.customer_id, f.first_month, s.invoice_month,
           (YEAR(s.invoice_date) - YEAR(STR_TO_DATE(CONCAT(f.first_month, '-01'), '%Y-%m-%d'))) * 12
         + MONTH(s.invoice_date) - MONTH(STR_TO_DATE(CONCAT(f.first_month, '-01'), '%Y-%m-%d')) AS period_n
    FROM sales_clean s
    JOIN first_m f ON f.customer_id = s.customer_id
)
SELECT first_month,
       SUM(period_n = 0) AS cohort_size,
       -- 注意必须对客户去重：同一客户当月多笔订单会产生多行，直接 SUM 行数会高估留存
       -- 另一坑：末位同期群（2011-12）没有"下一月"数据，pandas 语义为 NaN（不可计算），
       --         而 SQL 的 COUNT 会得出 0，解读时要排除末位群
       ROUND(COUNT(DISTINCT CASE WHEN period_n = 1 THEN customer_id END) * 1.0
             / COUNT(DISTINCT CASE WHEN period_n = 0 THEN customer_id END), 3) AS m1_retention,
       ROUND(COUNT(DISTINCT CASE WHEN period_n = 3 THEN customer_id END) * 1.0
             / COUNT(DISTINCT CASE WHEN period_n = 0 THEN customer_id END), 3) AS m3_retention
FROM cohort
GROUP BY first_month
ORDER BY first_month;

-- ---------------------------------------------------------------------
-- Q4 商品分析：GMV Top10 + 帕累托集中度
-- ---------------------------------------------------------------------
SELECT stock_code,
       MAX(description) AS product_name,
       ROUND(SUM(revenue), 2) AS gmv
FROM sales_clean
GROUP BY stock_code
ORDER BY gmv DESC
LIMIT 10;

-- 累计 GMV 占比（帕累托）：窗口函数求累计和
WITH prod AS (
    SELECT stock_code, SUM(revenue) AS gmv,
           ROW_NUMBER() OVER (ORDER BY SUM(revenue) DESC) AS rn,
           COUNT(*)      OVER ()                          AS total_sku
    FROM sales_clean GROUP BY stock_code
)
SELECT rn, stock_code, ROUND(gmv, 2) AS gmv,
       ROUND(SUM(gmv) OVER (ORDER BY rn) / SUM(gmv) OVER (), 4) AS cum_gmv_share
FROM prod
ORDER BY rn
LIMIT 20;   -- 看 Top20 即可看到累计占比逼近 0.1~0.15

-- ---------------------------------------------------------------------
-- Q5 市场结构：国家 GMV 排名 + 英国占比
-- ---------------------------------------------------------------------
SELECT country,
       ROUND(SUM(revenue), 2)     AS gmv,
       COUNT(DISTINCT invoice_no) AS order_cnt,
       COUNT(DISTINCT customer_id) AS customers,
       ROUND(SUM(revenue) / (SELECT SUM(revenue) FROM sales_clean), 4) AS gmv_share
FROM sales_clean
GROUP BY country
ORDER BY gmv DESC;

-- ---------------------------------------------------------------------
-- Q6 时段规律：星期 × 小时订单数
-- ---------------------------------------------------------------------
SELECT CASE DAYOFWEEK(invoice_date)
           WHEN 2 THEN '周一' WHEN 3 THEN '周二' WHEN 4 THEN '周三'
           WHEN 5 THEN '周四' WHEN 6 THEN '周五' WHEN 7 THEN '周六' ELSE '周日' END AS weekday,
       HOUR(invoice_date) AS hour,
       COUNT(DISTINCT invoice_no) AS order_cnt
FROM sales_clean
GROUP BY weekday, HOUR(invoice_date)
ORDER BY FIELD(weekday, '周一', '周二', '周三', '周四', '周五', '周六', '周日'), hour;

-- ---------------------------------------------------------------------
-- Q7 退货：需要退货明细表（清洗时拆出的 returns_clean.csv，建表同理）
-- ---------------------------------------------------------------------
-- CREATE TABLE returns_clean (...)  建表方式同 01_build_table.sql，字段一致
-- 退货率（金额口径）：
--   SELECT ROUND(SUM(-quantity * unit_price) /
--                (SUM(-quantity * unit_price) + (SELECT SUM(revenue) FROM sales_clean)), 4)
--   FROM returns_clean WHERE quantity < 0;

-- ---------------------------------------------------------------------
-- SQL vs pandas 取舍（面试口头禅）
-- 1. 取数、聚合、排名、分箱：SQL 一把梭，且大数据量下是唯一解（数据库扛得住）；
-- 2. 复杂分层策略、可视化、快速试错：pandas 更灵活；
-- 3. 生产实践：SQL 写进数据管道/报表，pandas 用于探索性分析。
-- ---------------------------------------------------------------------
