{{ config(materialized='view') }}

with recovery as (

    select
        *,

        lag(reached_25_by_close) over (
            partition by
                source,
                provider,
                symbol,
                timeframe,
                move_direction,
                move_sequence
            order by analytical_date
        ) as previous_reached_25_by_close,

        lag(reached_50_by_close) over (
            partition by
                source,
                provider,
                symbol,
                timeframe,
                move_direction,
                move_sequence
            order by analytical_date
        ) as previous_reached_50_by_close,

        lag(reached_75_by_close) over (
            partition by
                source,
                provider,
                symbol,
                timeframe,
                move_direction,
                move_sequence
            order by analytical_date
        ) as previous_reached_75_by_close

    from {{ ref('int_tradingview__daily_recovery_context') }}

),

recovery_25_events as (

    select
        source,
        provider,
        symbol,
        timeframe,

        analytical_date as event_date,

        'RECOVERY_25_REACHED_BY_CLOSE' as evidence_type,

        move_direction,
        move_sequence,
        impulse_start_date,

        move_origin_price,
        current_extreme_price,
        current_move_size,

        recovery_by_close as evidence_value,
        recovery_25_level as reference_price,

        cast(null as string) as evidence_direction,

        cast(null as float64) as zone_low,
        cast(null as float64) as zone_high,
        cast(null as float64) as zone_size,
        cast(null as float64) as zone_size_pips

    from recovery

    where reached_25_by_close = true
      and coalesce(previous_reached_25_by_close, false) = false

),

recovery_50_events as (

    select
        source,
        provider,
        symbol,
        timeframe,

        analytical_date as event_date,

        'RECOVERY_50_REACHED_BY_CLOSE' as evidence_type,

        move_direction,
        move_sequence,
        impulse_start_date,

        move_origin_price,
        current_extreme_price,
        current_move_size,

        recovery_by_close as evidence_value,
        recovery_50_level as reference_price,

        cast(null as string) as evidence_direction,

        cast(null as float64) as zone_low,
        cast(null as float64) as zone_high,
        cast(null as float64) as zone_size,
        cast(null as float64) as zone_size_pips

    from recovery

    where reached_50_by_close = true
      and coalesce(previous_reached_50_by_close, false) = false

),

recovery_75_events as (

    select
        source,
        provider,
        symbol,
        timeframe,

        analytical_date as event_date,

        'RECOVERY_75_REACHED_BY_CLOSE' as evidence_type,

        move_direction,
        move_sequence,
        impulse_start_date,

        move_origin_price,
        current_extreme_price,
        current_move_size,

        recovery_by_close as evidence_value,
        recovery_75_level as reference_price,

        cast(null as string) as evidence_direction,

        cast(null as float64) as zone_low,
        cast(null as float64) as zone_high,
        cast(null as float64) as zone_size,
        cast(null as float64) as zone_size_pips

    from recovery

    where reached_75_by_close = true
      and coalesce(previous_reached_75_by_close, false) = false

),

daily_imbalance_events as (

    select
        source,
        provider,
        symbol,
        timeframe,

        zone_formed_date as event_date,

        case
            when zone_direction = 'UP'
                then 'DAILY_UP_IMBALANCE_FORMED'
            when zone_direction = 'DOWN'
                then 'DAILY_DOWN_IMBALANCE_FORMED'
        end as evidence_type,

        cast(null as string) as move_direction,
        cast(null as int64) as move_sequence,
        cast(null as date) as impulse_start_date,

        cast(null as float64) as move_origin_price,
        cast(null as float64) as current_extreme_price,
        cast(null as float64) as current_move_size,

        cast(null as float64) as evidence_value,
        cast(null as float64) as reference_price,

        zone_direction as evidence_direction,

        zone_low,
        zone_high,
        zone_size,
        zone_size_pips

    from {{ ref('int_tradingview__daily_imbalance_zones') }}

)

select * from recovery_25_events

union all

select * from recovery_50_events

union all

select * from recovery_75_events

union all

select * from daily_imbalance_events
