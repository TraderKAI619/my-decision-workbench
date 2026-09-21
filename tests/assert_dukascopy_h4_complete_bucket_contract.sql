select *

from {{ ref('int_dukascopy__h1_to_h4') }}

where
    (
        is_complete_4h_bucket
        and (
            actual_1h_bar_count != 4
            or first_1h_timestamp != bar_start_utc
            or last_1h_timestamp != timestamp_add(
                bar_start_utc,
                interval 3 hour
            )
        )
    )
    or actual_1h_bar_count > 4
