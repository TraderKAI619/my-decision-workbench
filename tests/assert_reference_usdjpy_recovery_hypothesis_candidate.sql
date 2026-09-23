with actual as (

    select *

    from {{ ref('int_hypothesis__recovery_candidates') }}

    where source = 'TRADINGVIEW'
      and provider = 'OANDA'
      and symbol = 'USDJPY'
      and timeframe = '1D'
      and triggering_move_direction = 'DOWN'
      and move_sequence = 6
      and hypothesis_type = 'RECOVERY_EXPECTED'

),

validation as (

    select
        count(*) as row_count,

        countif(
            hypothesis_direction = 'UP'
            and triggering_move_direction = 'DOWN'
            and trigger_type = 'DIRECTIONAL_MOVE_SEQUENCE'
            and trigger_date = date('2026-07-30')
            and availability_precision = 'DATE_ONLY'
            and hypothesis_status = 'CANDIDATE'
            and source_context_type = 'DAILY_DIRECTIONAL_MOVE_CONTEXT'

            and abs(trigger_origin_price - 163.988) < 0.000001
            and abs(trigger_extreme_price - 157.953) < 0.000001
            and abs(trigger_move_size - 6.035) < 0.000001

            and hypothesis_created_date is null
            and hypothesis_created_utc is null
        ) as valid_row_count

    from actual

)

select *

from validation

where row_count != 1
   or valid_row_count != 1
