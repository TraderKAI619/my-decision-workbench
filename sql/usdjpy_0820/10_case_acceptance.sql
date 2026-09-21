-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 10 — End-to-End Case Acceptance
--
-- PURPOSE
-- -------
-- Final acceptance test for the reconstructed case.
--
-- This file introduces NO new decision logic.
--
-- It verifies that the production analytical tables support
-- the complete documented reconstruction:
--
--     swing / dealing range
--         ↓
--     recovery context
--         ↓
--     Daily UP imbalance
--         ↓
--     Daily-zone interaction
--         ↓
--     H4 reaction
--         ↓
--     H4 UP imbalance
--         ↓
--     temporal availability
--         ↓
--     documented human decision context
--         ↓
--     explicit outcome knowledge boundary
--
-- CRITICAL CONTRACT
-- -----------------
-- SQL reconstructs the context surrounding a documented
-- historical LONG decision.
--
-- SQL does NOT generate the LONG decision.
--
-- actual_entry_time = UNKNOWN
-- realized_pnl      = UNKNOWN
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

        34.6::DOUBLE
            AS daily_zone_size_pips,

        DATE '2026-08-18'
            AS recovery_50_date,

        DATE '2026-08-19'
            AS deep_interaction_date,

        TIMESTAMPTZ '2026-08-20 13:00:00+00:00'
            AS h4_reaction_bar_start_utc,

        TIMESTAMPTZ '2026-08-20 17:00:00+00:00'
            AS h4_confirmation_bar_start_utc,

        TIMESTAMPTZ '2026-08-20 21:00:00+00:00'
            AS h4_confirmation_available_time,

        158.799::DOUBLE
            AS h4_imbalance_low,

        158.969::DOUBLE
            AS h4_imbalance_high,

        17.0::DOUBLE
            AS h4_imbalance_size_pips,

        NULL::TIMESTAMPTZ
            AS actual_entry_time,

        NULL::DOUBLE
            AS actual_entry_price,

        NULL::TIMESTAMPTZ
            AS actual_exit_time,

        NULL::DOUBLE
            AS actual_exit_price,

        NULL::DOUBLE
            AS realized_pnl,

        'STILL_HOLDING'
            ::VARCHAR
            AS documented_position_state,

        FALSE
            AS documented_profit_taking_occurred
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
            AS midpoint

    FROM case_contract
),


-- ============================================================
-- Canonical Daily timeline
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
-- Canonical H4 timeline
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
-- Swing anchors
-- ============================================================

swing_high_fact AS (

    SELECT
        d.high

    FROM daily d

    CROSS JOIN derived_contract c

    WHERE
        CAST(d.date AS DATE)
        = c.swing_high_date
),


swing_low_fact AS (

    SELECT
        d.low

    FROM daily d

    CROSS JOIN derived_contract c

    WHERE
        CAST(d.date AS DATE)
        = c.swing_low_date
),


-- ============================================================
-- Recovery context
-- ============================================================

recovery_fact AS (

    SELECT
        d.high,
        d.close,
        d.available_time,

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
        = c.recovery_50_date
),


-- ============================================================
-- Daily supporting evidence
-- ============================================================

daily_imbalance_fact AS (

    SELECT
        d.bar_start_utc
            AS event_time,

        d.available_time,

        d.imbalance_direction,
        d.imbalance_low,
        d.imbalance_high,
        d.imbalance_size_pips

    FROM daily d

    CROSS JOIN derived_contract c

    WHERE
        CAST(d.date AS DATE)
            = c.daily_up_imbalance_date

        AND d.has_imbalance = TRUE
),


-- ============================================================
-- Cross-provider validation
-- ============================================================

provider_fact AS (

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
-- Daily-zone interaction
-- ============================================================

interaction_fact AS (

    SELECT
        d.bar_start_utc
            AS event_time,

        d.available_time,

        d.high,
        d.low,
        d.close,

        (
            d.high >= c.daily_zone_high
            AND d.low <= c.daily_zone_low
        ) AS traverses_zone,

        (
            d.close < c.daily_zone_low
        ) AS closes_below_zone

    FROM daily d

    CROSS JOIN derived_contract c

    WHERE
        CAST(d.date AS DATE)
        = c.deep_interaction_date
),


-- ============================================================
-- H4 reaction
-- ============================================================

h4_reaction_fact AS (

    SELECT
        h.bar_start_utc
            AS event_time,

        h.available_time,

        h.open,
        h.high,
        h.low,
        h.close,

        (
            h.low <= c.daily_zone_high
            AND h.close > c.daily_zone_high
        ) AS recovers_above_daily_zone

    FROM h4 h

    CROSS JOIN derived_contract c

    WHERE
        h.bar_start_utc
        = c.h4_reaction_bar_start_utc
),


-- ============================================================
-- H4 confirmation
-- ============================================================

h4_confirmation_fact AS (

    SELECT
        h.bar_start_utc
            AS event_time,

        h.available_time,

        h.imbalance_direction,
        h.imbalance_low,
        h.imbalance_high,
        h.imbalance_size_pips,

        (
            h.imbalance_low <= c.daily_zone_high
            AND h.imbalance_high >= c.daily_zone_low
        ) AS overlaps_daily_zone

    FROM h4 h

    CROSS JOIN derived_contract c

    WHERE
        h.bar_start_utc
            = c.h4_confirmation_bar_start_utc

        AND h.has_imbalance = TRUE
),


-- ============================================================
-- Final acceptance state
-- ============================================================

acceptance AS (

    SELECT
        c.case_id,
        c.symbol,
        c.documented_decision_direction,

        -- ----------------------------------------------------
        -- Case anchors
        -- ----------------------------------------------------

        ABS(
            sh.high
            - c.swing_high
        ) < 1e-9
            AS swing_high_valid,

        ABS(
            sl.low
            - c.swing_low
        ) < 1e-9
            AS swing_low_valid,

        ABS(
            c.dealing_range_pips
            - 876.2
        ) < 1e-6
            AS dealing_range_valid,

        ABS(
            c.midpoint
            - 159.607
        ) < 1e-9
            AS midpoint_valid,

        -- ----------------------------------------------------
        -- Recovery
        -- ----------------------------------------------------

        rf.recovery_pct_high >= 50.0
            AS recovery_50_valid,

        rf.available_time
            < c.h4_confirmation_available_time
            AS recovery_available_before_h4_confirmation,

        -- ----------------------------------------------------
        -- Daily evidence
        -- ----------------------------------------------------

        dif.imbalance_direction = 'UP'
            AS daily_imbalance_direction_valid,

        ABS(
            dif.imbalance_low
            - c.daily_zone_low
        ) < 1e-9
            AS daily_zone_low_valid,

        ABS(
            dif.imbalance_high
            - c.daily_zone_high
        ) < 1e-9
            AS daily_zone_high_valid,

        ABS(
            dif.imbalance_size_pips
            - c.daily_zone_size_pips
        ) < 1e-6
            AS daily_zone_size_valid,

        dif.available_time
            < c.h4_confirmation_available_time
            AS daily_evidence_available_before_h4_confirmation,

        -- ----------------------------------------------------
        -- Cross-provider agreement
        -- ----------------------------------------------------

        pf.imbalance_consensus = 'UP'
            AS provider_consensus_valid,

        (
            pf.imbalance_agreeing_sources = 5
            AND pf.imbalance_valid_sources = 5
            AND ABS(
                pf.imbalance_agreement_pct
                - 100.0
            ) < 1e-9
            AND pf.imbalance_tie = FALSE
        ) AS provider_agreement_valid,

        -- ----------------------------------------------------
        -- Interaction / WAIT state
        -- ----------------------------------------------------

        ix.traverses_zone
            AS daily_interaction_valid,

        ix.closes_below_zone
            AS deep_interaction_close_below_valid,

        ix.available_time
            < c.h4_confirmation_available_time
            AS interaction_available_before_h4_confirmation,

        -- ----------------------------------------------------
        -- H4 reaction
        -- ----------------------------------------------------

        hr.recovers_above_daily_zone
            AS h4_reaction_valid,

        hr.available_time
            <= c.h4_confirmation_bar_start_utc
            AS h4_reaction_available_before_confirmation_event,

        -- ----------------------------------------------------
        -- H4 supporting evidence
        -- ----------------------------------------------------

        hc.imbalance_direction = 'UP'
            AS h4_imbalance_direction_valid,

        ABS(
            hc.imbalance_low
            - c.h4_imbalance_low
        ) < 1e-9
            AS h4_imbalance_low_valid,

        ABS(
            hc.imbalance_high
            - c.h4_imbalance_high
        ) < 1e-9
            AS h4_imbalance_high_valid,

        ABS(
            hc.imbalance_size_pips
            - c.h4_imbalance_size_pips
        ) < 1e-6
            AS h4_imbalance_size_valid,

        hc.overlaps_daily_zone
            AS h4_daily_zone_overlap_valid,

        hc.available_time
            = c.h4_confirmation_available_time
            AS h4_confirmation_availability_valid,

        -- ----------------------------------------------------
        -- Temporal integrity
        -- ----------------------------------------------------

        (
            dif.available_time
                <= rf.available_time

            AND rf.available_time
                <= ix.available_time

            AND ix.available_time
                <= hr.available_time

            AND hr.available_time
                <= hc.available_time
        ) AS evidence_temporal_order_valid,

        -- ----------------------------------------------------
        -- Historical decision metadata
        -- ----------------------------------------------------

        c.documented_decision_direction = 'LONG'
            AS documented_direction_valid,

        -- ----------------------------------------------------
        -- Unknown entry contract
        -- ----------------------------------------------------

        c.actual_entry_time IS NULL
            AS actual_entry_time_unknown,

        c.actual_entry_price IS NULL
            AS actual_entry_price_unknown,

        CASE
            WHEN c.actual_entry_time IS NULL
                THEN NULL
            ELSE
                hc.available_time
                <= c.actual_entry_time
        END AS h4_confirmation_before_entry,

        -- ----------------------------------------------------
        -- Outcome knowledge boundary
        -- ----------------------------------------------------

        c.documented_position_state
            = 'STILL_HOLDING'
            AS documented_position_state_valid,

        c.documented_profit_taking_occurred
            = FALSE
            AS documented_no_profit_taking_valid,

        c.actual_exit_time IS NULL
            AS actual_exit_time_unknown,

        c.actual_exit_price IS NULL
            AS actual_exit_price_unknown,

        c.realized_pnl IS NULL
            AS realized_pnl_unknown

    FROM derived_contract c

    CROSS JOIN swing_high_fact sh
    CROSS JOIN swing_low_fact sl
    CROSS JOIN recovery_fact rf
    CROSS JOIN daily_imbalance_fact dif
    CROSS JOIN provider_fact pf
    CROSS JOIN interaction_fact ix
    CROSS JOIN h4_reaction_fact hr
    CROSS JOIN h4_confirmation_fact hc
)


SELECT
    *

FROM acceptance;
