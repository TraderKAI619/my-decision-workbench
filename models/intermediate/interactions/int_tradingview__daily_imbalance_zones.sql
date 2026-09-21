with daily_market_facts as (

    select *

    from {{ ref('int_tradingview__daily_market_facts') }}

),

daily_imbalance_zones as (

    select
        source,
        provider,
        symbol,
        timeframe,

        analytical_date as zone_formed_date,

        imbalance_direction as zone_direction,

        imbalance_low as zone_low,
        imbalance_high as zone_high,

        imbalance_size as zone_size,
        imbalance_size_pips as zone_size_pips

    from daily_market_facts

    where has_imbalance = true
      and imbalance_direction is not null
      and imbalance_low is not null
      and imbalance_high is not null

)

select *

from daily_imbalance_zones
