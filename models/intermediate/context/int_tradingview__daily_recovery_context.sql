{{ config(materialized='view') }}

with move_context as (

    select *
    from {{ ref('int_tradingview__daily_directional_move_context') }}

),

recovery_levels as (

    select
        *,

        case
            when move_direction = 'DOWN' then
                current_extreme_price
                + current_move_size * 0.25

            when move_direction = 'UP' then
                current_extreme_price
                - current_move_size * 0.25
        end as recovery_25_level,

        case
            when move_direction = 'DOWN' then
                current_extreme_price
                + current_move_size * 0.50

            when move_direction = 'UP' then
                current_extreme_price
                - current_move_size * 0.50
        end as recovery_50_level,

        case
            when move_direction = 'DOWN' then
                current_extreme_price
                + current_move_size * 0.75

            when move_direction = 'UP' then
                current_extreme_price
                - current_move_size * 0.75
        end as recovery_75_level

    from move_context

),

recovery_progress as (

    select
        *,

        case
            when current_move_size = 0 then null

            when move_direction = 'DOWN' then
                safe_divide(
                    high - current_extreme_price,
                    current_move_size
                )

            when move_direction = 'UP' then
                safe_divide(
                    current_extreme_price - low,
                    current_move_size
                )
        end as recovery_by_extreme,

        case
            when current_move_size = 0 then null

            when move_direction = 'DOWN' then
                safe_divide(
                    close - current_extreme_price,
                    current_move_size
                )

            when move_direction = 'UP' then
                safe_divide(
                    current_extreme_price - close,
                    current_move_size
                )
        end as recovery_by_close

    from recovery_levels

)

select
    *,

    case
        when move_direction = 'DOWN'
            then high >= recovery_25_level
        when move_direction = 'UP'
            then low <= recovery_25_level
    end as reached_25_by_extreme,

    case
        when move_direction = 'DOWN'
            then high >= recovery_50_level
        when move_direction = 'UP'
            then low <= recovery_50_level
    end as reached_50_by_extreme,

    case
        when move_direction = 'DOWN'
            then high >= recovery_75_level
        when move_direction = 'UP'
            then low <= recovery_75_level
    end as reached_75_by_extreme,

    case
        when move_direction = 'DOWN'
            then close >= recovery_25_level
        when move_direction = 'UP'
            then close <= recovery_25_level
    end as reached_25_by_close,

    case
        when move_direction = 'DOWN'
            then close >= recovery_50_level
        when move_direction = 'UP'
            then close <= recovery_50_level
    end as reached_50_by_close,

    case
        when move_direction = 'DOWN'
            then close >= recovery_75_level
        when move_direction = 'UP'
            then close <= recovery_75_level
    end as reached_75_by_close

from recovery_progress
