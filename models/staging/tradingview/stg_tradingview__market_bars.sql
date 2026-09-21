with source_data as (

    select *
    from {{ source('tradingview', 'market_bars') }}

),

renamed as (

    select
        source,
        provider,
        symbol,
        timeframe,

        raw_timestamp,

        timestamp_seconds(raw_timestamp) as raw_timestamp_utc,

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

    from source_data

)

select *
from renamed
