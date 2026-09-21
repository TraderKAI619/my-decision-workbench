-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 08 — Decision Context
--
-- PURPOSE
-- -------
-- Reconstruct the structured decision context surrounding the
-- documented USDJPY long decision.
--
-- This phase combines previously validated market facts into:
--
--     Observation
--         ↓
--     Hypothesis
--         ↓
--     Supporting Evidence
--         ↓
--     Wait
--         ↓
--     Lower-Timeframe Reaction
--         ↓
--     New Supporting Evidence
--         ↓
--     Documented Human Decision
--
-- IMPORTANT
-- ---------
-- SQL does NOT generate a LONG recommendation.
--
-- LONG is historical decision metadata from the documented
-- case study.
--
-- actual_entry_time remains UNKNOWN.
-- Therefore evidence-before-entry also remains UNKNOWN.
-- ============================================================


WITH case_contract AS (

    SELECT
        'USDJPY_2026_08_20_LONG'
            ::VARCHAR
            AS case_id,

        'USDJPY'
            ::VARCHAR
            AS symbol,

        'LONG'
            ::VARCHAR
            AS documented_decision_direction,

        'OANDA'
            ::VARCHAR
            AS canonical_daily_source,

        'DUKASCOPY'
            ::VARCHAR
            AS canonical_h4_source,

        DATE '2026-07-23'
            AS swing_high_date,

        163.988::DOUBLE
            AS swing_high,

        DATE '2026-08-03'
            AS swing_low_date,

        155.226::DOUBLE
            AS swing_low,

        DATE '2026-08-11'
            AS daily_up_imbalance_date,

        158.575::DOUBLE
            AS daily_zone_low,

        158.921::DOUBLE
            AS daily_zone_high,

        DATE '2026-08-20'
            AS decision_date,

        TIMESTAMPTZ '2026-08-20 17:00:00+00:00'
            AS h4_up_imbalance_bar_start_utc,

        158.799::DOUBLE
            AS h4_up_imbalance_low,

        158.969::DOUBLE
            AS h4_up_imbalance_high,

        NULL::TIMESTAMPTZ
            AS actual_entry_time
),


derived_contract AS (

    SELECT
        *,

        swing_high
            - swing_low
            AS dealing_range,

        (
            swing_high
            - swing_low
        ) * 100
            AS dealing_range_pips,

        (
            swing_high
            + swing_low
        ) / 2.0
            AS fifty_percent_midpoint

    FROM case_contract
),


-- ============================================================
-- Daily timeline with conservative completed-bar availability
-- ============================================================

daily AS (

    SELECT
        d.date,
        d.bar_start_utc,

        LEAD(d.bar_start_utc) OVER (
            ORDER BY d.bar_start_utc
        ) AS available_time,

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

    CROSS JOIN derived_contract c

    WHERE
        d.symbol = c.symbol
        AND d.source = c.canonical_daily_source
),


-- ============================================================
-- H4 timeline with completed-bar availability
-- ============================================================

h4 AS (

    SELECT
        h.bar_start_utc,

        LEAD(h.bar_start_utc) OVER (
            ORDER BY h.bar_start_utc
        ) AS available_time,

        h.open,
        h.high,
        h.low,
        h.close,

        h.candle_direction,

        h.has_imbalance,
        h.imbalance_direction,
        h.imbalance_low,
        h.imbalance_high,
        h.imbalance_size_pips

    FROM market_bars_dukascopy_4h h

    CROSS JOIN derived_contract c

    WHERE
        h.symbol = c.symbol
),


-- ============================================================
-- Observation 1:
-- documented decline / dealing range
-- ============================================================

decline_context AS (

    SELECT
        c.dealing_range,
        c.dealing_range_pips,
        c.fifty_percent_midpoint

    FROM derived_contract c
),


-- ============================================================
-- Observation 2:
-- recovery reached/exceeded 50% before decision
-- ============================================================

recovery_context AS (

    SELECT
        d.date
            AS recovery_date,

        d.bar_start_utc
            AS recovery_event_time,

        d.available_time
            AS recovery_available_time,

        d.high
            AS recovery_high,

        d.close
            AS recovery_close,

        (
            (
                d.high
                - c.swing_low
            )
            /
            NULLIF(
                c.dealing_range,
                0
            )
            * 100
        ) AS recovery_pct_high,

        (
            (
                d.close
                - c.swing_low
            )
            /
            NULLIF(
                c.dealing_range,
                0
            )
            * 100
        ) AS recovery_pct_close

    FROM daily d

    CROSS JOIN derived_contract c

    WHERE
        CAST(d.date AS DATE)
        = DATE '2026-08-18'
),


-- ============================================================
-- Supporting Evidence 1:
-- pre-existing Daily UP Imbalance
-- ============================================================

daily_imbalance_context AS (

    SELECT
        d.date
            AS daily_imbalance_date,

        d.bar_start_utc
            AS daily_imbalance_event_time,

        d.available_time
            AS daily_imbalance_available_time,

        d.imbalance_low
            AS daily_imbalance_low,

        d.imbalance_high
            AS daily_imbalance_high,

        d.imbalance_size_pips
            AS daily_imbalance_size_pips

    FROM daily d

    CROSS JOIN derived_contract c

    WHERE
        CAST(d.date AS DATE)
            = c.daily_up_imbalance_date

        AND d.has_imbalance = TRUE
        AND d.imbalance_direction = 'UP'
),


-- ============================================================
-- WAIT / interaction context:
-- Daily structure is revisited deeply.
--
-- This remains an observation.
-- It is not itself labeled bullish confirmation.
-- ============================================================

daily_interaction_context AS (

    SELECT
        d.date
            AS interaction_date,

        d.bar_start_utc
            AS interaction_event_time,

        d.available_time
            AS interaction_available_time,

        d.low
            AS interaction_low,

        d.close
            AS interaction_close,

        (
            d.high >= c.daily_zone_high
            AND d.low <= c.daily_zone_low
        ) AS traverses_daily_zone,

        (
            d.close < c.daily_zone_low
        ) AS closes_below_daily_zone

    FROM daily d

    CROSS JOIN derived_contract c

    WHERE
        CAST(d.date AS DATE)
        = DATE '2026-08-19'
),


-- ============================================================
-- Lower-timeframe reaction observation:
-- H4 trades through the Daily zone and closes above it.
-- ============================================================

h4_reaction_context AS (

    SELECT
        h.bar_start_utc
            AS h4_reaction_event_time,

        h.available_time
            AS h4_reaction_available_time,

        h.open
            AS h4_reaction_open,

        h.high
            AS h4_reaction_high,

        h.low
            AS h4_reaction_low,

        h.close
            AS h4_reaction_close,

        (
            h.low <= c.daily_zone_high
            AND h.close > c.daily_zone_high
        ) AS h4_recovers_above_daily_zone

    FROM h4 h

    CROSS JOIN derived_contract c

    WHERE
        h.bar_start_utc
        = TIMESTAMPTZ '2026-08-20 13:00:00+00:00'
),


-- ============================================================
-- Supporting Evidence 2:
-- new H4 UP Imbalance
-- ============================================================

h4_confirmation_context AS (

    SELECT
        h.bar_start_utc
            AS h4_confirmation_event_time,

        h.available_time
            AS h4_confirmation_available_time,

        h.imbalance_low
            AS h4_imbalance_low,

        h.imbalance_high
            AS h4_imbalance_high,

        h.imbalance_size_pips
            AS h4_imbalance_size_pips,

        (
            h.imbalance_low
                <= c.daily_zone_high

            AND h.imbalance_high
                >= c.daily_zone_low
        ) AS h4_imbalance_overlaps_daily_zone

    FROM h4 h

    CROSS JOIN derived_contract c

    WHERE
        h.bar_start_utc
            = c.h4_up_imbalance_bar_start_utc

        AND h.has_imbalance = TRUE
        AND h.imbalance_direction = 'UP'
),


-- ============================================================
-- Cross-provider validation for Daily structural evidence
-- ============================================================

daily_provider_validation AS (

    SELECT
        r.imbalance_consensus,
        r.imbalance_agreeing_sources,
        r.imbalance_valid_sources,
        r.imbalance_agreement_pct,
        r.imbalance_tie

    FROM provider_reconciliation_daily r

    CROSS JOIN derived_contract c

    WHERE
        r.symbol = c.symbol

        AND CAST(r.date AS DATE)
            = c.daily_up_imbalance_date
),


-- ============================================================
-- Decision-state reconstruction
--
-- This is intentionally descriptive.
--
-- "documented_decision_direction" comes from the historical
-- case study, not from an SQL-generated recommendation.
-- ============================================================

decision_state AS (

    SELECT
        c.case_id,
        c.symbol,

        c.decision_date,

        c.documented_decision_direction,

        c.actual_entry_time,

        dc.dealing_range,
        dc.dealing_range_pips,
        dc.fifty_percent_midpoint,

        rc.recovery_date,
        rc.recovery_event_time,
        rc.recovery_available_time,
        rc.recovery_high,
        rc.recovery_close,
        rc.recovery_pct_high,
        rc.recovery_pct_close,

        di.daily_imbalance_date,
        di.daily_imbalance_event_time,
        di.daily_imbalance_available_time,
        di.daily_imbalance_low,
        di.daily_imbalance_high,
        di.daily_imbalance_size_pips,

        pv.imbalance_agreeing_sources,
        pv.imbalance_valid_sources,
        pv.imbalance_agreement_pct,

        ix.interaction_date,
        ix.interaction_event_time,
        ix.interaction_available_time,
        ix.interaction_low,
        ix.interaction_close,
        ix.traverses_daily_zone,
        ix.closes_below_daily_zone,

        hr.h4_reaction_event_time,
        hr.h4_reaction_available_time,
        hr.h4_reaction_low,
        hr.h4_reaction_close,
        hr.h4_recovers_above_daily_zone,

        hc.h4_confirmation_event_time,
        hc.h4_confirmation_available_time,
        hc.h4_imbalance_low,
        hc.h4_imbalance_high,
        hc.h4_imbalance_size_pips,
        hc.h4_imbalance_overlaps_daily_zone,

        -- ----------------------------------------------------
        -- Structured state flags
        --
        -- These describe whether the documented analytical
        -- context existed. They do not generate a trade.
        -- ----------------------------------------------------

        rc.recovery_pct_high >= 50.0
            AS recovery_context_present,

        di.daily_imbalance_low IS NOT NULL
            AS daily_supporting_evidence_present,

        ix.traverses_daily_zone
            AS wait_for_reaction_context_present,

        hr.h4_recovers_above_daily_zone
            AS lower_timeframe_reaction_observed,

        hc.h4_imbalance_low IS NOT NULL
            AS h4_supporting_evidence_present,

        -- ----------------------------------------------------
        -- Evidence state immediately after H4 confirmation.
        -- ----------------------------------------------------

        (
            rc.recovery_pct_high >= 50.0

            AND di.daily_imbalance_low
                IS NOT NULL

            AND ix.traverses_daily_zone

            AND hr.h4_recovers_above_daily_zone

            AND hc.h4_imbalance_low
                IS NOT NULL
        ) AS documented_context_reconstructed,

        -- ----------------------------------------------------
        -- Critical UNKNOWN contract
        -- ----------------------------------------------------

        CASE
            WHEN c.actual_entry_time IS NULL
                THEN NULL
            ELSE
                hc.h4_confirmation_available_time
                <= c.actual_entry_time
        END AS h4_confirmation_available_before_entry

    FROM derived_contract c

    CROSS JOIN decline_context dc
    CROSS JOIN recovery_context rc
    CROSS JOIN daily_imbalance_context di
    CROSS JOIN daily_provider_validation pv
    CROSS JOIN daily_interaction_context ix
    CROSS JOIN h4_reaction_context hr
    CROSS JOIN h4_confirmation_context hc
)


SELECT
    *

FROM decision_state;
