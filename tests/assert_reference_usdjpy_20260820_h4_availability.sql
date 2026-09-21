with actual as (

    select
        bar_start_utc,
        bar_available_utc,
        last_1h_timestamp,
        has_imbalance,
        imbalance_direction,
        imbalance_low,
        imbalance_high,
        imbalance_size_pips

    from {{ ref('int_dukascopy__h4_market_facts') }}

    where source = 'DUKASCOPY'
      and symbol = 'USDJPY'
      and timeframe = 'H4'
      and bar_start_utc = timestamp('2026-08-20 17:00:00+00')

),

validation_errors as (

    select *

    from actual

    where bar_available_utc
              != timestamp('2026-08-20 21:00:00+00')

       or last_1h_timestamp
              != timestamp('2026-08-20 20:00:00+00')

       or has_imbalance is not true

       or imbalance_direction != 'UP'

       or abs(imbalance_low - 158.799) > 0.000001

       or abs(imbalance_high - 158.969) > 0.000001

       or abs(imbalance_size_pips - 17.0) > 0.000001

),

row_count_error as (

    select
        count(*) as row_count

    from actual

    having count(*) != 1

)

select *
from validation_errors

union all

select
    cast(null as timestamp) as bar_start_utc,
    cast(null as timestamp) as bar_available_utc,
    cast(null as timestamp) as last_1h_timestamp,
    cast(null as bool) as has_imbalance,
    cast(null as string) as imbalance_direction,
    cast(null as float64) as imbalance_low,
    cast(null as float64) as imbalance_high,
    cast(null as float64) as imbalance_size_pips

from row_count_error
