{{ config(materialized='view') }}

with bars as (

    select *
    from {{ ref('int_tradingview__canonical_daily') }}

),

instruments as (

    select
        symbol,
        pip_size
    from {{ ref('fx_instruments') }}

),

with_instrument as (

    select
        b.*,
        i.pip_size

    from bars b

    inner join instruments i
        on b.symbol = i.symbol

),

with_previous as (

    select
        *,

        lag(open, 1) over (
            partition by source, provider, symbol, timeframe
            order by analytical_date
        ) as previous_open,

        lag(high, 1) over (
            partition by source, provider, symbol, timeframe
            order by analytical_date
        ) as previous_high,

        lag(low, 1) over (
            partition by source, provider, symbol, timeframe
            order by analytical_date
        ) as previous_low,

        lag(close, 1) over (
            partition by source, provider, symbol, timeframe
            order by analytical_date
        ) as previous_close,

        lag(high, 2) over (
            partition by source, provider, symbol, timeframe
            order by analytical_date
        ) as candle_1_high,

        lag(low, 2) over (
            partition by source, provider, symbol, timeframe
            order by analytical_date
        ) as candle_1_low

    from with_instrument

),

facts as (

    select
        *,

        high - low as `range`,
        safe_divide(high - low, pip_size) as range_pips,

        abs(close - open) as body_size,
        safe_divide(abs(close - open), pip_size) as body_size_pips,

        high - greatest(open, close) as upper_wick,
        safe_divide(
            high - greatest(open, close),
            pip_size
        ) as upper_wick_pips,

        least(open, close) - low as lower_wick,
        safe_divide(
            least(open, close) - low,
            pip_size
        ) as lower_wick_pips,

        safe_divide(
            abs(close - open),
            high - low
        ) as body_pct_of_range,

        safe_divide(
            high - greatest(open, close),
            high - low
        ) as upper_wick_pct_of_range,

        safe_divide(
            least(open, close) - low,
            high - low
        ) as lower_wick_pct_of_range,

        close - previous_close as close_change,

        safe_divide(
            close - previous_close,
            pip_size
        ) as close_change_pips,

        case
            when previous_close is null then null
            else high > previous_high
        end as break_previous_high,

        case
            when previous_close is null then null
            else low < previous_low
        end as break_previous_low,

        case
            when close > open then 'UP'
            when close < open then 'DOWN'
            else 'FLAT'
        end as candle_direction,

        case
            when candle_1_high < low
              or candle_1_low > high
            then true
            else false
        end as has_imbalance,

        case
            when candle_1_high < low then 'UP'
            when candle_1_low > high then 'DOWN'
            else null
        end as imbalance_direction,

        case
            when candle_1_high < low then low
            when candle_1_low > high then candle_1_low
            else null
        end as imbalance_high,

        case
            when candle_1_high < low then candle_1_high
            when candle_1_low > high then high
            else null
        end as imbalance_low

    from with_previous

),

final as (

    select
        *,

        imbalance_high - imbalance_low as imbalance_size,

        safe_divide(
            imbalance_high - imbalance_low,
            pip_size
        ) as imbalance_size_pips

    from facts

)

select *
from final
