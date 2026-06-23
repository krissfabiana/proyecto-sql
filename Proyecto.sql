-------------
-- projecto.sql
-------------

create database proyecto;
go 

create table proyecto (
    id_proyecto int primary key,
    nombre varchar(100) not null,
    descripcion text,
    fecha_inicio date,
    fecha_fin date
);
