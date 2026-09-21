-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 01 — Case Parameters
--
-- PURPOSE
-- -------
-- Define the fixed analytical contract for this documented case.
--
-- This file contains PARAMETERS, not evidence.
-- ============================================================


WITH case_parameters AS (

    SELECT

        -- ----------------------------------------------------
        -- Case identity
        -- ----------------------------------------------------

        'USDJPY'::VARCHAR
            AS symbol,

        'OANDA'::VARCHAR
            AS canonical_daily_source,


        -- ----------------------------------------------------
        -- Documented Daily dealing-range anchors
        --
        -- Production validation:
        -- OANDA Daily high = 163.988
        -- OANDA Daily low  = 155.226
        --
        -- PDF reference:
        -- high ≈ 163.987
        -- low  ≈ 155.226
        -- ----------------------------------------------------

        DATE '2026-07-23'
            AS swing_high_date,

        163.988::DOUBLE
            AS swing_high,

        DATE '2026-08-03'
            AS swing_low_date,

        155.226::DOUBLE
            AS swing_low,


        -- ----------------------------------------------------
        -- Daily Upward Imbalance
        --
        -- Canonical numerical representation: OANDA
        -- Cross-provider validation remains separate.
        -- ----------------------------------------------------

        DATE '2026-08-11'
            AS daily_up_imbalance_date,

        158.575::DOUBLE
            AS daily_up_imbalance_low,

        158.921::DOUBLE
            AS daily_up_imbalance_high,

        34.6::DOUBLE
            AS daily_up_imbalance_size_pips,


        -- ----------------------------------------------------
        -- Documented decision date
        -- ----------------------------------------------------

        DATE '2026-08-20'
            AS decision_date,


        -- ----------------------------------------------------
        -- Canonical H4 source
        --
        -- H4 is generated from validated Dukascopy H1.
        -- ----------------------------------------------------

        'DUKASCOPY'::VARCHAR
            AS canonical_h4_source,


        -- ----------------------------------------------------
        -- Documented H4 Upward Imbalance
        -- ----------------------------------------------------

        TIMESTAMPTZ '2026-08-20 17:00:00+00:00'
            AS h4_up_imbalance_bar_start_utc,

        158.799::DOUBLE
            AS h4_up_imbalance_low,

        158.969::DOUBLE
            AS h4_up_imbalance_high,

        17.0::DOUBLE
            AS h4_up_imbalance_size_pips
)

SELECT

    *,

    swing_high
        - swing_low
        AS dealing_range,

    (
        swing_high
        + swing_low
    ) / 2.0
        AS dealing_range_midpoint,

    (
        swing_high
        - swing_low
    ) * 100
        AS dealing_range_pips,

    daily_up_imbalance_high
        - daily_up_imbalance_low
        AS daily_up_imbalance_size,

    h4_up_imbalance_high
        - h4_up_imbalance_low
        AS h4_up_imbalance_size

FROM case_parameters;
