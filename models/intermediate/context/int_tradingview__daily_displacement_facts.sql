{{ config(materialized='view') }}

with daily as (

    select
        source,
        provider,
        symbol,
        timeframe,
        analytical_date,
        open,
        high,
        low,
        close,

        lag(close) over (
            partition by
                source,
                provider,
                symbol,
                timeframe
            order by analytical_date
        ) as previous_close

    from {{ ref('int_tradingview__daily_market_facts') }}

),

true_ranges as (

    select
        *,

        greatest(
            high - low,
            abs(high - previous_close),
            abs(low - previous_close)
        ) as true_range,

        close - previous_close as close_change,

        abs(close - previous_close) as abs_close_change

    from daily

),

baselines as (

    select
        *,

        avg(true_range) over (
            partition by
                source,
                provider,
                symbol,
                timeframe
            order by analytical_date
            rows between 20 preceding and 1 preceding
        ) as prior_20bar_avg_true_range,

        avg(abs_close_change) over (
            partition by
                source,
                provider,
                symbol,
                timeframe
            order by analytical_date
            rows between 20 preceding and 1 preceding
        ) as prior_20bar_avg_abs_close_change

    from true_ranges

)

select
    source,
    provider,
    symbol,
    timeframe,
    analytical_date,

    open,
    high,
    low,
    close,
    previous_close,

    true_range,
    prior_20bar_avg_true_range,

    safe_divide(
        true_range,
        prior_20bar_avg_true_range
    ) as true_range_multiple,

    close_change,
    abs_close_change,
    prior_20bar_avg_abs_close_change,

    safe_divide(
        abs_close_change,
        prior_20bar_avg_abs_close_change
    ) as close_change_multiple,

    case
        when close_change > 0 then 'UP'
        when close_change < 0 then 'DOWN'
        else 'FLAT'
    end as close_change_direction

from baselines
