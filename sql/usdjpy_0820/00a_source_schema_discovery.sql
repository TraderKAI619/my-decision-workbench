-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 0A — Source Schema Discovery
--
-- PURPOSE
-- -------
-- Discover the exact production DuckDB contract before writing
-- any analytical or evidence SQL.
--
-- RULES
-- -----
-- 1. No guessed analytical column names.
-- 2. No evidence logic.
-- 3. No canonical Daily source selection.
-- 4. No database mutation.
-- 5. Production schema is the source of truth.
-- ============================================================


-- ============================================================
-- 1. PRODUCTION TABLE INVENTORY
-- ============================================================

SELECT
    table_schema,
    table_name,
    table_type
FROM information_schema.tables
WHERE table_schema = 'main'
ORDER BY table_name;


-- ============================================================
-- 2. TRADINGVIEW DAILY — EXACT SCHEMA
-- ============================================================

DESCRIBE market_bars_tradingview_daily;


-- ============================================================
-- 3. DUKASCOPY H4 — EXACT SCHEMA
-- ============================================================

DESCRIBE market_bars_dukascopy_4h;


-- ============================================================
-- 4. DAILY PROVIDER RECONCILIATION — EXACT SCHEMA
-- ============================================================

DESCRIBE provider_reconciliation_daily;


-- ============================================================
-- 5. DUKASCOPY H1 — EXACT SCHEMA
--
-- Included because H1 is the upstream source of canonical H4.
-- We are not analysing H1 yet.
-- ============================================================

DESCRIBE market_bars_dukascopy_1h;


-- ============================================================
-- 6. AGGREGATED DUKASCOPY H4 — EXACT SCHEMA
--
-- Distinguishes aggregation/provenance fields from canonical
-- H4 market-fact fields.
-- ============================================================

DESCRIBE aggregated_dukascopy_4h;


-- ============================================================
-- 7. VALIDATED TRADINGVIEW DAILY — EXACT SCHEMA
--
-- Lets us distinguish validated source fields from transformed
-- canonical Daily market facts.
-- ============================================================

DESCRIBE validated_tradingview_daily;


-- ============================================================
-- 8. VALIDATED DUKASCOPY H1 — EXACT SCHEMA
-- ============================================================

DESCRIBE validated_dukascopy_1h;


-- ============================================================
-- 9. ROW COUNTS ONLY
--
-- COUNT(*) requires no knowledge of analytical column names.
-- ============================================================

SELECT
    'validated_tradingview_daily' AS table_name,
    COUNT(*) AS row_count
FROM validated_tradingview_daily

UNION ALL

SELECT
    'validated_dukascopy_1h',
    COUNT(*)
FROM validated_dukascopy_1h

UNION ALL

SELECT
    'aggregated_dukascopy_4h',
    COUNT(*)
FROM aggregated_dukascopy_4h

UNION ALL

SELECT
    'market_bars_tradingview_daily',
    COUNT(*)
FROM market_bars_tradingview_daily

UNION ALL

SELECT
    'market_bars_dukascopy_1h',
    COUNT(*)
FROM market_bars_dukascopy_1h

UNION ALL

SELECT
    'market_bars_dukascopy_4h',
    COUNT(*)
FROM market_bars_dukascopy_4h

UNION ALL

SELECT
    'provider_reconciliation_daily',
    COUNT(*)
FROM provider_reconciliation_daily

ORDER BY table_name;
