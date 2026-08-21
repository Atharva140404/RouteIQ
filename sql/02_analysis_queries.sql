-- =============================================================
--  ADDRESS ACCURACY & DELIVERY INSIGHTS
--  02_analysis_queries.sql  –  30+ Interview-Level SQL Queries
-- =============================================================


-- ─────────────────────────────────────────────────────────────
-- Q-01  OVERALL KPI SUMMARY
--       Aggregates core business metrics in one pass
-- ─────────────────────────────────────────────────────────────
SELECT
    COUNT(*)                                                                      AS total_records,
    SUM(CASE WHEN correction_required  THEN 1 ELSE 0 END)                        AS total_corrections,
    ROUND(100.0 * SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                          AS correction_rate_pct,
    SUM(CASE WHEN pincode_mismatch     THEN 1 ELSE 0 END)                        AS pincode_mismatches,
    ROUND(100.0 * SUM(CASE WHEN pincode_mismatch THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                          AS pincode_mismatch_rate_pct,
    ROUND(AVG(address_accuracy_score), 2)                                         AS avg_accuracy_score,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                          AS delivery_success_rate_pct
FROM address_corrections;


-- ─────────────────────────────────────────────────────────────
-- Q-02  CORRECTION TYPE FREQUENCY & DELIVERY IMPACT
--       GROUP BY + HAVING – finds error types affecting > 50 records
-- ─────────────────────────────────────────────────────────────
SELECT
    correction_type,
    COUNT(*)                                                             AS frequency,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                  AS share_pct,
    ROUND(AVG(address_accuracy_score), 2)                               AS avg_accuracy,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS delivery_success_rate,
    ROUND(100.0 * SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                 AS delivery_fail_rate
FROM address_corrections
WHERE correction_required = TRUE
GROUP BY correction_type
HAVING COUNT(*) > 50
ORDER BY frequency DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-03  ZONE-WISE ERROR ANALYSIS WITH RANKING
--       RANK window function + GROUP BY
-- ─────────────────────────────────────────────────────────────
SELECT
    delivery_zone,
    COUNT(*)                                                                        AS total_orders,
    SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)                           AS corrections,
    ROUND(100.0 * SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                            AS correction_rate_pct,
    ROUND(AVG(address_accuracy_score), 2)                                           AS avg_accuracy,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                            AS delivery_success_pct,
    RANK() OVER (ORDER BY AVG(address_accuracy_score) DESC)                        AS accuracy_rank,
    RANK() OVER (ORDER BY SUM(CASE WHEN correction_required THEN 1 ELSE 0 END) DESC) AS corrections_rank
FROM address_corrections
GROUP BY delivery_zone
ORDER BY avg_accuracy DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-04  PINCODE MISMATCH RATE BY CITY  (TOP 10)
--       GROUP BY + ORDER BY + LIMIT
-- ─────────────────────────────────────────────────────────────
SELECT
    city,
    COUNT(*)                                                                     AS total_orders,
    SUM(CASE WHEN pincode_mismatch THEN 1 ELSE 0 END)                           AS mismatch_count,
    ROUND(100.0 * SUM(CASE WHEN pincode_mismatch THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                         AS mismatch_rate_pct,
    ROUND(AVG(address_accuracy_score), 2)                                        AS avg_accuracy,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                         AS delivery_success_pct
FROM address_corrections
GROUP BY city
HAVING SUM(CASE WHEN pincode_mismatch THEN 1 ELSE 0 END) > 0
ORDER BY mismatch_count DESC
LIMIT 10;


-- ─────────────────────────────────────────────────────────────
-- Q-05  WEEKLY TREND – CORRECTIONS & ACCURACY
--       GROUP BY week_number with rolling context
-- ─────────────────────────────────────────────────────────────
SELECT
    week_number,
    COUNT(*)                                                                      AS total_orders,
    SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)                         AS corrections,
    ROUND(100.0 * SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                          AS correction_rate_pct,
    ROUND(AVG(address_accuracy_score), 2)                                         AS avg_accuracy,
    ROUND(AVG(AVG(address_accuracy_score))
          OVER (ORDER BY week_number ROWS BETWEEN 3 PRECEDING AND CURRENT ROW), 2) AS rolling_4wk_accuracy
FROM address_corrections
GROUP BY week_number
ORDER BY week_number;


-- ─────────────────────────────────────────────────────────────
-- Q-06  CITY × ZONE HOTSPOT MATRIX  (CTE)
--       CTE + DENSE_RANK for composite hotspot scoring
-- ─────────────────────────────────────────────────────────────
WITH city_zone_stats AS (
    SELECT
        city,
        delivery_zone,
        COUNT(*)                                                                   AS total_orders,
        SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)                      AS corrections,
        ROUND(100.0 * SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)
              / COUNT(*), 2)                                                       AS correction_rate,
        ROUND(100.0 * SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)
              / COUNT(*), 2)                                                       AS fail_rate,
        ROUND(AVG(address_accuracy_score), 2)                                      AS avg_accuracy
    FROM address_corrections
    GROUP BY city, delivery_zone
),
scored AS (
    SELECT *,
        ROUND(correction_rate * 0.4 + fail_rate * 0.4 + (100 - avg_accuracy) * 0.2, 2) AS hotspot_score
    FROM city_zone_stats
)
SELECT
    city,
    delivery_zone,
    total_orders,
    correction_rate,
    fail_rate,
    avg_accuracy,
    hotspot_score,
    DENSE_RANK() OVER (ORDER BY hotspot_score DESC) AS hotspot_rank
FROM scored
ORDER BY hotspot_score DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────
-- Q-07  ROOT CAUSE: WHICH ERROR TYPES DRIVE DELIVERY FAILURES?
--       CASE WHEN classification + aggregation
-- ─────────────────────────────────────────────────────────────
SELECT
    correction_type,
    SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)                         AS delivery_failures,
    ROUND(100.0 * SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                           AS failure_rate_pct,
    CASE
        WHEN ROUND(100.0 * SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)
                   / COUNT(*), 2) >= 50 THEN 'CRITICAL'
        WHEN ROUND(100.0 * SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)
                   / COUNT(*), 2) >= 35 THEN 'HIGH'
        WHEN ROUND(100.0 * SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)
                   / COUNT(*), 2) >= 20 THEN 'MEDIUM'
        ELSE 'LOW'
    END                                                                            AS risk_classification
FROM address_corrections
WHERE correction_required = TRUE
GROUP BY correction_type
ORDER BY failure_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-08  ACCURACY BAND DISTRIBUTION ACROSS ZONES
--       CASE WHEN banding + GROUP BY two columns
-- ─────────────────────────────────────────────────────────────
SELECT
    delivery_zone,
    SUM(CASE WHEN address_accuracy_score < 50            THEN 1 ELSE 0 END) AS critical,
    SUM(CASE WHEN address_accuracy_score BETWEEN 50 AND 64 THEN 1 ELSE 0 END) AS low,
    SUM(CASE WHEN address_accuracy_score BETWEEN 65 AND 79 THEN 1 ELSE 0 END) AS medium,
    SUM(CASE WHEN address_accuracy_score BETWEEN 80 AND 89 THEN 1 ELSE 0 END) AS high,
    SUM(CASE WHEN address_accuracy_score >= 90            THEN 1 ELSE 0 END) AS excellent,
    COUNT(*)                                                                  AS total
FROM address_corrections
GROUP BY delivery_zone
ORDER BY delivery_zone;


-- ─────────────────────────────────────────────────────────────
-- Q-09  LAG – WEEK-OVER-WEEK ACCURACY CHANGE
--       LAG window function for trend delta
-- ─────────────────────────────────────────────────────────────
WITH weekly_acc AS (
    SELECT
        week_number,
        ROUND(AVG(address_accuracy_score), 2)                          AS avg_accuracy
    FROM address_corrections
    GROUP BY week_number
)
SELECT
    week_number,
    avg_accuracy,
    LAG(avg_accuracy) OVER (ORDER BY week_number)                      AS prev_week_accuracy,
    ROUND(avg_accuracy - LAG(avg_accuracy) OVER (ORDER BY week_number), 2) AS wow_delta,
    CASE
        WHEN avg_accuracy > LAG(avg_accuracy) OVER (ORDER BY week_number) THEN '▲ Improved'
        WHEN avg_accuracy < LAG(avg_accuracy) OVER (ORDER BY week_number) THEN '▼ Declined'
        ELSE '– No Change'
    END                                                                AS trend_direction
FROM weekly_acc
ORDER BY week_number;


-- ─────────────────────────────────────────────────────────────
-- Q-10  LEAD – NEXT-WEEK FORECAST COMPARISON
--       LEAD window function
-- ─────────────────────────────────────────────────────────────
WITH weekly_stats AS (
    SELECT
        week_number,
        COUNT(*)                                                             AS orders,
        ROUND(100.0 * SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)
              / COUNT(*), 2)                                                 AS correction_rate
    FROM address_corrections
    GROUP BY week_number
)
SELECT
    week_number,
    orders,
    correction_rate,
    LEAD(correction_rate) OVER (ORDER BY week_number)                       AS next_week_rate,
    ROUND(LEAD(correction_rate) OVER (ORDER BY week_number) - correction_rate, 2) AS expected_change
FROM weekly_stats
ORDER BY week_number;


-- ─────────────────────────────────────────────────────────────
-- Q-11  ROW_NUMBER – DEDUPLICATE: LATEST RECORD PER CUSTOMER
--       ROW_NUMBER to keep most recent per customer
-- ─────────────────────────────────────────────────────────────
WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY correction_timestamp DESC
        ) AS rn
    FROM address_corrections
)
SELECT
    order_id, customer_id, city, state, pincode,
    correction_required, address_accuracy_score, delivery_success,
    correction_timestamp
FROM ranked
WHERE rn = 1
ORDER BY correction_timestamp DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────
-- Q-12  CORRECTION SOURCE EFFECTIVENESS (INNER JOIN with zone ref)
--       JOIN + GROUP BY
-- ─────────────────────────────────────────────────────────────
SELECT
    ac.correction_source,
    dz.priority_level                                                        AS zone_priority,
    COUNT(*)                                                                 AS corrections_handled,
    ROUND(AVG(ac.address_accuracy_score), 2)                                AS avg_accuracy,
    ROUND(100.0 * SUM(CASE WHEN ac.delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                     AS delivery_success_rate
FROM address_corrections ac
INNER JOIN delivery_zones dz ON ac.delivery_zone = dz.zone_name
WHERE ac.correction_required = TRUE
  AND ac.correction_source <> 'None'
GROUP BY ac.correction_source, dz.priority_level
ORDER BY delivery_success_rate DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-13  HIGH-RISK CUSTOMERS (repeated failures)
--       CTE + HAVING + subquery
-- ─────────────────────────────────────────────────────────────
WITH customer_stats AS (
    SELECT
        customer_id,
        COUNT(*)                                                             AS total_orders,
        SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)               AS corrections,
        SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)              AS delivery_failures,
        ROUND(AVG(address_accuracy_score), 2)                              AS avg_accuracy
    FROM address_corrections
    GROUP BY customer_id
    HAVING COUNT(*) >= 2
)
SELECT *,
    ROUND(100.0 * corrections / total_orders, 2)      AS correction_rate_pct,
    ROUND(100.0 * delivery_failures / total_orders, 2) AS failure_rate_pct
FROM customer_stats
WHERE delivery_failures >= 2
ORDER BY delivery_failures DESC
LIMIT 25;


-- ─────────────────────────────────────────────────────────────
-- Q-14  MONTHLY CORRECTION TREND WITH CUMULATIVE SUM
--       SUM OVER (ORDER BY) – running total
-- ─────────────────────────────────────────────────────────────
SELECT
    year,
    month,
    COUNT(*)                                                                 AS monthly_orders,
    SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)                    AS monthly_corrections,
    SUM(SUM(CASE WHEN correction_required THEN 1 ELSE 0 END))
        OVER (PARTITION BY year ORDER BY month)                             AS cumulative_corrections,
    ROUND(AVG(address_accuracy_score), 2)                                    AS avg_accuracy
FROM address_corrections
GROUP BY year, month
ORDER BY year, month;


-- ─────────────────────────────────────────────────────────────
-- Q-15  PERCENTILE RANKING OF CITY ACCURACY
--       NTILE + PERCENT_RANK
-- ─────────────────────────────────────────────────────────────
WITH city_accuracy AS (
    SELECT
        city,
        ROUND(AVG(address_accuracy_score), 2)  AS avg_accuracy,
        COUNT(*)                               AS total_orders
    FROM address_corrections
    GROUP BY city
)
SELECT
    city,
    avg_accuracy,
    total_orders,
    NTILE(4) OVER (ORDER BY avg_accuracy DESC)                     AS accuracy_quartile,
    ROUND(PERCENT_RANK() OVER (ORDER BY avg_accuracy DESC) * 100, 2) AS percentile_rank
FROM city_accuracy
ORDER BY avg_accuracy DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-16  FIRST CORRECTION vs SUBSEQUENT CORRECTIONS PER CUSTOMER
--       FIRST_VALUE + ROW_NUMBER
-- ─────────────────────────────────────────────────────────────
SELECT
    customer_id,
    order_id,
    correction_timestamp,
    correction_type,
    address_accuracy_score,
    FIRST_VALUE(correction_type)
        OVER (PARTITION BY customer_id ORDER BY correction_timestamp)      AS first_error_type,
    ROW_NUMBER()
        OVER (PARTITION BY customer_id ORDER BY correction_timestamp)      AS correction_sequence
FROM address_corrections
WHERE correction_required = TRUE
ORDER BY customer_id, correction_sequence;


-- ─────────────────────────────────────────────────────────────
-- Q-17  ZONE PERFORMANCE RELATIVE TO AVERAGE (SELF-JOIN VIA CTE)
-- ─────────────────────────────────────────────────────────────
WITH zone_stats AS (
    SELECT
        delivery_zone,
        ROUND(AVG(address_accuracy_score), 2)                                AS zone_avg
    FROM address_corrections
    GROUP BY delivery_zone
),
overall AS (
    SELECT ROUND(AVG(address_accuracy_score), 2) AS overall_avg FROM address_corrections
)
SELECT
    z.delivery_zone,
    z.zone_avg,
    o.overall_avg,
    ROUND(z.zone_avg - o.overall_avg, 2)                                     AS variance_from_avg,
    CASE
        WHEN z.zone_avg > o.overall_avg THEN 'Above Average'
        WHEN z.zone_avg < o.overall_avg THEN 'Below Average'
        ELSE 'At Average'
    END                                                                      AS performance_label
FROM zone_stats z
CROSS JOIN overall o
ORDER BY z.zone_avg DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-18  TOP 3 ERROR TYPES PER ZONE (DENSE_RANK partitioned)
-- ─────────────────────────────────────────────────────────────
WITH zone_error_count AS (
    SELECT
        delivery_zone,
        correction_type,
        COUNT(*) AS freq
    FROM address_corrections
    WHERE correction_required = TRUE
    GROUP BY delivery_zone, correction_type
),
ranked AS (
    SELECT *,
        DENSE_RANK() OVER (PARTITION BY delivery_zone ORDER BY freq DESC) AS dr
    FROM zone_error_count
)
SELECT delivery_zone, correction_type, freq, dr AS rank_within_zone
FROM ranked
WHERE dr <= 3
ORDER BY delivery_zone, dr;


-- ─────────────────────────────────────────────────────────────
-- Q-19  DELIVERY SUCCESS RATE BREAKDOWN BY ACCURACY BAND
--       CASE WHEN banding + aggregate
-- ─────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN address_accuracy_score < 50              THEN '1. Critical (<50)'
        WHEN address_accuracy_score BETWEEN 50 AND 64 THEN '2. Low (50-64)'
        WHEN address_accuracy_score BETWEEN 65 AND 79 THEN '3. Medium (65-79)'
        WHEN address_accuracy_score BETWEEN 80 AND 89 THEN '4. High (80-89)'
        ELSE                                               '5. Excellent (90+)'
    END                                                                      AS accuracy_band,
    COUNT(*)                                                                 AS total_records,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                     AS delivery_success_rate,
    ROUND(AVG(address_accuracy_score), 2)                                    AS avg_score
FROM address_corrections
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────
-- Q-20  CORRECTION VOLUME: HOUR-OF-DAY ANALYSIS
-- ─────────────────────────────────────────────────────────────
SELECT
    EXTRACT(HOUR FROM correction_timestamp)::INT                             AS hour_of_day,
    COUNT(*)                                                                 AS total_queries,
    SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)                    AS corrections,
    ROUND(AVG(address_accuracy_score), 2)                                    AS avg_accuracy,
    CASE
        WHEN EXTRACT(HOUR FROM correction_timestamp) BETWEEN 9 AND 17 THEN 'Business Hours'
        WHEN EXTRACT(HOUR FROM correction_timestamp) BETWEEN 18 AND 22 THEN 'Evening Peak'
        ELSE 'Off-Peak'
    END                                                                      AS time_segment
FROM address_corrections
GROUP BY hour_of_day
ORDER BY total_queries DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-21  STATE-LEVEL CORRECTION RATE WITH METRO FLAG (JOIN)
-- ─────────────────────────────────────────────────────────────
SELECT
    ac.state,
    MAX(c.is_metro::INT)                                                     AS has_metro_city,
    COUNT(*)                                                                 AS total_orders,
    SUM(CASE WHEN ac.correction_required THEN 1 ELSE 0 END)                 AS corrections,
    ROUND(100.0 * SUM(CASE WHEN ac.correction_required THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                     AS correction_rate_pct,
    ROUND(AVG(ac.address_accuracy_score), 2)                                 AS avg_accuracy
FROM address_corrections ac
LEFT JOIN cities c ON LOWER(ac.city) = LOWER(c.city_name)
GROUP BY ac.state
ORDER BY correction_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-22  SLA BREACH RISK: ZONES WITH HIGH FAIL RATE + LOW SLA
--       JOIN delivery_zones for SLA context
-- ─────────────────────────────────────────────────────────────
SELECT
    ac.delivery_zone,
    dz.sla_hours,
    dz.priority_level,
    COUNT(*)                                                                    AS total_orders,
    ROUND(100.0 * SUM(CASE WHEN NOT ac.delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                        AS failure_rate_pct,
    ROUND(AVG(ac.address_accuracy_score), 2)                                    AS avg_accuracy,
    CASE WHEN dz.sla_hours <= 36
         AND ROUND(100.0 * SUM(CASE WHEN NOT ac.delivery_success THEN 1 ELSE 0 END)
                   / COUNT(*), 2) > 25
    THEN 'HIGH SLA RISK'
    ELSE 'Acceptable'
    END                                                                         AS sla_risk_flag
FROM address_corrections ac
JOIN delivery_zones dz ON ac.delivery_zone = dz.zone_name
GROUP BY ac.delivery_zone, dz.sla_hours, dz.priority_level
ORDER BY failure_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-23  PINCODE MISMATCH PAIRS (entered vs correct)
--       GROUP BY pair to find most common mismatches
-- ─────────────────────────────────────────────────────────────
SELECT
    pincode           AS entered_pincode,
    correct_pincode,
    city,
    COUNT(*)          AS mismatch_occurrences,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2) AS delivery_success_rate
FROM address_corrections
WHERE pincode_mismatch = TRUE
GROUP BY pincode, correct_pincode, city
HAVING COUNT(*) >= 2
ORDER BY mismatch_occurrences DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────
-- Q-24  CORRECTION SOURCE RANKING PER ZONE
--       ROW_NUMBER partitioned by zone
-- ─────────────────────────────────────────────────────────────
WITH src_zone AS (
    SELECT
        delivery_zone,
        correction_source,
        COUNT(*)                                                              AS fixes,
        ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
              / COUNT(*), 2)                                                  AS success_rate
    FROM address_corrections
    WHERE correction_required = TRUE
      AND correction_source <> 'None'
    GROUP BY delivery_zone, correction_source
)
SELECT *,
    ROW_NUMBER() OVER (PARTITION BY delivery_zone ORDER BY success_rate DESC) AS source_rank
FROM src_zone
ORDER BY delivery_zone, source_rank;


-- ─────────────────────────────────────────────────────────────
-- Q-25  MULTI-ERROR CUSTOMERS (>1 different correction type)
--       STRING_AGG + HAVING
-- ─────────────────────────────────────────────────────────────
SELECT
    customer_id,
    COUNT(DISTINCT correction_type)                                          AS distinct_error_types,
    STRING_AGG(DISTINCT correction_type, ' | ' ORDER BY correction_type)    AS error_types,
    COUNT(*)                                                                 AS total_orders,
    ROUND(AVG(address_accuracy_score), 2)                                    AS avg_accuracy
FROM address_corrections
WHERE correction_required = TRUE
GROUP BY customer_id
HAVING COUNT(DISTINCT correction_type) > 1
ORDER BY distinct_error_types DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────
-- Q-26  ACCURACY SCORE MOVING AVERAGE (4-WEEK WINDOW)
--       AVG OVER ROWS BETWEEN
-- ─────────────────────────────────────────────────────────────
WITH weekly AS (
    SELECT
        week_number,
        ROUND(AVG(address_accuracy_score), 2) AS weekly_avg
    FROM address_corrections
    GROUP BY week_number
)
SELECT
    week_number,
    weekly_avg,
    ROUND(AVG(weekly_avg)
        OVER (ORDER BY week_number ROWS BETWEEN 3 PRECEDING AND CURRENT ROW), 2) AS ma_4week,
    ROUND(AVG(weekly_avg)
        OVER (ORDER BY week_number ROWS BETWEEN 7 PRECEDING AND CURRENT ROW), 2) AS ma_8week
FROM weekly
ORDER BY week_number;


-- ─────────────────────────────────────────────────────────────
-- Q-27  CORRECTION REQUIRED FLAG: CITY PIVOT SUMMARY
--       Conditional aggregation as column pivot
-- ─────────────────────────────────────────────────────────────
SELECT
    city,
    COUNT(*)                                                                  AS total,
    SUM(CASE WHEN correction_required = FALSE               THEN 1 ELSE 0 END) AS clean_addresses,
    SUM(CASE WHEN correction_type = 'Pincode Mismatch'      THEN 1 ELSE 0 END) AS pincode_mismatch,
    SUM(CASE WHEN correction_type = 'Spelling Error'         THEN 1 ELSE 0 END) AS spelling_error,
    SUM(CASE WHEN correction_type = 'Missing Locality'       THEN 1 ELSE 0 END) AS missing_locality,
    SUM(CASE WHEN correction_type = 'Incomplete Address'     THEN 1 ELSE 0 END) AS incomplete_address,
    SUM(CASE WHEN correction_type = 'Wrong City-State'       THEN 1 ELSE 0 END) AS wrong_city_state,
    SUM(CASE WHEN correction_type = 'Duplicate Address'      THEN 1 ELSE 0 END) AS duplicate_address
FROM address_corrections
GROUP BY city
ORDER BY total DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-28  WEEK-OVER-WEEK DELIVERY FAILURE SPIKE DETECTION
--       CTE + LAG + threshold filter
-- ─────────────────────────────────────────────────────────────
WITH weekly_fail AS (
    SELECT
        week_number,
        COUNT(*)                                                              AS total,
        SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)               AS failures,
        ROUND(100.0 * SUM(CASE WHEN NOT delivery_success THEN 1 ELSE 0 END)
              / COUNT(*), 2)                                                  AS fail_rate
    FROM address_corrections
    GROUP BY week_number
),
with_lag AS (
    SELECT *,
        LAG(fail_rate) OVER (ORDER BY week_number) AS prev_fail_rate,
        ROUND(fail_rate - LAG(fail_rate) OVER (ORDER BY week_number), 2)     AS delta
    FROM weekly_fail
)
SELECT *,
    CASE WHEN delta > 5 THEN 'SPIKE DETECTED' ELSE 'Normal' END              AS spike_alert
FROM with_lag
WHERE delta > 5
ORDER BY delta DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-29  TOP REPEAT CUSTOMERS IN HOTSPOT ZONES
--       Subquery + JOIN
-- ─────────────────────────────────────────────────────────────
SELECT
    ac.customer_id,
    ac.city,
    ac.delivery_zone,
    COUNT(*)                                                                   AS total_orders,
    SUM(CASE WHEN ac.correction_required THEN 1 ELSE 0 END)                   AS corrections,
    ROUND(AVG(ac.address_accuracy_score), 2)                                   AS avg_accuracy,
    SUM(CASE WHEN NOT ac.delivery_success THEN 1 ELSE 0 END)                  AS delivery_failures
FROM address_corrections ac
WHERE ac.delivery_zone IN (
    SELECT delivery_zone
    FROM address_corrections
    GROUP BY delivery_zone
    HAVING ROUND(100.0 * SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)
                 / COUNT(*), 2) > 60
)
GROUP BY ac.customer_id, ac.city, ac.delivery_zone
HAVING COUNT(*) >= 2
ORDER BY delivery_failures DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────
-- Q-30  CORRECTION TYPE TRANSITION (BEFORE → AFTER) PER CUSTOMER
--       LEAD to show next correction type for repeat customers
-- ─────────────────────────────────────────────────────────────
WITH ordered_corrections AS (
    SELECT
        customer_id,
        order_id,
        correction_type,
        correction_timestamp,
        LEAD(correction_type) OVER (
            PARTITION BY customer_id ORDER BY correction_timestamp
        )                                                                     AS next_correction_type,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id ORDER BY correction_timestamp
        )                                                                     AS seq
    FROM address_corrections
    WHERE correction_required = TRUE
)
SELECT
    correction_type               AS from_error,
    next_correction_type          AS to_error,
    COUNT(*)                      AS transition_count
FROM ordered_corrections
WHERE next_correction_type IS NOT NULL
GROUP BY from_error, to_error
ORDER BY transition_count DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────
-- Q-31  CITY ACCURACY QUARTILE ANALYSIS (NTILE)
-- ─────────────────────────────────────────────────────────────
WITH city_scores AS (
    SELECT
        city,
        ROUND(AVG(address_accuracy_score), 2)  AS avg_acc,
        COUNT(*)                               AS orders
    FROM address_corrections
    GROUP BY city
)
SELECT
    city, avg_acc, orders,
    NTILE(4) OVER (ORDER BY avg_acc)                                         AS quartile,
    CASE NTILE(4) OVER (ORDER BY avg_acc)
        WHEN 1 THEN 'Bottom 25% – Needs Intervention'
        WHEN 2 THEN 'Lower-Mid – Monitor Closely'
        WHEN 3 THEN 'Upper-Mid – Stable'
        WHEN 4 THEN 'Top 25% – High Performer'
    END                                                                      AS quartile_label
FROM city_scores
ORDER BY quartile, avg_acc;


-- ─────────────────────────────────────────────────────────────
-- Q-32  CORRECTION REQUIRED FLAG RATE BY CORRECTION SOURCE
--       Useful for operational review
-- ─────────────────────────────────────────────────────────────
SELECT
    correction_source,
    COUNT(*)                                                                 AS total_handled,
    ROUND(AVG(address_accuracy_score), 2)                                    AS avg_accuracy_after,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                     AS post_correction_success_rate,
    ROUND(100.0 * SUM(CASE WHEN pincode_mismatch THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                     AS residual_pincode_mismatch_pct
FROM address_corrections
WHERE correction_required = TRUE
  AND correction_source <> 'None'
GROUP BY correction_source
ORDER BY post_correction_success_rate DESC;


-- ─────────────────────────────────────────────────────────────
-- Q-33  MONTH-OVER-MONTH IMPROVEMENT RATE
--       LAG on monthly aggregates
-- ─────────────────────────────────────────────────────────────
WITH monthly_stats AS (
    SELECT
        year,
        month,
        ROUND(AVG(address_accuracy_score), 2)                               AS avg_acc,
        ROUND(100.0 * SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)
              / COUNT(*), 2)                                                 AS correction_rate
    FROM address_corrections
    GROUP BY year, month
)
SELECT
    year, month, avg_acc, correction_rate,
    LAG(avg_acc)        OVER (ORDER BY year, month) AS prev_month_acc,
    LAG(correction_rate) OVER (ORDER BY year, month) AS prev_month_rate,
    ROUND(avg_acc - LAG(avg_acc) OVER (ORDER BY year, month), 2)           AS acc_mom_delta,
    ROUND(correction_rate - LAG(correction_rate) OVER (ORDER BY year, month), 2) AS rate_mom_delta
FROM monthly_stats
ORDER BY year, month;


-- ─────────────────────────────────────────────────────────────
-- Q-34  FULL CITY PERFORMANCE SCORECARD
--       Comprehensive city-level report using multiple aggregations
-- ─────────────────────────────────────────────────────────────
SELECT
    ac.city,
    c.state_name,
    c.is_metro,
    COUNT(*)                                                                   AS total_orders,
    ROUND(AVG(ac.address_accuracy_score), 2)                                   AS avg_accuracy,
    ROUND(100.0 * SUM(CASE WHEN ac.correction_required THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                       AS correction_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN ac.pincode_mismatch THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                       AS pincode_mismatch_pct,
    ROUND(100.0 * SUM(CASE WHEN ac.delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                       AS delivery_success_pct,
    RANK() OVER (ORDER BY AVG(ac.address_accuracy_score) DESC)                 AS accuracy_rank,
    RANK() OVER (ORDER BY ROUND(100.0 * SUM(CASE WHEN ac.delivery_success THEN 1 ELSE 0 END)
                                / COUNT(*), 2) DESC)                           AS delivery_rank
FROM address_corrections ac
LEFT JOIN cities c ON LOWER(ac.city) = LOWER(c.city_name)
GROUP BY ac.city, c.state_name, c.is_metro
ORDER BY avg_accuracy DESC;
