{{ config(materialized='view') }}

with move_context as (

    select *

    from {{ ref('int_tradingview__daily_directional_move_context') }}

),

sequence_start as (

    select
        *,

        row_number() over (
            partition by
                source,
                provider,
                symbol,
                timeframe,
                move_direction,
                move_sequence
            order by analytical_date
        ) as sequence_row_number

    from move_context

),

candidates as (

    select
        concat(
            source, '|',
            provider, '|',
            symbol, '|',
            timeframe, '|',
            move_direction, '|',
            cast(move_sequence as string), '|',
            'RECOVERY_EXPECTED'
        ) as hypothesis_id,

        source,
        provider,
        symbol,
        timeframe,

        'RECOVERY' as hypothesis_family,
        'RECOVERY_EXPECTED' as hypothesis_type,

        case
            when move_direction = 'DOWN' then 'UP'
            when move_direction = 'UP' then 'DOWN'
        end as hypothesis_direction,

        move_direction as triggering_move_direction,
        move_sequence,

        'DIRECTIONAL_MOVE_SEQUENCE' as trigger_type,

        impulse_start_date as trigger_date,

        cast(null as timestamp) as trigger_start_utc,
        cast(null as timestamp) as trigger_available_utc,

        cast(null as date) as hypothesis_created_date,
        cast(null as timestamp) as hypothesis_created_utc,

        'DAILY' as temporal_granularity,
        'DATE_ONLY' as availability_precision,

        'CANDIDATE' as hypothesis_status,

        'DAILY_DIRECTIONAL_MOVE_CONTEXT' as source_context_type,

        concat(
            source, '|',
            provider, '|',
            symbol, '|',
            timeframe, '|',
            move_direction, '|',
            cast(move_sequence as string)
        ) as source_context_id,

        move_origin_price as trigger_origin_price,
        current_extreme_price as trigger_extreme_price,
        current_move_size as trigger_move_size

    from sequence_start

    where sequence_row_number = 1
      and move_direction in ('UP', 'DOWN')

)

select *
from candidates
