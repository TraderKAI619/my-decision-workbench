with source_data as (

    select *
    from {{ source('dukascopy', 'market_bars') }}

),

renamed as (

    select
        source,
        price_type,
        symbol,
        timeframe,

        bar_start_utc,

        open,
        high,
        low,
        close,
        volume,

        source_file,
        ingested_at

    from source_data

)

select *
from renamed
