{{ config(materialized='view') }}

with events as (

    select
        *,

        lag(displacement_date) over (
            partition by
                source,
                provider,
                symbol,
                timeframe,
                move_direction
            order by displacement_date
        ) as previous_same_direction_event_date

    from {{ ref('int_tradingview__daily_directional_moves') }}

),

event_groups as (

    select
        *,

        case
            when previous_same_direction_event_date is null then 1

            when date_diff(
                displacement_date,
                previous_same_direction_event_date,
                day
            ) <= 3 then 0

            else 1
        end as starts_new_move

    from events

),

numbered_moves as (

    select
        *,

        sum(starts_new_move) over (
            partition by
                source,
                provider,
                symbol,
                timeframe,
                move_direction
            order by displacement_date
            rows between unbounded preceding and current row
        ) as move_sequence

    from event_groups

),

moves as (

    select
        source,
        provider,
        symbol,
        timeframe,
        move_direction,
        move_sequence,

        min(displacement_date) as impulse_start_date,

        array_agg(
            struct(
                displacement_date,
                move_origin_price
            )
            order by displacement_date
            limit 1
        )[offset(0)].move_origin_price as move_origin_price

    from numbered_moves

    group by
        source,
        provider,
        symbol,
        timeframe,
        move_direction,
        move_sequence

),

daily as (

    select
        source,
        provider,
        symbol,
        timeframe,
        analytical_date,
        high,
        low,
        close

    from {{ ref('int_tradingview__daily_market_facts') }}

),

tracking as (

    select
        m.source,
        m.provider,
        m.symbol,
        m.timeframe,
        m.move_direction,
        m.move_sequence,
        m.impulse_start_date,
        m.move_origin_price,

        d.analytical_date,
        d.high,
        d.low,
        d.close,

        case
            when m.move_direction = 'DOWN' then
                min(d.low) over (
                    partition by
                        m.source,
                        m.provider,
                        m.symbol,
                        m.timeframe,
                        m.move_direction,
                        m.move_sequence
                    order by d.analytical_date
                    rows between unbounded preceding and current row
                )

            when m.move_direction = 'UP' then
                max(d.high) over (
                    partition by
                        m.source,
                        m.provider,
                        m.symbol,
                        m.timeframe,
                        m.move_direction,
                        m.move_sequence
                    order by d.analytical_date
                    rows between unbounded preceding and current row
                )
        end as current_extreme_price

    from moves m

    join daily d
        on d.source = m.source
       and d.provider = m.provider
       and d.symbol = m.symbol
       and d.timeframe = m.timeframe
       and d.analytical_date >= m.impulse_start_date

)

select
    *,

    abs(
        move_origin_price - current_extreme_price
    ) as current_move_size

from tracking
