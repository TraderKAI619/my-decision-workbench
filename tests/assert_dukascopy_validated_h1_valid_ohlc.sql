select *

from {{ ref('int_dukascopy__validated_h1') }}

where
    high < greatest(open, close)
    or low > least(open, close)
    or high < low
