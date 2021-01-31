create or replace procedure warehouse.register_user(_surname character varying, _name character varying,
                                                    _patronymic character varying, _login character varying,
                                                    _password character varying, _access integer)
    language plpgsql
as
$$
begin
    insert into warehouse.users (surname, name, patronymic, login, password, access)
    values (_surname, _name, _patronymic, _login, _password, _access);
    commit;
end;
$$;

alter procedure warehouse.register_user(varchar, varchar, varchar, varchar, varchar, integer) owner to ensler;

create or replace function warehouse.showinfobyme(_login character varying)
    returns TABLE
            (
                user_id     integer,
                surname     character varying,
                name        character varying,
                patronymic  character varying,
                login       character varying,
                access_id   integer,
                access_name character varying
            )
    language plpgsql
as
$$
begin
    return query
        select users.id          as user_id,
               users.surname,
               users.name,
               users.patronymic,
               users.login,
               access_roles.id   as access_id,
               access_roles.name as access_name
        from warehouse.users
                 inner join warehouse.access_roles
                            on users.access = access_roles.id
        where users.login = _login;
    return;
end;
$$;

alter function warehouse.showinfobyme(varchar) owner to ensler;

create or replace procedure warehouse.changeuserrole(_user_id integer, _access_id integer)
    language plpgsql
as
$$
begin
    update warehouse.users set access = _access_id where id = _user_id;
    commit;
end;
$$;

alter procedure warehouse.changeuserrole(integer, integer) owner to ensler;

create or replace function warehouse.add_new_shipment(_order json) returns void
    language plpgsql
as
$$
declare
    _date        varchar;
    _supplier_id int;
    _prod        record;
    _p_id        int;
    _sup         record;
    _emp_id      int;
    _emp         record;
    _product     record;
    _ship        record;
begin
    drop table if exists _products;
    create TEMP table _products as
    select o.id, o.name, o.description, o.amount, o.price, o.barcode
    from json_to_recordset(_order -> 'products') as o
             (
              id int,
              name varchar,
              description varchar,
              amount int,
              price int,
              barcode varchar
                 );

    select o.date, o.supplier_id, o.emp_id
    into _date, _supplier_id, _emp_id
    from json_to_record(_order) as o (date varchar, supplier_id int, emp_id int);

    select * into _sup from warehouse.users where id = _supplier_id;
    if _sup.access <> 4 and _sup.access <> 1 then
        RAISE EXCEPTION 'Пользователь % не является поставщиком', _sup.login;
    end if;

    select * into _emp from warehouse.users where id = _emp_id;
    if _emp.access <> 3 and _emp.access <> 1 then
        RAISE EXCEPTION 'Пользователь % не является сотрудником склада', _emp.login;
    end if;

    if _emp IS NULL then
        RAISE EXCEPTION 'Пользователя с id % не существует', _emp_id;
    end if;

    if _sup IS NULL then
        RAISE EXCEPTION 'Пользователя с id % не существует', _supplier_id;
    end if;

    insert into warehouse.products (name, description, amount, price, barcode)
    select _p.name, _p.description, _p.amount, _p.price, _p.barcode
    from _products _p
    on conflict (barcode)
        do update set amount = warehouse.products.amount + excluded.amount;

    insert into warehouse.shipments (supplier_id, employee_id, status_id, date)
    values (_supplier_id, _emp_id, 1, _date);

    select * into _ship from warehouse.shipments where supplier_id = _supplier_id and date = _date;

    for _prod in select * from _products
        loop
            select * into _product from warehouse.products where barcode = _prod.barcode;
            insert into warehouse.product_history (product_id, name, description, amount, price, barcode)
            values (_product.id, _product.name, _product.description, _product.amount, _product.price,
                    _product.barcode);

            insert into warehouse.products_shipments (shipment_id, product_id, product_amount)
            values (_ship.id, _product.id, _prod.amount);

            insert
            into warehouse.shipment_history (datetime, supplier_id, employee_id, status_id, shipment_id)
            values (_date, _supplier_id, _emp_id, 1, _ship.id);
        end loop;

end;
$$;

alter function warehouse.add_new_shipment(json) owner to ensler;

create or replace function warehouse.add_new_dispatch(_order json) returns void
    language plpgsql
as
$$
declare
    _date        varchar;
    _date_create varchar;
    _customer_id int;
    _cus         record;
    _prod        record;
    _product     record;
    _dis         int;
begin
    drop table if exists _products;
    create temp table _products as
    select o.barcode, o.amount
    from json_to_recordset(_order -> 'products') as o
             (
              barcode varchar,
              amount int
                 );

    select o.date, o.customer_id, o.date_create
    into _date, _customer_id, _date_create
    from json_to_record(_order) as o (customer_id int, date varchar, date_create varchar);

    select * into _cus from warehouse.users where id = _customer_id;
    if _cus is null then
        RAISE EXCEPTION 'Пользователя с id % не существует', _customer_id;
    elsif _cus.access <> 5 and _cus.access <> 1 then
        RAISE EXCEPTION 'Пользователь % не является заказчиком', _cus.login;
    end if;

    insert into warehouse.dispatch (date, status_id, date_create, customer_id)
    VALUES (_date, 1, _date_create, _customer_id)
    returning id into _dis;

    for _prod in select * from _products
        loop
            select * into _product from warehouse.products where barcode = _prod.barcode;
            if _product is null then
                raise exception 'Товар с баркодом % не существует', _prod.barcode;
            elsif _product.amount < _prod.amount then
                raise exception 'На складе не имеется указанное кол-во товара для товара с баркодом %, вы передали %, остаток на складе: %', _prod.barcode, _prod.amount, _product.amount;
            end if;

            insert into warehouse.product_dispatch (dispatch_id, product_id, product_amount)
            VALUES (_dis, _product.id, _prod.amount);

            insert into warehouse.dispatch_history (date, status_id, customer_id, dispatch_id)
            VALUES (_date, 1, _customer_id, _dis);

        end loop;
end;
$$;

alter function warehouse.add_new_dispatch(json) owner to ensler;

create or replace function warehouse.close_dispatch(_order json) returns void
    language plpgsql
as
$$
declare
    _date        varchar;
    _customer_id int;
    _emp_id      int;
    _dis_id      int;
    _cus         record;
    _prod        record;
    _product     record;
    _emp         record;
    _dis         record;
    _p           record;
begin
    drop table if exists _products;
    create temp table _products as
    select o.barcode, o.amount
    from json_to_recordset(_order -> 'products') as o
             (
              barcode varchar,
              amount int
                 );

    select o.date, o.customer_id, o.emp_id, o.dispatch_id
    into _date, _customer_id, _emp_id, _dis_id
    from json_to_record(_order) as o (date varchar, customer_id int, emp_id int, dispatch_id int);

    select * into _cus from warehouse.users where id = _customer_id;
    if _cus is null then
        RAISE EXCEPTION 'Пользователя с id % не существует', _customer_id;
    elsif _cus.access <> 5 and _cus.access <> 1 then
        RAISE EXCEPTION 'Пользователь % не является заказчиком', _cus.login;
    end if;

    select * into _emp from warehouse.users where id = _emp_id;
    if _emp is null then
        RAISE EXCEPTION 'Пользователя с id % не существует', _emp_id;
    elsif _emp.access <> 3 and _emp.access <> 1 then
        RAISE EXCEPTION 'Пользователь % не сотрудником склада', _emp.login;
    end if;

    select * into _dis from warehouse.dispatch where id = _dis_id;
    if _dis is null then
        RAISE EXCEPTION 'Отгрузки с id % не существует', _dis_id;
    elsif _dis.status_id = 2 then
        RAISE EXCEPTION 'Отгрузка с id % уже закрыта', _dis_id;
    elsif _dis.status_id = 3 then
        RAISE EXCEPTION 'Отгрузка с id % отклонена', _dis_id;
    end if;

    for _prod in select * from _products
        loop
            select * into _product from warehouse.products where barcode = _prod.barcode;
            if _product is null then
                raise exception 'Товар с баркодом % не существует', _prod.barcode;
            elsif _product.amount < _prod.amount then
                raise exception 'Остаток на складе меньше чем в запросе, сейчас на складе имеется % для баркода %, вы передаёте %', _product.amount, _product.barcode, _prod.amount;
            end if;

            select * into _dis from warehouse.product_dispatch where product_id = _product.id and dispatch_id = _dis_id;
            if _dis.product_amount <> _prod.amount then
                raise exception 'Ожидается отгрузка % коробок, вы отгружаете % коробок, для товара с баркодом %', _dis.product_amount, _prod.amount, _prod.barcode;
            end if;

            update warehouse.products
            set amount = warehouse.products.amount - _prod.amount
            where barcode = _prod.barcode;

            select * into _p from warehouse.products where barcode = _prod.barcode;
            insert
            into warehouse.product_history (product_id, name, description, amount, price, barcode)
            VALUES (_product.id, _product.name, _product.description, _p.amount, _product.price, _prod.barcode);

            update warehouse.dispatch
            set status_id   = 2,
                employee_id = _emp_id
            where id = _dis_id;

            insert into warehouse.dispatch_history (date, employee_id, status_id, customer_id, dispatch_id)
            VALUES (_date, _emp_id, 2, _customer_id, _dis_id);

        end loop;
end;
$$;

alter function warehouse.close_dispatch(json) owner to ensler;

create or replace function warehouse.truncate_all_tables() returns void
    language plpgsql
as
$$
begin
    truncate table warehouse.dispatch_history restart identity cascade;
    truncate table warehouse.dispatch restart identity cascade;
    truncate table warehouse.product_dispatch restart identity cascade;
    truncate table warehouse.products_shipments restart identity cascade;
    truncate table warehouse.shipments restart identity cascade;
    truncate table warehouse.products restart identity cascade;
    truncate table warehouse.shipment_history restart identity cascade;
    raise info 'ok';
end
$$;

alter function warehouse.truncate_all_tables() owner to ensler;

create or replace function warehouse.get_dispatches()
    returns TABLE
            (
                dispatch_id      integer,
                emp_id           integer,
                emp_surname      character varying,
                emp_name         character varying,
                emp_pat          character varying,
                status_id        integer,
                status_name      character varying,
                dispatch_date    character varying,
                customer_id      integer,
                customer_surname character varying,
                customer_name    character varying,
                customer_pat     character varying
            )
    language plpgsql
as
$$
begin
    drop table if exists _cust;
    create temp table _cust as
    select u.id, u.surname, u.name, u.patronymic
    from warehouse.users as u;

    drop table if exists _emps;
    create temp table _emps as
    select u.id, u.surname, u.name, u.patronymic
    from warehouse.users as u;

    drop table if exists _stat;
    create temp table _stat as
    select p.id, p.name
    from warehouse.dispatch_status as p;

    return query
        select dis.id          as dispatch_id,
               dis.employee_id as emp_id,
               u.surname       as emp_surname,
               u.name          as emp_name,
               u.patronymic    as emp_pat,
               dis.status_id   as status_id,
               ds.name         as status_name,
               dis.date_create as dispatch_date,
               dis.customer_id as customer_id,
               s.surname       as customer_surname,
               s.name          as customer_name,
               s.patronymic    as customer_pat
        from warehouse.dispatch as dis
                 left join _emps as u on u.id = dis.employee_id
                 left join _cust as s on s.id = dis.customer_id
                 left join _stat as ds on ds.id = dis.status_id;
    return;
end;
$$;

alter function warehouse.get_dispatches() owner to ensler;

create or replace function warehouse.refuse_dispatch(_dis_id integer, _emp_id integer, _cus_id integer,
                                                     _date character varying) returns void
    language plpgsql
as
$$
declare
    _dis record;
begin
    select * into _dis from warehouse.dispatch where id = _dis_id;
    if _dis is null then
        RAISE EXCEPTION 'Отгрузки с id % не существует', _dis_id;
    elsif _dis.status_id = 2 then
        RAISE EXCEPTION 'Отгрузка с id % уже закрыта', _dis_id;
    elsif _dis.status_id = 3 then
        RAISE EXCEPTION 'Отгрузка с id % уже отклонена', _dis_id;
    end if;

    update warehouse.dispatch
    set status_id   = 3,
        employee_id = _emp_id
    where id = _dis_id;
    insert into warehouse.dispatch_history
    values (_date, _emp_id, 3, _cus_id, _dis_id);
    return;
end;
$$;

alter function warehouse.refuse_dispatch(integer, integer, integer, varchar) owner to ensler;

create or replace function warehouse.delete_product(_prod_id integer) returns void
    language plpgsql
as
$$
declare
    _product record;
begin
    update warehouse.products
    set is_delete = true
    where id = _prod_id;

    select *
    into _product
    from warehouse.products
    where id = _prod_id;

    insert
    into warehouse.product_history
    values (_prod_id, _product.name, _product.description, _product.amount, _product.price, _product.barcode, true);
    return;
end;
$$;

alter function warehouse.delete_product(integer) owner to ensler;

create or replace function warehouse.get_products_by_dispatch(dis_id integer)
    returns TABLE
            (
                customer_id         integer,
                product_id          integer,
                product_amount      integer,
                product_name        character varying,
                product_description character varying,
                product_barcode     character varying
            )
    language plpgsql
as
$$
begin
    drop table if exists _prod;
    create temp table _prod as
    select p.id, p.amount, p.name, p.description, p.barcode
    from warehouse.products as p
    where is_delete = false;

    return query
        select disp.customer_id   as customer_id,
               dis.product_id     as product_id,
               dis.product_amount as product_amount,
               p.name             as product_name,
               p.description      as product_description,
               p.barcode          as product_barcode
        from warehouse.products as p
                 inner join warehouse.product_dispatch as dis on dis.dispatch_id = dis_id and p.id = dis.product_id
                 inner join warehouse.dispatch as disp on dis.dispatch_id = disp.id;
    return;
end;
$$;

alter function warehouse.get_products_by_dispatch(integer) owner to ensler;

create or replace function warehouse.get_shipments()
    returns TABLE
            (
                id               integer,
                supplier_id      integer,
                supplier_surname character varying,
                supplier_name    character varying,
                supplier_pat     character varying,
                employee_id      integer,
                employee_surname character varying,
                employee_name    character varying,
                employee_pat     character varying,
                date             character varying,
                product_barcode  character varying,
                product_amount   integer
            )
    language plpgsql
as
$$
begin
    drop table if exists _sups;
    create temp table _sups as
    select u.id, u.surname, u.name, u.patronymic
    from warehouse.users as u;

    drop table if exists _emps;
    create temp table _emps as
    select u.id, u.surname, u.name, u.patronymic
    from warehouse.users as u;

    drop table if exists _prods;
    create temp table _prods as
    select p.id, p.barcode, p.amount
    from warehouse.products as p
    where is_delete = false;

    return query
        select ship.id          as ship_id,
               ship.supplier_id as supplier_id,
               us.surname       as supplier_surname,
               us.name          as supplier_name,
               us.patronymic    as supplier_pat,
               ship.employee_id as employee_id,
               e.surname        as employee_surname,
               e.name           as employee_name,
               e.patronymic     as employee_pat,
               ship.date,
               pr.barcode,
               ps.product_amount
        from warehouse.shipments as ship
                 inner join _sups as us on ship.supplier_id = us.id
                 inner join _emps as e on ship.employee_id = e.id
                 inner join warehouse.products_shipments as ps on ship.id = ps.shipment_id
                 inner join warehouse.products as pr on ps.product_id = pr.id;
    return;
end;
$$;

alter function warehouse.get_shipments() owner to ensler;

create or replace function warehouse.edit_product(_prod_id integer, _prod_name character varying,
                                                  _prod_des character varying, _prod_price integer) returns void
    language plpgsql
as
$$
declare
    _product record;
begin
    update warehouse.products
    set name        = _prod_name,
        description = _prod_des,
        price       = _prod_price
    where id = _prod_id;

    select *
    into _product
    from warehouse.products
    where id = _prod_id;

    insert
    into warehouse.product_history
    values (_prod_id, _prod_name, _prod_des, _product.amount, _prod_price, _product.barcode);
    return;
end;
$$;

alter function warehouse.edit_product(integer, varchar, varchar, integer) owner to ensler;

create or replace function warehouse.get_history_dispatches()
    returns TABLE
            (
                dispatch_id      integer,
                dispatch_date    character varying,
                emp_id           integer,
                emp_surname      character varying,
                emp_name         character varying,
                emp_pat          character varying,
                status_id        integer,
                status_name      character varying,
                customer_id      integer,
                customer_surname character varying,
                customer_name    character varying,
                customer_pat     character varying
            )
    language plpgsql
as
$$
begin
    drop table if exists _cust;
    create temp table _cust as
    select u.id, u.surname, u.name, u.patronymic
    from warehouse.users as u;

    drop table if exists _emps;
    create temp table _emps as
    select u.id, u.surname, u.name, u.patronymic
    from warehouse.users as u;

    drop table if exists _stat;
    create temp table _stat as
    select p.id, p.name
    from warehouse.dispatch_status as p;

    return query
        select dis.dispatch_id as dispatch_id,
               dis.date        as dispatch_date,
               dis.employee_id as emp_id,
               u.surname       as emp_surname,
               u.name          as emp_name,
               u.patronymic    as emp_pat,
               dis.status_id   as status_id,
               ds.name         as status_name,
               dis.customer_id as customer_id,
               s.surname       as customer_surname,
               s.name          as customer_name,
               s.patronymic    as customer_pat
        from warehouse.dispatch_history as dis
                 left join _emps as u on u.id = dis.employee_id
                 left join _cust as s on s.id = dis.customer_id
                 left join _stat as ds on ds.id = dis.status_id;
    return;
end;
$$;

alter function warehouse.get_history_dispatches() owner to ensler;

create or replace function warehouse.get_shipments_history()
    returns TABLE
            (
                id               integer,
                supplier_id      integer,
                supplier_surname character varying,
                supplier_name    character varying,
                supplier_pat     character varying,
                employee_id      integer,
                employee_surname character varying,
                employee_name    character varying,
                employee_pat     character varying,
                date             character varying,
                product_barcode  character varying,
                product_amount   integer
            )
    language plpgsql
as
$$
begin
    drop table if exists _sups;
    create temp table _sups as
    select u.id, u.surname, u.name, u.patronymic
    from warehouse.users as u;

    drop table if exists _emps;
    create temp table _emps as
    select u.id, u.surname, u.name, u.patronymic
    from warehouse.users as u;

    drop table if exists _prods;
    create temp table _prods as
    select p.id, p.barcode, p.amount
    from warehouse.products as p
    where is_delete = false;

    return query
        select ship.shipment_id as ship_id,
               ship.supplier_id as supplier_id,
               us.surname       as supplier_surname,
               us.name          as supplier_name,
               us.patronymic    as supplier_pat,
               ship.employee_id as employee_id,
               e.surname        as employee_surname,
               e.name           as employee_name,
               e.patronymic     as employee_pat,
               ship.datetime,
               pr.barcode,
               ps.product_amount
        from warehouse.shipment_history as ship
                 inner join _sups as us on ship.supplier_id = us.id
                 inner join _emps as e on ship.employee_id = e.id
                 inner join warehouse.products_shipments as ps on ship.shipment_id = ps.shipment_id
                 inner join warehouse.products as pr on ps.product_id = pr.id;
    return;
end;
$$;

alter function warehouse.get_shipments_history() owner to ensler;

