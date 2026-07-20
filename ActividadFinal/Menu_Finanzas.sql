USE ElTorrero;
GO

-- CREAR ESQUEMA 
CREATE SCHEMA Administracion;
GO

-- MOVER TABLAS EXISTENTES
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'Menu' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    ALTER SCHEMA Administracion TRANSFER dbo.Menu;
END
ELSE
BEGIN
    PRINT 'ADVERTENCIA: Tabla Menu no encontrada en dbo';
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE name = 'Finanzas' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    ALTER SCHEMA Administracion TRANSFER dbo.Finanzas;
    PRINT 'Tabla Finanzas movida a Administracion';
END
ELSE
BEGIN
    PRINT 'ADVERTENCIA: Tabla Finanzas no encontrada en dbo';
END
GO

-- CREAR ROLE
CREATE ROLE Administracion;
GO

-- CREAR LOGIN
CREATE LOGIN Administrador WITH PASSWORD = 'Administrador1';
GO

PRINT 'Login Administrador creado';
GO

-- CREAR USUARIO
CREATE USER Administrador FOR LOGIN Administrador;
GO


-- ASIGNAR ROLE AL USUARIO
ALTER ROLE Administracion ADD MEMBER Administrador;
GO

PRINT 'Role asignado al usuario';
GO

-- ASIGNAR PERMISOS AL ROLE
IF EXISTS (SELECT * FROM sys.objects WHERE name = 'Menu' AND schema_id = SCHEMA_ID('Administracion'))
BEGIN
    GRANT SELECT, UPDATE, INSERT, DELETE ON Administracion.Menu TO Administracion;
    PRINT 'Permisos asignados a Menu';
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE name = 'Finanzas' AND schema_id = SCHEMA_ID('Administracion'))
BEGIN
    GRANT SELECT, UPDATE, INSERT, DELETE ON Administracion.Finanzas TO Administracion;
    PRINT 'Permisos asignados a Finanzas';
END
GO

-- CREAR PROCEDIMIENTOS
CREATE PROCEDURE Administracion.sp_ActualizarPrecioMenu
    @IdMenu INT,
    @NuevoPrecio DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    IF @NuevoPrecio < 0
    BEGIN
        RAISERROR('El precio no puede ser negativo', 16, 1);
        RETURN;
    END

    UPDATE Administracion.Menu
    SET Precio = @NuevoPrecio
    WHERE IdMenu = @IdMenu;
END
GO

PRINT 'Procedimiento sp_ActualizarPrecioMenu creado';
GO

CREATE PROCEDURE Administracion.sp_RegistrarFinanza
    @Origen VARCHAR(50),
    @Tipo VARCHAR(30),
    @Monto DECIMAL(10,2),
    @IdEmpleado INT = NULL,
    @FechaAñoMesSalario DATE = NULL,
    @IdInventario INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Monto = 0
    BEGIN
        RAISERROR('El monto no puede ser cero', 16, 1);
        RETURN;
    END

    INSERT INTO Administracion.Finanzas
        (Origen, Tipo, Fecha, Monto, IdEmpleado, FechaAñoMesSalario, IdInventario)
    VALUES
        (@Origen, @Tipo, GETDATE(), @Monto, @IdEmpleado, @FechaAñoMesSalario, @IdInventario);
END
GO

PRINT 'Procedimiento sp_RegistrarFinanza creado';
GO

-- CREAR TRIGGERS
CREATE TRIGGER Administracion.trg_Menu_LogCambioPrecio
ON Administracion.Menu
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(Precio)
    BEGIN
        INSERT INTO Administracion.Finanzas (Origen, Tipo, Fecha, Monto)
        SELECT 'Menu', 'AjustePrecio', GETDATE(), i.Precio - d.Precio
        FROM inserted i
        JOIN deleted d ON i.IdMenu = d.IdMenu
        WHERE i.Precio <> d.Precio;
    END
END
GO

PRINT 'Trigger trg_Menu_LogCambioPrecio creado';
GO

CREATE TRIGGER Administracion.trg_Finanzas_BloquearBorrado
ON Administracion.Finanzas
INSTEAD OF DELETE
AS
BEGIN
    RAISERROR('No se permite eliminar registros de Movimientos', 16, 1);
    ROLLBACK;
END
GO

PRINT 'Trigger trg_Finanzas_BloquearBorrado creado';
GO
-- CREAR VISTAS
CREATE VIEW Administracion.vw_MenuActivo
AS
SELECT IdMenu, NombreComida, Precio
FROM Administracion.Menu;
GO

PRINT 'Vista vw_MenuActivo creada';
GO

CREATE VIEW Administracion.vw_ResumenFinanzasPorTipo
AS
SELECT Tipo,
       COUNT(*) AS CantidadMovimientos,
       SUM(Monto) AS TotalMonto
FROM Administracion.Finanzas
GROUP BY Tipo;
GO

PRINT 'Vista vw_ResumenFinanzasPorTipo creada';
GO

-- CREAR VISTA INDEXADA
CREATE VIEW Administracion.vw_FinanzasPorTipo_Indexada
WITH SCHEMABINDING
AS
SELECT Tipo,
       COUNT_BIG(*) AS CantidadMovimientos,
       SUM(Monto) AS TotalMonto
FROM Administracion.Finanzas
GROUP BY Tipo;
GO

PRINT 'Vista indexada vw_FinanzasPorTipo_Indexada creada';
GO

CREATE UNIQUE CLUSTERED INDEX IX_FinanzasPorTipo_Indexada
ON Administracion.vw_FinanzasPorTipo_Indexada (Tipo);
GO