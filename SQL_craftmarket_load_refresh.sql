with dwh_delta as ( -- определяем, какие данные были изменены в витрине или добавлены в DWH. Формируем дельту изменений
	select
		dcu.customer_id customer_id,
		dcu.customer_name customer_name,
		dcu.customer_address customer_address,
		dcu.customer_birthday customer_birthday,
		dcu.customer_email customer_email,
		dcr.craftsman_id craftsman_id,
		fo.order_id order_id,
		dpr.product_id product_id,
		dpr.product_price product_price,
		dpr.product_type product_type,
		fo.order_completion_date - fo.order_created_date diff_order_date,
		fo.order_status order_status,
		to_char(fo.order_created_date, 'yyyy-mm') report_period,
		crd.customer_id exist_customer_id,
		dcu.load_dttm customers_load_dttm,
		dcr.load_dttm craftsman_load_dttm,
		dpr.load_dttm products_load_dttm	
	from dwh.f_order fo
	join dwh.d_customer dcu on fo.customer_id = dcu.customer_id
	join dwh.d_craftsman dcr on fo.craftsman_id = dcr.craftsman_id
	join dwh.d_product dpr on fo.product_id = dpr.product_id
	left join dwh.customer_report_datamart crd on fo.customer_id = crd.customer_id
	where (fo.load_dttm > (select coalesce(max(load_dttm), '1900-01-01') from dwh.load_dates_customer_report_datamart))
	or (dcu.load_dttm > (select coalesce(max(load_dttm), '1900-01-01') from dwh.load_dates_customer_report_datamart))
	or (dcr.load_dttm > (select coalesce(max(load_dttm), '1900-01-01') from dwh.load_dates_customer_report_datamart))
	or (dpr.load_dttm > (select coalesce(max(load_dttm), '1900-01-01') from dwh.load_dates_customer_report_datamart))
),
dwh_update_delta as -- делаем выборку мастеров ручной работы, по которым были изменения в DWH. По этим мастерам данные в витрине нужно будет обновить
(select
	dd.exist_customer_id customer_id
	from dwh_delta dd
	where dd.exist_customer_id is not null
),
dwh_delta_insert_result as (  -- делаем расчёт витрины по новым данным. Этой информации по мастерам в рамках расчётного периода раньше не было, это новые данные. Их можно просто вставить (insert) в витрину без обновления
select
	T5.customer_id AS customer_id,
    T5.customer_name AS customer_name,
    T5.customer_address AS customer_address,
    T5.customer_birthday AS customer_birthday,
    T5.customer_email AS customer_email,
    T5.customer_money AS customer_money,
    T5.platform_money AS platform_money,
    T5.count_order AS count_order,
    T5.avg_price_order AS avg_price_order,
    T5.product_type AS top_product_category,
    T5.rank_craftsman_by_customer AS top_craftsman,
    T5.median_time_order_completed AS median_time_order_completed,
    T5.count_order_created AS count_order_created,
    T5.count_order_in_progress AS count_order_in_progress,
    T5.count_order_delivery AS count_order_delivery,
    T5.count_order_done AS count_order_done,
    T5.count_order_not_done AS count_order_not_done,
    T5.report_period AS report_period 
from
	(select -- в этой выборке объединяем три внутренние выборки по расчёту столбцов витрины и применяем оконную функцию для определения самых популярных категории товаров и мастеров
		*,
		rank() over (partition by t2.customer_id order by count_product desc) rank_count_product,
		first_value(t4.craftsman_id) over (partition by t2.customer_id order by count_order_craftsman desc) rank_craftsman_by_customer
		from
		(select -- в этой выборке делаем расчёт по большинству столбцов, так как все они требуют одной и той же группировки, кроме столбцов с самой популярной категорией товаров и мастера. Для них сделаем отдельные выборки с другой группировкой и выполним JOIN
			t1.customer_id customer_id,
			t1.customer_name customer_name,
			t1.customer_address customer_address,
			t1.customer_birthday customer_birthday,
			t1.customer_email customer_email,
			sum(t1.product_price) customer_money,
			sum(t1.product_price) * 0.1 platform_money,
			count(t1.order_id) count_order,
			avg(t1.product_price) avg_price_order,
			percentile_cont(0.5) within group(order by diff_order_date) median_time_order_completed,
			sum(case when t1.order_status = 'created' then 1 else 0 end) count_order_created,
			sum(case when t1.order_status = 'in progress' then 1 else 0 end) count_order_in_progress,
			sum(case when t1.order_status = 'delivery' then 1 else 0 end) count_order_delivery,
			sum(case when t1.order_status = 'done' then 1 else 0 end) count_order_done,
			sum(case when t1.order_status != 'done' then 1 else 0 end) count_order_not_done,
			t1.report_period report_period
			from dwh_delta as t1
            where t1.exist_customer_id is null
            group by t1.customer_id, t1.customer_name, t1.customer_address, t1.customer_birthday, t1.customer_email, t1.report_period
			) as t2
		join 
			(select -- Эта выборка поможет определить самую популярную катугорию товаров у заказчика
				dd.customer_id customer_id_for_product_type,
				dd.product_type,
				count(dd.product_type) count_product
			from dwh_delta dd
			group by dd.customer_id, dd.product_type
			order by count_product desc
			) as t3 on t2.customer_id = t3.customer_id_for_product_type
		join
			(select -- Эта выборка поможет определить самого популярного мастера у заказчика
				dd.customer_id customer_for_craftsman,
				dd.craftsman_id craftsman_id,
				count(dd.order_id) count_order_craftsman
			from dwh_delta dd
			group by dd.customer_id, dd.craftsman_id
			order by count_order_craftsman desc
		) as t4 on t2.customer_id = t4.customer_for_craftsman
	) as t5
	where t5.rank_count_product = 1
	order by report_period
),
dwh_delta_update_result as ( -- делаем перерасчёт для существующих записей витрины, так как данные обновились за отчётные периоды.
	select
		T5.customer_id AS customer_id,
		T5.customer_name AS customer_name,
		T5.customer_address AS customer_address,
		T5.customer_birthday AS customer_birthday,
		T5.customer_email AS customer_email,
		T5.customer_money AS customer_money,
		T5.platform_money AS platform_money,
		T5.count_order AS count_order,
		T5.avg_price_order AS avg_price_order,
		T5.median_time_order_completed AS median_time_order_completed,
		T5.product_type AS top_product_category,
		T5.rank_craftsman_by_customer AS top_craftsman,
		T5.count_order_created AS count_order_created,
		T5.count_order_in_progress AS count_order_in_progress,
		T5.count_order_delivery AS count_order_delivery,
		T5.count_order_done AS count_order_done,
		T5.count_order_not_done AS count_order_not_done,
		T5.report_period AS report_period 
	from ( -- в этой выборке объединяем три внутренние выборки по расчёту столбцов витрины и применяем оконную функцию для определения самых популярных категории товаров и мастеров
		select
			*,
			rank() over (partition by t2.customer_id order by count_product desc) rank_count_product,
			first_value(t4.craftsman_id) over (partition by t2.customer_id order by count_order_craftsman desc) rank_craftsman_by_customer
		from ( -- в этой выборке делаем расчёт по большинству столбцов, так как все они требуют одной и той же группировки, кроме столбцов с самой популярной категорией товаров и мастера. Для них сделаем отдельные выборки с другой группировкой и выполним JOIN
			select
				t1.customer_id customer_id,
				t1.customer_name customer_name,
				t1.customer_address customer_address,
				t1.customer_birthday customer_birthday,
				t1.customer_email customer_email,
				sum(t1.product_price) customer_money,
				sum(t1.product_price) * 0.1 platform_money,
				count(t1.order_id) count_order,
				avg(t1.product_price) avg_price_order,
				percentile_cont(0.5) within group(order by diff_order_date) median_time_order_completed,
				sum(case when t1.order_status = 'created' then 1 else 0 end) count_order_created,
				sum(case when t1.order_status = 'in progress' then 1 else 0 end) count_order_in_progress,
				sum(case when t1.order_status = 'delivery' then 1 else 0 end) count_order_delivery,
				sum(case when t1.order_status = 'done' then 1 else 0 end) count_order_done,
				sum(case when t1.order_status != 'done' then 1 else 0 end) count_order_not_done,
				t1.report_period report_period
			from (
				select
					dcu.customer_id customer_id,
					dcu.customer_name customer_name,
					dcu.customer_address customer_address,
					dcu.customer_birthday customer_birthday,
					dcu.customer_email customer_email,
					dcr.craftsman_id craftsman_id,
					fo.order_id order_id,
					dpr.product_id product_id,
					dpr.product_price product_price,
					dpr.product_type product_type,
					fo.order_completion_date - fo.order_created_date diff_order_date,
					fo.order_status order_status,
					to_char(fo.order_created_date, 'yyyy-mm') report_period,
					crd.customer_id exist_customer_id,
					dcu.load_dttm customers_load_dttm,
					dcr.load_dttm craftsman_load_dttm,
					dpr.load_dttm products_load_dttm	
				from dwh.f_order fo
				join dwh.d_customer dcu on fo.customer_id = dcu.customer_id
				join dwh.d_craftsman dcr on fo.craftsman_id = dcr.craftsman_id
				join dwh.d_product dpr on fo.product_id = dpr.product_id
				left join dwh.customer_report_datamart crd on fo.customer_id = crd.customer_id
				) as t1
				group by t1.customer_id, t1.customer_name, t1.customer_address, t1.customer_birthday, t1.customer_email, t1.report_period
			) as t2
				join ( -- Эта выборка поможет определить самую популярную катугорию товаров у заказчика
					select
						dd.customer_id customer_id_for_product_type,
						dd.product_type,
						count(dd.product_type) count_product
					from dwh_delta dd
					group by dd.customer_id, dd.product_type
					order by count_product desc
					) as t3 on t2.customer_id = t3.customer_id_for_product_type
				join ( -- Эта выборка поможет определить самого популярного мастера у заказчика
					select
						dd.customer_id customer_for_craftsman,
						dd.craftsman_id craftsman_id,
						count(dd.order_id) count_order_craftsman
					from dwh_delta dd
					group by dd.customer_id, dd.craftsman_id
					order by count_order_craftsman desc
				) as t4 on t2.customer_id = t4.customer_for_craftsman
			) as t5
	where t5.rank_count_product = 1
	order by report_period
),
insert_delta as ( -- выполняем insert новых расчитанных данных для витрины 
	insert into dwh.customer_report_datamart (
		customer_id,
		customer_name,
		customer_address,
		customer_birthday,
		customer_email,
		customer_money,
		platform_money,
		count_order,
		avg_price_order,
		median_time_order_completed,
		top_product_category,
		top_craftsman,
		count_order_created,
		count_order_in_progress,
		count_order_delivery,
		count_order_done,
		count_order_not_done,
		report_period
	)
	select customer_id,
		customer_name,
		customer_address,
		customer_birthday,
		customer_email,
		customer_money,
		platform_money,
		count_order,
		avg_price_order,
		median_time_order_completed,
		top_product_category,
		top_craftsman,
		count_order_created,
		count_order_in_progress,
		count_order_delivery,
		count_order_done,
		count_order_not_done,
		report_period
	from dwh_delta_insert_result
),
update_delta as ( -- выполняем обновление показателей в отчёте по уже существующим заказчикам
	update dwh.customer_report_datamart set
		customer_name = updates.customer_name,
		customer_address = updates.customer_address,
		customer_birthday = updates.customer_birthday,
		customer_email = updates.customer_email,
		customer_money = updates.customer_money,
		platform_money = updates.platform_money,
		count_order = updates.count_order,
		avg_price_order = updates.avg_price_order,
		median_time_order_completed = updates.median_time_order_completed,
		top_product_category = updates.top_product_category,
		top_craftsman = updates.top_craftsman,
		count_order_created = updates.count_order_created,
		count_order_in_progress = updates.count_order_in_progress,
		count_order_delivery = updates.count_order_delivery,
		count_order_done = updates.count_order_done,
		count_order_not_done = updates.count_order_not_done,
		report_period = updates.report_period
	from (
	select
		customer_id,
		customer_name,
		customer_address,
		customer_birthday,
		customer_email,
		customer_money,
		platform_money,
		count_order,
		avg_price_order,
		median_time_order_completed,
		top_product_category,
		top_craftsman,
		count_order_created,
		count_order_in_progress,
		count_order_delivery,
		count_order_done,
		count_order_not_done,
		report_period
	from dwh_delta_insert_result) as updates
	where dwh.customer_report_datamart.customer_id = updates.customer_id
),
insert_load_date as ( -- делаем запись в таблицу загрузок о том, когда была совершена загрузка, чтобы в следующий раз взять данные, которые будут добавлены или изменены после этой даты
    INSERT INTO dwh.load_dates_craftsman_report_datamart (
	INSERT INTO dwh.load_dates_customer_report_datamart (
        load_dttm
    )
    SELECT GREATEST(COALESCE(MAX(craftsman_load_dttm), NOW()), 
                    COALESCE(MAX(customers_load_dttm), NOW()), 
                    COALESCE(MAX(products_load_dttm), NOW())) 
        FROM dwh_delta
)
select 'increment datamart';