-- создание временной широкой таблицы продаж из всех доступных источников
drop table if exists tmp_sources;
create temp table tmp_sources as
select
	order_id,
    order_created_date,
    order_completion_date,
    order_status,
    craftsman_id,
    craftsman_name,
    craftsman_address,
    craftsman_birthday,
    craftsman_email,
    product_id,
    product_name,
    product_description,
    product_type,
    product_price,
    customer_id,
    customer_name,
    customer_address,
    customer_birthday,
    customer_email 
from source1.craft_market_wide
union
select
	t2.order_id,
    t2.order_created_date,
    t2.order_completion_date,
    t2.order_status,
    t1.craftsman_id,
    t1.craftsman_name,
    t1.craftsman_address,
    t1.craftsman_birthday,
    t1.craftsman_email,
    t1.product_id,
    t1.product_name,
    t1.product_description,
    t1.product_type,
    t1.product_price,
    t2.customer_id,
    t2.customer_name,
    t2.customer_address,
    t2.customer_birthday,
    t2.customer_email 
from source2.craft_market_masters_products t1
join source2.craft_market_orders_customers t2 
	on t1.craftsman_id = t2.craftsman_id and t1.product_id = t2.product_id
union
select
	t1.order_id,
	t1.order_created_date,
	t1.order_completion_date,
	t1.order_status,
	t2.craftsman_id,
	t2.craftsman_name,
	t2.craftsman_address,
	t2.craftsman_birthday,
	t2.craftsman_email,
	t1.product_id,
	t1.product_name,
	t1.product_description,
	t1.product_type,
	t1.product_price,
	t3.customer_id,
	t3.customer_name,
	t3.customer_address,
	t3.customer_birthday,
	t3.customer_email
from source3.craft_market_orders t1
join source3.craft_market_craftsmans t2 on t1.craftsman_id = t2.craftsman_id
join source3.craft_market_customers t3 on t1.customer_id = t3.customer_id
union
select
	t1.order_id,
	t1.order_created_date,
	t1.order_completion_date,
	t1.order_status,
	t1.craftsman_id,
	t1.craftsman_name,
	t1.craftsman_address,
	t1.craftsman_birthday,
	t1.craftsman_email,
	t1.product_id,
	t1.product_name,
	t1.product_description,
	t1.product_type,
	t1.product_price,
	t2.customer_id,
	t2.customer_name,
	t2.customer_address,
	t2.customer_birthday,
	t2.customer_email
from external_source.craft_products_orders t1
join external_source.customers t2 on t1.customer_id = t2.customer_id;

-- заполнение таблицы измерений изготовителей
merge into dwh.d_craftsman d
using (select distinct craftsman_name, craftsman_address, craftsman_birthday, craftsman_email from tmp_sources) t
on d.craftsman_name = t.craftsman_name and d.craftsman_email = t.craftsman_email
when matched then
	update set craftsman_address = t.craftsman_address, craftsman_birthday = t.craftsman_birthday, load_dttm = current_timestamp
when not matched then
	insert (craftsman_name, craftsman_address, craftsman_birthday, craftsman_email, load_dttm)
	values (t.craftsman_name, t.craftsman_address, t.craftsman_birthday, t.craftsman_email, current_timestamp);

-- заполнение таблицы измерений товаров
merge into dwh.d_product d
using (select distinct product_name, product_description, product_type, product_price from tmp_sources) t
on d.product_name = t.product_name and d.product_description = t.product_description and d.product_price = t.product_price
when matched then 
	update set product_type = t.product_type, load_dttm = current_timestamp
when not matched then
	insert (product_name, product_description, product_type, product_price, load_dttm)
	values (t.product_name, t.product_description, t.product_type, t.product_price, current_timestamp);

-- заполнение таблицы измерений заказчиков
merge into dwh.d_customer d
using (select distinct customer_name, customer_address, customer_birthday, customer_email from tmp_sources) t
on d.customer_name = t.customer_name and d.customer_email = t.customer_email
when matched then
	update set customer_address = t.customer_address, customer_birthday = t.customer_birthday, load_dttm = current_timestamp
when not matched then
	insert (customer_name, customer_address, customer_birthday, customer_email, load_dttm)
	values (t.customer_name, t.customer_address, t.customer_birthday, t.customer_email, current_timestamp);

-- создание временной таблицы фактов
drop table if exists tmp_sources_fact;
create temp table tmp_sources_fact as
select
	dpr.product_id,
    dcr.craftsman_id,
    dcu.customer_id,
    src.order_created_date,
    src.order_completion_date,
    src.order_status,
    current_timestamp
from tmp_sources src
join dwh.d_craftsman dcr on src.craftsman_name = dcr.craftsman_name and src.craftsman_email = dcr.craftsman_email
join dwh.d_customer dcu on src.customer_name = dcu.customer_name and src.customer_email = dcu.customer_email
join dwh.d_product dpr on src.product_name = dpr.product_name and src.product_description = dpr.product_description and src.product_price = dpr.product_price;

-- заполнение таблицы фактов
merge into dwh.f_order f
using tmp_sources_fact t
on f.product_id = t.product_id and f.craftsman_id = t.craftsman_id and f.customer_id = t.customer_id and f.order_created_date = t.order_created_date
when matched then
	update set order_completion_date = t.order_completion_date, order_status = t.order_status, load_dttm = current_timestamp
when not matched then
	insert (product_id, craftsman_id, customer_id, order_created_date, order_completion_date, order_status, load_dttm)
	values (t.product_id, t.craftsman_id, t.customer_id, t.order_created_date, t.order_completion_date, t.order_status, current_timestamp);
