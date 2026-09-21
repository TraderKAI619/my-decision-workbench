select *

from {{ ref('int_tradingview__daily_market_facts') }}

where
       `range` < 0
    or body_size < 0
    or upper_wick < 0
    or lower_wick < 0
    or imbalance_size < 0

    or (
        has_imbalance
        and imbalance_direction is null
    )

    or (
        not has_imbalance
        and (
            imbalance_direction is not null
            or imbalance_low is not null
            or imbalance_high is not null
            or imbalance_size is not null
            or imbalance_size_pips is not null
        )
    )

    or candle_direction not in ('UP', 'DOWN', 'FLAT')
