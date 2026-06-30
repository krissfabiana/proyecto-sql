USE ProyectoASG
GO
--Crear login para desarrollador
CREATE LOGIN desarrollador
WITH PASSWORD = 'desarrolladorAGS';
GO
--Crear usuario desarrollador
CREATE USER desarrollador
FOR LOGIN desarrollador;
GO
-- Crear rol a desarrollador
CREATE ROLE desarrollo;

--Que pueda hacer funciones, tablas, procesos almacenados en los schemas dbo (luego lo cambio
-- al tener todos los nombres de los schemas por que el chiste es que realice de todo en casi todo)
GRANT CREATE TABLE TO desarrollo;
GRANT CREATE PROCEDURE TO desarrollo;
GRANT CREATE FUNCTION TO desarrollo;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA:: dbo TO desarrollo;

GO
--Crear esquema bitacora
CREATE SCHEMA Bitacora;
GO

--Asignamos rectricciones al schema bitacora
--Por que quiero que el unico que lo toque sea el sistema
--nadie maes aparte del sysadmin
GRANT SELECT ON SCHEMA:: Bitacora to desarrollo;
GO

--Asignamos rol
ALTER ROLE desarrollo
ADD MEMBER desarrollador

--Crear tabla con el esquema Bitacora
CREATE TABLE Bitacora.bitacora_errores(
	id INT IDENTITY PRIMARY KEY,
	numero_error int,
	mensaje VARCHAR(500),
	fecha DATETIME,
	id_usuario INT
	CONSTRAINT FK_Id_Usuario
        FOREIGN KEY(id_usuario)
        REFERENCES usuario(id_usuario)
)
GO
-- Agregar procesos almacenados
-- sp insertar error a la bitacora
CREATE PROCEDURE sp_agregarError
	@IdUsuario INT
AS
BEGIN TRY
	INSERT INTO Bitacora.bitacora_errores VALUES(
	ERROR_NUMBER(),
	ERROR_MESSAGE(),
	GETDATE(),
	@IdUsuario);
END TRY
BEGIN CATCH
	PRINT 'No se puedo guardar en la bitocara
	Probablemente no se encontro el ID USUARIO'
END CATCH
GO
-- sp Buscar al usuario que cometio el error
CREATE PROCEDURE sp_BuscarUsuarioError
	@IdUsuario INT
AS
BEGIN 
	SELECT *
	FROM Bitacora.bitacora_errores b
	WHERE b.id_usuario = @IdUsuario
END;
GO
-- sp Contar cantidad tipo Error que se registraron apartir del mes pasado
CREATE PROCEDURE sp_CantidadTipoErrorMesPasado
AS
BEGIN
	SELECT b.mensaje,COUNT(*) AS Cantidad_Errores
	FROM Bitacora.bitacora_errores b
	WHERE b.fecha >= DATEADD(MONTH, -1, GETDATE())
	GROUP BY b.mensaje
END
GO
-- Triggers
-- Evita que cualquier usuario pueda borrar datos
CREATE TRIGGER trg_EvitarEliminarDatos
ON Bitacora.bitacora_errores
INSTEAD OF DELETE
AS
BEGIN
    PRINT 'No se permite eliminar registros de la bitácora de errores.';
END
GO
--Evita el problema idempotencia que al recibir el mismo error del mismo usuario
--No lo guarde en la base de datos Si utilice de apoyo la IA con el tema 
--tiempo de 60s que no sabia como agregarlo
CREATE TRIGGER trg_EvitarDuplicados
ON Bitacora.bitacora_errores
INSTEAD OF INSERT
AS
BEGIN
    INSERT INTO Bitacora.bitacora_errores (numero_error, mensaje, fecha, id_usuario)
    SELECT i.numero_error, i.mensaje, i.fecha, i.id_usuario
    FROM inserted i
    WHERE NOT EXISTS (
        SELECT 1
        FROM Bitacora.bitacora_errores b
        WHERE b.id_usuario = i.id_usuario
          AND b.numero_error = i.numero_error
          AND b.fecha >= DATEADD(SECOND, -60, GETDATE())
    );
END
GO