{{ config(materialized='view') }}

with h1 as (

    select *
    from {{ ref('int_dukascopy__validated_h1') }}

),

bucketed as (

    select
        *,

        timestamp_add(
            timestamp_seconds(
                div(
                    unix_seconds(
                        timestamp_sub(
                            bar_start_utc,
                            interval 1 hour
                        )
                    ),
                    14400
                ) * 14400
            ),
            interval 1 hour
        ) as h4_bucket_start

    from h1

),

aggregated as (

    select
        source,
        symbol,

        h4_bucket_start as bar_start_utc,

        'H4' as timeframe,

        array_agg(
            open
            order by bar_start_utc
            limit 1
        )[offset(0)] as open,

        max(high) as high,
        min(low) as low,

        array_agg(
            close
            order by bar_start_utc desc
            limit 1
        )[offset(0)] as close,

        sum(volume) as volume,

        'H1' as source_timeframe,
        'AGGREGATED' as bar_origin,

        4 as expected_1h_bar_count,
        count(*) as actual_1h_bar_count,

        min(bar_start_utc) as first_1h_timestamp,
        max(bar_start_utc) as last_1h_timestamp,

        array_agg(
            bar_start_utc
            order by bar_start_utc
        ) as actual_timestamps

    from bucketed

    group by
        source,
        symbol,
        h4_bucket_start

),

classified as (

    select
        * except(actual_timestamps),

        (
            actual_1h_bar_count = 4

            and array_length(actual_timestamps) = 4

            and actual_timestamps[offset(0)]
                = bar_start_utc

            and actual_timestamps[offset(1)]
                = timestamp_add(
                    bar_start_utc,
                    interval 1 hour
                )

            and actual_timestamps[offset(2)]
                = timestamp_add(
                    bar_start_utc,
                    interval 2 hour
                )

            and actual_timestamps[offset(3)]
                = timestamp_add(
                    bar_start_utc,
                    interval 3 hour
                )
        ) as is_complete_4h_bucket

    from aggregated

)

select *
from classified
