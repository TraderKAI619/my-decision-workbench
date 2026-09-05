-- ============================================================
-- Event Attention Model
-- ============================================================
-- Purpose:
-- Explain why a specific market event deserves further
-- investigation using only information available at that time.
--
-- This model is descriptive, not predictive.
-- It does not produce BUY / SELL decisions.
--
-- Primary reference source: FXCM
-- Event date: 2026-07-30
-- ============================================================


WITH parameters AS (

    SELECT
        DATE '2026-07-30' AS event_date,
        'USDJPY' AS symbol,
        'FXCM' AS reference_source

),


-- ============================================================
-- 1. Reference market history
-- ============================================================

reference_history AS (

    SELECT
        CAST(m.date AS DATE) AS date,
        m.source,
        m.symbol,

        m.open,
        m.high,
        m.low,
        m.close,
        m.previous_close,

        m.range_pips,
        m.close_change_pips,
        ABS(m.close_change_pips) AS abs_close_change_pips,

        m.body_size_pips,
        m.body_pct_of_range,
        m.upper_wick_pips,
        m.lower_wick_pips,

        m.candle_direction,

        m.break_previous_high,
        m.break_previous_low,

        m.candle_sequence_state,
        m.candle_sequence_direction,

        m.has_imbalance,
        m.imbalance_direction,

        m.week_high_so_far,
        m.week_low_so_far,
        m.previous_week_high,
        m.previous_week_low,

        m.week_high_vs_previous_week,
        m.week_low_vs_previous_week

    FROM market_bars_tradingview_daily AS m

    CROSS JOIN parameters AS p

    WHERE m.source = p.reference_source
      AND m.symbol = p.symbol
      AND CAST(m.date AS DATE) <= p.event_date

),


-- ============================================================
-- 2. Event snapshot
-- ============================================================

event AS (

    SELECT h.*

    FROM reference_history AS h
    CROSS JOIN parameters AS p

    WHERE h.date = p.event_date

),


-- ============================================================
-- 3. YTD history available as of the event date
-- ============================================================

ytd_history AS (

    SELECT h.*

    FROM reference_history AS h
    CROSS JOIN parameters AS p

    WHERE h.date >= DATE_TRUNC('year', p.event_date)

),


-- ============================================================
-- 4. Point-in-time YTD ranking
-- ============================================================

ytd_ranked AS (

    SELECT
        date,

        RANK() OVER (
            ORDER BY range_pips DESC
        ) AS range_ytd_rank,

        RANK() OVER (
            ORDER BY abs_close_change_pips DESC
        ) AS abs_close_move_ytd_rank,

        COUNT(*) OVER () AS ytd_observation_count

    FROM ytd_history

),


event_ytd_context AS (

    SELECT r.*

    FROM ytd_ranked AS r
    CROSS JOIN parameters AS p

    WHERE r.date = p.event_date

),


-- ============================================================
-- 5. Previous 20 completed trading days
-- ============================================================

prior_20 AS (

    SELECT h.*

    FROM reference_history AS h
    CROSS JOIN parameters AS p

    WHERE h.date < p.event_date

    ORDER BY h.date DESC

    LIMIT 20

),


-- ============================================================
-- 6. Recent baseline
-- ============================================================

recent_context AS (

    SELECT
        COUNT(*) AS prior_20_observation_count,

        AVG(range_pips) AS prior_20_avg_range_pips,
        MEDIAN(range_pips) AS prior_20_median_range_pips,

        AVG(abs_close_change_pips)
            AS prior_20_avg_abs_close_move_pips,

        MEDIAN(abs_close_change_pips)
            AS prior_20_median_abs_close_move_pips

    FROM prior_20

),


-- ============================================================
-- 7. Cross-provider confidence
-- ============================================================

data_confidence AS (

    SELECT
        r.source_count,
        r.sources_present,

        r.coverage_pct,
        r.coverage_status,

        r.behavior_agreeing_sources,
        r.behavior_agreement_pct,
        r.behavior_agreement,

        r.range_pips_median,
        r.range_pips_min,
        r.range_pips_max,

        r.range_divergence_pct,
        r.range_divergence_flag

    FROM provider_reconciliation_daily AS r

    CROSS JOIN parameters AS p

    WHERE CAST(r.date AS DATE) = p.event_date
      AND r.symbol = p.symbol

),


-- ============================================================
-- 8. Final curated event record
-- ============================================================

final AS (

    SELECT
        e.date,
        e.symbol,
        e.source AS reference_source,

        -- Event snapshot
        e.open,
        e.high,
        e.low,
        e.close,
        e.previous_close,

        e.range_pips,
        e.close_change_pips,
        e.abs_close_change_pips,

        e.body_size_pips,
        e.body_pct_of_range,
        e.upper_wick_pips,
        e.lower_wick_pips,

        e.candle_direction,

        -- Market structure
        e.break_previous_high,
        e.break_previous_low,

        e.candle_sequence_state,
        e.candle_sequence_direction,

        e.has_imbalance,
        e.imbalance_direction,

        e.week_high_so_far,
        e.week_low_so_far,
        e.previous_week_high,
        e.previous_week_low,

        e.week_high_vs_previous_week,
        e.week_low_vs_previous_week,

        (e.week_high_so_far - e.previous_week_high)
            / 0.01
            AS week_high_vs_previous_week_pips,

        (e.week_low_so_far - e.previous_week_low)
            / 0.01
            AS week_low_vs_previous_week_pips,

        -- YTD context
        y.range_ytd_rank,
        y.abs_close_move_ytd_rank,
        y.ytd_observation_count,

        -- Recent context
        rc.prior_20_observation_count,

        rc.prior_20_avg_range_pips,
        rc.prior_20_median_range_pips,

        e.range_pips
            / NULLIF(rc.prior_20_avg_range_pips, 0)
            AS range_vs_prior_20_avg,

        e.range_pips
            / NULLIF(rc.prior_20_median_range_pips, 0)
            AS range_vs_prior_20_median,

        rc.prior_20_avg_abs_close_move_pips,
        rc.prior_20_median_abs_close_move_pips,

        e.abs_close_change_pips
            / NULLIF(rc.prior_20_avg_abs_close_move_pips, 0)
            AS abs_close_move_vs_prior_20_avg,

        e.abs_close_change_pips
            / NULLIF(rc.prior_20_median_abs_close_move_pips, 0)
            AS abs_close_move_vs_prior_20_median,

        -- Data confidence
        dc.source_count,
        dc.sources_present,

        dc.coverage_pct,
        dc.coverage_status,

        dc.behavior_agreeing_sources,
        dc.behavior_agreement_pct,
        dc.behavior_agreement,

        dc.range_pips_median,
        dc.range_pips_min,
        dc.range_pips_max,

        dc.range_divergence_pct,
        dc.range_divergence_flag

    FROM event AS e

    CROSS JOIN event_ytd_context AS y
    CROSS JOIN recent_context AS rc
    CROSS JOIN data_confidence AS dc

)


SELECT *
FROM final;