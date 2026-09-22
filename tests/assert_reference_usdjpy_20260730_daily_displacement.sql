with actual as (

    select *

    from {{ ref('int_tradingview__daily_displacement_facts') }}

    where symbol = 'USDJPY'
      and provider = 'OANDA'
      and analytical_date = date('2026-07-30')

),

validation_errors as (

    select *

    from actual

    where close_change_direction != 'DOWN'

       or abs(true_range - 5.787) > 0.000001

       or abs(prior_20bar_avg_true_range - 0.73055) > 0.000001

       or abs(true_range_multiple - 7.921429060297081) > 0.000001

       or abs(close_change - (-3.891)) > 0.000001

       or abs(
            prior_20bar_avg_abs_close_change - 0.3688
       ) > 0.000001

       or abs(
            close_change_multiple - 10.550433839479442
       ) > 0.000001

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
