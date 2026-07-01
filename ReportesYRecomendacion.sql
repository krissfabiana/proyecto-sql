USE ProyectoASG;
GO

--ESQUEMA Reportes
-- Separe reporte y recomendacion del esquema dbo para poder
-- administrar los permisos de forma independiente.


IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Reportes')
BEGIN
    EXEC('CREATE SCHEMA Reportes AUTHORIZATION dbo');
END
GO

--las tablas existentes de dbo a Reportes
IF EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
           WHERE t.name = 'reporte' AND s.name = 'dbo')
BEGIN
    ALTER SCHEMA Reportes TRANSFER dbo.reporte;
END
GO

IF EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
           WHERE t.name = 'recomendacion' AND s.name = 'dbo')
BEGIN
    ALTER SCHEMA Reportes TRANSFER dbo.recomendacion;
END
GO

--AUTENTICACIÓN DE LOGINS DE SERVIDOR
-- Un login para el perfil "Analista" (gestiona reportes/recomendaciones)
-- y otro para el perfil "Consultor" (solo consulta).

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_analista_reportes')
BEGIN
    CREATE LOGIN login_analista_reportes
        WITH PASSWORD = 'Analista#Reportes2024';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'login_consultor_reportes')
BEGIN
    CREATE LOGIN login_consultor_reportes
        WITH PASSWORD = 'Consultor#Reportes2024';
END
GO


--USUARIOS DE BASE DE DATOS VINCULADOS A CADA LOGIN

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'analista_reportes')
BEGIN
    CREATE USER analista_reportes FOR LOGIN login_analista_reportes;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'consultor_reportes')
BEGIN
    CREATE USER consultor_reportes FOR LOGIN login_consultor_reportes;
END
GO



--ROLES DE BASE DE DATOS
-- rol_gestor_reportes tiene CRUD completo (Administrador/Analista)
-- rol_consultor_reportes tiene Solo lectura (Consultor)

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_gestor_reportes')
BEGIN
    CREATE ROLE rol_gestor_reportes AUTHORIZATION dbo;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'rol_consultor_reportes')
BEGIN
    CREATE ROLE rol_consultor_reportes AUTHORIZATION dbo;
END
GO

--AUTORIZACION DE PERMISOS SOBRE LAS TABLAS

--Gestor tiene control total sobre las dos tablas
GRANT SELECT, INSERT, UPDATE, DELETE ON Reportes.reporte       TO rol_gestor_reportes;
GRANT SELECT, INSERT, UPDATE, DELETE ON Reportes.recomendacion TO rol_gestor_reportes;

--consultor tiene solo lectura, edición explícitamente denegada
GRANT SELECT ON Reportes.reporte       TO rol_consultor_reportes;
GRANT SELECT ON Reportes.recomendacion TO rol_consultor_reportes;
DENY  INSERT, UPDATE, DELETE ON Reportes.reporte       TO rol_consultor_reportes;
DENY  INSERT, UPDATE, DELETE ON Reportes.recomendacion TO rol_consultor_reportes;
GO

--TRIGGERS
-- Los reportes ASG y sus recomendaciones son evidencia de cumplimiento
-- nadie (ni siquiera el rol gestor) debe poder eliminarlos físicamente.
-- Igual que con Bitacora, se bloquea el DELETE a nivel de tabla.

CREATE OR ALTER TRIGGER Reportes.trg_Reporte_EvitarEliminacion
ON Reportes.reporte
INSTEAD OF DELETE
AS
BEGIN
    PRINT 'No se permite eliminar reportes ASG: son evidencia de cumplimiento histórico.';
END
GO

CREATE OR ALTER TRIGGER Reportes.trg_Recomendacion_EvitarEliminacion
ON Reportes.recomendacion
INSTEAD OF DELETE
AS
BEGIN
    PRINT 'No se permite eliminar recomendaciones: forman parte del historial del reporte.';
END
GO


--PROCEDIMIENTOS ALMACENADOS de REPORTE
-- Cada SP registra el error en Bitacora.bitacora_errores si algo falla,
-- igual que el patrón sp_agregarError.

--insertar un nuevo reporte
CREATE OR ALTER PROCEDURE Reportes.sp_Reporte_Insertar
    @IdEmpresa   INT,
    @IdUsuario   INT,
    @Titulo      VARCHAR(150),
    @TipoReporte VARCHAR(50),
    @Contenido   NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO Reportes.reporte (id_empresa, id_usuario, titulo, tipo_reporte, contenido)
        VALUES (@IdEmpresa, @IdUsuario, @Titulo, @TipoReporte, @Contenido);

        SELECT SCOPE_IDENTITY() AS id_reporte_creado;
    END TRY
    BEGIN CATCH
        EXEC Bitacora.sp_agregarError @IdUsuario = @IdUsuario;
        THROW;
    END CATCH
END
GO

--actualizar un reporte existente
CREATE OR ALTER PROCEDURE Reportes.sp_Reporte_Actualizar
    @IdReporte   INT,
    @Titulo      VARCHAR(150),
    @TipoReporte VARCHAR(50),
    @Contenido   NVARCHAR(MAX),
    @IdUsuario   INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Reportes.reporte WHERE id_reporte = @IdReporte)
        BEGIN
            RAISERROR('El reporte indicado no existe.', 16, 1);
            RETURN;
        END

        UPDATE Reportes.reporte
        SET titulo = @Titulo,
            tipo_reporte = @TipoReporte,
            contenido = @Contenido
        WHERE id_reporte = @IdReporte;
    END TRY
    BEGIN CATCH
        EXEC Bitacora.sp_agregarError @IdUsuario = @IdUsuario;
        THROW;
    END CATCH
END
GO

--consultar un reporte por id
CREATE OR ALTER PROCEDURE Reportes.sp_Reporte_ConsultarPorId
    @IdReporte INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.id_reporte, r.titulo, r.tipo_reporte, r.fecha_generacion,
           r.contenido, e.nombre_empresa, u.nombre AS generado_por
    FROM Reportes.reporte r
    JOIN dbo.empresa e ON e.id_empresa = r.id_empresa
    JOIN dbo.usuario u ON u.id_usuario = r.id_usuario
    WHERE r.id_reporte = @IdReporte;
END
GO

--consultar todos los reportes de una empresa por id
CREATE OR ALTER PROCEDURE Reportes.sp_Reporte_ConsultarPorEmpresa
    @IdEmpresa INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.id_reporte, r.titulo, r.tipo_reporte, r.fecha_generacion
    FROM Reportes.reporte r
    WHERE r.id_empresa = @IdEmpresa
    ORDER BY r.fecha_generacion DESC;
END
GO

--consultar todos los reportes
CREATE OR ALTER PROCEDURE Reportes.sp_Reporte_ConsultarTodos
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.id_reporte, e.nombre_empresa, r.titulo, r.tipo_reporte, r.fecha_generacion
    FROM Reportes.reporte r
    JOIN dbo.empresa e ON e.id_empresa = r.id_empresa
    ORDER BY r.fecha_generacion DESC;
END
GO

--Intenta eliminar un reporte, el trigger lo bloqueara y solo imprimirá el aviso
CREATE OR ALTER PROCEDURE Reportes.sp_Reporte_Eliminar
    @IdReporte INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM Reportes.reporte WHERE id_reporte = @IdReporte;
END
GO

--PROCEDIMIENTOS ALMACENADOS DE RECOMENDACION

--inserta una nueva recomendacion asociada a un reporte
CREATE OR ALTER PROCEDURE Reportes.sp_Recomendacion_Insertar
    @IdReporte  INT,
    @Descripcion NVARCHAR(MAX),
    @Prioridad  VARCHAR(20),
    @IdUsuario  INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Reportes.reporte WHERE id_reporte = @IdReporte)
        BEGIN
            RAISERROR('El reporte indicado no existe.', 16, 1);
            RETURN;
        END

        INSERT INTO Reportes.recomendacion (id_reporte, descripcion, prioridad)
        VALUES (@IdReporte, @Descripcion, @Prioridad);

        SELECT SCOPE_IDENTITY() AS id_recomendacion_creada;
    END TRY
    BEGIN CATCH
        EXEC Bitacora.sp_agregarError @IdUsuario = @IdUsuario;
        THROW;
    END CATCH
END
GO

--actualizar una recomendacion existente
CREATE OR ALTER PROCEDURE Reportes.sp_Recomendacion_Actualizar
    @IdRecomendacion INT,
    @Descripcion     NVARCHAR(MAX),
    @Prioridad       VARCHAR(20),
    @IdUsuario       INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Reportes.recomendacion WHERE id_recomendacion = @IdRecomendacion)
        BEGIN
            RAISERROR('La recomendación indicada no existe.', 16, 1);
            RETURN;
        END

        UPDATE Reportes.recomendacion
        SET descripcion = @Descripcion,
            prioridad = @Prioridad
        WHERE id_recomendacion = @IdRecomendacion;
    END TRY
    BEGIN CATCH
        EXEC Bitacora.sp_agregarError @IdUsuario = @IdUsuario;
        THROW;
    END CATCH
END
GO

--consulta recomendaciones de un reporte especiiico
CREATE OR ALTER PROCEDURE Reportes.sp_Recomendacion_ConsultarPorReporte
    @IdReporte INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_recomendacion, descripcion, prioridad, fecha_generacion
    FROM Reportes.recomendacion
    WHERE id_reporte = @IdReporte
    ORDER BY CASE prioridad WHEN 'Alta' THEN 1 WHEN 'Media' THEN 2 ELSE 3 END;
END
GO

--consultar recomendaciones por nivel de prioridad en todas las empresas
CREATE OR ALTER PROCEDURE Reportes.sp_Recomendacion_ConsultarPorPrioridad
    @Prioridad VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT rec.id_recomendacion, e.nombre_empresa, rep.titulo AS reporte, rec.descripcion, rec.fecha_generacion
    FROM Reportes.recomendacion rec
    JOIN Reportes.reporte rep ON rep.id_reporte = rec.id_reporte
    JOIN dbo.empresa e        ON e.id_empresa = rep.id_empresa
    WHERE rec.prioridad = @Prioridad;
END
GO

--intentar eliminar una recomendación el trigger lo bloqueara
CREATE OR ALTER PROCEDURE Reportes.sp_Recomendacion_Eliminar
    @IdRecomendacion INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM Reportes.recomendacion WHERE id_recomendacion = @IdRecomendacion;
END
GO

--PERMISOS GRANt SOBRE LOS PROCEDIMIENTOS (EXECUTE)
--El gestor puede ejecutar todo el esquema y  el consultor solo los sp de lectura.


GRANT EXECUTE ON SCHEMA::Reportes TO rol_gestor_reportes;

GRANT EXECUTE ON Reportes.sp_Reporte_ConsultarPorId             TO rol_consultor_reportes;
GRANT EXECUTE ON Reportes.sp_Reporte_ConsultarPorEmpresa         TO rol_consultor_reportes;
GRANT EXECUTE ON Reportes.sp_Reporte_ConsultarTodos               TO rol_consultor_reportes;
GRANT EXECUTE ON Reportes.sp_Recomendacion_ConsultarPorReporte    TO rol_consultor_reportes;
GRANT EXECUTE ON Reportes.sp_Recomendacion_ConsultarPorPrioridad  TO rol_consultor_reportes;
GO


--ASIGNACIÓN DE USUARIOS A LOS ROLES

ALTER ROLE rol_gestor_reportes     ADD MEMBER analista_reportes;
ALTER ROLE rol_consultor_reportes  ADD MEMBER consultor_reportes;
GO



--PRUEBAS RaPIDAS 
USE ProyectoASG;
EXEC Reportes.sp_Reporte_ConsultarTodos;
EXEC Reportes.sp_Reporte_ConsultarPorEmpresa @IdEmpresa = 1;
EXEC Reportes.sp_Recomendacion_ConsultarPorReporte @IdReporte = 3;
EXEC Reportes.sp_Recomendacion_ConsultarPorPrioridad @Prioridad = 'Alta';
