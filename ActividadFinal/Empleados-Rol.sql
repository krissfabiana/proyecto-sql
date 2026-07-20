
USE ElTorrero;
GO

-- Opciones requeridas para poder crear la vista indexada mas adelante
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO


-- =====================================================================
-- SECCION 1: SCHEMAS
-- =====================================================================
-- Personal  -> objetos programables del modulo (SPs, funciones, vistas)
-- Auditoria -> bitacora de errores y de cambios del modulo
-- Las tablas Rol y Empleados se quedan en dbo porque otras tablas del
-- equipo (Horarios, Pedidos, SalarioEmpleados) las referencian por FK.

IF SCHEMA_ID('Personal') IS NULL
    EXEC('CREATE SCHEMA Personal');
GO

IF SCHEMA_ID('Auditoria') IS NULL
    EXEC('CREATE SCHEMA Auditoria');
GO


-- =====================================================================
-- SECCION 2: SEGURIDAD
-- =====================================================================
-- Se crean dos perfiles de acceso:
--   gestor_personal  -> puede ejecutar todo el modulo (jefatura / RRHH)
--   consulta_personal -> solo puede leer las vistas (uso general)

-- ---------- Login y usuario de base de datos ----------
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'usr_personal')
    CREATE LOGIN usr_personal WITH PASSWORD = 'Personal.Torrero2026';
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_personal')
    CREATE USER usr_personal FOR LOGIN usr_personal;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'usr_consulta')
    CREATE LOGIN usr_consulta WITH PASSWORD = 'Consulta.Torrero2026';
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'usr_consulta')
    CREATE USER usr_consulta FOR LOGIN usr_consulta;
GO

-- ---------- Roles de base de datos ----------
IF DATABASE_PRINCIPAL_ID('gestor_personal') IS NULL
    CREATE ROLE gestor_personal;
GO

IF DATABASE_PRINCIPAL_ID('consulta_personal') IS NULL
    CREATE ROLE consulta_personal;
GO

-- ---------- Permisos ----------
-- El gestor NO toca las tablas directamente: solo ejecuta los
-- procedimientos. Asi se obliga a que pasen por las validaciones.
GRANT EXECUTE ON SCHEMA::Personal TO gestor_personal;
GRANT SELECT  ON SCHEMA::Personal TO gestor_personal;
DENY  INSERT, UPDATE, DELETE ON dbo.Empleados TO gestor_personal;
DENY  INSERT, UPDATE, DELETE ON dbo.Rol       TO gestor_personal;
GO

-- El rol de consulta solo lee las vistas del schema Personal
GRANT SELECT ON SCHEMA::Personal TO consulta_personal;
GO

-- La bitacora la escribe el sistema (los procedimientos), nadie mas.
GRANT SELECT ON SCHEMA::Auditoria TO gestor_personal;
DENY  INSERT, UPDATE, DELETE ON SCHEMA::Auditoria TO gestor_personal;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Auditoria TO consulta_personal;
GO

-- ---------- Asignacion de usuarios a roles ----------
ALTER ROLE gestor_personal   ADD MEMBER usr_personal;
ALTER ROLE consulta_personal ADD MEMBER usr_consulta;
GO


-- =====================================================================
-- SECCION 3: TABLA DE BITACORA DEL MODULO
-- =====================================================================
-- Guarda los errores capturados por los bloques TRY/CATCH y los
-- cambios de rol de los empleados.

IF OBJECT_ID('Auditoria.BitacoraPersonal') IS NULL
BEGIN
    CREATE TABLE Auditoria.BitacoraPersonal (
        IdBitacora    INT IDENTITY(1,1) PRIMARY KEY,
        Origen        VARCHAR(100)  NOT NULL,   -- procedimiento o trigger
        NumeroError   INT           NULL,
        Mensaje       VARCHAR(1000) NOT NULL,
        Severidad     INT           NULL,
        Linea         INT           NULL,
        UsuarioSQL    VARCHAR(100)  NOT NULL DEFAULT SUSER_SNAME(),
        Fecha         DATETIME      NOT NULL DEFAULT GETDATE()
    );
END
GO


-- =====================================================================
-- SECCION 4: PROCEDIMIENTOS ALMACENADOS - ROL
-- =====================================================================

-- Procedimiento centralizado para registrar errores en la bitacora.
CREATE OR ALTER PROCEDURE Auditoria.sp_RegistrarError
    @Origen VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Auditoria.BitacoraPersonal
        (Origen, NumeroError, Mensaje, Severidad, Linea)
    VALUES (
        @Origen,
        ERROR_NUMBER(),
        ERROR_MESSAGE(),
        ERROR_SEVERITY(),
        ERROR_LINE()
    );
END
GO


-- Insertar un rol nuevo
CREATE OR ALTER PROCEDURE Personal.sp_InsertarRol
    @Role VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Validaciones de entrada
        IF @Role IS NULL OR LTRIM(RTRIM(@Role)) = ''
            THROW 50001, 'El nombre del rol no puede estar vacio.', 1;

        IF EXISTS (SELECT 1 FROM dbo.Rol WHERE Role = @Role)
            THROW 50002, 'Ya existe un rol con ese nombre.', 1;

        INSERT INTO dbo.Rol (Role)
        VALUES (LTRIM(RTRIM(@Role)));

        SELECT SCOPE_IDENTITY() AS IdRolCreado;
    END TRY
    BEGIN CATCH
        EXEC Auditoria.sp_RegistrarError 'Personal.sp_InsertarRol';
        THROW;   -- se relanza para que la aplicacion se entere
    END CATCH
END
GO


-- Actualizar el nombre de un rol
CREATE OR ALTER PROCEDURE Personal.sp_ActualizarRol
    @IdRol INT,
    @Role  VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE IdRol = @IdRol)
            THROW 50003, 'El rol indicado no existe.', 1;

        IF EXISTS (SELECT 1 FROM dbo.Rol WHERE Role = @Role AND IdRol <> @IdRol)
            THROW 50002, 'Ya existe otro rol con ese nombre.', 1;

        UPDATE dbo.Rol
        SET Role = LTRIM(RTRIM(@Role))
        WHERE IdRol = @IdRol;
    END TRY
    BEGIN CATCH
        EXEC Auditoria.sp_RegistrarError 'Personal.sp_ActualizarRol';
        THROW;
    END CATCH
END
GO


-- Eliminar un rol (el trigger valida que no tenga empleados)
CREATE OR ALTER PROCEDURE Personal.sp_EliminarRol
    @IdRol INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE IdRol = @IdRol)
            THROW 50003, 'El rol indicado no existe.', 1;

        DELETE FROM dbo.Rol WHERE IdRol = @IdRol;
    END TRY
    BEGIN CATCH
        EXEC Auditoria.sp_RegistrarError 'Personal.sp_EliminarRol';
        THROW;
    END CATCH
END
GO


-- Listar todos los roles
CREATE OR ALTER PROCEDURE Personal.sp_ListarRoles
AS
BEGIN
    SET NOCOUNT ON;

    SELECT IdRol, Role
    FROM dbo.Rol
    ORDER BY IdRol;
END
GO


-- =====================================================================
-- SECCION 5: PROCEDIMIENTOS ALMACENADOS - EMPLEADOS
-- =====================================================================

-- Insertar un empleado
CREATE OR ALTER PROCEDURE Personal.sp_InsertarEmpleado
    @Nombre   VARCHAR(80),
    @Apellido VARCHAR(80),
    @Contacto VARCHAR(50) = NULL,
    @IdRol    INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Nombre IS NULL OR LTRIM(RTRIM(@Nombre)) = ''
            THROW 50010, 'El nombre del empleado es obligatorio.', 1;

        IF @Apellido IS NULL OR LTRIM(RTRIM(@Apellido)) = ''
            THROW 50011, 'El apellido del empleado es obligatorio.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE IdRol = @IdRol)
            THROW 50012, 'El rol indicado no existe.', 1;

        -- Evita duplicados: mismo nombre, apellido y contacto
        IF EXISTS (
            SELECT 1 FROM dbo.Empleados
            WHERE Nombre = @Nombre
              AND Apellido = @Apellido
              AND ISNULL(Contacto, '') = ISNULL(@Contacto, '')
        )
            THROW 50013, 'Ya existe un empleado con esos mismos datos.', 1;

        INSERT INTO dbo.Empleados (Nombre, Apellido, Contacto, IdRol)
        VALUES (LTRIM(RTRIM(@Nombre)), LTRIM(RTRIM(@Apellido)), @Contacto, @IdRol);

        SELECT SCOPE_IDENTITY() AS IdEmpleadoCreado;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC Auditoria.sp_RegistrarError 'Personal.sp_InsertarEmpleado';
        THROW;
    END CATCH
END
GO


-- Actualizar los datos de un empleado
CREATE OR ALTER PROCEDURE Personal.sp_ActualizarEmpleado
    @IdEmpleado INT,
    @Nombre     VARCHAR(80),
    @Apellido   VARCHAR(80),
    @Contacto   VARCHAR(50) = NULL,
    @IdRol      INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.Empleados WHERE IdEmpleado = @IdEmpleado)
            THROW 50014, 'El empleado indicado no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE IdRol = @IdRol)
            THROW 50012, 'El rol indicado no existe.', 1;

        UPDATE dbo.Empleados
        SET Nombre   = LTRIM(RTRIM(@Nombre)),
            Apellido = LTRIM(RTRIM(@Apellido)),
            Contacto = @Contacto,
            IdRol    = @IdRol
        WHERE IdEmpleado = @IdEmpleado;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        EXEC Auditoria.sp_RegistrarError 'Personal.sp_ActualizarEmpleado';
        THROW;
    END CATCH
END
GO


-- Cambiar unicamente el rol de un empleado (queda auditado por trigger)
CREATE OR ALTER PROCEDURE Personal.sp_CambiarRolEmpleado
    @IdEmpleado INT,
    @IdRolNuevo INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Empleados WHERE IdEmpleado = @IdEmpleado)
            THROW 50014, 'El empleado indicado no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE IdRol = @IdRolNuevo)
            THROW 50012, 'El rol indicado no existe.', 1;

        UPDATE dbo.Empleados
        SET IdRol = @IdRolNuevo
        WHERE IdEmpleado = @IdEmpleado;
    END TRY
    BEGIN CATCH
        EXEC Auditoria.sp_RegistrarError 'Personal.sp_CambiarRolEmpleado';
        THROW;
    END CATCH
END
GO


-- Eliminar un empleado
CREATE OR ALTER PROCEDURE Personal.sp_EliminarEmpleado
    @IdEmpleado INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Empleados WHERE IdEmpleado = @IdEmpleado)
            THROW 50014, 'El empleado indicado no existe.', 1;

        DELETE FROM dbo.Empleados WHERE IdEmpleado = @IdEmpleado;
    END TRY
    BEGIN CATCH
        -- Aqui suele caer el error 547 de llave foranea cuando el
        -- empleado tiene horarios, pedidos o salarios asociados.
        EXEC Auditoria.sp_RegistrarError 'Personal.sp_EliminarEmpleado';

        IF ERROR_NUMBER() = 547
            THROW 50015, 'No se puede eliminar: el empleado tiene registros asociados (horarios, pedidos o salarios).', 1;
        ELSE
            THROW;
    END CATCH
END
GO


-- Listar empleados con su rol
CREATE OR ALTER PROCEDURE Personal.sp_ListarEmpleados
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.IdEmpleado, e.Nombre, e.Apellido, e.Contacto, r.Role
    FROM dbo.Empleados e
    INNER JOIN dbo.Rol r ON e.IdRol = r.IdRol
    ORDER BY e.IdEmpleado;
END
GO


-- Buscar empleados por nombre o apellido
CREATE OR ALTER PROCEDURE Personal.sp_BuscarEmpleado
    @Texto VARCHAR(80)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.IdEmpleado, e.Nombre, e.Apellido, e.Contacto, r.Role
    FROM dbo.Empleados e
    INNER JOIN dbo.Rol r ON e.IdRol = r.IdRol
    WHERE e.Nombre LIKE '%' + @Texto + '%'
       OR e.Apellido LIKE '%' + @Texto + '%'
    ORDER BY e.Apellido, e.Nombre;
END
GO


-- Listar los empleados de un rol especifico
CREATE OR ALTER PROCEDURE Personal.sp_EmpleadosPorRol
    @IdRol INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Rol WHERE IdRol = @IdRol)
            THROW 50003, 'El rol indicado no existe.', 1;

        SELECT e.IdEmpleado, e.Nombre, e.Apellido, e.Contacto
        FROM dbo.Empleados e
        WHERE e.IdRol = @IdRol
        ORDER BY e.Apellido;
    END TRY
    BEGIN CATCH
        EXEC Auditoria.sp_RegistrarError 'Personal.sp_EmpleadosPorRol';
        THROW;
    END CATCH
END
GO


-- =====================================================================
-- SECCION 6: FUNCIONES
-- =====================================================================

-- Cuenta cuantos empleados tiene un rol
CREATE OR ALTER FUNCTION Personal.fn_ContarEmpleadosPorRol(@IdRol INT)
RETURNS INT
AS
BEGIN
    DECLARE @Total INT;

    SELECT @Total = COUNT(*)
    FROM dbo.Empleados
    WHERE IdRol = @IdRol;

    RETURN ISNULL(@Total, 0);
END
GO


-- Devuelve el nombre completo del empleado
CREATE OR ALTER FUNCTION Personal.fn_NombreCompleto(@IdEmpleado INT)
RETURNS VARCHAR(161)
AS
BEGIN
    DECLARE @NombreCompleto VARCHAR(161);

    SELECT @NombreCompleto = Nombre + ' ' + Apellido
    FROM dbo.Empleados
    WHERE IdEmpleado = @IdEmpleado;

    RETURN ISNULL(@NombreCompleto, 'No encontrado');
END
GO


-- =====================================================================
-- SECCION 7: VISTAS
-- =====================================================================

-- Vista principal: empleados con su rol en texto legible
CREATE OR ALTER VIEW Personal.vw_EmpleadosDetalle
AS
SELECT e.IdEmpleado,
       e.Nombre,
       e.Apellido,
       e.Nombre + ' ' + e.Apellido AS NombreCompleto,
       e.Contacto,
       r.IdRol,
       r.Role
FROM dbo.Empleados e
INNER JOIN dbo.Rol r ON e.IdRol = r.IdRol;
GO


-- Vista de roles que actualmente no tienen ningun empleado asignado
CREATE OR ALTER VIEW Personal.vw_RolesSinEmpleados
AS
SELECT r.IdRol, r.Role
FROM dbo.Rol r
LEFT JOIN dbo.Empleados e ON e.IdRol = r.IdRol
WHERE e.IdEmpleado IS NULL;
GO


-- Vista de empleados sin datos de contacto registrados
CREATE OR ALTER VIEW Personal.vw_EmpleadosSinContacto
AS
SELECT e.IdEmpleado,
       e.Nombre,
       e.Apellido,
       r.Role
FROM dbo.Empleados e
INNER JOIN dbo.Rol r ON e.IdRol = r.IdRol
WHERE e.Contacto IS NULL OR LTRIM(RTRIM(e.Contacto)) = '';
GO


-- =====================================================================
-- SECCION 8: VISTA INDEXADA
-- =====================================================================
-- Resumen de cuantos empleados hay por rol, materializado en disco.
--
-- Requisitos que cumple esta vista para poder indexarse:
--   1. WITH SCHEMABINDING
--   2. Nombres en dos partes (dbo.Empleados, no solo Empleados)
--   3. COUNT_BIG(*) obligatorio cuando se usa GROUP BY
--   4. Sin OUTER JOIN, sin subconsultas, sin DISTINCT ni TOP
--   5. Solo funciones deterministas
--
-- Nota: al usar SCHEMABINDING, el equipo NO podra modificar la
-- estructura de dbo.Rol ni de dbo.Empleados sin borrar antes esta
-- vista. Es el precio de la vista indexada y hay que avisarlo.

IF OBJECT_ID('Personal.vw_ResumenEmpleadosPorRol') IS NOT NULL
    DROP VIEW Personal.vw_ResumenEmpleadosPorRol;
GO

CREATE VIEW Personal.vw_ResumenEmpleadosPorRol
WITH SCHEMABINDING
AS
SELECT r.IdRol,
       r.Role,
       COUNT_BIG(*) AS CantidadEmpleados
FROM dbo.Empleados e
INNER JOIN dbo.Rol r ON e.IdRol = r.IdRol
GROUP BY r.IdRol, r.Role;
GO

-- El indice CLUSTERED UNICO es el que convierte la vista en indexada
CREATE UNIQUE CLUSTERED INDEX IX_vw_ResumenEmpleadosPorRol
    ON Personal.vw_ResumenEmpleadosPorRol (IdRol);
GO

-- Indice adicional no agrupado para busquedas por nombre de rol
CREATE NONCLUSTERED INDEX IX_vw_ResumenEmpleadosPorRol_Role
    ON Personal.vw_ResumenEmpleadosPorRol (Role);
GO


-- =====================================================================
-- SECCION 9: TRIGGERS
-- =====================================================================

-- Trigger 1: impide eliminar un rol que todavia tiene empleados
CREATE OR ALTER TRIGGER dbo.trg_Rol_EvitarEliminarConEmpleados
ON dbo.Rol
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM dbo.Empleados e
        INNER JOIN deleted d ON e.IdRol = d.IdRol
    )
    BEGIN
        INSERT INTO Auditoria.BitacoraPersonal (Origen, Mensaje)
        VALUES ('trg_Rol_EvitarEliminarConEmpleados',
                'Se intento eliminar un rol que tiene empleados asignados.');

        THROW 50020, 'No se puede eliminar un rol con empleados asignados.', 1;
        RETURN;
    END

    -- Si no tiene empleados, se permite el borrado
    DELETE FROM dbo.Rol
    WHERE IdRol IN (SELECT IdRol FROM deleted);
END
GO


-- Trigger 2: valida los datos del empleado al insertar o actualizar
CREATE OR ALTER TRIGGER dbo.trg_Empleados_Validar
ON dbo.Empleados
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Nombre o apellido vacios
    IF EXISTS (
        SELECT 1 FROM inserted
        WHERE LTRIM(RTRIM(Nombre)) = ''
           OR LTRIM(RTRIM(Apellido)) = ''
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50021, 'El nombre y el apellido del empleado no pueden estar vacios.', 1;
        RETURN;
    END

    -- El contacto, si viene, debe tener al menos 8 caracteres
    IF EXISTS (
        SELECT 1 FROM inserted
        WHERE Contacto IS NOT NULL
          AND LEN(LTRIM(RTRIM(Contacto))) < 8
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50022, 'El contacto debe tener al menos 8 caracteres.', 1;
        RETURN;
    END
END
GO


-- Trigger 3: audita los cambios de rol de los empleados
CREATE OR ALTER TRIGGER dbo.trg_Empleados_AuditarCambioRol
ON dbo.Empleados
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF UPDATE(IdRol)
    BEGIN
        INSERT INTO Auditoria.BitacoraPersonal (Origen, Mensaje)
        SELECT 'trg_Empleados_AuditarCambioRol',
               'Empleado ' + CAST(i.IdEmpleado AS VARCHAR(10)) +
               ' cambio del rol ' + CAST(d.IdRol AS VARCHAR(10)) +
               ' al rol ' + CAST(i.IdRol AS VARCHAR(10)) + '.'
        FROM inserted i
        INNER JOIN deleted d ON i.IdEmpleado = d.IdEmpleado
        WHERE i.IdRol <> d.IdRol;
    END
END
GO


-- =====================================================================
-- SECCION 10: PRUEBAS
-- =====================================================================
-- Ejecutar de arriba hacia abajo y revisar los resultados.

-- ---------- 10.1 Insertar roles ----------
EXEC Personal.sp_InsertarRol @Role = 'Gerente';
EXEC Personal.sp_InsertarRol @Role = 'Mesero';
EXEC Personal.sp_InsertarRol @Role = 'Cocinero';
EXEC Personal.sp_InsertarRol @Role = 'Cajero';
EXEC Personal.sp_ListarRoles;
GO

-- ---------- 10.2 Insertar empleados ----------
EXEC Personal.sp_InsertarEmpleado 'Carlos',   'Mora Rodriguez',  '8888-1122', 1;
EXEC Personal.sp_InsertarEmpleado 'Daniela',  'Ulate Brenes',    '8888-3344', 2;
EXEC Personal.sp_InsertarEmpleado 'Sofia',    'Jimenez Vargas',  '8888-5566', 2;
EXEC Personal.sp_InsertarEmpleado 'Marco',    'Araya Solano',    '8888-7788', 3;
EXEC Personal.sp_InsertarEmpleado 'Priscilla','Nunez Castro',    NULL,        4;
EXEC Personal.sp_ListarEmpleados;
GO

-- ---------- 10.3 Probar el manejo de excepciones ----------
-- Rol duplicado -> error 50002
BEGIN TRY
    EXEC Personal.sp_InsertarRol @Role = 'Mesero';
END TRY
BEGIN CATCH
    PRINT 'Error capturado: ' + ERROR_MESSAGE();
END CATCH
GO

-- Rol inexistente -> error 50012
BEGIN TRY
    EXEC Personal.sp_InsertarEmpleado 'Prueba', 'Fallida', '8888-0000', 999;
END TRY
BEGIN CATCH
    PRINT 'Error capturado: ' + ERROR_MESSAGE();
END CATCH
GO

-- Nombre vacio -> error 50010
BEGIN TRY
    EXEC Personal.sp_InsertarEmpleado '', 'SinNombre', '8888-0000', 1;
END TRY
BEGIN CATCH
    PRINT 'Error capturado: ' + ERROR_MESSAGE();
END CATCH
GO

-- ---------- 10.4 Probar los triggers ----------
-- Trigger 1: eliminar un rol con empleados -> error 50020
BEGIN TRY
    EXEC Personal.sp_EliminarRol @IdRol = 2;
END TRY
BEGIN CATCH
    PRINT 'Error capturado: ' + ERROR_MESSAGE();
END CATCH
GO

-- Trigger 2: contacto muy corto -> error 50022
BEGIN TRY
    EXEC Personal.sp_InsertarEmpleado 'Luis', 'Montero Vindas', '123', 3;
END TRY
BEGIN CATCH
    PRINT 'Error capturado: ' + ERROR_MESSAGE();
END CATCH
GO

-- Trigger 3: cambiar el rol de un empleado y revisar la auditoria
EXEC Personal.sp_CambiarRolEmpleado @IdEmpleado = 3, @IdRolNuevo = 4;
SELECT * FROM Auditoria.BitacoraPersonal ORDER BY IdBitacora DESC;
GO

-- ---------- 10.5 Probar las funciones ----------
SELECT Personal.fn_ContarEmpleadosPorRol(2) AS CantidadMeseros;
SELECT Personal.fn_NombreCompleto(1)        AS NombreCompletoEmpleado1;
GO

-- ---------- 10.6 Probar las vistas ----------
SELECT * FROM Personal.vw_EmpleadosDetalle;
SELECT * FROM Personal.vw_RolesSinEmpleados;
SELECT * FROM Personal.vw_EmpleadosSinContacto;
GO

-- ---------- 10.7 Probar la vista indexada ----------
SELECT * FROM Personal.vw_ResumenEmpleadosPorRol;

-- Comprobar que el indice quedo creado correctamente
SELECT i.name AS NombreIndice,
       i.type_desc AS TipoIndice,
       i.is_unique AS EsUnico
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('Personal.vw_ResumenEmpleadosPorRol');
GO

-- ---------- 10.8 Probar la seguridad ----------
-- El usuario de consulta SI puede leer las vistas
EXECUTE AS USER = 'usr_consulta';
    SELECT * FROM Personal.vw_EmpleadosDetalle;
REVERT;
GO

-- Pero NO puede tocar la tabla directamente (debe dar error de permisos)
EXECUTE AS USER = 'usr_consulta';
    BEGIN TRY
        INSERT INTO dbo.Rol (Role) VALUES ('Intruso');
    END TRY
    BEGIN CATCH
        PRINT 'Permiso denegado correctamente: ' + ERROR_MESSAGE();
    END CATCH
REVERT;
GO

-- El gestor SI puede ejecutar los procedimientos del modulo
EXECUTE AS USER = 'usr_personal';
    EXEC Personal.sp_ListarEmpleados;
REVERT;
GO

-- Pero tampoco puede insertar directo en la tabla (DENY explicito)
EXECUTE AS USER = 'usr_personal';
    BEGIN TRY
        INSERT INTO dbo.Rol (Role) VALUES ('SaltandoElProcedimiento');
    END TRY
    BEGIN CATCH
        PRINT 'Permiso denegado correctamente: ' + ERROR_MESSAGE();
    END CATCH
REVERT;
GO

-- ---------- 10.9 Revisar la bitacora completa ----------
SELECT * FROM Auditoria.BitacoraPersonal ORDER BY IdBitacora;
GO