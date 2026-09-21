{{ config(materialized='view') }}

with staged as (

    select *
    from {{ ref('stg_tradingview__market_bars') }}

),

canonicalized as (

    select
        source,

        case
            when provider = 'FX' then 'FXCM'
            else provider
        end as provider,

        symbol,
        '1D' as timeframe,

        raw_timestamp_utc as bar_start_utc,

        date(
            timestamp_add(
                raw_timestamp_utc,
                interval 3 hour
            )
        ) as analytical_date,

        open,
        high,
        low,
        close,

        up,
        down,
        daily_high,
        daily_low,

        source_file,
        ingested_at

    from staged

    where timeframe = 'D'

)

select *
from canonicalized
