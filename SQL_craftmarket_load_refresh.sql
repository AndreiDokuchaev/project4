-- создание витрины заказчиков
drop table if exists dwh.customer_report_datamart;
create table dwh.customer_report_datamart (
	id bigint generated always as identity not null, -- идентификатор записи
	customer_id bigint not null, -- идентификатор заказчика
	customer_name varchar not null, -- Ф. И. О. заказчика
	customer_address varchar not null, -- адрес заказчика
	customer_birthday date not null, -- дата рождения заказчика
	customer_email varchar not null, -- электронная почта заказчика
	customer_money numeric(15,2) not null, -- сумма, которую потратил заказчик
	platform_money bigint not null, -- сумма, которую заработала платформа от покупок заказчика за месяц (10% от суммы, которую потратил заказчик)
	count_order bigint not null, -- количество заказов у заказчика за месяц
	avg_price_order numeric(10,2) not null, -- средняя стоимость одного заказа у заказчика за месяц
	median_time_order_completed numeric(10,1), -- медианное время в днях от момента создания заказа до его завершения за месяц
	top_product_category varchar not null, -- популярная категория товаров у заказчика
	top_craftsman bigint not null, -- идентификатор самого популярного мастера
	count_order_created bigint not null, -- количество созданных заказов за месяц
	count_order_in_progress bigint not null, -- количество заказов в процессе изготовки за месяц
	count_order_delivery bigint not null, -- количество заказов в доставке за месяц
	count_order_done bigint not null, -- количество завершённых заказов за месяц
	count_order_not_done bigint not null, -- количество незавершённых заказов за месяц
	report_period varchar not null, -- отчётный период год и месяц
	constraint customer_report_datamart_pk primary key (id)
);

-- создание таблицы с датами обновлений витрины заказчиков
drop table if exists dwh.load_dates_customer_report_datamart;
create table dwh.load_dates_customer_report_datamart (
	id bigint generated always as identity not null,
	load_dttm timestamp not null,
	constraint load_dates_customer_report_datamart_pk primary key (id)
);
