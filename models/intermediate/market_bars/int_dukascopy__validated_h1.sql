{{ config(materialized='view') }}

with staged as (

    select *
    from {{ ref('stg_dukascopy__market_bars') }}

),

classified as (

    select
        *,

        case
            when
                high < greatest(open, close)
                or low > least(open, close)
                or high < low
            then true
            else false
        end as is_invalid_ohlc,

        row_number() over (
            partition by
                source,
                price_type,
                symbol,
                timeframe,
                bar_start_utc
            order by
                source_file,
                ingested_at
        ) as duplicate_row_number

    from staged

),

canonical as (

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

    from classified

    where duplicate_row_number = 1
      and not is_invalid_ohlc

)

select *
from canonical
