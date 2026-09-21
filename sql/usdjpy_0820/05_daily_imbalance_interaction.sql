-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 05 — Daily Imbalance Interaction
--
-- PURPOSE
-- -------
-- Reconstruct how price interacted with the previously formed
-- Daily Upward Imbalance.
--
-- IMPORTANT
-- ---------
-- Interaction is NOT the same as reaction.
--
-- This phase establishes:
-- 1. when price first returned to the zone after formation
-- 2. whether the bar touched / entered / traversed the zone
-- 3. where the bar closed relative to the zone
-- 4. whether Daily data alone is sufficient to claim a
--    bullish reaction
--
-- H4 reaction / confirmation is intentionally deferred to
-- the next phase.
-- ============================================================


WITH case_parameters AS (

    SELECT
        'USDJPY'::VARCHAR
            AS symbol,

        'OANDA'::VARCHAR
            AS canonical_daily_source,

        DATE '2026-08-11'
            AS imbalance_formation_date,

        158.575::DOUBLE
            AS imbalance_low,

        158.921::DOUBLE
            AS imbalance_high,

        DATE '2026-08-20'
            AS decision_date
),


-- ============================================================
-- Daily bars AFTER imbalance formation
-- ============================================================

post_formation_daily AS (

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

        p.imbalance_low,
        p.imbalance_high,

        -- Any overlap between candle range and zone.
        (
            d.high >= p.imbalance_low
            AND d.low <= p.imbalance_high
        ) AS overlaps_zone,

        -- Candle trades inside the zone from above.
        (
            d.low <= p.imbalance_high
            AND d.high >= p.imbalance_high
        ) AS reaches_zone_from_above,

        -- Candle reaches the lower boundary.
        (
            d.low <= p.imbalance_low
        ) AS reaches_or_breaks_zone_low,

        -- Candle spans both numerical boundaries.
        (
            d.high >= p.imbalance_high
            AND d.low <= p.imbalance_low
        ) AS traverses_full_zone,

        -- Close-location facts.
        (
            d.close > p.imbalance_high
        ) AS closes_above_zone,

        (
            d.close >= p.imbalance_low
            AND d.close <= p.imbalance_high
        ) AS closes_inside_zone,

        (
            d.close < p.imbalance_low
        ) AS closes_below_zone,

        -- Distance from upper boundary to candle low.
        (
            p.imbalance_high
            - d.low
        ) * 100
            AS penetration_from_zone_high_pips,

        -- Zone width.
        (
            p.imbalance_high
            - p.imbalance_low
        ) * 100
            AS zone_size_pips

    FROM market_bars_tradingview_daily d

    CROSS JOIN case_parameters p

    WHERE
        d.symbol = p.symbol
        AND d.source = p.canonical_daily_source

        AND CAST(d.date AS DATE)
            > p.imbalance_formation_date

        AND CAST(d.date AS DATE)
            <= p.decision_date
),


-- ============================================================
-- Add interaction ordering
-- ============================================================

interaction_sequence AS (

    SELECT
        *,

        ROW_NUMBER() OVER (
            ORDER BY date
        ) AS post_formation_bar_number,

        SUM(
            CASE
                WHEN overlaps_zone
                THEN 1
                ELSE 0
            END
        ) OVER (
            ORDER BY date
            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW
        ) AS interaction_count_so_far

    FROM post_formation_daily
),


-- ============================================================
-- First post-formation interaction
-- ============================================================

first_interaction AS (

    SELECT
        *,

        ROW_NUMBER() OVER (
            ORDER BY date
        ) AS interaction_rank

    FROM interaction_sequence

    WHERE overlaps_zone = TRUE
),


-- ============================================================
-- Classify only the OBSERVED interaction geometry.
--
-- This is descriptive.
-- It is NOT a directional trading signal.
-- ============================================================

classified AS (

    SELECT
        *,

        CASE

            WHEN traverses_full_zone
                 AND closes_below_zone
                THEN 'FULL_TRAVERSE_CLOSE_BELOW'

            WHEN traverses_full_zone
                 AND closes_inside_zone
                THEN 'FULL_TRAVERSE_CLOSE_INSIDE'

            WHEN reaches_zone_from_above
                 AND closes_above_zone
                THEN 'TOUCH_OR_ENTER_CLOSE_ABOVE'

            WHEN overlaps_zone
                 AND closes_inside_zone
                THEN 'OVERLAP_CLOSE_INSIDE'

            WHEN overlaps_zone
                THEN 'OTHER_ZONE_OVERLAP'

            ELSE 'NO_INTERACTION'

        END AS interaction_geometry

    FROM first_interaction

    WHERE interaction_rank = 1
)


SELECT
    date
        AS first_interaction_date,

    bar_start_utc
        AS first_interaction_bar_start_utc,

    open,
    high,
    low,
    close,

    imbalance_low,
    imbalance_high,
    zone_size_pips,

    overlaps_zone,
    reaches_zone_from_above,
    reaches_or_breaks_zone_low,
    traverses_full_zone,

    closes_above_zone,
    closes_inside_zone,
    closes_below_zone,

    penetration_from_zone_high_pips,

    penetration_from_zone_high_pips
        / NULLIF(
            zone_size_pips,
            0
        )
        * 100
        AS penetration_vs_zone_size_pct,

    interaction_geometry,

    interaction_count_so_far,

    -- --------------------------------------------------------
    -- Semantic guardrail:
    --
    -- A full traverse with a close below the zone is NOT,
    -- by itself, sufficient Daily evidence of a bullish
    -- reaction.
    -- --------------------------------------------------------

    CASE

        WHEN traverses_full_zone
             AND closes_below_zone
            THEN FALSE

        WHEN reaches_zone_from_above
             AND closes_above_zone
            THEN TRUE

        ELSE NULL

    END AS daily_bar_alone_supports_bullish_reaction

FROM classified;
