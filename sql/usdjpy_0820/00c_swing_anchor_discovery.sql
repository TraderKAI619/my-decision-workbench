-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 0C — Swing Anchor Discovery
--
-- PURPOSE
-- -------
-- Locate the production Daily observations corresponding to
-- the documented case-study swing anchors:
--
-- documented high ≈ 163.987
-- documented low  ≈ 155.226
--
-- Discovery only.
-- No canonical source is selected here.
-- ============================================================


-- ============================================================
-- 1. ALL DAILY BARS AROUND DOCUMENTED SWING HIGH
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
    ABS(high - 163.987) AS distance_from_documented_high,
    ROUND(
        ABS(high - 163.987) * 100,
        1
    ) AS distance_pips
FROM market_bars_tradingview_daily
WHERE
    symbol = 'USDJPY'
    AND CAST(date AS DATE)
        BETWEEN DATE '2026-07-20'
            AND DATE '2026-07-27'
ORDER BY
    distance_from_documented_high,
    source
LIMIT 25;


-- ============================================================
-- 2. CLOSEST HIGH PER PROVIDER
-- ============================================================

WITH ranked AS (
    SELECT
        source,
        date,
        bar_start_utc,
        time_utc9,
        high,
        ABS(high - 163.987) AS distance,
        ROW_NUMBER() OVER (
            PARTITION BY source
            ORDER BY
                ABS(high - 163.987),
                bar_start_utc
        ) AS rn
    FROM market_bars_tradingview_daily
    WHERE
        symbol = 'USDJPY'
        AND CAST(date AS DATE)
            BETWEEN DATE '2026-07-20'
                AND DATE '2026-07-27'
)

SELECT
    source,
    date,
    bar_start_utc,
    time_utc9,
    high,
    ROUND(distance * 100, 1) AS distance_pips
FROM ranked
WHERE rn = 1
ORDER BY source;


-- ============================================================
-- 3. ALL DAILY BARS AROUND DOCUMENTED SWING LOW
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
    ABS(low - 155.226) AS distance_from_documented_low,
    ROUND(
        ABS(low - 155.226) * 100,
        1
    ) AS distance_pips
FROM market_bars_tradingview_daily
WHERE
    symbol = 'USDJPY'
    AND CAST(date AS DATE)
        BETWEEN DATE '2026-07-29'
            AND DATE '2026-08-07'
ORDER BY
    distance_from_documented_low,
    source
LIMIT 30;


-- ============================================================
-- 4. CLOSEST LOW PER PROVIDER
-- ============================================================

WITH ranked AS (
    SELECT
        source,
        date,
        bar_start_utc,
        time_utc9,
        low,
        ABS(low - 155.226) AS distance,
        ROW_NUMBER() OVER (
            PARTITION BY source
            ORDER BY
                ABS(low - 155.226),
                bar_start_utc
        ) AS rn
    FROM market_bars_tradingview_daily
    WHERE
        symbol = 'USDJPY'
        AND CAST(date AS DATE)
            BETWEEN DATE '2026-07-29'
                AND DATE '2026-08-07'
)

SELECT
    source,
    date,
    bar_start_utc,
    time_utc9,
    low,
    ROUND(distance * 100, 1) AS distance_pips
FROM ranked
WHERE rn = 1
ORDER BY source;


-- ============================================================
-- 5. PROVIDER-LEVEL DOCUMENTED RANGE MATCH
--
-- Find each provider's closest high and closest low independently,
-- then compare the resulting range with the documented range.
-- ============================================================

WITH high_ranked AS (
    SELECT
        source,
        date AS high_date,
        bar_start_utc AS high_bar_start_utc,
        high,
        ROW_NUMBER() OVER (
            PARTITION BY source
            ORDER BY
                ABS(high - 163.987),
                bar_start_utc
        ) AS rn
    FROM market_bars_tradingview_daily
    WHERE
        symbol = 'USDJPY'
        AND CAST(date AS DATE)
            BETWEEN DATE '2026-07-20'
                AND DATE '2026-07-27'
),

low_ranked AS (
    SELECT
        source,
        date AS low_date,
        bar_start_utc AS low_bar_start_utc,
        low,
        ROW_NUMBER() OVER (
            PARTITION BY source
            ORDER BY
                ABS(low - 155.226),
                bar_start_utc
        ) AS rn
    FROM market_bars_tradingview_daily
    WHERE
        symbol = 'USDJPY'
        AND CAST(date AS DATE)
            BETWEEN DATE '2026-07-29'
                AND DATE '2026-08-07'
),

anchors AS (
    SELECT
        h.source,
        h.high_date,
        h.high_bar_start_utc,
        h.high,
        l.low_date,
        l.low_bar_start_utc,
        l.low,
        h.high - l.low AS reconstructed_range,
        163.987 - 155.226 AS documented_range
    FROM high_ranked h
    JOIN low_ranked l
        ON h.source = l.source
    WHERE
        h.rn = 1
        AND l.rn = 1
)

SELECT
    source,
    high_date,
    high_bar_start_utc,
    high,
    low_date,
    low_bar_start_utc,
    low,
    reconstructed_range,
    documented_range,
    ROUND(
        ABS(
            reconstructed_range
            - documented_range
        ) * 100,
        1
    ) AS range_difference_pips
FROM anchors
ORDER BY
    range_difference_pips,
    source;
