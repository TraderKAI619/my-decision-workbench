-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 07 — Evidence Timeline
--
-- PURPOSE
-- -------
-- Convert reconstructed market observations into a temporal
-- evidence timeline.
--
-- Core contract:
--
--     event_time     = bar / market event being described
--     available_time = earliest time the completed observation
--                      can safely be treated as known
--
-- IMPORTANT
-- ---------
-- No actual trade-entry timestamp has been established.
-- Therefore this file does NOT claim that any evidence was
-- available before entry.
--
-- No trading recommendation is generated here.
-- ============================================================


WITH case_parameters AS (

    SELECT
        'USDJPY'::VARCHAR
            AS symbol,

        'OANDA'::VARCHAR
            AS canonical_daily_source
),


-- ============================================================
-- Canonical Daily series with next observed bar start.
--
-- For this case reconstruction, next_bar_start_utc is used as
-- the conservative availability timestamp for completed Daily
-- observations.
-- ============================================================

daily_timeline AS (

    SELECT
        d.date,
        d.bar_start_utc,

        LEAD(d.bar_start_utc) OVER (
            ORDER BY d.bar_start_utc
        ) AS next_bar_start_utc,

        d.open,
        d.high,
        d.low,
        d.close,

        d.has_imbalance,
        d.imbalance_direction,
        d.imbalance_low,
        d.imbalance_high,
        d.imbalance_size_pips

    FROM market_bars_tradingview_daily d

    CROSS JOIN case_parameters p

    WHERE
        d.symbol = p.symbol
        AND d.source = p.canonical_daily_source
),


-- ============================================================
-- H4 series with next observed bar start.
--
-- The H4 canonical table already excludes incomplete H4 bars.
-- The next observed complete bar start is used here as the
-- confirmation availability timestamp for the case event.
-- ============================================================

h4_timeline AS (

    SELECT
        h.bar_start_utc,

        LEAD(h.bar_start_utc) OVER (
            ORDER BY h.bar_start_utc
        ) AS next_bar_start_utc,

        h.open,
        h.high,
        h.low,
        h.close,

        h.has_imbalance,
        h.imbalance_direction,
        h.imbalance_low,
        h.imbalance_high,
        h.imbalance_size_pips

    FROM market_bars_dukascopy_4h h

    CROSS JOIN case_parameters p

    WHERE
        h.symbol = p.symbol
),


-- ============================================================
-- 1. Swing low established
-- ============================================================

swing_low_event AS (

    SELECT
        10::INTEGER
            AS sequence_order,

        'OBSERVATION'::VARCHAR
            AS evidence_layer,

        'SWING_LOW'::VARCHAR
            AS evidence_type,

        CAST(date AS DATE)
            AS analytical_date,

        bar_start_utc
            AS event_time,

        next_bar_start_utc
            AS available_time,

        'Daily'::VARCHAR
            AS timeframe,

        'OANDA'::VARCHAR
            AS source,

        low
            AS value_1,

        NULL::DOUBLE
            AS value_2,

        'Documented dealing-range swing low'
            ::VARCHAR
            AS description

    FROM daily_timeline

    WHERE
        CAST(date AS DATE)
        = DATE '2026-08-03'
),


-- ============================================================
-- 2. Daily UP Imbalance formed
-- ============================================================

daily_up_imbalance_event AS (

    SELECT
        20::INTEGER
            AS sequence_order,

        'EVIDENCE'::VARCHAR
            AS evidence_layer,

        'DAILY_UP_IMBALANCE'::VARCHAR
            AS evidence_type,

        CAST(date AS DATE)
            AS analytical_date,

        bar_start_utc
            AS event_time,

        next_bar_start_utc
            AS available_time,

        'Daily'::VARCHAR
            AS timeframe,

        'OANDA'::VARCHAR
            AS source,

        imbalance_low
            AS value_1,

        imbalance_high
            AS value_2,

        'Daily Upward Imbalance formed'
            ::VARCHAR
            AS description

    FROM daily_timeline

    WHERE
        CAST(date AS DATE)
            = DATE '2026-08-11'

        AND has_imbalance = TRUE
        AND imbalance_direction = 'UP'
),


-- ============================================================
-- 3. Recovery reaches the 50% dealing-range midpoint
--
-- This is an observation supporting the recovery context.
-- It is not itself converted into a LONG signal.
-- ============================================================

recovery_50_event AS (

    SELECT
        30::INTEGER
            AS sequence_order,

        'OBSERVATION'::VARCHAR
            AS evidence_layer,

        'RECOVERY_REACHES_50_PERCENT'::VARCHAR
            AS evidence_type,

        CAST(date AS DATE)
            AS analytical_date,

        bar_start_utc
            AS event_time,

        next_bar_start_utc
            AS available_time,

        'Daily'::VARCHAR
            AS timeframe,

        'OANDA'::VARCHAR
            AS source,

        high
            AS value_1,

        (
            (
                high - 155.226
            )
            /
            (
                163.988 - 155.226
            )
            * 100
        )::DOUBLE
            AS value_2,

        'Daily recovery first reaches/exceeds 50% of documented decline'
            ::VARCHAR
            AS description

    FROM daily_timeline

    WHERE
        CAST(date AS DATE)
        = DATE '2026-08-18'
),


-- ============================================================
-- 4. Deep Daily-zone interaction / traverse
--
-- This is an interaction fact, not yet H4 confirmation.
-- ============================================================

daily_zone_interaction_event AS (

    SELECT
        40::INTEGER
            AS sequence_order,

        'OBSERVATION'::VARCHAR
            AS evidence_layer,

        'DAILY_ZONE_DEEP_INTERACTION'::VARCHAR
            AS evidence_type,

        CAST(date AS DATE)
            AS analytical_date,

        bar_start_utc
            AS event_time,

        next_bar_start_utc
            AS available_time,

        'Daily'::VARCHAR
            AS timeframe,

        'OANDA'::VARCHAR
            AS source,

        low
            AS value_1,

        close
            AS value_2,

        'Daily bar traverses the pre-existing Daily UP imbalance zone'
            ::VARCHAR
            AS description

    FROM daily_timeline

    WHERE
        CAST(date AS DATE)
        = DATE '2026-08-19'

        AND high >= 158.921
        AND low <= 158.575
),


-- ============================================================
-- 5. H4 reaction sequence recovers above Daily zone
--
-- The 13:00 UTC H4 bar closes above the Daily-zone upper
-- boundary after prior H4 trading below / through the zone.
-- ============================================================

h4_recovery_event AS (

    SELECT
        50::INTEGER
            AS sequence_order,

        'OBSERVATION'::VARCHAR
            AS evidence_layer,

        'H4_RECOVERY_ABOVE_DAILY_ZONE'::VARCHAR
            AS evidence_type,

        CAST(bar_start_utc AS DATE)
            AS analytical_date,

        bar_start_utc
            AS event_time,

        next_bar_start_utc
            AS available_time,

        'H4'::VARCHAR
            AS timeframe,

        'DUKASCOPY'::VARCHAR
            AS source,

        low
            AS value_1,

        close
            AS value_2,

        'H4 bar trades through Daily zone and closes above its upper boundary'
            ::VARCHAR
            AS description

    FROM h4_timeline

    WHERE
        bar_start_utc
        = TIMESTAMPTZ '2026-08-20 13:00:00+00:00'

        AND low <= 158.921
        AND close > 158.921
),


-- ============================================================
-- 6. New H4 UP Imbalance confirms
-- ============================================================

h4_up_imbalance_event AS (

    SELECT
        60::INTEGER
            AS sequence_order,

        'EVIDENCE'::VARCHAR
            AS evidence_layer,

        'H4_UP_IMBALANCE'::VARCHAR
            AS evidence_type,

        CAST(bar_start_utc AS DATE)
            AS analytical_date,

        bar_start_utc
            AS event_time,

        next_bar_start_utc
            AS available_time,

        'H4'::VARCHAR
            AS timeframe,

        'DUKASCOPY'::VARCHAR
            AS source,

        imbalance_low
            AS value_1,

        imbalance_high
            AS value_2,

        'New H4 Upward Imbalance forms after Daily-zone reaction sequence'
            ::VARCHAR
            AS description

    FROM h4_timeline

    WHERE
        bar_start_utc
        = TIMESTAMPTZ '2026-08-20 17:00:00+00:00'

        AND has_imbalance = TRUE
        AND imbalance_direction = 'UP'
),


timeline AS (

    SELECT * FROM swing_low_event

    UNION ALL

    SELECT * FROM daily_up_imbalance_event

    UNION ALL

    SELECT * FROM recovery_50_event

    UNION ALL

    SELECT * FROM daily_zone_interaction_event

    UNION ALL

    SELECT * FROM h4_recovery_event

    UNION ALL

    SELECT * FROM h4_up_imbalance_event
)


SELECT
    sequence_order,
    evidence_layer,
    evidence_type,
    analytical_date,
    event_time,
    available_time,
    timeframe,
    source,
    value_1,
    value_2,
    description,

    available_time
        >= event_time
        AS availability_not_before_event

FROM timeline

ORDER BY
    available_time,
    sequence_order;
