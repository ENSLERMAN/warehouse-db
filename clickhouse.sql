create database warehouse;
use warehouse;
create table warehouse.dispatch_history
(
	dt            DateTime,
	dispatch_id   Nullable(Int32),
	dispatch_date Nullable(String),
	emp_id        Nullable(Int32),
	emp_fio       Nullable(String),
	status_id     Nullable(Int32),
	status_name   Nullable(String),
	customer_id   Nullable(Int32),
	customer_fio  Nullable(String)
)
	engine = MergeTree PARTITION BY toYYYYMMDD(dt)
		ORDER BY dt
		SETTINGS index_granularity = 8192;

create table warehouse.product_history
(
	dt          DateTime,
	product_id  Int32,
	name        String,
	description String,
	amount      Int32,
	price       Int32,
	barcode     String,
	is_delete   String
)
	engine = MergeTree PARTITION BY toYYYYMMDD(dt)
		ORDER BY dt
		SETTINGS index_granularity = 8192;

create table warehouse.shipment_history
(
	dt              DateTime,
	ship_id         Nullable(Int32),
	supplier_id     Nullable(Int32),
	supplier_fio    Nullable(String),
	employee_id     Nullable(Int32),
	employee_fio    Nullable(String),
	date            Nullable(String),
	product_barcode Nullable(String),
	product_amount  Nullable(Int32)
)
	engine = MergeTree PARTITION BY toYYYYMMDD(dt)
		ORDER BY dt
		SETTINGS index_granularity = 8192;

