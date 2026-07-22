-- =====================================================================
-- MODULO: NOMINA  (Horarios, Jornadas, SalarioEmpleados)
-- Proyecto: ElTorrero
-- Autor: [Tu nombre]
-- =====================================================================
-- Este script asume que ya se ejecuto BD_ElTorrero_con_tablas.sql
-- (crea la base de datos y las tablas dbo.Horarios, dbo.Jornadas y
-- dbo.SalarioEmpleados). No depende de los scripts de Compras,
-- Personal ni Administracion, pero puede ejecutarse en cualquier
-- orden despues de la creacion de tablas sin generar conflicto,
-- ya que usa su propio schema y sus propios nombres de roles/logins.

USE ElTorrero;
GO

-- =====================================================================
-- SECCION 1: SCHEMA
-- =====================================================================
-- Nomina agrupa todo lo relacionado con la programacion de turnos
-- (Jornadas, Horarios) y el pago de salarios (SalarioEmpleados).
-- Se separa de Personal (que maneja Empleados y Rol) porque son
-- procesos de negocio distintos: uno administra la planilla de
-- personal, el otro administra cuanto y cuando trabaja cada quien.

IF SCHEMA_ID('Nomina') IS NULL
    EXEC('CREATE SCHEMA Nomina AUTHORIZATION dbo');
GO

-- aqui se trasladan al schema Nomina. dbo.Empleados se queda en dbo porque
-- es responsabilidad del modulo Personal de un companero.
IF OBJECT_ID('dbo.Horarios') IS NOT NULL
    ALTER SCHEMA Nomina TRANSFER dbo.Horarios;
GO
IF OBJECT_ID('dbo.Jornadas') IS NOT NULL
    ALTER SCHEMA Nomina TRANSFER dbo.Jornadas;
GO
IF OBJECT_ID('dbo.SalarioEmpleados') IS NOT NULL
    ALTER SCHEMA Nomina TRANSFER dbo.SalarioEmpleados;
GO

-- Nota: dbo.Finanzas (modulo de Administracion) referencia a
-- SalarioEmpleados(IdEmpleado, FechaAñoMes) mediante llave foranea.
-- Mover la tabla de schema no rompe esa relacion, SQL Server la
-- conserva porque la referencia es al objeto, no al nombre calificado.


-- =====================================================================
-- SECCION 2: TABLAS DE BITACORA / AUDITORIA DEL MODULO
-- =====================================================================

-- Guarda los errores atrapados en el CATCH de los procedimientos
IF OBJECT_ID('Nomina.ErrorLog') IS NULL
BEGIN
    CREATE TABLE Nomina.ErrorLog (
        IdError       INT IDENTITY(1,1) PRIMARY KEY,
        Procedimiento VARCHAR(200)  NOT NULL,
        Mensaje       VARCHAR(4000) NOT NULL,
        UsuarioSQL    VARCHAR(100)  NOT NULL DEFAULT SUSER_SNAME(),
        Fecha         DATETIME      NOT NULL DEFAULT GETDATE()
    );
END
GO

-- Historial de cambios de salario (queda registro de cada ajuste)
IF OBJECT_ID('Nomina.SalarioAuditoria') IS NULL
BEGIN
    CREATE TABLE Nomina.SalarioAuditoria (
        IdAuditoria     INT IDENTITY(1,1) PRIMARY KEY,
        IdEmpleado      INT NOT NULL,
        FechaAñoMes     DATE NOT NULL,
        SalarioAnterior DECIMAL(10,2) NOT NULL,
        SalarioNuevo    DECIMAL(10,2) NOT NULL,
        FechaCambio     DATETIME NOT NULL DEFAULT GETDATE()
    );
END
GO


-- =====================================================================
-- SECCION 3: SEGURIDAD (ROLES, LOGINS, USUARIOS, PERMISOS)
-- =====================================================================
-- Nomina_Editor  -> encargado de RRHH: crea/edita jornadas, horarios
--                   y salarios, pero no borra directo (pasa por SP).
-- Nomina_Lector  -> jefatura/gerencia: solo consulta reportes y vistas.

IF DATABASE_PRINCIPAL_ID('Nomina_Editor') IS NULL
    CREATE ROLE Nomina_Editor AUTHORIZATION dbo;
GO

IF DATABASE_PRINCIPAL_ID('Nomina_Lector') IS NULL
    CREATE ROLE Nomina_Lector AUTHORIZATION dbo;
GO

-- El editor puede leer, insertar y modificar; el borrado queda
-- bloqueado a nivel de permiso, se hace solo mediante los SP
-- (que a su vez respetan los triggers de control).
GRANT SELECT, INSERT, UPDATE ON SCHEMA::Nomina TO Nomina_Editor;
DENY  DELETE ON SCHEMA::Nomina TO Nomina_Editor;
GO

-- El lector solo consulta
GRANT SELECT ON SCHEMA::Nomina TO Nomina_Lector;
GO

-- ---------- Logins y usuarios ----------
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'encargado_rrhh')
    CREATE LOGIN encargado_rrhh WITH PASSWORD = 'Nomina#2026', CHECK_POLICY = ON;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'encargado_rrhh')
    CREATE USER encargado_rrhh FOR LOGIN encargado_rrhh;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'auxiliar_nomina')
    CREATE LOGIN auxiliar_nomina WITH PASSWORD = 'Consulta#2026', CHECK_POLICY = ON;
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'auxiliar_nomina')
    CREATE USER auxiliar_nomina FOR LOGIN auxiliar_nomina;
GO

ALTER ROLE Nomina_Editor ADD MEMBER encargado_rrhh;
ALTER ROLE Nomina_Lector ADD MEMBER auxiliar_nomina;
GO


-- =====================================================================
-- SECCION 4: PROCEDIMIENTOS ALMACENADOS - JORNADAS
-- =====================================================================

-- Registrar un tipo de jornada nueva (ej. "Matutina", "Nocturna")
CREATE OR ALTER PROCEDURE Nomina.sp_InsertarJornada
    @TipoJornada VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @TipoJornada IS NULL OR LTRIM(RTRIM(@TipoJornada)) = ''
        BEGIN
            RAISERROR('El tipo de jornada no puede estar vacio', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM Nomina.Jornadas WHERE TipoJornada = @TipoJornada)
        BEGIN
            RAISERROR('Ya existe una jornada con ese nombre', 16, 1);
            RETURN;
        END

        INSERT INTO Nomina.Jornadas (TipoJornada)
        VALUES (LTRIM(RTRIM(@TipoJornada)));
    END TRY
    BEGIN CATCH
        INSERT INTO Nomina.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_InsertarJornada', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- Actualizar el nombre de una jornada
CREATE OR ALTER PROCEDURE Nomina.sp_ActualizarJornada
    @IdJornada INT,
    @TipoJornada VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Nomina.Jornadas WHERE IdJornada = @IdJornada)
        BEGIN
            RAISERROR('La jornada indicada no existe', 16, 1);
            RETURN;
        END

        UPDATE Nomina.Jornadas
        SET TipoJornada = LTRIM(RTRIM(@TipoJornada))
        WHERE IdJornada = @IdJornada;
    END TRY
    BEGIN CATCH
        INSERT INTO Nomina.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_ActualizarJornada', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- Eliminar una jornada (el trigger valida que no tenga horarios asociados)
CREATE OR ALTER PROCEDURE Nomina.sp_EliminarJornada
    @IdJornada INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DELETE FROM Nomina.Jornadas WHERE IdJornada = @IdJornada;
    END TRY
    BEGIN CATCH
        INSERT INTO Nomina.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_EliminarJornada', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- Listar todas las jornadas
CREATE OR ALTER PROCEDURE Nomina.sp_ListarJornadas
AS
BEGIN
    SET NOCOUNT ON;
    SELECT IdJornada, TipoJornada FROM Nomina.Jornadas ORDER BY IdJornada;
END
GO


-- =====================================================================
-- SECCION 5: PROCEDIMIENTOS ALMACENADOS - HORARIOS
-- =====================================================================

-- Asignar un horario a un empleado (el trigger valida que no se
-- solape con otro horario que ya tenga ese mismo empleado)
CREATE OR ALTER PROCEDURE Nomina.sp_InsertarHorario
    @FechaIngresa TIME,
    @FechaSalida  TIME,
    @IdEmpleado   INT,
    @IdJornada    INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Empleados WHERE IdEmpleado = @IdEmpleado)
        BEGIN
            RAISERROR('El empleado indicado no existe', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM Nomina.Jornadas WHERE IdJornada = @IdJornada)
        BEGIN
            RAISERROR('La jornada indicada no existe', 16, 1);
            RETURN;
        END

        IF @FechaSalida <= @FechaIngresa
        BEGIN
            RAISERROR('La hora de salida debe ser mayor a la hora de ingreso', 16, 1);
            RETURN;
        END

        INSERT INTO Nomina.Horarios (FechaIngresa, FechaSalida, IdEmpleado, IdJornada)
        VALUES (@FechaIngresa, @FechaSalida, @IdEmpleado, @IdJornada);
    END TRY
    BEGIN CATCH
        INSERT INTO Nomina.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_InsertarHorario', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- Modificar un horario existente
CREATE OR ALTER PROCEDURE Nomina.sp_ActualizarHorario
    @IdHorario    INT,
    @FechaIngresa TIME,
    @FechaSalida  TIME,
    @IdJornada    INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Nomina.Horarios WHERE IdHorario = @IdHorario)
        BEGIN
            RAISERROR('El horario indicado no existe', 16, 1);
            RETURN;
        END

        IF @FechaSalida <= @FechaIngresa
        BEGIN
            RAISERROR('La hora de salida debe ser mayor a la hora de ingreso', 16, 1);
            RETURN;
        END

        UPDATE Nomina.Horarios
        SET FechaIngresa = @FechaIngresa,
            FechaSalida  = @FechaSalida,
            IdJornada    = @IdJornada
        WHERE IdHorario = @IdHorario;
    END TRY
    BEGIN CATCH
        INSERT INTO Nomina.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_ActualizarHorario', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- Eliminar un horario
CREATE OR ALTER PROCEDURE Nomina.sp_EliminarHorario
    @IdHorario INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Nomina.Horarios WHERE IdHorario = @IdHorario)
        BEGIN
            RAISERROR('El horario indicado no existe', 16, 1);
            RETURN;
        END

        DELETE FROM Nomina.Horarios WHERE IdHorario = @IdHorario;
    END TRY
    BEGIN CATCH
        INSERT INTO Nomina.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_EliminarHorario', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- Consultar todos los horarios asignados a un empleado
CREATE OR ALTER PROCEDURE Nomina.sp_ConsultarHorariosPorEmpleado
    @IdEmpleado INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT h.IdHorario, h.FechaIngresa, h.FechaSalida, j.TipoJornada
    FROM Nomina.Horarios h
    INNER JOIN Nomina.Jornadas j ON j.IdJornada = h.IdJornada
    WHERE h.IdEmpleado = @IdEmpleado
    ORDER BY h.FechaIngresa;
END
GO


-- =====================================================================
-- SECCION 6: PROCEDIMIENTOS ALMACENADOS - SALARIOEMPLEADOS
-- =====================================================================

-- Registrar el salario de un empleado para un mes (un registro por
-- empleado/mes, se normaliza la fecha al primer dia del mes)
CREATE OR ALTER PROCEDURE Nomina.sp_RegistrarSalario
    @IdEmpleado  INT,
    @FechaAñoMes DATE,
    @Salario     DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @PrimerDiaMes DATE = DATEFROMPARTS(YEAR(@FechaAñoMes), MONTH(@FechaAñoMes), 1);

        IF NOT EXISTS (SELECT 1 FROM dbo.Empleados WHERE IdEmpleado = @IdEmpleado)
        BEGIN
            RAISERROR('El empleado indicado no existe', 16, 1);
            RETURN;
        END

        IF @Salario <= 0
        BEGIN
            RAISERROR('El salario debe ser mayor a cero', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM Nomina.SalarioEmpleados
            WHERE IdEmpleado = @IdEmpleado AND FechaAñoMes = @PrimerDiaMes
        )
        BEGIN
            RAISERROR('Ya existe un salario registrado para ese empleado en ese mes', 16, 1);
            RETURN;
        END

        INSERT INTO Nomina.SalarioEmpleados (IdEmpleado, FechaAñoMes, Salario)
        VALUES (@IdEmpleado, @PrimerDiaMes, @Salario);
    END TRY
    BEGIN CATCH
        INSERT INTO Nomina.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_RegistrarSalario', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- Ajustar el salario ya registrado de un empleado en un mes
-- (el trigger de auditoria deja el registro del cambio)
CREATE OR ALTER PROCEDURE Nomina.sp_ActualizarSalario
    @IdEmpleado  INT,
    @FechaAñoMes DATE,
    @NuevoSalario DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @PrimerDiaMes DATE = DATEFROMPARTS(YEAR(@FechaAñoMes), MONTH(@FechaAñoMes), 1);

        IF @NuevoSalario <= 0
        BEGIN
            RAISERROR('El salario debe ser mayor a cero', 16, 1);
            RETURN;
        END

        UPDATE Nomina.SalarioEmpleados
        SET Salario = @NuevoSalario
        WHERE IdEmpleado = @IdEmpleado AND FechaAñoMes = @PrimerDiaMes;

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('No existe un salario registrado para ese empleado en ese mes', 16, 1);
        END
    END TRY
    BEGIN CATCH
        INSERT INTO Nomina.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_ActualizarSalario', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- Consultar el historial salarial de un empleado
CREATE OR ALTER PROCEDURE Nomina.sp_ConsultarHistorialSalarial
    @IdEmpleado INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT FechaAñoMes, Salario
    FROM Nomina.SalarioEmpleados
    WHERE IdEmpleado = @IdEmpleado
    ORDER BY FechaAñoMes;
END
GO

-- Reporte basico: total pagado en planilla por mes
CREATE OR ALTER PROCEDURE Nomina.sp_ReporteNominaMensual
AS
BEGIN
    SET NOCOUNT ON;
    SELECT FechaAñoMes,
           COUNT(*)     AS CantidadEmpleadosPagados,
           SUM(Salario) AS TotalPlanilla
    FROM Nomina.SalarioEmpleados
    GROUP BY FechaAñoMes
    ORDER BY FechaAñoMes;
END
GO


-- =====================================================================
-- SECCION 7: TRIGGERS
-- =====================================================================

-- Trigger 1: no deja borrar una jornada si todavia tiene horarios
-- asignados (control de integridad de negocio, ademas de la FK)
CREATE OR ALTER TRIGGER Nomina.trg_Jornadas_NoEliminarConHorarios
ON Nomina.Jornadas
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM DELETED d
        INNER JOIN Nomina.Horarios h ON h.IdJornada = d.IdJornada
    )
    BEGIN
        RAISERROR('No se puede eliminar una jornada que tiene horarios asignados', 16, 1);
        RETURN;
    END

    DELETE FROM Nomina.Jornadas
    WHERE IdJornada IN (SELECT IdJornada FROM DELETED);
END
GO

-- Trigger 2: evita que un mismo empleado quede con dos horarios cuyo
-- rango de horas se traslapa (evita doble asignacion de turno)
CREATE OR ALTER TRIGGER Nomina.trg_Horarios_ValidarSolapamiento
ON Nomina.Horarios
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM INSERTED i
        INNER JOIN Nomina.Horarios h
            ON h.IdEmpleado = i.IdEmpleado
           AND h.IdHorario <> i.IdHorario
        WHERE i.FechaIngresa < h.FechaSalida
          AND i.FechaSalida  > h.FechaIngresa
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('El empleado ya tiene un horario asignado que se traslapa con ese rango de horas', 16, 1);
        RETURN;
    END
END
GO

-- Trigger 3: guarda en la auditoria cada vez que cambia el salario
-- de un empleado (queda trazabilidad de cada ajuste)
CREATE OR ALTER TRIGGER Nomina.trg_SalarioEmpleados_Auditoria
ON Nomina.SalarioEmpleados
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(Salario)
    BEGIN
        INSERT INTO Nomina.SalarioAuditoria (IdEmpleado, FechaAñoMes, SalarioAnterior, SalarioNuevo)
        SELECT i.IdEmpleado, i.FechaAñoMes, d.Salario, i.Salario
        FROM INSERTED i
        INNER JOIN DELETED d
            ON d.IdEmpleado = i.IdEmpleado AND d.FechaAñoMes = i.FechaAñoMes
        WHERE i.Salario <> d.Salario;
    END
END
GO


-- =====================================================================
-- SECCION 8: VISTAS
-- =====================================================================

-- Vista general: horario + empleado + tipo de jornada
CREATE OR ALTER VIEW Nomina.vw_HorariosDetalle
AS
SELECT
    h.IdHorario,
    e.IdEmpleado,
    e.Nombre + ' ' + e.Apellido AS Empleado,
    j.TipoJornada,
    h.FechaIngresa,
    h.FechaSalida
FROM Nomina.Horarios h
INNER JOIN dbo.Empleados e ON e.IdEmpleado = h.IdEmpleado
INNER JOIN Nomina.Jornadas j ON j.IdJornada = h.IdJornada;
GO

-- Vista: cuantos empleados tiene asignados cada tipo de jornada
CREATE OR ALTER VIEW Nomina.vw_ResumenJornadas
AS
SELECT
    j.IdJornada,
    j.TipoJornada,
    COUNT(h.IdHorario) AS CantidadHorariosAsignados
FROM Nomina.Jornadas j
LEFT JOIN Nomina.Horarios h ON h.IdJornada = j.IdJornada
GROUP BY j.IdJornada, j.TipoJornada;
GO

-- Vista: el salario mas reciente registrado por cada empleado
CREATE OR ALTER VIEW Nomina.vw_SalarioActual
AS
SELECT s.IdEmpleado, e.Nombre + ' ' + e.Apellido AS Empleado, s.FechaAñoMes, s.Salario
FROM Nomina.SalarioEmpleados s
INNER JOIN dbo.Empleados e ON e.IdEmpleado = s.IdEmpleado
WHERE s.FechaAñoMes = (
    SELECT MAX(s2.FechaAñoMes)
    FROM Nomina.SalarioEmpleados s2
    WHERE s2.IdEmpleado = s.IdEmpleado
);
GO

-- Vista indexada: total pagado en planilla por mes.
-- Se indexa porque el reporte de nomina mensual (sp_ReporteNominaMensual)
-- se va a consultar seguido por gerencia/finanzas, y precalcular la
-- suma agregada evita recorrer y sumar toda la tabla SalarioEmpleados
-- cada vez que se pide el reporte.
CREATE OR ALTER VIEW Nomina.vw_NominaPorMes
WITH SCHEMABINDING
AS
SELECT
    FechaAñoMes,
    COUNT_BIG(*) AS CantidadEmpleadosPagados,
    SUM(Salario) AS TotalPlanilla
FROM Nomina.SalarioEmpleados
GROUP BY FechaAñoMes;
GO

CREATE UNIQUE CLUSTERED INDEX IX_NominaPorMes
ON Nomina.vw_NominaPorMes (FechaAñoMes);
GO


-- =====================================================================
-- SECCION 9: PRUEBAS / EVIDENCIAS
-- =====================================================================
-- Ejecutar de arriba hacia abajo. Aqui se generan las capturas de
-- pantalla que pide el enunciado (triggers, SP y vistas funcionando).
-- NOTA: requiere que ya existan empleados cargados (modulo Personal).

-- ---------- 9.1 Jornadas ----------
EXEC Nomina.sp_InsertarJornada @TipoJornada = 'Matutina';
EXEC Nomina.sp_InsertarJornada @TipoJornada = 'Vespertina';
EXEC Nomina.sp_InsertarJornada @TipoJornada = 'Nocturna';
EXEC Nomina.sp_ListarJornadas;
GO

-- ---------- 9.2 Horarios ----------
-- Ajustar @IdEmpleado a un IdEmpleado real que exista en dbo.Empleados
EXEC Nomina.sp_InsertarHorario '07:00', '15:00', 1, 1;
EXEC Nomina.sp_InsertarHorario '15:00', '23:00', 2, 2;
EXEC Nomina.sp_ConsultarHorariosPorEmpleado @IdEmpleado = 1;
GO

-- Probar el trigger de solapamiento -> debe dar error
BEGIN TRY
    EXEC Nomina.sp_InsertarHorario '08:00', '12:00', 1, 1;
END TRY
BEGIN CATCH
    PRINT 'Error capturado: ' + ERROR_MESSAGE();
END CATCH
GO

-- ---------- 9.3 Salarios ----------
EXEC Nomina.sp_RegistrarSalario @IdEmpleado = 1, @FechaAñoMes = '2026-07-01', @Salario = 450000;
EXEC Nomina.sp_RegistrarSalario @IdEmpleado = 2, @FechaAñoMes = '2026-07-01', @Salario = 420000;
EXEC Nomina.sp_ActualizarSalario @IdEmpleado = 1, @FechaAñoMes = '2026-07-01', @NuevoSalario = 470000;
EXEC Nomina.sp_ConsultarHistorialSalarial @IdEmpleado = 1;
EXEC Nomina.sp_ReporteNominaMensual;
GO

-- Probar el manejo de excepciones -> salario duplicado en el mismo mes
BEGIN TRY
    EXEC Nomina.sp_RegistrarSalario @IdEmpleado = 1, @FechaAñoMes = '2026-07-15', @Salario = 500000;
END TRY
BEGIN CATCH
    PRINT 'Error capturado: ' + ERROR_MESSAGE();
END CATCH
GO

-- ---------- 9.4 Trigger de auditoria salarial ----------
SELECT * FROM Nomina.SalarioAuditoria ORDER BY IdAuditoria DESC;
GO

-- ---------- 9.5 Trigger de jornada con horarios asignados ----------
BEGIN TRY
    EXEC Nomina.sp_EliminarJornada @IdJornada = 1;
END TRY
BEGIN CATCH
    PRINT 'Error capturado: ' + ERROR_MESSAGE();
END CATCH
GO

-- ---------- 9.6 Vistas ----------
SELECT * FROM Nomina.vw_HorariosDetalle;
SELECT * FROM Nomina.vw_ResumenJornadas;
SELECT * FROM Nomina.vw_SalarioActual;
SELECT * FROM Nomina.vw_NominaPorMes;
GO

-- Confirmar que el indice de la vista indexada quedo creado
SELECT i.name AS NombreIndice, i.type_desc AS TipoIndice, i.is_unique AS EsUnico
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('Nomina.vw_NominaPorMes');
GO

-- ---------- 9.7 Seguridad ----------
-- El lector si puede consultar las vistas
EXECUTE AS USER = 'auxiliar_nomina';
    SELECT * FROM Nomina.vw_SalarioActual;
REVERT;
GO

-- Pero no puede borrar directo en la tabla
EXECUTE AS USER = 'encargado_rrhh';
    BEGIN TRY
        DELETE FROM Nomina.Horarios WHERE IdHorario = 1;
    END TRY
    BEGIN CATCH
        PRINT 'Permiso denegado correctamente: ' + ERROR_MESSAGE();
    END CATCH
REVERT;
GO

-- ---------- 9.8 Bitacora de errores del modulo ----------
SELECT * FROM Nomina.ErrorLog ORDER BY IdError DESC;
GO