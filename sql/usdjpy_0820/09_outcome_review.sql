-- ============================================================
-- USDJPY 2026-08-20 Decision Reconstruction
-- Phase 09 — Outcome Review
--
-- PURPOSE
-- -------
-- Separate:
--
-- 1. documented historical outcome state
-- 2. observable market evolution after the reconstructed
--    decision context
-- 3. facts that remain unknown
--
-- IMPORTANT
-- ---------
-- The case study documents that the position was still being
-- held and that profit-taking had not yet occurred.
--
-- It does NOT establish:
--
--     exact entry timestamp
--     exact entry price
--     exact exit timestamp
--     exact exit price
--     final realized P&L
--
-- Therefore SQL must NOT classify the trade as WIN / LOSS
-- or manufacture realized performance.
--
-- Market evolution is descriptive only.
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

        TIMESTAMPTZ '2026-08-20 21:00:00+00:00'
            AS reconstructed_context_available_time,

        TIMESTAMPTZ '2026-08-28 06:35:00+00:00'
            AS documented_review_cutoff_utc,

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


-- ============================================================
-- H1 market evolution after reconstructed context availability
-- and up to the documented review cutoff.
--
-- H1 is used because it is the finest canonical analytical
-- timeframe currently available in the project.
-- ============================================================

post_context_h1 AS (

    SELECT
        h.bar_start_utc,
        h.open,
        h.high,
        h.low,
        h.close

    FROM market_bars_dukascopy_1h h

    CROSS JOIN case_contract c

    WHERE
        h.symbol = c.symbol

        AND h.bar_start_utc
            >= c.reconstructed_context_available_time

        AND h.bar_start_utc
            <= c.documented_review_cutoff_utc
),


market_evolution AS (

    SELECT
        COUNT(*)
            AS observed_h1_bar_count,

        MIN(bar_start_utc)
            AS first_observed_h1_bar_start,

        MAX(bar_start_utc)
            AS last_observed_h1_bar_start,

        MIN(low)
            AS post_context_low,

        MAX(high)
            AS post_context_high,

        ARG_MIN(
            bar_start_utc,
            low
        ) AS post_context_low_time,

        ARG_MAX(
            bar_start_utc,
            high
        ) AS post_context_high_time

    FROM post_context_h1
),


last_observed_bar AS (

    SELECT
        bar_start_utc
            AS last_bar_start_utc,

        close
            AS last_observed_close

    FROM post_context_h1

    ORDER BY bar_start_utc DESC

    LIMIT 1
),


review_state AS (

    SELECT
        c.case_id,
        c.symbol,
        c.documented_decision_direction,

        c.reconstructed_context_available_time,
        c.documented_review_cutoff_utc,

        c.documented_position_state,
        c.documented_profit_taking_occurred,

        c.actual_entry_time,
        c.actual_entry_price,
        c.actual_exit_time,
        c.actual_exit_price,
        c.realized_pnl,

        m.observed_h1_bar_count,
        m.first_observed_h1_bar_start,
        m.last_observed_h1_bar_start,

        m.post_context_low,
        m.post_context_low_time,

        m.post_context_high,
        m.post_context_high_time,

        l.last_bar_start_utc,
        l.last_observed_close,

        -- ----------------------------------------------------
        -- These are MARKET-MOVEMENT statistics relative to
        -- context availability, NOT trade P&L.
        -- ----------------------------------------------------

        m.post_context_high
            - l.last_observed_close
            AS high_minus_last_close,

        l.last_observed_close
            - m.post_context_low
            AS last_close_minus_low,

        -- ----------------------------------------------------
        -- Knowledge-state fields
        -- ----------------------------------------------------

        c.actual_entry_time IS NULL
            AS entry_time_unknown,

        c.actual_entry_price IS NULL
            AS entry_price_unknown,

        c.actual_exit_time IS NULL
            AS exit_time_unknown,

        c.actual_exit_price IS NULL
            AS exit_price_unknown,

        c.realized_pnl IS NULL
            AS realized_pnl_unknown,

        CASE
            WHEN c.realized_pnl IS NULL
                THEN 'UNKNOWN'
            WHEN c.realized_pnl > 0
                THEN 'PROFIT'
            WHEN c.realized_pnl < 0
                THEN 'LOSS'
            ELSE 'FLAT'
        END AS final_realized_outcome

    FROM case_contract c

    CROSS JOIN market_evolution m
    CROSS JOIN last_observed_bar l
)


SELECT
    *

FROM review_state;
