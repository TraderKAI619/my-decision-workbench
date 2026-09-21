-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 06 — H4 Reaction & Confirmation
--
-- PURPOSE
-- -------
-- Reconstruct the H4 sequence around the documented
-- interaction with the pre-existing Daily Upward Imbalance.
--
-- Daily context:
--     zone = 158.575 -> 158.921
--
-- This phase asks:
--
-- 1. Which H4 bars interacted with the Daily zone?
-- 2. How did price behave around / below that zone?
-- 3. Did a NEW H4 Upward Imbalance subsequently form?
-- 4. What were its numerical boundaries?
--
-- IMPORTANT
-- ---------
-- The Daily zone and H4 structure come from independent
-- analytical layers.
--
-- This file reconstructs H4 market facts.
-- It does NOT infer an entry or trading recommendation.
-- ============================================================


WITH case_parameters AS (

    SELECT
        'USDJPY'::VARCHAR
            AS symbol,

        158.575::DOUBLE
            AS daily_zone_low,

        158.921::DOUBLE
            AS daily_zone_high,

        TIMESTAMPTZ '2026-08-19 00:00:00+00:00'
            AS h4_window_start,

        TIMESTAMPTZ '2026-08-21 21:00:00+00:00'
            AS h4_window_end
),


-- ============================================================
-- H4 facts in the documented reaction window
-- ============================================================

h4 AS (

    SELECT
        h.bar_start_utc,
        h.open,
        h.high,
        h.low,
        h.close,

        h.range_pips,
        h.close_change_pips,
        h.candle_direction,

        h.previous_high,
        h.previous_low,
        h.previous_close,

        h.break_previous_high,
        h.break_previous_low,

        h.has_imbalance,
        h.imbalance_direction,
        h.imbalance_low,
        h.imbalance_high,
        h.imbalance_size_pips,

        p.daily_zone_low,
        p.daily_zone_high,

        (
            h.high >= p.daily_zone_low
            AND h.low <= p.daily_zone_high
        ) AS overlaps_daily_zone,

        (
            h.high >= p.daily_zone_high
            AND h.low <= p.daily_zone_low
        ) AS traverses_full_daily_zone,

        (
            h.low < p.daily_zone_low
        ) AS trades_below_daily_zone,

        (
            h.high > p.daily_zone_high
        ) AS trades_above_daily_zone,

        CASE
            WHEN h.close > p.daily_zone_high
                THEN 'ABOVE'
            WHEN h.close < p.daily_zone_low
                THEN 'BELOW'
            ELSE 'INSIDE'
        END AS close_location_vs_daily_zone

    FROM market_bars_dukascopy_4h h

    CROSS JOIN case_parameters p

    WHERE
        h.symbol = p.symbol

        AND h.bar_start_utc
            BETWEEN p.h4_window_start
                AND p.h4_window_end
),


-- ============================================================
-- Sequence state
--
-- Running low lets us describe the deepest observed excursion
-- before subsequent H4 structure forms.
-- ============================================================

h4_sequence AS (

    SELECT
        *,

        MIN(low) OVER (
            ORDER BY bar_start_utc
            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW
        ) AS window_low_so_far,

        MAX(high) OVER (
            ORDER BY bar_start_utc
            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW
        ) AS window_high_so_far

    FROM h4
),


-- ============================================================
-- New H4 UP imbalances in the window
-- ============================================================

h4_up_imbalances AS (

    SELECT
        *,

        ROW_NUMBER() OVER (
            ORDER BY bar_start_utc
        ) AS up_imbalance_sequence

    FROM h4_sequence

    WHERE
        has_imbalance = TRUE
        AND imbalance_direction = 'UP'
),


-- ============================================================
-- Documented H4 confirmation structure
--
-- We do not derive this by hard-coding its boundaries.
-- We identify the documented bar timestamp, then read the
-- production-calculated market facts from the H4 table.
-- ============================================================

documented_confirmation AS (

    SELECT
        *

    FROM h4_up_imbalances

    WHERE
        bar_start_utc
        = TIMESTAMPTZ '2026-08-20 17:00:00+00:00'
),


-- ============================================================
-- Prior H4 bars relative to confirmation
--
-- This preserves the sequence without pretending that the
-- confirmation existed before its own bar completed.
-- ============================================================

pre_confirmation_context AS (

    SELECT
        MIN(h.low)
            AS pre_confirmation_window_low,

        MAX(h.high)
            AS pre_confirmation_window_high,

        COUNT(*)
            AS pre_confirmation_bar_count,

        COUNT(*) FILTER (
            WHERE h.overlaps_daily_zone
        ) AS pre_confirmation_zone_overlap_bars,

        COUNT(*) FILTER (
            WHERE h.trades_below_daily_zone
        ) AS pre_confirmation_bars_below_zone,

        COUNT(*) FILTER (
            WHERE h.candle_direction = 'UP'
        ) AS pre_confirmation_up_bars

    FROM h4_sequence h

    CROSS JOIN documented_confirmation c

    WHERE
        h.bar_start_utc
        < c.bar_start_utc
)


SELECT
    c.bar_start_utc
        AS confirmation_bar_start_utc,

    c.open
        AS confirmation_open,

    c.high
        AS confirmation_high,

    c.low
        AS confirmation_low,

    c.close
        AS confirmation_close,

    c.candle_direction
        AS confirmation_candle_direction,

    c.has_imbalance,

    c.imbalance_direction,

    c.imbalance_low,

    c.imbalance_high,

    c.imbalance_size_pips,

    c.daily_zone_low,

    c.daily_zone_high,

    p.pre_confirmation_window_low,

    p.pre_confirmation_window_high,

    p.pre_confirmation_bar_count,

    p.pre_confirmation_zone_overlap_bars,

    p.pre_confirmation_bars_below_zone,

    p.pre_confirmation_up_bars,

    c.low
        - p.pre_confirmation_window_low
        AS confirmation_low_above_prior_window_low,

    c.close
        - p.pre_confirmation_window_low
        AS confirmation_close_above_prior_window_low,

    c.imbalance_low
        >= c.daily_zone_low
        AND c.imbalance_low
            <= c.daily_zone_high
        AS h4_imbalance_low_inside_daily_zone,

    c.imbalance_high
        >= c.daily_zone_low
        AND c.imbalance_high
            <= c.daily_zone_high
        AS h4_imbalance_high_inside_daily_zone,

    (
        c.imbalance_low
        <= c.daily_zone_high
        AND c.imbalance_high
        >= c.daily_zone_low
    ) AS h4_imbalance_overlaps_daily_zone

FROM documented_confirmation c

CROSS JOIN pre_confirmation_context p;
