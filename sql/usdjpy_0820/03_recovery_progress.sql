-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 03 — Recovery Progress
--
-- PURPOSE
-- -------
-- Quantify the recovery that occurred AFTER the documented
-- swing low and BEFORE / BY the documented decision date.
--
-- This reconstructs the historical recovery context.
--
-- IMPORTANT
-- ---------
-- We do NOT assume the decision-date price itself must be at
-- the 50% midpoint.
--
-- We ask instead:
--
-- 1. How far had the recovery progressed before the decision?
-- 2. What was the maximum recovery reached?
-- 3. When was the 50% midpoint first reached?
-- 4. Was that information already historically available
--    before the documented decision?
--
-- No LONG / SHORT decision is generated here.
-- ============================================================


WITH case_parameters AS (

    SELECT
        'USDJPY'::VARCHAR
            AS symbol,

        'OANDA'::VARCHAR
            AS canonical_daily_source,

        DATE '2026-07-23'
            AS swing_high_date,

        163.988::DOUBLE
            AS swing_high,

        DATE '2026-08-03'
            AS swing_low_date,

        155.226::DOUBLE
            AS swing_low,

        DATE '2026-08-20'
            AS decision_date
),


range_parameters AS (

    SELECT
        *,

        swing_high
            - swing_low
            AS dealing_range,

        (
            swing_high
            + swing_low
        ) / 2.0
            AS fifty_percent_midpoint

    FROM case_parameters
),


-- ============================================================
-- Daily observations after the swing low
-- ============================================================

daily_recovery AS (

    SELECT
        d.date,
        d.bar_start_utc,
        d.open,
        d.high,
        d.low,
        d.close,
        d.range_pips,
        d.close_change_pips,
        d.candle_direction,

        p.swing_low,
        p.swing_high,
        p.dealing_range,
        p.fifty_percent_midpoint,

        (
            d.open
            - p.swing_low
        )
        /
        NULLIF(
            p.dealing_range,
            0
        )
        * 100
            AS recovery_pct_open,

        (
            d.high
            - p.swing_low
        )
        /
        NULLIF(
            p.dealing_range,
            0
        )
        * 100
            AS recovery_pct_high,

        (
            d.low
            - p.swing_low
        )
        /
        NULLIF(
            p.dealing_range,
            0
        )
        * 100
            AS recovery_pct_low,

        (
            d.close
            - p.swing_low
        )
        /
        NULLIF(
            p.dealing_range,
            0
        )
        * 100
            AS recovery_pct_close,

        d.high
            >= p.fifty_percent_midpoint
            AS touched_or_exceeded_50pct,

        d.close
            >= p.fifty_percent_midpoint
            AS closed_at_or_above_50pct

    FROM market_bars_tradingview_daily d

    CROSS JOIN range_parameters p

    WHERE
        d.symbol = p.symbol
        AND d.source = p.canonical_daily_source
        AND CAST(d.date AS DATE)
            BETWEEN p.swing_low_date
                AND p.decision_date
),


-- ============================================================
-- Running recovery state
--
-- This is point-in-time:
-- each row knows only the maximum recovery observed up to
-- that row.
-- ============================================================

running_recovery AS (

    SELECT
        *,

        MAX(high) OVER (
            ORDER BY date
            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW
        ) AS recovery_high_so_far,

        MAX(recovery_pct_high) OVER (
            ORDER BY date
            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW
        ) AS max_recovery_pct_so_far

    FROM daily_recovery
),


-- ============================================================
-- First historical 50% interaction
-- ============================================================

first_50pct_touch AS (

    SELECT
        MIN(
            CASE
                WHEN touched_or_exceeded_50pct
                THEN CAST(date AS DATE)
            END
        ) AS first_50pct_touch_date,

        MIN(
            CASE
                WHEN closed_at_or_above_50pct
                THEN CAST(date AS DATE)
            END
        ) AS first_50pct_close_date

    FROM daily_recovery
),


-- ============================================================
-- Maximum recovery observation available by decision date
-- ============================================================

maximum_recovery AS (

    SELECT
        date
            AS max_recovery_date,

        bar_start_utc
            AS max_recovery_bar_start_utc,

        high
            AS max_recovery_price,

        recovery_pct_high
            AS max_recovery_pct,

        ROW_NUMBER() OVER (
            ORDER BY
                recovery_pct_high DESC,
                date ASC
        ) AS rn

    FROM daily_recovery
),


decision_state AS (

    SELECT
        r.date
            AS decision_date,

        r.bar_start_utc
            AS decision_daily_bar_start_utc,

        r.open
            AS decision_daily_open,

        r.high
            AS decision_daily_high,

        r.low
            AS decision_daily_low,

        r.close
            AS decision_daily_close,

        r.recovery_pct_close
            AS decision_close_recovery_pct,

        r.recovery_high_so_far,

        r.max_recovery_pct_so_far

    FROM running_recovery r

    CROSS JOIN range_parameters p

    WHERE
        CAST(r.date AS DATE)
        = p.decision_date
)

SELECT
    p.symbol,
    p.canonical_daily_source,

    p.swing_high_date,
    p.swing_high,

    p.swing_low_date,
    p.swing_low,

    p.dealing_range,
    p.fifty_percent_midpoint,

    f.first_50pct_touch_date,
    f.first_50pct_close_date,

    m.max_recovery_date,
    m.max_recovery_bar_start_utc,
    m.max_recovery_price,
    m.max_recovery_pct,

    d.decision_date,
    d.decision_daily_bar_start_utc,
    d.decision_daily_close,
    d.decision_close_recovery_pct,

    d.recovery_high_so_far,
    d.max_recovery_pct_so_far,

    f.first_50pct_touch_date
        IS NOT NULL
        AS recovery_reached_50pct_before_or_by_decision,

    f.first_50pct_touch_date
        < p.decision_date
        AS recovery_reached_50pct_before_decision

FROM range_parameters p

CROSS JOIN first_50pct_touch f

JOIN maximum_recovery m
    ON m.rn = 1

CROSS JOIN decision_state d;
