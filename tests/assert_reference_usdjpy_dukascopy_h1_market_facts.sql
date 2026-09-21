with actual as (

    select
        count(*) as row_count,
        countif(has_imbalance) as imbalance_rows,
        countif(candle_direction = 'UP') as up_candles,
        countif(candle_direction = 'DOWN') as down_candles,
        countif(candle_direction = 'FLAT') as flat_candles,
        countif(break_previous_high) as break_previous_high_rows,
        countif(break_previous_low) as break_previous_low_rows

    from {{ ref('int_dukascopy__h1_market_facts') }}

    where symbol = 'USDJPY'
      and timeframe = 'H1'
      and price_type = 'BID'

)

select *

from actual

where row_count != 35851
   or imbalance_rows != 7184
   or up_candles != 18541
   or down_candles != 17130
   or flat_candles != 180
   or break_previous_high_rows != 17605
   or break_previous_low_rows != 16151
