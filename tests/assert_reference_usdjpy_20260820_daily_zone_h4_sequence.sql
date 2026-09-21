with actual as (

    select *

    from {{ ref('int_daily_zone_h4_interaction_sequences') }}

    where symbol = 'USDJPY'
      and zone_provider = 'OANDA'
      and zone_formed_date = date('2026-08-11')
      and interaction_start_utc = timestamp('2026-08-20 13:00:00+00')
      and subsequent_imbalance_number = 1

),

validation_errors as (

    select *

    from actual

    where zone_direction != 'UP'

       or interaction_available_utc
            != timestamp('2026-08-20 17:00:00+00')

       or segment_id != 223

       or previous_close_location != 'INSIDE'

       or close_location != 'ABOVE'

       or fully_traversed_zone is not true

       or subsequent_imbalance_start_utc
            != timestamp('2026-08-20 17:00:00+00')

       or subsequent_imbalance_available_utc
            != timestamp('2026-08-20 21:00:00+00')

       or subsequent_imbalance_direction != 'UP'

       or abs(subsequent_imbalance_low - 158.799) > 0.000001

       or abs(subsequent_imbalance_high - 158.969) > 0.000001

       or abs(subsequent_imbalance_size_pips - 17.0) > 0.000001

),

row_count_error as (

    select 1 as error

    from (select 1)

    where (
        select count(*)
        from actual
    ) != 1

)

select 1
from validation_errors

union all

select error
from row_count_error
