with actual as (

    select
        count(*) as row_count

    from {{ ref('int_dukascopy__h4_market_facts') }}

    where symbol = 'USDJPY'
      and bar_start_utc = timestamp('2026-08-20 17:00:00+00')

)

select *

from actual

where row_count != 1
