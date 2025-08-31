-- =========================
-- KPI MODELING BOOT
-- =========================
-- Run it into a big query dataset named n8ndataestproject

-- 1) DATASETS (SCHEMAS)
CREATE SCHEMA IF NOT EXISTS `n8ndatatestproject.mkt_bronze`;
CREATE SCHEMA IF NOT EXISTS `n8ndatatestproject.mkt_silver`;
CREATE SCHEMA IF NOT EXISTS `n8ndatatestproject.mkt_gold`;
CREATE SCHEMA IF NOT EXISTS `n8ndatatestproject.mkt_lib`;

-- 2) SILVER - TABLES
CREATE TABLE IF NOT EXISTS `n8ndatatestproject.mkt_silver.fact_mkt_daily` (
  date DATE,
  platform STRING,
  account STRING,
  campaign STRING,
  country STRING,
  device STRING,
  spend FLOAT64,
  clicks INT64,
  impressions INT64,
  conversions INT64,
  load_date TIMESTAMP,
  source_file_name STRING
)
PARTITION BY date
CLUSTER BY platform, country;

-- 3) GOLD - VIEWS
CREATE OR REPLACE VIEW `n8ndatatestproject.mkt_gold.v_mkt_totals_daily` AS
SELECT
  DATE(date) AS dt,
  SUM(spend) AS spend,
  SUM(CAST(conversions AS FLOAT64)) AS conversions,
  SUM(CAST(conversions AS FLOAT64)) * 100.0 AS revenue
FROM `n8ndatatestproject.mkt_silver.fact_mkt_daily`
GROUP BY dt;

-- 4) TABLE FUNCTION (LIB) - END_DATE INCLUSIVO
CREATE OR REPLACE TABLE FUNCTION `n8ndatatestproject.mkt_lib.fn_kpi_window`(
  start_date DATE,
  end_date   DATE
)
AS (
  WITH params AS (
    SELECT
      start_date AS sd,
      end_date   AS ed,
      DATE_DIFF(end_date, start_date, DAY) + 1 AS n_days 
  ),
  agg AS (
    SELECT
      (SELECT SUM(spend)
         FROM `n8ndatatestproject.mkt_gold.v_mkt_totals_daily` v
        WHERE v.dt BETWEEN sd AND ed) AS spend_c,
      (SELECT SUM(conversions)
         FROM `n8ndatatestproject.mkt_gold.v_mkt_totals_daily` v
        WHERE v.dt BETWEEN sd AND ed) AS conv_c,
      (SELECT SUM(spend)
         FROM `n8ndatatestproject.mkt_gold.v_mkt_totals_daily` v
        WHERE v.dt BETWEEN DATE_SUB(sd, INTERVAL n_days DAY) AND DATE_SUB(sd, INTERVAL 1 DAY)) AS spend_p,
      (SELECT SUM(conversions)
         FROM `n8ndatatestproject.mkt_gold.v_mkt_totals_daily` v
        WHERE v.dt BETWEEN DATE_SUB(sd, INTERVAL n_days DAY) AND DATE_SUB(sd, INTERVAL 1 DAY)) AS conv_p
    FROM params
  ),
  calc AS (
    SELECT
      SAFE_DIVIDE(spend_c, NULLIF(conv_c, 0)) AS cac_current_raw,
      SAFE_DIVIDE(spend_p, NULLIF(conv_p, 0)) AS cac_previous_raw,
      SAFE_DIVIDE(conv_c * 100.0, NULLIF(spend_c, 0)) AS roas_current_raw,   -- revenue = conv * 100
      SAFE_DIVIDE(conv_p * 100.0, NULLIF(spend_p, 0)) AS roas_previous_raw
    FROM agg
  )
  SELECT
    ROUND(cac_current_raw,  6) AS cac_current,
    ROUND(cac_previous_raw, 6) AS cac_previous,
    ROUND(SAFE_DIVIDE(cac_current_raw - cac_previous_raw, cac_previous_raw), 6) AS cac_delta_pct,
    ROUND(roas_current_raw,  6) AS roas_current,
    ROUND(roas_previous_raw, 6) AS roas_previous,
    ROUND(SAFE_DIVIDE(roas_current_raw - roas_previous_raw, roas_previous_raw), 6) AS roas_delta_pct
  FROM calc
);

-- SMOKE TESTS
-- (a) check view
----SELECT * FROM `n8ndatatestproject.mkt_gold.v_mkt_totals_daily` LIMIT 5;

-- (b) check function
----SELECT * FROM `n8ndatatestproject.mkt_lib.fn_kpi_window`(DATE '2025-07-30', DATE '2025-08-29');
