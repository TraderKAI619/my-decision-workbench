with expected as (

    select 'FOREXCOM' as provider, 158.5765 as imbalance_low, 158.926 as imbalance_high, 34.95 as imbalance_size_pips
    union all
    select 'FXCM', 158.574, 158.917, 34.30
    union all
    select 'FX_IDC', 158.576, 158.923, 34.70
    union all
    select 'OANDA', 158.575, 158.921, 34.60
    union all
    select 'PEPPERSTONE', 158.575, 158.919, 34.40

),

actual as (

    select
        provider,
        imbalance_low,
        imbalance_high,
        imbalance_size_pips,
        has_imbalance,
        imbalance_direction

    from {{ ref('int_tradingview__daily_market_facts') }}

    where symbol = 'USDJPY'
      and timeframe = '1D'
      and analytical_date = date('2026-08-11')

),

comparison as (

    select
        e.provider,

        a.provider is not null as actual_row_exists,

        a.has_imbalance,
        a.imbalance_direction,

        e.imbalance_low as expected_low,
        a.imbalance_low as actual_low,

        e.imbalance_high as expected_high,
        a.imbalance_high as actual_high,

        e.imbalance_size_pips as expected_size_pips,
        a.imbalance_size_pips as actual_size_pips

    from expected e

    left join actual a
        on e.provider = a.provider

)

select *

from comparison

where not actual_row_exists
   or has_imbalance is not true
   or imbalance_direction != 'UP'
   or abs(actual_low - expected_low) > 0.000001
   or abs(actual_high - expected_high) > 0.000001
   or abs(actual_size_pips - expected_size_pips) > 0.000001
