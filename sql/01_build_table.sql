-- =====================================================================
-- 01 · 建表与数据导入（MySQL 8.0+）
-- 说明：导入 Notebook 01 清洗后的销售明细 sales_clean.csv。
-- 你的另一个项目（非遗工坊管理系统）用的是 MySQL 5.7+，本文件完全兼容。
-- =====================================================================

CREATE DATABASE IF NOT EXISTS retail_analysis DEFAULT CHARSET utf8mb4;
USE retail_analysis;

DROP TABLE IF EXISTS sales_clean;
CREATE TABLE sales_clean (
    id           BIGINT AUTO_INCREMENT PRIMARY KEY,
    invoice_no   VARCHAR(16)  NOT NULL COMMENT '发票号，C开头=取消单（清洗后销售表无C单）',
    stock_code   VARCHAR(32)  NOT NULL COMMENT '商品编码',
    description  VARCHAR(128)          COMMENT '商品描述',
    quantity     INT          NOT NULL COMMENT '数量（均为正）',
    invoice_date DATETIME     NOT NULL COMMENT '开票时间',
    unit_price   DECIMAL(10,2) NOT NULL COMMENT '单价（英镑）',
    customer_id  INT          NOT NULL COMMENT '客户编号（清洗后无缺失）',
    country      VARCHAR(64)           COMMENT '国家',
    revenue      DECIMAL(12,2)         COMMENT '收入 = quantity * unit_price',
    invoice_month VARCHAR(7)           COMMENT '账期 YYYY-MM',
    KEY idx_month (invoice_month),
    KEY idx_customer (customer_id),
    KEY idx_stock (stock_code)
) ENGINE=InnoDB;

-- Windows 下 LOAD DATA 需将 csv 放到 secure_file_priv 允许的目录，
-- 或在 my.ini 配置 secure_file_priv=''。路径按实际修改。
LOAD DATA LOCAL INFILE 'D:/develop/code/fenxi/data/cleaned/sales_clean.csv'
INTO TABLE sales_clean
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(invoice_no, stock_code, description, quantity, invoice_date, unit_price,
 customer_id, country, revenue, invoice_month)
SET id = NULL;

SELECT COUNT(*) AS 总行数, ROUND(SUM(revenue),2) AS 总GMV FROM sales_clean;
