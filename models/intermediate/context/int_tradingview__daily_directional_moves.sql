{{ config(materialized='view') }}

with displacement_facts as (

    select *
    from {{ ref('int_tradingview__daily_displacement_facts') }}

),

with_prior_extremes as (

    select
        *,

        max(high) over (
            partition by
                source,
                provider,
                symbol,
                timeframe
            order by analytical_date
            rows between 5 preceding and 1 preceding
        ) as prior_5bar_high,

        min(low) over (
            partition by
                source,
                provider,
                symbol,
                timeframe
            order by analytical_date
            rows between 5 preceding and 1 preceding
        ) as prior_5bar_low

    from displacement_facts

),

displacement_events as (

    select
        source,
        provider,
        symbol,
        timeframe,

        analytical_date as displacement_date,
        close_change_direction as move_direction,

        true_range,
        prior_20bar_avg_true_range,
        true_range_multiple,

        close_change,
        prior_20bar_avg_abs_close_change,
        close_change_multiple,

        case
            when close_change_direction = 'DOWN'
                then prior_5bar_high
            when close_change_direction = 'UP'
                then prior_5bar_low
        end as move_origin_price,

        case
            when close_change_direction = 'DOWN'
                then high
            when close_change_direction = 'UP'
                then low
        end as displacement_near_extreme,

        case
            when close_change_direction = 'DOWN'
                then low
            when close_change_direction = 'UP'
                then high
        end as displacement_far_extreme

    from with_prior_extremes

    where true_range_multiple >= 3.0
       or close_change_multiple >= 3.0

)

select
    *,

    abs(
        move_origin_price - displacement_far_extreme
    ) as initial_move_size

from displacement_events
