select *

from {{ ref('int_dukascopy__h4_market_facts') }}

where symbol = 'USDJPY'
  and bar_start_utc = timestamp('2026-08-20 17:00:00+00')

  and (
         abs(open - 158.997) > 0.000001
      or abs(high - 159.182) > 0.000001
      or abs(low - 158.969) > 0.000001
      or abs(close - 159.038) > 0.000001

      or not has_imbalance
      or imbalance_direction != 'UP'

      or abs(imbalance_low - 158.799) > 0.000001
      or abs(imbalance_high - 158.969) > 0.000001
      or abs(imbalance_size_pips - 17.0) > 0.000001
  )
