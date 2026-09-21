{{ config(materialized='view') }}

with aggregated as (

    select *
    from {{ ref('int_dukascopy__h1_to_h4') }}

),

with_segment as (

    select
        *,

        sum(
            case
                when not is_complete_4h_bucket then 1
                else 0
            end
        ) over (
            partition by source, symbol
            order by bar_start_utc
            rows between unbounded preceding and current row
        ) as segment_id

    from aggregated

),

canonical as (

    select
        source,
        symbol,
        'H4' as timeframe,

        bar_start_utc,

        open,
        high,
        low,
        close,
        volume,

        source_timeframe,
        bar_origin,

        expected_1h_bar_count,
        actual_1h_bar_count,

        first_1h_timestamp,
        last_1h_timestamp,

        is_complete_4h_bucket,
        segment_id

    from with_segment

    where is_complete_4h_bucket

)

select *
from canonical
