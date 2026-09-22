with actual as (

    select *

    from {{ ref('int_daily_zones__h4_interactions') }}

    where symbol = 'USDJPY'
      and zone_provider = 'FXCM'
      and zone_formed_date = date('2024-10-29')
      and reaction_source = 'DUKASCOPY'
      and reaction_timeframe = 'H4'
      and segment_id = 144
      and bar_start_utc = timestamp('2024-11-04 01:00:00+00')

),

validation_errors as (

    select *

    from actual

    where previous_close_location is not null

),

row_count_error as (

    select 1 as error
    from (select 1)

    where (
        select count(*)
        from actual
    ) != 1

)

select 1
from validation_errors

union all

select error
from row_count_error
