with actual as (

    select *

    from {{ ref('int_tradingview__daily_zone_interactions') }}

    where source = 'TRADINGVIEW'
      and provider = 'OANDA'
      and symbol = 'USDJPY'
      and timeframe = '1D'
      and zone_formed_date = date('2026-08-20')
      and interaction_date = date('2026-08-24')

),

validation as (

    select *

    from actual

    where zone_direction != 'DOWN'
       or abs(zone_low - 159.184) > 0.000001
       or abs(zone_high - 159.298) > 0.000001
       or abs(zone_size_pips - 11.4) > 0.000001
       or touched_zone != true
       or entered_zone != true
       or fully_traversed_zone != false
       or abs(penetration_depth - 0.8684210526314543) > 0.000001
       or close_location != 'BELOW'

),

row_count_validation as (

    select count(*) as actual_row_count

    from actual

    having count(*) != 1

)

select 1
from validation

union all

select 1
from row_count_validation
