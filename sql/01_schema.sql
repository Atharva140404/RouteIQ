-- =============================================================
--  ADDRESS ACCURACY & DELIVERY INSIGHTS
--  01_schema.sql  –  Database Schema & Table Definitions
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- DROP & RECREATE (idempotent)
-- ─────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS address_corrections CASCADE;
DROP TABLE IF EXISTS delivery_zones       CASCADE;
DROP TABLE IF EXISTS cities               CASCADE;

-- ─────────────────────────────────────────────────────────────
-- 1. REFERENCE: CITIES
-- ─────────────────────────────────────────────────────────────

CREATE TABLE cities (
    city_id      SERIAL       PRIMARY KEY,
    city_name    VARCHAR(100) NOT NULL,
    state_name   VARCHAR(100) NOT NULL,
    region       VARCHAR(50),
    is_metro     BOOLEAN      DEFAULT FALSE,
    created_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO cities (city_name, state_name, region, is_metro) VALUES
    ('Mumbai',      'Maharashtra',       'West',  TRUE),
    ('Pune',        'Maharashtra',       'West',  TRUE),
    ('Nagpur',      'Maharashtra',       'West',  FALSE),
    ('Delhi',       'Delhi',             'North', TRUE),
    ('Bengaluru',   'Karnataka',         'South', TRUE),
    ('Hyderabad',   'Telangana',         'South', TRUE),
    ('Chennai',     'Tamil Nadu',        'South', TRUE),
    ('Kolkata',     'West Bengal',       'East',  TRUE),
    ('Ahmedabad',   'Gujarat',           'West',  TRUE),
    ('Jaipur',      'Rajasthan',         'North', FALSE),
    ('Lucknow',     'Uttar Pradesh',     'North', FALSE),
    ('Kanpur',      'Uttar Pradesh',     'North', FALSE),
    ('Patna',       'Bihar',             'East',  FALSE),
    ('Bhopal',      'Madhya Pradesh',    'Central',FALSE),
    ('Indore',      'Madhya Pradesh',    'Central',FALSE),
    ('Surat',       'Gujarat',           'West',  FALSE),
    ('Vadodara',    'Gujarat',           'West',  FALSE),
    ('Coimbatore',  'Tamil Nadu',        'South', FALSE);

-- ─────────────────────────────────────────────────────────────
-- 2. REFERENCE: DELIVERY ZONES
-- ─────────────────────────────────────────────────────────────

CREATE TABLE delivery_zones (
    zone_id          SERIAL       PRIMARY KEY,
    zone_name        VARCHAR(20)  NOT NULL UNIQUE,
    zone_description VARCHAR(200),
    sla_hours        INT          NOT NULL,
    priority_level   VARCHAR(20)  CHECK (priority_level IN ('High','Medium','Low')),
    created_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO delivery_zones (zone_name, zone_description, sla_hours, priority_level) VALUES
    ('Zone A', 'Metro Core – High Density',     24, 'High'),
    ('Zone B', 'Metro Periphery – Medium Density', 36, 'High'),
    ('Zone C', 'Tier-2 Urban',                  48, 'Medium'),
    ('Zone D', 'Tier-2 Suburban',               60, 'Medium'),
    ('Zone E', 'Tier-3 / Rural',                72, 'Low');

-- ─────────────────────────────────────────────────────────────
-- 3. MAIN FACT TABLE: ADDRESS CORRECTIONS
-- ─────────────────────────────────────────────────────────────

CREATE TABLE address_corrections (
    record_id                SERIAL        PRIMARY KEY,
    order_id                 VARCHAR(20)   NOT NULL UNIQUE,
    customer_id              VARCHAR(20)   NOT NULL,
    city                     VARCHAR(100)  NOT NULL,
    state                    VARCHAR(100)  NOT NULL,
    pincode                  CHAR(6)       NOT NULL,
    correct_pincode          CHAR(6)       NOT NULL,
    entered_address          TEXT          NOT NULL,
    corrected_address        TEXT,
    correction_required      BOOLEAN       NOT NULL DEFAULT FALSE,
    correction_type          VARCHAR(100),
    correction_source        VARCHAR(100),
    delivery_zone            VARCHAR(20)   REFERENCES delivery_zones(zone_name),
    address_accuracy_score   NUMERIC(5,2)  CHECK (address_accuracy_score BETWEEN 0 AND 100),
    delivery_success         BOOLEAN       NOT NULL DEFAULT FALSE,
    correction_timestamp     TIMESTAMP     NOT NULL,
    week_number              INT,
    month                    INT,
    year                     INT,
    -- Derived / computed flags
    pincode_mismatch         BOOLEAN       GENERATED ALWAYS AS (pincode <> correct_pincode) STORED,
    created_at               TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

-- ─────────────────────────────────────────────────────────────
-- 4. INDEXES FOR PERFORMANCE
-- ─────────────────────────────────────────────────────────────

CREATE INDEX idx_ac_city           ON address_corrections (city);
CREATE INDEX idx_ac_state          ON address_corrections (state);
CREATE INDEX idx_ac_zone           ON address_corrections (delivery_zone);
CREATE INDEX idx_ac_correction_req ON address_corrections (correction_required);
CREATE INDEX idx_ac_pincode        ON address_corrections (pincode);
CREATE INDEX idx_ac_timestamp      ON address_corrections (correction_timestamp);
CREATE INDEX idx_ac_week           ON address_corrections (week_number);
CREATE INDEX idx_ac_correction_type ON address_corrections (correction_type);
CREATE INDEX idx_ac_customer       ON address_corrections (customer_id);
CREATE INDEX idx_ac_accuracy       ON address_corrections (address_accuracy_score);

-- ─────────────────────────────────────────────────────────────
-- 5. VIEWS
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW vw_daily_summary AS
SELECT
    DATE(correction_timestamp)          AS report_date,
    COUNT(*)                            AS total_orders,
    SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)    AS corrections_needed,
    SUM(CASE WHEN pincode_mismatch     THEN 1 ELSE 0 END)   AS pincode_mismatches,
    ROUND(AVG(address_accuracy_score), 2)                   AS avg_accuracy,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END) / COUNT(*), 2) AS delivery_success_rate
FROM address_corrections
GROUP BY DATE(correction_timestamp)
ORDER BY report_date;


CREATE OR REPLACE VIEW vw_zone_kpis AS
SELECT
    delivery_zone,
    COUNT(*)                                                                    AS total_orders,
    SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)                       AS total_corrections,
    ROUND(100.0 * SUM(CASE WHEN correction_required THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                        AS correction_rate_pct,
    SUM(CASE WHEN pincode_mismatch THEN 1 ELSE 0 END)                          AS pincode_mismatches,
    ROUND(AVG(address_accuracy_score), 2)                                       AS avg_accuracy_score,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                        AS delivery_success_rate
FROM address_corrections
GROUP BY delivery_zone;


CREATE OR REPLACE VIEW vw_correction_type_summary AS
SELECT
    correction_type,
    COUNT(*)                                                                   AS frequency,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                        AS pct_of_all_corrections,
    ROUND(AVG(address_accuracy_score), 2)                                      AS avg_accuracy,
    ROUND(100.0 * SUM(CASE WHEN delivery_success THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                                       AS delivery_success_rate
FROM address_corrections
WHERE correction_required = TRUE
GROUP BY correction_type
ORDER BY frequency DESC;

-- ─────────────────────────────────────────────────────────────
-- 6. LOAD DATA FROM CSV (PostgreSQL COPY)
-- ─────────────────────────────────────────────────────────────

-- Run this after generating data/address_records.csv:
-- COPY address_corrections (
--     order_id, customer_id, city, state, pincode, correct_pincode,
--     entered_address, corrected_address, correction_required,
--     correction_type, correction_source, delivery_zone,
--     address_accuracy_score, delivery_success, correction_timestamp,
--     week_number, month, year
-- )
-- FROM '/absolute/path/to/data/address_records.csv'
-- WITH (FORMAT csv, HEADER true, NULL 'None');
