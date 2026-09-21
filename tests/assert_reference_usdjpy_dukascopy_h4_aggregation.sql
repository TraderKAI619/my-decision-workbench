with actual as (

    select
        count(*) as total_h4_buckets,
        countif(is_complete_4h_bucket) as complete_h4_buckets,
        countif(not is_complete_4h_bucket) as incomplete_h4_buckets

    from {{ ref('int_dukascopy__h1_to_h4') }}

    where symbol = 'USDJPY'

)

select *

from actual

where total_h4_buckets != 9073
   or complete_h4_buckets != 8849
   or incomplete_h4_buckets != 224
