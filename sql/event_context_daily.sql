-- ============================================================
-- Event Daily Context Model
-- ============================================================
-- Purpose:
-- Provide point-in-time daily market context for visualizing
-- how the investigated event compares with prior observations.
--
-- Grain:
-- One row = one FXCM USDJPY Daily bar.
--
-- No observations after the event date are included.
-- ============================================================


WITH parameters AS (

    SELECT
        DATE '2026-07-30' AS event_date,
        'USDJPY' AS symbol,
        'FXCM' AS reference_source

),


-- ============================================================
-- 1. Point-in-time YTD history
-- ============================================================

history AS (

    SELECT
        CAST(m.date AS DATE) AS date,

        m.source,
        m.symbol,

        m.open,
        m.high,
        m.low,
        m.close,

        m.range_pips,
        m.close_change_pips,
        ABS(m.close_change_pips) AS abs_close_change_pips,

        m.body_size_pips,
        m.body_pct_of_range,

        m.candle_direction,

        m.break_previous_high,
        m.break_previous_low,

        m.week_high_so_far,
        m.week_low_so_far,
        m.previous_week_high,
        m.previous_week_low,

        p.event_date

    FROM market_bars_tradingview_daily AS m

    CROSS JOIN parameters AS p

    WHERE m.source = p.reference_source
      AND m.symbol = p.symbol
      AND CAST(m.date AS DATE)
          BETWEEN DATE_TRUNC('year', p.event_date)
              AND p.event_date

),


-- ============================================================
-- 2. Historical ranking
-- ============================================================

ranked AS (

    SELECT
        *,

        RANK() OVER (
            ORDER BY range_pips DESC
        ) AS range_ytd_rank,

        RANK() OVER (
            ORDER BY abs_close_change_pips DESC
        ) AS abs_close_move_ytd_rank,

        COUNT(*) OVER ()
            AS ytd_observation_count

    FROM history

),


-- ============================================================
-- 3. Prior 20 completed observations
-- ============================================================

prior_20 AS (

    SELECT
        date,
        range_pips

    FROM history

    CROSS JOIN parameters AS p

    WHERE date < p.event_date

    ORDER BY date DESC

    LIMIT 20

),


-- ============================================================
-- 4. Prior-20 baseline metrics
-- ============================================================

prior_20_metrics AS (

    SELECT
        COUNT(*) AS prior_20_observation_count,

        AVG(range_pips)
            AS prior_20_avg_range_pips,

        MEDIAN(range_pips)
            AS prior_20_median_range_pips,

        MAX(range_pips)
            AS prior_20_max_range_pips

    FROM prior_20

),


-- ============================================================
-- 5. Mark prior-20 rows explicitly
-- ============================================================

ranked_with_window AS (

    SELECT
        r.*,

        p20.date IS NOT NULL
            AS is_prior_20_window

    FROM ranked AS r

    LEFT JOIN prior_20 AS p20
        ON r.date = p20.date

),


-- ============================================================
-- 6. Final Tableau-ready daily context
-- ============================================================

final AS (

    SELECT
        r.date,
        r.source AS reference_source,
        r.symbol,

        r.open,
        r.high,
        r.low,
        r.close,

        r.range_pips,
        r.close_change_pips,
        r.abs_close_change_pips,

        r.body_size_pips,
        r.body_pct_of_range,

        r.candle_direction,

        r.break_previous_high,
        r.break_previous_low,

        r.week_high_so_far,
        r.week_low_so_far,
        r.previous_week_high,
        r.previous_week_low,

        r.range_ytd_rank,
        r.abs_close_move_ytd_rank,
        r.ytd_observation_count,

        -- Event identification
        r.date = r.event_date
            AS is_event_date,

        -- Prior-20 identification
        r.is_prior_20_window,

        -- Prior-20 baseline metrics
        p.prior_20_observation_count,
        p.prior_20_avg_range_pips,
        p.prior_20_median_range_pips,
        p.prior_20_max_range_pips,

        -- Event vs Prior-20 comparisons
        CASE
            WHEN r.date = r.event_date
            THEN r.range_pips
                / NULLIF(p.prior_20_avg_range_pips, 0)
        END AS range_vs_prior_20_avg,

        CASE
            WHEN r.date = r.event_date
            THEN r.range_pips
                / NULLIF(p.prior_20_median_range_pips, 0)
        END AS range_vs_prior_20_median,

        CASE
            WHEN r.date = r.event_date
            THEN r.range_pips
                / NULLIF(p.prior_20_max_range_pips, 0)
        END AS range_vs_prior_20_max

    FROM ranked_with_window AS r

    CROSS JOIN prior_20_metrics AS p

)


SELECT *
FROM final
ORDER BY date;
