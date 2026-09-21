with actual as (

    select
        *

    from {{ ref('int_daily_zones__h4_interactions') }}

    where symbol = 'USDJPY'
      and zone_provider = 'OANDA'
      and zone_formed_date = date('2026-08-11')
      and bar_start_utc = timestamp('2026-08-20 13:00:00+00')

),

validation_errors as (

    select *

    from actual

    where zone_direction != 'UP'

       or abs(zone_low - 158.575) > 0.000001
       or abs(zone_high - 158.921) > 0.000001

       or reaction_source != 'DUKASCOPY'
       or reaction_timeframe != 'H4'

       or bar_available_utc
            != timestamp('2026-08-20 17:00:00+00')

       or touched_zone is not true
       or entered_zone is not true
       or fully_traversed_zone is not true

       or abs(penetration_depth - 1.0) > 0.000001

       or close_location != 'ABOVE'

       or previous_close_location != 'INSIDE'

       or h4_has_imbalance is not false
       or h4_imbalance_direction is not null

),

row_count_error as (

    select count(*) as row_count

    from actual

    having count(*) != 1

)

select *
from validation_errors

union all

select
    a.*

from actual a
cross join row_count_error
