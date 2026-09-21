-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 07.5 — Case Contract Regression
--
-- PURPOSE
-- -------
-- Establish one explicit authoritative contract for the case
-- and verify that the reconstructed SQL layers agree with it.
--
-- IMPORTANT
-- ---------
-- This phase does NOT introduce new market logic.
-- It does NOT change production tables.
-- It does NOT infer an entry timestamp.
--
-- It freezes the already validated case-study contract before
-- the Decision Context layer is built.
--
-- UNKNOWN CONTRACT
-- ----------------
-- actual_entry_time is intentionally NULL.
--
-- Therefore:
--     evidence_available_before_entry
-- remains UNKNOWN and must not be inferred.
-- ============================================================


WITH case_contract AS (

    SELECT
        'USDJPY_2026_08_20_LONG'
            ::VARCHAR
            AS case_id,

        'USDJPY'
            ::VARCHAR
            AS symbol,

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
            AS daily_up_imbalance_low,

        158.921::DOUBLE
            AS daily_up_imbalance_high,

        34.6::DOUBLE
            AS daily_up_imbalance_size_pips,

        DATE '2026-08-20'
            AS decision_date,

        TIMESTAMPTZ '2026-08-20 17:00:00+00:00'
            AS h4_up_imbalance_bar_start_utc,

        158.799::DOUBLE
            AS h4_up_imbalance_low,

        158.969::DOUBLE
            AS h4_up_imbalance_high,

        17.0::DOUBLE
            AS h4_up_imbalance_size_pips,

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
            AS fifty_percent_midpoint,

        daily_up_imbalance_high
            - daily_up_imbalance_low
            AS daily_up_imbalance_size,

        h4_up_imbalance_high
            - h4_up_imbalance_low
            AS h4_up_imbalance_size

    FROM case_contract
),


-- ============================================================
-- Production-table verification
-- ============================================================

daily_swing_high_check AS (

    SELECT
        d.high
            AS observed_swing_high

    FROM market_bars_tradingview_daily d

    CROSS JOIN derived_contract c

    WHERE
        d.symbol = c.symbol
        AND d.source = c.canonical_daily_source
        AND CAST(d.date AS DATE)
            = c.swing_high_date
),


daily_swing_low_check AS (

    SELECT
        d.low
            AS observed_swing_low

    FROM market_bars_tradingview_daily d

    CROSS JOIN derived_contract c

    WHERE
        d.symbol = c.symbol
        AND d.source = c.canonical_daily_source
        AND CAST(d.date AS DATE)
            = c.swing_low_date
),


daily_imbalance_check AS (

    SELECT
        d.imbalance_direction
            AS observed_direction,

        d.imbalance_low
            AS observed_low,

        d.imbalance_high
            AS observed_high,

        d.imbalance_size_pips
            AS observed_size_pips

    FROM market_bars_tradingview_daily d

    CROSS JOIN derived_contract c

    WHERE
        d.symbol = c.symbol
        AND d.source = c.canonical_daily_source

        AND CAST(d.date AS DATE)
            = c.daily_up_imbalance_date

        AND d.has_imbalance = TRUE
),


h4_imbalance_check AS (

    SELECT
        h.imbalance_direction
            AS observed_direction,

        h.imbalance_low
            AS observed_low,

        h.imbalance_high
            AS observed_high,

        h.imbalance_size_pips
            AS observed_size_pips

    FROM market_bars_dukascopy_4h h

    CROSS JOIN derived_contract c

    WHERE
        h.symbol = c.symbol

        AND h.bar_start_utc
            = c.h4_up_imbalance_bar_start_utc

        AND h.has_imbalance = TRUE
),


provider_agreement_check AS (

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
-- Temporal availability verification
--
-- Use the next observed canonical bar start as conservative
-- completed-bar availability.
-- ============================================================

daily_with_availability AS (

    SELECT
        d.date,
        d.bar_start_utc,

        LEAD(d.bar_start_utc) OVER (
            ORDER BY d.bar_start_utc
        ) AS available_time,

        d.has_imbalance,
        d.imbalance_direction

    FROM market_bars_tradingview_daily d

    CROSS JOIN derived_contract c

    WHERE
        d.symbol = c.symbol
        AND d.source = c.canonical_daily_source
),


h4_with_availability AS (

    SELECT
        h.bar_start_utc,

        LEAD(h.bar_start_utc) OVER (
            ORDER BY h.bar_start_utc
        ) AS available_time,

        h.has_imbalance,
        h.imbalance_direction

    FROM market_bars_dukascopy_4h h

    CROSS JOIN derived_contract c

    WHERE
        h.symbol = c.symbol
),


daily_imbalance_availability AS (

    SELECT
        d.bar_start_utc
            AS event_time,

        d.available_time

    FROM daily_with_availability d

    CROSS JOIN derived_contract c

    WHERE
        CAST(d.date AS DATE)
            = c.daily_up_imbalance_date

        AND d.has_imbalance = TRUE
        AND d.imbalance_direction = 'UP'
),


h4_imbalance_availability AS (

    SELECT
        h.bar_start_utc
            AS event_time,

        h.available_time

    FROM h4_with_availability h

    CROSS JOIN derived_contract c

    WHERE
        h.bar_start_utc
            = c.h4_up_imbalance_bar_start_utc

        AND h.has_imbalance = TRUE
        AND h.imbalance_direction = 'UP'
)


SELECT
    c.case_id,
    c.symbol,

    c.canonical_daily_source,
    c.canonical_h4_source,

    c.swing_high_date,
    c.swing_high,

    c.swing_low_date,
    c.swing_low,

    c.dealing_range,
    c.dealing_range_pips,
    c.fifty_percent_midpoint,

    c.daily_up_imbalance_date,
    c.daily_up_imbalance_low,
    c.daily_up_imbalance_high,
    c.daily_up_imbalance_size_pips,

    c.h4_up_imbalance_bar_start_utc,
    c.h4_up_imbalance_low,
    c.h4_up_imbalance_high,
    c.h4_up_imbalance_size_pips,

    da.event_time
        AS daily_imbalance_event_time,

    da.available_time
        AS daily_imbalance_available_time,

    ha.event_time
        AS h4_imbalance_event_time,

    ha.available_time
        AS h4_imbalance_available_time,

    c.actual_entry_time,

    -- --------------------------------------------------------
    -- UNKNOWN must remain UNKNOWN.
    -- --------------------------------------------------------

    CASE
        WHEN c.actual_entry_time IS NULL
            THEN NULL
        ELSE
            ha.available_time
            <= c.actual_entry_time
    END AS h4_evidence_available_before_entry,

    -- --------------------------------------------------------
    -- Production consistency checks
    -- --------------------------------------------------------

    ABS(
        sh.observed_swing_high
        - c.swing_high
    ) < 1e-9
        AS swing_high_matches_contract,

    ABS(
        sl.observed_swing_low
        - c.swing_low
    ) < 1e-9
        AS swing_low_matches_contract,

    di.observed_direction = 'UP'
        AS daily_imbalance_direction_matches,

    ABS(
        di.observed_low
        - c.daily_up_imbalance_low
    ) < 1e-9
        AS daily_imbalance_low_matches,

    ABS(
        di.observed_high
        - c.daily_up_imbalance_high
    ) < 1e-9
        AS daily_imbalance_high_matches,

    ABS(
        di.observed_size_pips
        - c.daily_up_imbalance_size_pips
    ) < 1e-6
        AS daily_imbalance_size_matches,

    hi.observed_direction = 'UP'
        AS h4_imbalance_direction_matches,

    ABS(
        hi.observed_low
        - c.h4_up_imbalance_low
    ) < 1e-9
        AS h4_imbalance_low_matches,

    ABS(
        hi.observed_high
        - c.h4_up_imbalance_high
    ) < 1e-9
        AS h4_imbalance_high_matches,

    ABS(
        hi.observed_size_pips
        - c.h4_up_imbalance_size_pips
    ) < 1e-6
        AS h4_imbalance_size_matches,

    pa.imbalance_consensus = 'UP'
        AS provider_consensus_matches,

    pa.imbalance_agreeing_sources = 5
        AND pa.imbalance_valid_sources = 5
        AND ABS(
            pa.imbalance_agreement_pct
            - 100.0
        ) < 1e-9
        AND pa.imbalance_tie = FALSE
        AS provider_agreement_matches,

    da.available_time
        >= da.event_time
        AS daily_availability_valid,

    ha.available_time
        >= ha.event_time
        AS h4_availability_valid,

    c.actual_entry_time IS NULL
        AS actual_entry_time_is_unknown

FROM derived_contract c

CROSS JOIN daily_swing_high_check sh
CROSS JOIN daily_swing_low_check sl
CROSS JOIN daily_imbalance_check di
CROSS JOIN h4_imbalance_check hi
CROSS JOIN provider_agreement_check pa
CROSS JOIN daily_imbalance_availability da
CROSS JOIN h4_imbalance_availability ha;
