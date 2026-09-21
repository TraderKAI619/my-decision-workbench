select *

from {{ ref('int_tradingview__daily_reconciliation') }}

where
       provider_count <= 0

    or imbalance_provider_count < 0
    or imbalance_provider_count > provider_count

    or up_imbalance_provider_count < 0
    or down_imbalance_provider_count < 0

    or up_imbalance_provider_count
       + down_imbalance_provider_count
       != imbalance_provider_count

    or imbalance_agreement_ratio < 0
    or imbalance_agreement_ratio > 1

    or up_imbalance_agreement_ratio < 0
    or up_imbalance_agreement_ratio > 1

    or down_imbalance_agreement_ratio < 0
    or down_imbalance_agreement_ratio > 1

    or imbalance_consensus not in ('UP', 'DOWN', 'NONE', 'MIXED')

    or imbalance_low_spread < 0
    or imbalance_high_spread < 0

    or (
        imbalance_consensus = 'UP'
        and up_imbalance_provider_count != provider_count
    )

    or (
        imbalance_consensus = 'DOWN'
        and down_imbalance_provider_count != provider_count
    )

    or (
        imbalance_consensus = 'NONE'
        and imbalance_provider_count != 0
    )
