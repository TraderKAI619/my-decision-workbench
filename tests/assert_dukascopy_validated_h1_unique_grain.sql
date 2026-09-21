select
    source,
    price_type,
    symbol,
    timeframe,
    bar_start_utc,
    count(*) as row_count

from {{ ref('int_dukascopy__validated_h1') }}

group by 1, 2, 3, 4, 5

having count(*) > 1
