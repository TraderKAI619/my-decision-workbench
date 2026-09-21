{{ config(materialized='view') }}

with facts as (

    select *
    from {{ ref('int_tradingview__daily_market_facts') }}

),

reconciled as (

    select
        source,
        symbol,
        timeframe,
        analytical_date,

        count(*) as provider_count,

        countif(has_imbalance) as imbalance_provider_count,

        countif(
            has_imbalance
            and imbalance_direction = 'UP'
        ) as up_imbalance_provider_count,

        countif(
            has_imbalance
            and imbalance_direction = 'DOWN'
        ) as down_imbalance_provider_count,

        safe_divide(
            countif(has_imbalance),
            count(*)
        ) as imbalance_agreement_ratio,

        safe_divide(
            countif(
                has_imbalance
                and imbalance_direction = 'UP'
            ),
            count(*)
        ) as up_imbalance_agreement_ratio,

        safe_divide(
            countif(
                has_imbalance
                and imbalance_direction = 'DOWN'
            ),
            count(*)
        ) as down_imbalance_agreement_ratio,

        case
            when countif(
                has_imbalance
                and imbalance_direction = 'UP'
            ) = count(*)
            then 'UP'

            when countif(
                has_imbalance
                and imbalance_direction = 'DOWN'
            ) = count(*)
            then 'DOWN'

            when countif(has_imbalance) = 0
            then 'NONE'

            else 'MIXED'
        end as imbalance_consensus,

        min(
            case
                when has_imbalance
                then imbalance_low
            end
        ) as min_imbalance_low,

        max(
            case
                when has_imbalance
                then imbalance_low
            end
        ) as max_imbalance_low,

        min(
            case
                when has_imbalance
                then imbalance_high
            end
        ) as min_imbalance_high,

        max(
            case
                when has_imbalance
                then imbalance_high
            end
        ) as max_imbalance_high

    from facts

    group by
        source,
        symbol,
        timeframe,
        analytical_date

),

final as (

    select
        *,

        max_imbalance_low
            - min_imbalance_low
            as imbalance_low_spread,

        max_imbalance_high
            - min_imbalance_high
            as imbalance_high_spread

    from reconciled

)

select *
from final
