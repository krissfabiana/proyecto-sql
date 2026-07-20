-- =====================================================
-- Modulo: Empresa
-- Proyecto: ASG Analytics CR
-- Motor: SQL Server
-- Autor: Sam
-- =====================================================
-- Este script asume que ya se corrieron los scripts compartidos:
--   1) Creacion de la base ProyectoASG y las tablas (rol, usuario,
--      empresa, indicador, registro_indicador, reporte, recomendacion)
--   2) Avance de Bitacora (schema Bitacora, tabla bitacora_errores,
--      login/rol "desarrollo" y el SP dbo.sp_agregarError)
-- =====================================================

USE ProyectoASG;
GO


-- =====================================================
-- SECCION 1: SCHEMA Y PERMISOS DEL MODULO
-- =====================================================

IF SCHEMA_ID('Empresas') IS NULL
    EXEC('CREATE SCHEMA Empresas');
GO

-- Permisos al rol de desarrollo sobre mi schema (solo si el rol
-- ya existe, es decir, si ya corrio el script compartido de Bitacora)
IF DATABASE_PRINCIPAL_ID('desarrollo') IS NOT NULL
BEGIN
    GRANT EXECUTE ON SCHEMA::Empresas TO desarrollo;
    GRANT SELECT  ON SCHEMA::Empresas TO desarrollo;
END
GO

-- Traslado la tabla empresa de dbo al schema Empresas para poder
-- administrar sus permisos de forma independiente (mismo criterio
-- que uso mi compa con reporte/recomendacion -> schema Reportes)
IF EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
           WHERE t.name = 'empresa' AND s.name = 'dbo')
BEGIN
    ALTER SCHEMA Empresas TRANSFER dbo.empresa;
END
GO


-- =====================================================
-- SECCION 2: AUTENTICACION - LOGINS Y USUARIOS DE SERVIDOR
-- =====================================================
-- Un login para el perfil "Gestor" (crea/edita/elimina empresas)
-- y otro para el perfil "Consultor" (solo consulta el directorio).

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_gestor_empresas')
BEGIN
    CREATE LOGIN login_gestor_empresas
        WITH PASSWORD = 'Gestor#Empresas2024';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_consultor_empresas')
BEGIN
    CREATE LOGIN login_consultor_empresas
        WITH PASSWORD = 'Consultor#Empresas2024';
END
GO

-- Usuarios de base de datos vinculados a cada login
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'gestor_empresas')
BEGIN
    CREATE USER gestor_empresas FOR LOGIN login_gestor_empresas;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'consultor_empresas')
BEGIN
    CREATE USER consultor_empresas FOR LOGIN login_consultor_empresas;
END
GO


-- =====================================================
-- SECCION 3: ROLES DE BASE DE DATOS
-- =====================================================
-- rol_gestor_empresas    -> CRUD completo (Administrador/Analista)
-- rol_consultor_empresas -> Solo lectura (Consultor)

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_gestor_empresas')
BEGIN
    CREATE ROLE rol_gestor_empresas AUTHORIZATION dbo;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_consultor_empresas')
BEGIN
    CREATE ROLE rol_consultor_empresas AUTHORIZATION dbo;
END
GO

-- Autorizacion de permisos sobre la tabla
GRANT SELECT, INSERT, UPDATE, DELETE ON Empresas.empresa TO rol_gestor_empresas;

GRANT SELECT ON Empresas.empresa TO rol_consultor_empresas;
DENY  INSERT, UPDATE, DELETE ON Empresas.empresa TO rol_consultor_empresas;
GO

-- Asignacion de usuarios a los roles
ALTER ROLE rol_gestor_empresas     ADD MEMBER gestor_empresas;
ALTER ROLE rol_consultor_empresas  ADD MEMBER consultor_empresas;
GO


-- =====================================================
-- SECCION 4: PROCEDIMIENTOS ALMACENADOS - EMPRESA
-- =====================================================

-- Insertar empresa
CREATE OR ALTER PROCEDURE Empresas.sp_Empresa_Insertar
    @IdUsuario      INT,
    @NombreEmpresa  VARCHAR(150),
    @CedulaJuridica VARCHAR(20),
    @Sector         VARCHAR(80),
    @Tamano         VARCHAR(30),
    @Direccion      VARCHAR(200),
    @Telefono       VARCHAR(20)
AS
BEGIN
    BEGIN TRY
        INSERT INTO Empresas.empresa
            (id_usuario, nombre_empresa, cedula_juridica, sector, tamano, direccion, telefono)
        VALUES
            (@IdUsuario, @NombreEmpresa, @CedulaJuridica, @Sector, @Tamano, @Direccion, @Telefono);

        SELECT SCOPE_IDENTITY() AS id_empresa_creada;
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = @IdUsuario;
        PRINT 'No se pudo insertar la empresa. Se registro en la bitacora.';
    END CATCH
END
GO

-- Actualizar empresa
CREATE OR ALTER PROCEDURE Empresas.sp_Empresa_Actualizar
    @IdEmpresa      INT,
    @NombreEmpresa  VARCHAR(150),
    @Sector         VARCHAR(80),
    @Tamano         VARCHAR(30),
    @Direccion      VARCHAR(200),
    @Telefono       VARCHAR(20),
    @IdUsuario      INT
AS
BEGIN
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Empresas.empresa WHERE id_empresa = @IdEmpresa)
        BEGIN
            RAISERROR('La empresa indicada no existe.', 16, 1);
            RETURN;
        END

        UPDATE Empresas.empresa
        SET nombre_empresa = @NombreEmpresa,
            sector         = @Sector,
            tamano         = @Tamano,
            direccion      = @Direccion,
            telefono       = @Telefono
        WHERE id_empresa = @IdEmpresa;
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = @IdUsuario;
        PRINT 'No se pudo actualizar la empresa. Se registro en la bitacora.';
    END CATCH
END
GO

-- Eliminar empresa (el trigger trg_Empresa_EvitarEliminacion bloquea
-- el borrado si la empresa ya tiene registros o reportes asociados;
-- si algo mas falla, se manda a la bitacora)
CREATE OR ALTER PROCEDURE Empresas.sp_Empresa_Eliminar
    @IdEmpresa INT,
    @IdUsuario INT
AS
BEGIN
    BEGIN TRY
        DELETE FROM Empresas.empresa WHERE id_empresa = @IdEmpresa;
    END TRY
    BEGIN CATCH
        EXEC sp_agregarError @IdUsuario = @IdUsuario;
        PRINT 'No se pudo eliminar la empresa. Se registro en la bitacora.';
    END CATCH
END
GO

-- Consultar una empresa por id (con el nombre de quien la registro)
CREATE OR ALTER PROCEDURE Empresas.sp_Empresa_ConsultarPorId
    @IdEmpresa INT
AS
BEGIN
    SELECT e.id_empresa, e.nombre_empresa, e.cedula_juridica, e.sector,
           e.tamano, e.direccion, e.telefono, e.fecha_registro,
           u.nombre AS registrada_por
    FROM Empresas.empresa e
    INNER JOIN dbo.usuario u ON u.id_usuario = e.id_usuario
    WHERE e.id_empresa = @IdEmpresa;
END
GO

-- Listar todas las empresas
CREATE OR ALTER PROCEDURE Empresas.sp_Empresa_ConsultarTodas
AS
BEGIN
    SELECT e.id_empresa, e.nombre_empresa, e.cedula_juridica, e.sector,
           e.tamano, e.fecha_registro
    FROM Empresas.empresa e
    ORDER BY e.nombre_empresa;
END
GO

-- Listar las empresas registradas por un usuario especifico
CREATE OR ALTER PROCEDURE Empresas.sp_Empresa_ConsultarPorUsuario
    @IdUsuario INT
AS
BEGIN
    SELECT e.id_empresa, e.nombre_empresa, e.sector, e.tamano, e.fecha_registro
    FROM Empresas.empresa e
    WHERE e.id_usuario = @IdUsuario
    ORDER BY e.fecha_registro DESC;
END
GO

-- Filtrar empresas por sector (ej. "Energia y Telecomunicaciones")
CREATE OR ALTER PROCEDURE Empresas.sp_Empresa_ConsultarPorSector
    @Sector VARCHAR(80)
AS
BEGIN
    SELECT id_empresa, nombre_empresa, cedula_juridica, tamano, direccion, telefono
    FROM Empresas.empresa
    WHERE sector = @Sector
    ORDER BY nombre_empresa;
END
GO

-- Resumen: cantidad de empresas agrupadas por sector y tamano
-- (consulta agrupada, util para el dashboard)
CREATE OR ALTER PROCEDURE Empresas.sp_Empresa_ResumenPorSector
AS
BEGIN
    SELECT sector,
           tamano,
           COUNT(*) AS cantidad_empresas
    FROM Empresas.empresa
    GROUP BY sector, tamano
    ORDER BY sector, cantidad_empresas DESC;
END
GO


-- =====================================================
-- SECCION 5: FUNCION
-- =====================================================

-- Cuenta cuantas empresas ha registrado un usuario
CREATE OR ALTER FUNCTION Empresas.fn_ContarEmpresasPorUsuario(@IdUsuario INT)
RETURNS INT
AS
BEGIN
    DECLARE @Total INT;
    SELECT @Total = COUNT(*)
    FROM Empresas.empresa
    WHERE id_usuario = @IdUsuario;
    RETURN ISNULL(@Total, 0);
END
GO


-- =====================================================
-- SECCION 6: VISTA
-- =====================================================

-- Empresas con el nombre de quien las registro (sin exponer datos
-- sensibles del usuario, solo el nombre)
CREATE OR ALTER VIEW Empresas.vista_empresas_detalle
AS
SELECT e.id_empresa,
       e.nombre_empresa,
       e.cedula_juridica,
       e.sector,
       e.tamano,
       e.direccion,
       e.telefono,
       e.fecha_registro,
       u.nombre AS registrada_por
FROM Empresas.empresa e
INNER JOIN dbo.usuario u ON u.id_usuario = e.id_usuario;
GO


-- =====================================================
-- SECCION 7: TRIGGERS
-- =====================================================

-- Evita eliminar una empresa que ya tiene registros de indicadores
-- o reportes asociados (son evidencia historica, no se deben borrar)
CREATE OR ALTER TRIGGER Empresas.trg_Empresa_EvitarEliminacion
ON Empresas.empresa
INSTEAD OF DELETE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dbo.registro_indicador r
        INNER JOIN deleted d ON r.id_empresa = d.id_empresa
    )
    OR EXISTS (
        SELECT 1
        FROM Reportes.reporte rep
        INNER JOIN deleted d ON rep.id_empresa = d.id_empresa
    )
    BEGIN
        RAISERROR('No se puede eliminar una empresa con registros o reportes asociados.', 16, 1);
        RETURN;
    END

    DELETE FROM Empresas.empresa
    WHERE id_empresa IN (SELECT id_empresa FROM deleted);
END
GO

-- Valida el formato de la cedula juridica al insertar o actualizar
-- (formato costarricense tipo 3-101-123456)
CREATE OR ALTER TRIGGER Empresas.trg_Empresa_ValidarCedula
ON Empresas.empresa
AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM inserted
        WHERE cedula_juridica IS NOT NULL
          AND cedula_juridica NOT LIKE '[0-9]-[0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]'
    )
    BEGIN
        RAISERROR('La cedula juridica no tiene el formato valido (ej. 3-101-123456).', 16, 1);
        ROLLBACK TRANSACTION;
    END
END
GO


-- =====================================================
-- SECCION 8: PRUEBAS (ejecutar de arriba a abajo)
-- =====================================================

-- 1) Insertar una empresa de prueba
EXEC Empresas.sp_Empresa_Insertar
    @IdUsuario      = 6,
    @NombreEmpresa  = 'Cafetalera Volcan Poas S.A.',
    @CedulaJuridica = '3-101-987654',
    @Sector         = 'Agricultura y Cafe',
    @Tamano         = 'Pequena',
    @Direccion      = 'Poas, Alajuela',
    @Telefono       = '2441-2020';

-- 2) Consultar todas y por id (uso el id que salga del insertado arriba)
EXEC Empresas.sp_Empresa_ConsultarTodas;
-- EXEC Empresas.sp_Empresa_ConsultarPorId @IdEmpresa = 6;

-- 3) Ver la vista con detalle
SELECT * FROM Empresas.vista_empresas_detalle;

-- 4) Probar la funcion
SELECT Empresas.fn_ContarEmpresasPorUsuario(6) AS empresas_registradas;

-- 5) Filtros y resumenes
EXEC Empresas.sp_Empresa_ConsultarPorUsuario @IdUsuario = 6;
EXEC Empresas.sp_Empresa_ConsultarPorSector @Sector = 'Energía y Telecomunicaciones';
EXEC Empresas.sp_Empresa_ResumenPorSector;

-- 6) Probar el trigger de formato de cedula (esto DEBE dar error)
-- EXEC Empresas.sp_Empresa_Insertar
--     @IdUsuario = 6, @NombreEmpresa = 'Empresa Mala Cedula', @CedulaJuridica = '12345',
--     @Sector = 'Prueba', @Tamano = 'Pequena', @Direccion = 'N/A', @Telefono = '0000-0000';

-- 7) Probar el trigger de eliminacion bloqueada
--    (esto DEBE dar error porque la empresa 1 (ICE) ya tiene registros y reportes)
-- EXEC Empresas.sp_Empresa_Eliminar @IdEmpresa = 1, @IdUsuario = 6;
