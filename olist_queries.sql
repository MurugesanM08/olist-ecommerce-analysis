-- ============================================================
-- Olist E-Commerce Analysis
-- Tool: SQLite / DB Browser
-- Description: Customer revenue intelligence queries
-- covering monthly trends, RFM segmentation, cohort
-- retention, category performance, and AOV by state.
-- ============================================================


-- ============================================================
-- Query 1: Monthly Revenue & Profit Trend
-- Business question: How has revenue grown over time?
-- ============================================================

SELECT 
    strftime('%Y-%m', o.order_purchase_timestamp)        AS year_month,
    date(strftime('%Y-%m', o.order_purchase_timestamp) 
         || '-01')                                        AS order_date,
    COUNT(DISTINCT o.order_id)                            AS total_orders,
    ROUND(SUM(i.price + i.freight_value), 2)              AS total_revenue,
    ROUND(SUM(i.price * 0.4), 2)                          AS total_profit,
    ROUND(AVG(i.price + i.freight_value), 2)              AS avg_order_value
FROM orders o
JOIN items i ON o.order_id = i.order_id
WHERE o.order_status IN ('delivered', 'shipped')
GROUP BY year_month
ORDER BY year_month;


-- ============================================================
-- Query 2: RFM Segmentation
-- Business question: Which customers are most valuable,
-- at risk, or disengaged?
-- Note: Reference date set to 2018-09-01 (dataset end date)
-- ============================================================

WITH rfm_base AS (
    SELECT 
        c.customer_unique_id,
        CAST(
            julianday('2018-09-01') - 
            julianday(MAX(o.order_purchase_timestamp))
        AS INTEGER)                                AS recency,
        COUNT(DISTINCT o.order_id)                 AS frequency,
        ROUND(SUM(i.price + i.freight_value), 2)   AS monetary
    FROM orders o
    JOIN items i     ON o.order_id = i.order_id
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status IN ('delivered', 'shipped')
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY recency ASC)    AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)  AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)   AS m_score
    FROM rfm_base
),
rfm_segmented AS (
    SELECT *,
        CASE 
            WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2 THEN 'Promising'
            WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
            WHEN f_score = 1                   THEN 'One-Time Buyers'
            ELSE 'Needs Attention'
        END AS segment
    FROM rfm_scored
)
SELECT 
    segment,
    COUNT(*)                     AS customer_count,
    ROUND(AVG(recency), 1)       AS avg_recency_days,
    ROUND(AVG(frequency), 2)     AS avg_frequency,
    ROUND(AVG(monetary), 2)      AS avg_monetary,
    ROUND(SUM(monetary), 2)      AS total_revenue
FROM rfm_segmented
GROUP BY segment
ORDER BY total_revenue DESC;


-- ============================================================
-- Query 3: Cohort Retention Analysis
-- Business question: What % of customers return after
-- their first purchase month?
-- ============================================================

WITH first_purchase AS (
    SELECT 
        c.customer_unique_id,
        strftime('%Y-%m', MIN(o.order_purchase_timestamp)) AS cohort_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status IN ('delivered', 'shipped')
    GROUP BY c.customer_unique_id
),
order_months AS (
    SELECT 
        c.customer_unique_id,
        strftime('%Y-%m', o.order_purchase_timestamp) AS order_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status IN ('delivered', 'shipped')
),
cohort_data AS (
    SELECT 
        f.cohort_month,
        o.order_month,
        COUNT(DISTINCT f.customer_unique_id) AS customers
    FROM first_purchase f
    JOIN order_months o ON f.customer_unique_id = o.customer_unique_id
    GROUP BY f.cohort_month, o.order_month
)
SELECT 
    cohort_month,
    order_month,
    customers,
    ROUND(customers * 100.0 / 
        FIRST_VALUE(customers) OVER (
            PARTITION BY cohort_month 
            ORDER BY order_month
        ), 2) AS retention_pct
FROM cohort_data
ORDER BY cohort_month, order_month;


-- ============================================================
-- Query 4: Top 10 Product Categories by Revenue
-- Business question: Which categories drive the most
-- revenue and profit?
-- ============================================================

SELECT 
    p.product_category_name        AS category,
    COUNT(DISTINCT o.order_id)     AS total_orders,
    ROUND(SUM(i.price), 2)         AS total_price,
    ROUND(SUM(i.price 
          + i.freight_value), 2)   AS total_revenue,
    ROUND(AVG(i.price), 2)         AS avg_price,
    ROUND(SUM(i.price * 0.4), 2)   AS total_profit,
    ROUND(SUM(i.price * 0.4) 
          / SUM(i.price) * 100, 2) AS margin_pct
FROM orders o
JOIN items i    ON o.order_id = i.order_id
JOIN products p ON i.product_id = p.product_id
WHERE o.order_status IN ('delivered', 'shipped')
    AND p.product_category_name IS NOT NULL
GROUP BY p.product_category_name
ORDER BY total_revenue DESC
LIMIT 10;


-- ============================================================
-- Query 5: Revenue & Average Order Value by State
-- Business question: Which states generate the most revenue
-- and which have the highest spending customers?
-- ============================================================

SELECT 
    c.customer_state                           AS state,
    COUNT(DISTINCT o.order_id)                 AS total_orders,
    ROUND(SUM(i.price + i.freight_value), 2)   AS total_revenue,
    ROUND(AVG(i.price + i.freight_value), 2)   AS avg_order_value
FROM orders o
JOIN items i     ON o.order_id = i.order_id
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status IN ('delivered', 'shipped')
GROUP BY c.customer_state
ORDER BY total_revenue DESC
LIMIT 10;
