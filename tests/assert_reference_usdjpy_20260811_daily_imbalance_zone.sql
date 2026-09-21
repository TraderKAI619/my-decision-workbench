with actual as (

    select *

    from {{ ref('int_tradingview__daily_imbalance_zones') }}

    where source = 'TRADINGVIEW'
      and provider = 'OANDA'
      and symbol = 'USDJPY'
      and timeframe = '1D'
      and zone_formed_date = date('2026-08-11')

),

validation as (

    select *

    from actual

    where zone_direction != 'UP'
       or abs(zone_low - 158.575) > 0.000001
       or abs(zone_high - 158.921) > 0.000001
       or abs(zone_size - 0.346) > 0.000001
       or abs(zone_size_pips - 34.6) > 0.000001

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
