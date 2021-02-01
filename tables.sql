create schema if not exists warehouse;
create table warehouse.access_roles
(
	id serial not null,
	name varchar not null,
	constraint access_roles_pk
		primary key (id)
);

alter table warehouse.access_roles owner to ensler;

create unique index access_roles_id_uindex
	on warehouse.access_roles (id);

create unique index access_roles_name_uindex
	on warehouse.access_roles (name);

create table warehouse.products
(
	id serial not null,
	name varchar not null,
	description varchar,
	amount integer not null,
	price integer not null,
	barcode varchar not null,
	is_delete boolean default false not null,
	constraint products_pk
		primary key (id)
);

alter table warehouse.products owner to ensler;

create unique index products_id_uindex
	on warehouse.products (id);

create unique index products_barcode_uindex
	on warehouse.products (barcode);

create unique index products_name_uindex
	on warehouse.products (name);

create table warehouse.dispatch_status
(
	id serial not null,
	name varchar not null,
	constraint dispatch_status_pk
		primary key (id)
);

alter table warehouse.dispatch_status owner to ensler;

create unique index dispatch_status_id_uindex
	on warehouse.dispatch_status (id);

create unique index dispatch_status_name_uindex
	on warehouse.dispatch_status (name);

create table warehouse.shipments_status
(
	id serial not null,
	name varchar not null,
	constraint shipments_status_pk
		primary key (id)
);

alter table warehouse.shipments_status owner to ensler;

create unique index shipments_status_id_uindex
	on warehouse.shipments_status (id);

create unique index shipments_status_name_uindex
	on warehouse.shipments_status (name);

create table warehouse.users
(
	id serial not null,
	surname varchar not null,
	name varchar not null,
	patronymic varchar not null,
	login varchar not null,
	password varchar not null,
	access integer not null,
	is_delete boolean default false not null,
	constraint users_pk
		primary key (id),
	constraint users_access_roles_id_fk
		foreign key (access) references warehouse.access_roles
);

alter table warehouse.users owner to ensler;

create table warehouse.dispatch
(
	id serial not null,
	date varchar not null,
	employee_id integer,
	status_id integer not null,
	date_create varchar not null,
	customer_id integer not null,
	constraint dispatch_pk
		primary key (id),
	constraint dispatch_dispatch_status_id_fk
		foreign key (status_id) references warehouse.dispatch_status,
	constraint dispatch_users_id_fk
		foreign key (employee_id) references warehouse.users,
	constraint dispatch_users_id_fk_2
		foreign key (customer_id) references warehouse.users
);

alter table warehouse.dispatch owner to ensler;

create unique index dispatch_id_uindex
	on warehouse.dispatch (id);

create unique index dispatch_date_uindex
	on warehouse.dispatch (date);

create unique index users_id_uindex
	on warehouse.users (id);

create table warehouse.shipment_history
(
	datetime varchar not null,
	supplier_id integer not null,
	employee_id integer not null,
	status_id integer not null,
	shipment_id integer not null,
	constraint shipment_history_shipments_status_id_fk
		foreign key (status_id) references warehouse.shipments_status,
	constraint shipment_history_users_id_fk
		foreign key (employee_id) references warehouse.users
);

alter table warehouse.shipment_history owner to ensler;

create table warehouse.dispatch_history
(
	date varchar not null,
	employee_id integer,
	status_id integer not null,
	customer_id integer not null,
	dispatch_id integer not null,
	constraint dispatch_history_dispatch_status_id_fk
		foreign key (status_id) references warehouse.dispatch_status,
	constraint dispatch_history_users_id_fk
		foreign key (employee_id) references warehouse.users,
	constraint dispatch_history_users_id_fk_2
		foreign key (customer_id) references warehouse.users,
	constraint dispatch_history_dispatch_id_fk
		foreign key (dispatch_id) references warehouse.dispatch
);

alter table warehouse.dispatch_history owner to ensler;

create table warehouse.product_history
(
	product_id integer not null,
	name varchar not null,
	description varchar not null,
	amount integer not null,
	price integer not null,
	barcode varchar not null,
	is_delete boolean default false not null,
	constraint product_history_products_id_fk
		foreign key (product_id) references warehouse.products
);

alter table warehouse.product_history owner to ensler;

create table warehouse.shipments
(
	id serial not null,
	supplier_id integer not null,
	employee_id integer not null,
	status_id integer not null,
	date varchar not null,
	constraint shipments_pk
		primary key (id),
	constraint table_name_users_id_fk
		foreign key (supplier_id) references warehouse.users,
	constraint table_name_users_id_fk_2
		foreign key (employee_id) references warehouse.users,
	constraint table_name_shipments_status_id_fk
		foreign key (status_id) references warehouse.shipments_status
);

alter table warehouse.shipments owner to ensler;

create unique index shipments_id_uindex
	on warehouse.shipments (id);

create unique index shipments_date_uindex
	on warehouse.shipments (date);

create table warehouse.products_shipments
(
	shipment_id integer not null,
	product_id integer not null,
	product_amount integer not null,
	constraint products_shipments_products_id_fk
		foreign key (product_id) references warehouse.products,
	constraint products_shipments_shipments_id_fk
		foreign key (shipment_id) references warehouse.shipments
);

alter table warehouse.products_shipments owner to ensler;

create table warehouse.product_dispatch
(
	dispatch_id integer not null,
	product_id integer not null,
	product_amount integer not null,
	constraint product_dispatch_dispatch_id_fk
		foreign key (dispatch_id) references warehouse.dispatch,
	constraint product_dispatch_products_id_fk
		foreign key (product_id) references warehouse.products
);

alter table warehouse.product_dispatch owner to ensler;

