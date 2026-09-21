-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 0B — Case Value Discovery
--
-- PURPOSE
-- -------
-- Inspect the exact provider-level Daily facts,
-- cross-provider reconciliation facts,
-- case-range anchors, and canonical H4 facts required
-- to reconstruct the documented decision.
--
-- IMPORTANT
-- ---------
-- This file performs discovery only.
-- It does NOT select a canonical Daily provider.
-- It does NOT create evidence.
-- It does NOT infer a trading decision.
-- ============================================================


-- ============================================================
-- 1. DAILY PROVIDERS AVAILABLE
-- ============================================================

SELECT
    source,
    symbol,
    timeframe,
    COUNT(*) AS row_count,
    MIN(bar_start_utc) AS first_bar_utc,
    MAX(bar_start_utc) AS last_bar_utc
FROM market_bars_tradingview_daily
WHERE symbol = 'USDJPY'
GROUP BY
    source,
    symbol,
    timeframe
ORDER BY source;


-- ============================================================
-- 2. DOCUMENTED CASE RANGE ANCHORS
--
-- PDF / previously validated case:
-- High: around 2026-07-23
-- Low : around 2026-08-03
--
-- Inspect every provider independently.
-- ============================================================

SELECT
    source,

    MAX(
        CASE
            WHEN CAST(time_utc9 AS DATE) = DATE '2026-07-23'
            THEN high
        END
    ) AS jul_23_high,

    MIN(
        CASE
            WHEN CAST(time_utc9 AS DATE) = DATE '2026-08-03'
            THEN low
        END
    ) AS aug_03_low,

    MAX(
        CASE
            WHEN CAST(time_utc9 AS DATE) = DATE '2026-07-23'
            THEN high
        END
    )
    -
    MIN(
        CASE
            WHEN CAST(time_utc9 AS DATE) = DATE '2026-08-03'
            THEN low
        END
    ) AS high_to_low_price_range

FROM market_bars_tradingview_daily

WHERE
    symbol = 'USDJPY'
    AND CAST(time_utc9 AS DATE)
        BETWEEN DATE '2026-07-23'
            AND DATE '2026-08-03'

GROUP BY source
ORDER BY source;


-- ============================================================
-- 3. DAILY FACTS AROUND RECOVERY / DECISION WINDOW
--
-- No filtering on imbalance yet.
-- We first inspect the full Daily sequence.
-- ============================================================

SELECT
    source,
    date,
    bar_start_utc,
    time_utc9,
    open,
    high,
    low,
    close,
    range_pips,
    close_change_pips,
    candle_direction,
    break_previous_high,
    break_previous_low,
    has_imbalance,
    imbalance_direction,
    imbalance_low,
    imbalance_high,
    imbalance_size_pips
FROM market_bars_tradingview_daily
WHERE
    symbol = 'USDJPY'
    AND CAST(time_utc9 AS DATE)
        BETWEEN DATE '2026-08-03'
            AND DATE '2026-08-21'
ORDER BY
    time_utc9,
    source;


-- ============================================================
-- 4. ALL DAILY UPWARD IMBALANCES IN CASE WINDOW
--
-- This is the key Daily-zone discovery query.
-- ============================================================

SELECT
    source,
    date,
    bar_start_utc,
    time_utc9,
    low,
    high,
    close,
    imbalance_low,
    imbalance_high,
    imbalance_size,
    imbalance_size_pips
FROM market_bars_tradingview_daily
WHERE
    symbol = 'USDJPY'
    AND CAST(time_utc9 AS DATE)
        BETWEEN DATE '2026-08-03'
            AND DATE '2026-08-21'
    AND has_imbalance = TRUE
    AND imbalance_direction = 'UP'
ORDER BY
    time_utc9,
    source;


-- ============================================================
-- 5. CROSS-PROVIDER DAILY IMBALANCE COMPARISON
--
-- Group provider-level UP imbalance observations by Daily date.
-- This does NOT create a canonical zone.
--
-- It quantifies:
-- - provider coverage
-- - lower-bound spread
-- - upper-bound spread
-- - median numerical zone
--
-- Median is descriptive only, NOT canonical.
-- ============================================================

WITH daily_up AS (

    SELECT
        CAST(time_utc9 AS DATE) AS analytical_day,
        source,
        imbalance_low,
        imbalance_high,
        imbalance_size_pips

    FROM market_bars_tradingview_daily

    WHERE
        symbol = 'USDJPY'
        AND CAST(time_utc9 AS DATE)
            BETWEEN DATE '2026-08-03'
                AND DATE '2026-08-21'
        AND has_imbalance = TRUE
        AND imbalance_direction = 'UP'
)

SELECT
    analytical_day,

    COUNT(*) AS provider_count,

    string_agg(
        source,
        ', '
        ORDER BY source
    ) AS providers,

    MIN(imbalance_low) AS imbalance_low_min,
    MEDIAN(imbalance_low) AS imbalance_low_median,
    MAX(imbalance_low) AS imbalance_low_max,

    ROUND(
        (
            MAX(imbalance_low)
            - MIN(imbalance_low)
        ) * 100,
        1
    ) AS lower_bound_spread_pips,

    MIN(imbalance_high) AS imbalance_high_min,
    MEDIAN(imbalance_high) AS imbalance_high_median,
    MAX(imbalance_high) AS imbalance_high_max,

    ROUND(
        (
            MAX(imbalance_high)
            - MIN(imbalance_high)
        ) * 100,
        1
    ) AS upper_bound_spread_pips,

    MEDIAN(
        imbalance_size_pips
    ) AS imbalance_size_pips_median

FROM daily_up

GROUP BY analytical_day
ORDER BY analytical_day;


-- ============================================================
-- 6. RECONCILIATION — SAME CASE WINDOW
--
-- This is categorical cross-provider validation.
-- It is intentionally kept separate from numeric zone values.
-- ============================================================

SELECT
    date,
    symbol,
    timeframe,
    source_count,
    sources_present,
    coverage_pct,
    coverage_status,
    candle_direction_consensus,
    candle_direction_agreement_pct,
    break_previous_high_consensus,
    break_previous_high_agreement_pct,
    break_previous_low_consensus,
    break_previous_low_agreement_pct,
    imbalance_consensus,
    imbalance_agreeing_sources,
    imbalance_valid_sources,
    imbalance_agreement_pct,
    imbalance_tie,
    behavior_agreement
FROM provider_reconciliation_daily
WHERE
    symbol = 'USDJPY'
    AND CAST(date AS DATE)
        BETWEEN DATE '2026-08-03'
            AND DATE '2026-08-21'
ORDER BY date;


-- ============================================================
-- 7. H4 FACTS AROUND DOCUMENTED DECISION
--
-- H4 boundary contract is already calibrated upstream.
-- No boundary discovery occurs here.
-- ============================================================

SELECT
    bar_start_utc,
    time_utc9,
    open,
    high,
    low,
    close,
    range_pips,
    close_change_pips,
    candle_direction,
    previous_high,
    previous_low,
    previous_close,
    break_previous_high,
    break_previous_low,
    has_imbalance,
    imbalance_direction,
    imbalance_low,
    imbalance_high,
    imbalance_size_pips
FROM market_bars_dukascopy_4h
WHERE
    symbol = 'USDJPY'
    AND bar_start_utc >=
        TIMESTAMPTZ '2026-08-19 00:00:00+00:00'
    AND bar_start_utc <
        TIMESTAMPTZ '2026-08-22 00:00:00+00:00'
ORDER BY bar_start_utc;


-- ============================================================
-- 8. DOCUMENTED H4 PRODUCTION FACT
--
-- Expected from upstream regression:
-- 2026-08-20 17:00 UTC
-- UP imbalance
-- low  = 158.799
-- high = 158.969
-- size = 17.0 pips
-- ============================================================

SELECT
    bar_start_utc,
    time_utc9,
    open,
    high,
    low,
    close,
    has_imbalance,
    imbalance_direction,
    imbalance_low,
    imbalance_high,
    imbalance_size,
    imbalance_size_pips
FROM market_bars_dukascopy_4h
WHERE
    symbol = 'USDJPY'
    AND bar_start_utc =
        TIMESTAMPTZ '2026-08-20 17:00:00+00:00';


-- ============================================================
-- 9. H4 PRODUCTION FACT ACCEPTANCE
--
-- This is a regression assertion, not evidence creation.
-- ============================================================

SELECT
    CASE
        WHEN COUNT(*) = 1
         AND BOOL_AND(has_imbalance)
         AND MIN(imbalance_direction) = 'UP'
         AND ABS(MIN(imbalance_low) - 158.799) < 0.000001
         AND ABS(MIN(imbalance_high) - 158.969) < 0.000001
         AND ABS(MIN(imbalance_size_pips) - 17.0) < 0.000001
        THEN 'PASS'
        ELSE 'FAIL'
    END AS h4_production_fact_check

FROM market_bars_dukascopy_4h

WHERE
    symbol = 'USDJPY'
    AND bar_start_utc =
        TIMESTAMPTZ '2026-08-20 17:00:00+00:00';
