-- =====================================================================
-- OPCION 4 - VENTAS (Cliente, Pedidos, DetallePedido)
-- Continua sobre la base de datos ElTorrero ya creada por el equipo.
-- Requiere que ya existan: dbo.Empleados y Administracion.Menu
-- =====================================================================

USE ElTorrero;
GO

--Schema
CREATE SCHEMA Ventas AUTHORIZATION dbo;
GO
-- pasamos las tablas de dbo al schema Ventas
ALTER SCHEMA Ventas TRANSFER dbo.Cliente;
ALTER SCHEMA Ventas TRANSFER dbo.Pedidos;
ALTER SCHEMA Ventas TRANSFER dbo.DetallePedido;
GO

--Seguridad
-- rol que solo puede consultar informacion (ej. gerencia viendo reportes de ventas)
CREATE ROLE Ventas_Lector AUTHORIZATION dbo;
GO

-- rol que atiende pedidos en caja (inserta y actualiza, no borra directo)
CREATE ROLE Ventas_Cajero AUTHORIZATION dbo;
GO

-- el lector solo puede hacer select sobre el schema
GRANT SELECT ON SCHEMA::Ventas TO Ventas_Lector;
GO

-- el cajero puede insertar y actualizar, pero no ejecutar DELETE directo
GRANT SELECT, INSERT, UPDATE ON SCHEMA::Ventas TO Ventas_Cajero;
GO

-- nadie borra un pedido directo con DELETE, eso pasa por SP + trigger
DENY DELETE ON SCHEMA::Ventas TO Ventas_Cajero;
GO

-- login para el cajero que registra los pedidos
CREATE LOGIN cajero WITH PASSWORD = 'Cajero#2026', CHECK_POLICY = ON;
CREATE USER cajero FOR LOGIN cajero;
ALTER ROLE Ventas_Cajero ADD MEMBER cajero;
GO

-- login para el supervisor que solo consulta reportes de ventas
CREATE LOGIN supervisor_ventas WITH PASSWORD = 'Supervisor#2026', CHECK_POLICY = ON;
CREATE USER supervisor_ventas FOR LOGIN supervisor_ventas;
ALTER ROLE Ventas_Lector ADD MEMBER supervisor_ventas;
GO

--tablas de historial
--aqui se guardan los errores que caigan en el CATCH de los SP
CREATE TABLE Ventas.ErrorLog (
    IdError INT IDENTITY(1,1) PRIMARY KEY,
    Procedimiento VARCHAR(200),
    Mensaje VARCHAR(4000),
    Fecha DATETIME NOT NULL DEFAULT GETDATE()
);
GO

-- guarda el historial cada vez que el total de un pedido cambia (lo llena el trigger)
CREATE TABLE Ventas.TotalPedidoHistorial (
    IdHistorial INT IDENTITY(1,1) PRIMARY KEY,
    IdPedido INT NOT NULL,
    TotalAnterior DECIMAL(10,2),
    TotalNuevo DECIMAL(10,2),
    FechaCambio DATETIME NOT NULL DEFAULT GETDATE(),
    FOREIGN KEY (IdPedido) REFERENCES Ventas.Pedidos(IdPedido)
);
GO

--Procedimientos almacenados
-- registra un cliente nuevo
CREATE PROCEDURE Ventas.sp_InsertarCliente
    @Nombre VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO Ventas.Cliente (Nombre)
        VALUES (@Nombre);
    END TRY
    BEGIN CATCH
        INSERT INTO Ventas.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_InsertarCliente', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- actualiza el nombre de un cliente
CREATE PROCEDURE Ventas.sp_ActualizarCliente
    @IdCliente INT,
    @Nombre VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Ventas.Cliente WHERE IdCliente = @IdCliente)
        BEGIN
            RAISERROR('Ese cliente no existe', 16, 1);
            RETURN;
        END

        UPDATE Ventas.Cliente
        SET Nombre = @Nombre
        WHERE IdCliente = @IdCliente;
    END TRY
    BEGIN CATCH
        INSERT INTO Ventas.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_ActualizarCliente', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- elimina un cliente (si tiene pedidos, la FK de Pedidos lo va a impedir)
CREATE PROCEDURE Ventas.sp_EliminarCliente
    @IdCliente INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DELETE FROM Ventas.Cliente WHERE IdCliente = @IdCliente;
    END TRY
    BEGIN CATCH
        INSERT INTO Ventas.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_EliminarCliente', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- abre un pedido nuevo (arranca en 0, el trigger de DetallePedido lo va llenando)
CREATE PROCEDURE Ventas.sp_CrearPedido
    @IdCliente INT,
    @IdEmpleado INT,
    @MetodoPago VARCHAR(30),
    @NuevoIdPedido INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Ventas.Cliente WHERE IdCliente = @IdCliente)
        BEGIN
            RAISERROR('El cliente indicado no existe', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM dbo.Empleados WHERE IdEmpleado = @IdEmpleado)
        BEGIN
            RAISERROR('El empleado indicado no existe', 16, 1);
            RETURN;
        END

        INSERT INTO Ventas.Pedidos (MetodoPago, TotalPedido, IdEmpleado, IdCliente)
        VALUES (@MetodoPago, 0, @IdEmpleado, @IdCliente);

        SET @NuevoIdPedido = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        INSERT INTO Ventas.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_CrearPedido', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- agrega un platillo al pedido; si ya estaba, le suma la cantidad
CREATE PROCEDURE Ventas.sp_AgregarDetallePedido
    @IdPedido INT,
    @IdMenu INT,
    @Cantidad INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @Cantidad <= 0
        BEGIN
            RAISERROR('La cantidad debe ser mayor a cero', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM Ventas.Pedidos WHERE IdPedido = @IdPedido)
        BEGIN
            RAISERROR('El pedido indicado no existe', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM Administracion.Menu WHERE IdMenu = @IdMenu)
        BEGIN
            RAISERROR('El platillo indicado no existe en el menu', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM Ventas.DetallePedido WHERE IdPedido = @IdPedido AND IdMenu = @IdMenu)
        BEGIN
            UPDATE Ventas.DetallePedido
            SET Cantidad = Cantidad + @Cantidad
            WHERE IdPedido = @IdPedido AND IdMenu = @IdMenu;
        END
        ELSE
        BEGIN
            INSERT INTO Ventas.DetallePedido (IdPedido, IdMenu, Cantidad)
            VALUES (@IdPedido, @IdMenu, @Cantidad);
        END
    END TRY
    BEGIN CATCH
        INSERT INTO Ventas.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_AgregarDetallePedido', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- corrige la cantidad de un renglon ya existente del pedido
CREATE PROCEDURE Ventas.sp_ActualizarDetallePedido
    @IdPedido INT,
    @IdMenu INT,
    @Cantidad INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @Cantidad <= 0
        BEGIN
            RAISERROR('La cantidad debe ser mayor a cero', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM Ventas.DetallePedido WHERE IdPedido = @IdPedido AND IdMenu = @IdMenu)
        BEGIN
            RAISERROR('Ese renglon no existe en el pedido', 16, 1);
            RETURN;
        END

        UPDATE Ventas.DetallePedido
        SET Cantidad = @Cantidad
        WHERE IdPedido = @IdPedido AND IdMenu = @IdMenu;
    END TRY
    BEGIN CATCH
        INSERT INTO Ventas.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_ActualizarDetallePedido', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- quita un platillo del pedido
CREATE PROCEDURE Ventas.sp_EliminarDetallePedido
    @IdPedido INT,
    @IdMenu INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DELETE FROM Ventas.DetallePedido
        WHERE IdPedido = @IdPedido AND IdMenu = @IdMenu;

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('Ese renglon no existe en el pedido', 16, 1);
        END
    END TRY
    BEGIN CATCH
        INSERT INTO Ventas.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_EliminarDetallePedido', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

-- cierra/elimina un pedido (el trigger bloquea si todavia tiene platillos)
CREATE PROCEDURE Ventas.sp_EliminarPedido
    @IdPedido INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DELETE FROM Ventas.Pedidos WHERE IdPedido = @IdPedido;
    END TRY
    BEGIN CATCH
        INSERT INTO Ventas.ErrorLog (Procedimiento, Mensaje)
        VALUES ('sp_EliminarPedido', ERROR_MESSAGE());
        THROW;
    END CATCH
END
GO

--triggers
-- no deja borrar un pedido si todavia tiene platillos registrados en el detalle
CREATE TRIGGER Ventas.trg_Pedidos_NoDeleteConDetalle
ON Ventas.Pedidos
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM deleted d
        INNER JOIN Ventas.DetallePedido dp ON dp.IdPedido = d.IdPedido
    )
    BEGIN
        RAISERROR('No se puede eliminar un pedido que ya tiene platillos registrados', 16, 1);
        RETURN;
    END

    DELETE FROM Ventas.Pedidos
    WHERE IdPedido IN (SELECT IdPedido FROM deleted);
END
GO

-- recalcula automaticamente el TotalPedido cada vez que cambia el detalle
-- (insertar, actualizar o borrar un renglon) y deja constancia en el historial
CREATE TRIGGER Ventas.trg_DetallePedido_ActualizarTotal
ON Ventas.DetallePedido
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Cambios TABLE (
        IdPedido INT PRIMARY KEY,
        TotalAnterior DECIMAL(10,2),
        TotalNuevo DECIMAL(10,2)
    );

    -- calcula el total nuevo de cada pedido afectado, comparandolo contra el actual
    INSERT INTO @Cambios (IdPedido, TotalAnterior, TotalNuevo)
    SELECT
        p.IdPedido,
        p.TotalPedido,
        ISNULL(t.Total, 0)
    FROM Ventas.Pedidos p
    INNER JOIN (
        SELECT IdPedido FROM inserted
        UNION
        SELECT IdPedido FROM deleted
    ) afectados ON afectados.IdPedido = p.IdPedido
    LEFT JOIN (
        SELECT dp.IdPedido, SUM(dp.Cantidad * m.Precio) AS Total
        FROM Ventas.DetallePedido dp
        INNER JOIN Administracion.Menu m ON m.IdMenu = dp.IdMenu
        GROUP BY dp.IdPedido
    ) t ON t.IdPedido = p.IdPedido;

    UPDATE p
    SET p.TotalPedido = c.TotalNuevo
    FROM Ventas.Pedidos p
    INNER JOIN @Cambios c ON c.IdPedido = p.IdPedido;

    INSERT INTO Ventas.TotalPedidoHistorial (IdPedido, TotalAnterior, TotalNuevo)
    SELECT IdPedido, TotalAnterior, TotalNuevo
    FROM @Cambios
    WHERE TotalAnterior <> TotalNuevo;
END
GO

--Vistas
-- vista general del pedido: cliente, empleado que atendio y su total
CREATE VIEW Ventas.vw_PedidosResumen
AS
SELECT
    p.IdPedido,
    c.Nombre AS Cliente,
    e.Nombre + ' ' + e.Apellido AS Empleado,
    p.MetodoPago,
    p.TotalPedido,
    (SELECT COUNT(*) FROM Ventas.DetallePedido dp WHERE dp.IdPedido = p.IdPedido) AS CantidadItems
FROM Ventas.Pedidos p
INNER JOIN Ventas.Cliente c ON c.IdCliente = p.IdCliente
INNER JOIN dbo.Empleados e ON e.IdEmpleado = p.IdEmpleado;
GO

-- vista con el detalle de cada pedido, ya con nombre y subtotal calculado
CREATE VIEW Ventas.vw_DetallePedidoCompleto
AS
SELECT
    dp.IdPedido,
    m.NombreComida,
    m.Precio AS PrecioUnitario,
    dp.Cantidad,
    (dp.Cantidad * m.Precio) AS Subtotal
FROM Ventas.DetallePedido dp
INNER JOIN Administracion.Menu m ON m.IdMenu = dp.IdMenu;
GO

--Vista indexada
CREATE VIEW Ventas.vw_VentasPorMetodoPago_Indexada
WITH SCHEMABINDING
AS
SELECT
    MetodoPago,
    COUNT_BIG(*) AS CantidadPedidos,
    SUM(TotalPedido) AS TotalVentas
FROM Ventas.Pedidos
GROUP BY MetodoPago;
GO

-- el indice unico clustered es el que convierte la vista en indexada de verdad
CREATE UNIQUE CLUSTERED INDEX IX_VentasPorMetodoPago
ON Ventas.vw_VentasPorMetodoPago_Indexada (MetodoPago);
GO
