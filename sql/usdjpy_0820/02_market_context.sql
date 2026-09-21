-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 02 — Market Context
--
-- PURPOSE
-- -------
-- Reconstruct the objective Daily market context underlying
-- the documented recovery hypothesis.
--
-- IMPORTANT
-- ---------
-- This file creates OBSERVATIONS, not evidence.
--
-- It answers:
-- 1. How large was the documented decline?
-- 2. Where is the 50% midpoint?
-- 3. How far had price recovered by the decision date?
--
-- No LONG / SHORT interpretation is created here.
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


-- ============================================================
-- Canonical Daily bars for the case window
-- ============================================================

daily AS (

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
        d.break_previous_high,
        d.break_previous_low

    FROM market_bars_tradingview_daily d

    CROSS JOIN case_parameters p

    WHERE
        d.symbol = p.symbol
        AND d.source = p.canonical_daily_source
        AND CAST(d.date AS DATE)
            BETWEEN p.swing_high_date
                AND p.decision_date
),


-- ============================================================
-- Decision-date Daily observation
--
-- IMPORTANT:
-- This is the Daily bar identified by the analytical date.
-- We expose its OHLC rather than silently choosing one price.
-- ============================================================

decision_daily AS (

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
        d.break_previous_high,
        d.break_previous_low

    FROM daily d

    CROSS JOIN case_parameters p

    WHERE
        CAST(d.date AS DATE)
        = p.decision_date
),


-- ============================================================
-- Range mathematics
-- ============================================================

context AS (

    SELECT
        p.symbol,
        p.canonical_daily_source,

        p.swing_high_date,
        p.swing_high,

        p.swing_low_date,
        p.swing_low,

        p.decision_date,

        dd.bar_start_utc
            AS decision_daily_bar_start_utc,

        dd.open
            AS decision_daily_open,

        dd.high
            AS decision_daily_high,

        dd.low
            AS decision_daily_low,

        dd.close
            AS decision_daily_close,

        p.swing_high
            - p.swing_low
            AS decline_price_range,

        (
            p.swing_high
            - p.swing_low
        ) * 100
            AS decline_range_pips,

        (
            p.swing_high
            + p.swing_low
        ) / 2.0
            AS fifty_percent_midpoint,

        dd.open
            - p.swing_low
            AS recovery_from_low_at_daily_open,

        (
            dd.open
            - p.swing_low
        )
        /
        NULLIF(
            p.swing_high
            - p.swing_low,
            0
        )
        * 100
            AS recovery_pct_at_daily_open,

        dd.high
            - p.swing_low
            AS recovery_from_low_at_daily_high,

        (
            dd.high
            - p.swing_low
        )
        /
        NULLIF(
            p.swing_high
            - p.swing_low,
            0
        )
        * 100
            AS recovery_pct_at_daily_high,

        dd.low
            - p.swing_low
            AS recovery_from_low_at_daily_low,

        (
            dd.low
            - p.swing_low
        )
        /
        NULLIF(
            p.swing_high
            - p.swing_low,
            0
        )
        * 100
            AS recovery_pct_at_daily_low,

        dd.close
            - p.swing_low
            AS recovery_from_low_at_daily_close,

        (
            dd.close
            - p.swing_low
        )
        /
        NULLIF(
            p.swing_high
            - p.swing_low,
            0
        )
        * 100
            AS recovery_pct_at_daily_close,

        dd.high
            >= (
                p.swing_high
                + p.swing_low
            ) / 2.0
            AS daily_high_reached_50pct,

        dd.close
            >= (
                p.swing_high
                + p.swing_low
            ) / 2.0
            AS daily_close_reached_50pct

    FROM case_parameters p

    JOIN decision_daily dd
        ON TRUE
)

SELECT *
FROM context;
