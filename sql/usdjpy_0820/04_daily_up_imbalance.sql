-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 04 — Daily Upward Imbalance
--
-- PURPOSE
-- -------
-- Reconstruct the Daily Upward Imbalance that existed before
-- the documented decision.
--
-- This phase establishes:
-- 1. canonical numerical zone from OANDA
-- 2. formation date
-- 3. cross-provider structural agreement
-- 4. whether the structure existed before the decision date
--
-- IMPORTANT
-- ---------
-- Formation and later reaction are separate concepts.
--
-- This file does NOT inspect whether price later entered,
-- touched, rejected, or reacted from the zone.
-- ============================================================


WITH case_parameters AS (

    SELECT
        'USDJPY'::VARCHAR
            AS symbol,

        'OANDA'::VARCHAR
            AS canonical_daily_source,

        DATE '2026-08-03'
            AS swing_low_date,

        DATE '2026-08-20'
            AS decision_date
),


-- ============================================================
-- Canonical OANDA Daily UP imbalances available in the
-- post-swing-low / pre-decision case window.
-- ============================================================

canonical_candidates AS (

    SELECT
        d.date,
        d.bar_start_utc,
        d.open,
        d.high,
        d.low,
        d.close,

        d.has_imbalance,
        d.imbalance_direction,
        d.imbalance_low,
        d.imbalance_high,
        d.imbalance_size,
        d.imbalance_size_pips

    FROM market_bars_tradingview_daily d

    CROSS JOIN case_parameters p

    WHERE
        d.symbol = p.symbol
        AND d.source = p.canonical_daily_source

        AND CAST(d.date AS DATE)
            BETWEEN p.swing_low_date
                AND p.decision_date

        AND d.has_imbalance = TRUE
        AND d.imbalance_direction = 'UP'
),


-- ============================================================
-- Cross-provider reconciliation for the same Daily dates.
--
-- Numerical zone comes from canonical provider.
-- Structural agreement comes from reconciliation.
-- ============================================================

with_reconciliation AS (

    SELECT
        c.*,

        r.source_count,
        r.sources_present,
        r.coverage_pct,
        r.coverage_status,

        r.imbalance_consensus,
        r.imbalance_agreeing_sources,
        r.imbalance_valid_sources,
        r.imbalance_agreement_pct,
        r.imbalance_tie,

        r.behavior_agreement

    FROM canonical_candidates c

    LEFT JOIN provider_reconciliation_daily r

        ON CAST(r.date AS DATE)
            = CAST(c.date AS DATE)

        AND r.symbol = (
            SELECT symbol
            FROM case_parameters
        )
),


-- ============================================================
-- Provider-level numerical comparison.
--
-- This measures how tightly the five feeds agree on the
-- numerical zone boundaries.
-- ============================================================

provider_zone_comparison AS (

    SELECT
        CAST(d.date AS DATE)
            AS imbalance_date,

        COUNT(*) AS provider_count_with_up_imbalance,

        MIN(d.imbalance_low)
            AS imbalance_low_min,

        MEDIAN(d.imbalance_low)
            AS imbalance_low_median,

        MAX(d.imbalance_low)
            AS imbalance_low_max,

        (
            MAX(d.imbalance_low)
            - MIN(d.imbalance_low)
        ) * 100
            AS imbalance_low_spread_pips,

        MIN(d.imbalance_high)
            AS imbalance_high_min,

        MEDIAN(d.imbalance_high)
            AS imbalance_high_median,

        MAX(d.imbalance_high)
            AS imbalance_high_max,

        (
            MAX(d.imbalance_high)
            - MIN(d.imbalance_high)
        ) * 100
            AS imbalance_high_spread_pips

    FROM market_bars_tradingview_daily d

    CROSS JOIN case_parameters p

    WHERE
        d.symbol = p.symbol

        AND CAST(d.date AS DATE)
            BETWEEN p.swing_low_date
                AND p.decision_date

        AND d.has_imbalance = TRUE
        AND d.imbalance_direction = 'UP'

    GROUP BY
        CAST(d.date AS DATE)
)


SELECT
    c.date
        AS imbalance_date,

    c.bar_start_utc
        AS imbalance_bar_start_utc,

    c.imbalance_direction,

    c.imbalance_low,
    c.imbalance_high,
    c.imbalance_size,
    c.imbalance_size_pips,

    c.source_count,
    c.sources_present,
    c.coverage_pct,
    c.coverage_status,

    c.imbalance_consensus,
    c.imbalance_agreeing_sources,
    c.imbalance_valid_sources,
    c.imbalance_agreement_pct,
    c.imbalance_tie,

    z.provider_count_with_up_imbalance,

    z.imbalance_low_min,
    z.imbalance_low_median,
    z.imbalance_low_max,
    z.imbalance_low_spread_pips,

    z.imbalance_high_min,
    z.imbalance_high_median,
    z.imbalance_high_max,
    z.imbalance_high_spread_pips,

    CAST(c.date AS DATE)
        < p.decision_date
        AS formed_before_decision

FROM with_reconciliation c

JOIN provider_zone_comparison z
    ON z.imbalance_date
        = CAST(c.date AS DATE)

CROSS JOIN case_parameters p

ORDER BY c.date;
