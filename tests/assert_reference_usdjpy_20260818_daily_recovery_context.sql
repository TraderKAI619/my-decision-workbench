with actual as (

    select *

    from {{ ref('int_tradingview__daily_recovery_context') }}

    where symbol = 'USDJPY'
      and provider = 'OANDA'
      and move_direction = 'DOWN'
      and impulse_start_date = date('2026-07-30')
      and analytical_date in (
          date('2026-08-17'),
          date('2026-08-18')
      )

),

validation_errors as (

    select *

    from actual

    where
        abs(move_origin_price - 163.988) > 0.000001

        or abs(current_extreme_price - 155.226) > 0.000001

        or abs(current_move_size - 8.762) > 0.000001

        or abs(recovery_25_level - 157.4165) > 0.000001

        or abs(recovery_50_level - 159.607) > 0.000001

        or abs(recovery_75_level - 161.7975) > 0.000001

        or (
            analytical_date = date('2026-08-17')
            and (
                reached_50_by_extreme != false
                or reached_50_by_close != false
                or abs(recovery_by_extreme - 0.4989728372517706) > 0.000001
            )
        )

        or (
            analytical_date = date('2026-08-18')
            and (
                reached_50_by_extreme != true
                or reached_50_by_close != true
                or reached_75_by_extreme != false
                or reached_75_by_close != false
                or abs(recovery_by_extreme - 0.5197443506048849) > 0.000001
                or abs(recovery_by_close - 0.5022825838849589) > 0.000001
            )
        )

),

row_count_error as (

    select 1 as error
    from (select 1)

    where (
        select count(*)
        from actual
    ) != 2

)

select 1
from validation_errors

union all

select error
from row_count_error
