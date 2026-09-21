with actual as (

    select *

    from {{ ref('int_tradingview__daily_reconciliation') }}

    where symbol = 'USDJPY'
      and timeframe = '1D'
      and analytical_date = date('2026-08-11')

),

validated as (

    select
        *

    from actual

    where
           provider_count != 5
        or imbalance_provider_count != 5
        or up_imbalance_provider_count != 5
        or down_imbalance_provider_count != 0

        or abs(imbalance_agreement_ratio - 1.0) > 0.000001
        or abs(up_imbalance_agreement_ratio - 1.0) > 0.000001
        or abs(down_imbalance_agreement_ratio - 0.0) > 0.000001

        or imbalance_consensus != 'UP'

        or abs(min_imbalance_low - 158.574) > 0.000001
        or abs(max_imbalance_low - 158.5765) > 0.000001

        or abs(min_imbalance_high - 158.917) > 0.000001
        or abs(max_imbalance_high - 158.926) > 0.000001

        or abs(imbalance_low_spread - 0.0025) > 0.000001
        or abs(imbalance_high_spread - 0.009) > 0.000001

)

select *
from validated

union all

select *
from actual
where (select count(*) from actual) != 1
