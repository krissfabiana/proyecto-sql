-- =====================================================
-- Base de Datos: ProyectoASG
-- Motor: SQL Server
-- Proyecto: ASG Analytics CR
-- =====================================================

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'ProyectoASG')
BEGIN
    CREATE DATABASE ProyectoASG
        COLLATE Latin1_General_CI_AI; -- Acepta Emogis
END
GO

USE ProyectoASG;
GO

-- -----------------------------------------------------
-- Tabla: rol
-- -----------------------------------------------------
CREATE TABLE rol (
    id_rol      INT IDENTITY(1,1) PRIMARY KEY,
    nombre_rol  VARCHAR(50)  NOT NULL,
    descripcion VARCHAR(200)
);
GO

-- -----------------------------------------------------
-- Tabla: usuario
-- -----------------------------------------------------
CREATE TABLE usuario (
    id_usuario      INT IDENTITY(1,1) PRIMARY KEY,
    id_rol          INT          NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    correo          VARCHAR(100) NOT NULL UNIQUE,
    contrasena      VARCHAR(255) NOT NULL,
    fecha_registro  DATETIME     DEFAULT GETDATE(),
    estado          VARCHAR(20)  DEFAULT 'activo',
    CONSTRAINT fk_usuario_rol FOREIGN KEY (id_rol)
        REFERENCES rol(id_rol)
);
GO

-- -----------------------------------------------------
-- Tabla: empresa
-- -----------------------------------------------------
CREATE TABLE empresa (
    id_empresa      INT IDENTITY(1,1) PRIMARY KEY,
    id_usuario      INT          NOT NULL,
    nombre_empresa  VARCHAR(150) NOT NULL,
    cedula_juridica VARCHAR(20)  UNIQUE,
    sector          VARCHAR(80),
    tamano          VARCHAR(30),
    direccion       VARCHAR(200),
    telefono        VARCHAR(20),
    fecha_registro  DATETIME     DEFAULT GETDATE(),
    CONSTRAINT fk_empresa_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario(id_usuario)
);
GO

-- -----------------------------------------------------
-- Tabla: indicador
-- -----------------------------------------------------
CREATE TABLE indicador (
    id_indicador      INT IDENTITY(1,1) PRIMARY KEY,
    nombre_indicador  VARCHAR(120) NOT NULL,
    categoria         VARCHAR(30)  NOT NULL,
    unidad_medida     VARCHAR(30),
    descripcion       VARCHAR(255)
);
GO

-- -----------------------------------------------------
-- Tabla: registro_indicador
-- -----------------------------------------------------
CREATE TABLE registro_indicador (
    id_registro    INT IDENTITY(1,1) PRIMARY KEY,
    id_empresa     INT            NOT NULL,
    id_indicador   INT            NOT NULL,
    valor          DECIMAL(12,2)  NOT NULL,
    fecha_registro DATETIME       DEFAULT GETDATE(),
    periodo        VARCHAR(20),
    CONSTRAINT fk_registro_empresa FOREIGN KEY (id_empresa)
        REFERENCES empresa(id_empresa),
    CONSTRAINT fk_registro_indicador FOREIGN KEY (id_indicador)
        REFERENCES indicador(id_indicador)
);
GO

-- -----------------------------------------------------
-- Tabla: reporte
-- -----------------------------------------------------
CREATE TABLE reporte (
    id_reporte       INT IDENTITY(1,1) PRIMARY KEY,
    id_empresa       INT          NOT NULL,
    id_usuario       INT          NOT NULL,
    titulo           VARCHAR(150) NOT NULL,
    tipo_reporte     VARCHAR(50),
    fecha_generacion DATETIME     DEFAULT GETDATE(),
    contenido        NVARCHAR(MAX),
    CONSTRAINT fk_reporte_empresa FOREIGN KEY (id_empresa)
        REFERENCES empresa(id_empresa),
    CONSTRAINT fk_reporte_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario(id_usuario)
);
GO

-- -----------------------------------------------------
-- Tabla: recomendacion
-- -----------------------------------------------------
CREATE TABLE recomendacion (
    id_recomendacion INT IDENTITY(1,1) PRIMARY KEY,
    id_reporte       INT           NOT NULL,
    descripcion      NVARCHAR(MAX) NOT NULL,
    prioridad        VARCHAR(20),
    fecha_generacion DATETIME      DEFAULT GETDATE(),
    CONSTRAINT fk_recomendacion_reporte FOREIGN KEY (id_reporte)
        REFERENCES reporte(id_reporte)
);
GO