with actual as (

    select count(*) as row_count

    from {{ ref('int_dukascopy__validated_h1') }}

    where symbol = 'USDJPY'
      and timeframe = 'H1'
      and price_type = 'BID'

)

select *

from actual

where row_count != 35851
