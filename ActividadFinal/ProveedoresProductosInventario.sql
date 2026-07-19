USE ElTorrero;
GO 

--Schema
CREATE SCHEMA Compras AUTHORIZATION dbo;
GO
-- pasamos las tablas de dbo al schema Compras
ALTER SCHEMA Compras TRANSFER dbo.Proveedores;
ALTER SCHEMA Compras TRANSFER dbo.Productos;
ALTER SCHEMA Compras TRANSFER dbo.Inventario;
GO

--Seguridad
-- rol que solo puede ver informacion
CREATE ROLE Compras_Lector AUTHORIZATION dbo;
GO

-- rol que puede modificar datos
CREATE ROLE Compras_Editor AUTHORIZATION dbo;
GO

-- el lector solo puede hacer select sobre el schema
GRANT SELECT ON SCHEMA::Compras TO Compras_Lector;
GO

-- el editor puede hacer todo menos borrar directamente
GRANT SELECT, INSERT, UPDATE ON SCHEMA::Compras TO Compras_Editor;
GO

-- nadie borra proveedores directo con DELETE, eso se controla con SP y trigger
DENY DELETE ON SCHEMA::Compras TO Compras_Editor;
GO

-- login para el encargado de bodega y asignacion de rol
CREATE LOGIN bodeguero WITH PASSWORD = 'Bodega#2026', CHECK_POLICY = ON;
CREATE USER bodeguero FOR LOGIN bodeguero;
ALTER ROLE Compras_Editor ADD MEMBER bodeguero;
GO

-- login para el gerente que solo consulta reportes
CREATE LOGIN gerente WITH PASSWORD = 'Gerente#2026', CHECK_POLICY = ON;
CREATE USER gerente FOR LOGIN gerente;
ALTER ROLE Compras_Lector ADD MEMBER gerente;
GO

--tablas de historial 
--aqui se guardan los errores que caigan en el CATCH de los SP
CREATE TABLE Compras.ErrorLog (
    IdError INT IDENTITY(1,1) PRIMARY KEY,
    Procedimiento VARCHAR(200),
    Mensaje VARCHAR(4000),
    Fecha DATETIME NOT NULL DEFAULT GETDATE()
);
GO

-- guarda el historial cuando cambia la cantidad en inventario
CREATE TABLE Compras.InventarioAuditoria (
    IdAuditoria INT IDENTITY(1,1) PRIMARY KEY,
    IdInventario INT NOT NULL,
    CantidadAnterior INT,
    CantidadNueva INT,
    FechaCambio DATETIME NOT NULL DEFAULT GETDATE()
);
GO

-- guarda el historial cuando cambia el precio de un producto
CREATE TABLE Compras.HistorialPrecios (
    IdHistorial INT IDENTITY(1,1) PRIMARY KEY,
    IdProducto INT NOT NULL,
    PrecioAnterior DECIMAL(10,2),
    PrecioNuevo DECIMAL(10,2),
    FechaCambio DATETIME NOT NULL DEFAULT GETDATE(),
    FOREIGN KEY (IdProducto) REFERENCES Compras.Productos(IdProducto)
);
GO

--Procedimientos almacenados
-- registra un proveedor nuevo
CREATE PROCEDURE Compras.sp_InsertarProveedor
    @Nombre VARCHAR(100),
    @Contacto VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO Compras.Proveedores (Nombre, Contacto)
        VALUES (@Nombre, @Contacto);
    END TRY
    BEGIN CATCH
        INSERT INTO Compras.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_InsertarProveedor', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

--actualiza los datos de un proveedor
CREATE PROCEDURE Compras.sp_ActualizarProveedor
    @IdProveedor INT,
    @Nombre VARCHAR(100),
    @Contacto VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Compras.Proveedores WHERE IdProveedor = @IdProveedor)
        BEGIN
            RAISERROR('Ese proveedor no existe', 16, 1);
            RETURN;
        END

        UPDATE Compras.Proveedores
        SET Nombre = @Nombre, Contacto = @Contacto
        WHERE IdProveedor = @IdProveedor;
    END TRY
    BEGIN CATCH
        INSERT INTO Compras.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_ActualizarProveedor', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- elimina un proveedor, pasa por el trigger que valida que no tenga productos
CREATE PROCEDURE Compras.sp_EliminarProveedor
    @IdProveedor INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DELETE FROM Compras.Proveedores WHERE IdProveedor = @IdProveedor;
    END TRY
    BEGIN CATCH
        INSERT INTO Compras.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_EliminarProveedor', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- registra un producto nuevo y le crea su fila en inventario en 0
CREATE PROCEDURE Compras.sp_InsertarProducto
    @Nombre VARCHAR(80),
    @Precio DECIMAL(10,2),
    @IdProveedor INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Compras.Proveedores WHERE IdProveedor = @IdProveedor)
        BEGIN
            RAISERROR('El proveedor indicado no existe', 16, 1);
            RETURN;
        END

        BEGIN TRANSACTION;

        INSERT INTO Compras.Productos (Nombre, Precio, IdProveedor)
        VALUES (@Nombre, @Precio, @IdProveedor);

        INSERT INTO Compras.Inventario (Cantidad, IdProducto)
        VALUES (0, SCOPE_IDENTITY());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        INSERT INTO Compras.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_InsertarProducto', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- cambia el precio de un producto (el trigger de historial se dispara solo)
CREATE PROCEDURE Compras.sp_ActualizarPrecioProducto
    @IdProducto INT,
    @NuevoPrecio DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @NuevoPrecio < 0
        BEGIN
            RAISERROR('El precio no puede ser negativo', 16, 1);
            RETURN;
        END

        UPDATE Compras.Productos
        SET Precio = @NuevoPrecio
        WHERE IdProducto = @IdProducto;
    END TRY
    BEGIN CATCH
        INSERT INTO Compras.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_ActualizarPrecioProducto', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- entrada de mercaderia, le suma cantidad al inventario
CREATE PROCEDURE Compras.sp_EntradaInventario
    @IdProducto INT,
    @Cantidad INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @Cantidad <= 0
        BEGIN
            RAISERROR('La cantidad de entrada debe ser mayor a cero', 16, 1);
            RETURN;
        END

        UPDATE Compras.Inventario
        SET Cantidad = Cantidad + @Cantidad
        WHERE IdProducto = @IdProducto;

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('No existe registro de inventario para ese producto', 16, 1);
        END
    END TRY
    BEGIN CATCH
        INSERT INTO Compras.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_EntradaInventario', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- salida de mercaderia, valida que haya suficiente stock antes de restar
CREATE PROCEDURE Compras.sp_SalidaInventario
    @IdProducto INT,
    @Cantidad INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @StockActual INT;

        SELECT @StockActual = Cantidad
        FROM Compras.Inventario
        WHERE IdProducto = @IdProducto;

        IF @StockActual IS NULL
        BEGIN
            RAISERROR('No existe registro de inventario para ese producto', 16, 1);
            RETURN;
        END

        IF @StockActual < @Cantidad
        BEGIN
            RAISERROR('No hay suficiente stock para esa salida', 16, 1);
            RETURN;
        END

        UPDATE Compras.Inventario
        SET Cantidad = Cantidad - @Cantidad
        WHERE IdProducto = @IdProducto;
    END TRY
    BEGIN CATCH
        INSERT INTO Compras.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_SalidaInventario', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

--triggers
-- no deja borrar un proveedor si todavia tiene productos activos
CREATE TRIGGER Compras.trg_Proveedores_NoDelete
ON Compras.Proveedores
INSTEAD OF DELETE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM DELETED d
        INNER JOIN Compras.Productos p ON p.IdProveedor = d.IdProveedor
    )
    BEGIN
        RAISERROR('No se puede eliminar un proveedor que tiene productos asociados', 16, 1);
        RETURN;
    END

    DELETE FROM Compras.Proveedores
    WHERE IdProveedor IN (SELECT IdProveedor FROM DELETED);
END
GO

-- guarda en la auditoria cada vez que cambia la cantidad de un producto
CREATE TRIGGER Compras.trg_Inventario_Auditoria
ON Compras.Inventario
AFTER UPDATE
AS
BEGIN
    IF UPDATE(Cantidad)
    BEGIN
        INSERT INTO Compras.InventarioAuditoria (IdInventario, CantidadAnterior, CantidadNueva)
        SELECT i.IdInventario, d.Cantidad, i.Cantidad
        FROM INSERTED i
        INNER JOIN DELETED d ON d.IdInventario = i.IdInventario
        WHERE i.Cantidad <> d.Cantidad;
    END
END
GO

-- guarda en el historial cada vez que cambia el precio de un producto
CREATE TRIGGER Compras.trg_Productos_HistorialPrecio
ON Compras.Productos
AFTER UPDATE
AS
BEGIN
    IF UPDATE(Precio)
    BEGIN
        INSERT INTO Compras.HistorialPrecios (IdProducto, PrecioAnterior, PrecioNuevo)
        SELECT i.IdProducto, d.Precio, i.Precio
        FROM INSERTED i
        INNER JOIN DELETED d ON d.IdProducto = i.IdProducto
        WHERE i.Precio <> d.Precio;
    END
END
GO

--Vistss
-- vista general que junta producto, proveedor y su stock actual
CREATE VIEW Compras.vw_StockProductos
AS
SELECT
    p.IdProducto,
    p.Nombre AS Producto,
    p.Precio,
    pr.IdProveedor,
    pr.Nombre AS Proveedor,
    i.Cantidad AS Stock
FROM Compras.Productos p
INNER JOIN Compras.Proveedores pr ON pr.IdProveedor = p.IdProveedor
LEFT JOIN Compras.Inventario i ON i.IdProducto = p.IdProducto;
GO

-- vista para ver rapido cuales productos ya se estan quedando sin stock
CREATE VIEW Compras.vw_StockBajo
AS
SELECT *
FROM Compras.vw_StockProductos
WHERE Stock < 10;
GO

--Vista indexada 
CREATE VIEW Compras.vw_TotalStockPorProveedor
WITH SCHEMABINDING
AS
SELECT
    pr.IdProveedor,
    COUNT_BIG(*) AS CantidadProductos,
    SUM(i.Cantidad) AS TotalStock
FROM Compras.Proveedores pr
INNER JOIN Compras.Productos p ON p.IdProveedor = pr.IdProveedor
INNER JOIN Compras.Inventario i ON i.IdProducto = p.IdProducto
GROUP BY pr.IdProveedor;
GO

-- el indice unico clustered es el que convierte la vista en indexada de verdad
CREATE UNIQUE CLUSTERED INDEX IX_TotalStockPorProveedor
ON Compras.vw_TotalStockPorProveedor (IdProveedor);
GO

